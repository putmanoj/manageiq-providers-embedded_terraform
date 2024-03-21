# TODO: replace FakeAnsibleRepo with FakeTerraformRepo
FakeTerraformRepo = Spec::Support::FakeAnsibleRepo

RSpec.describe ManageIQ::Providers::EmbeddedTerraform::AutomationManager::ConfigurationScriptSource do

  context "with a local repo" do
    let(:manager) do
      FactoryBot.create(:provider_embedded_terraform, :default_organization => 1).managers.first
    end

    let(:params) do
      {
        :name    => "hello_world",
        :scm_url => "file://#{local_repo}"
      }
    end

    let(:clone_dir)          { Dir.mktmpdir }
    let(:local_repo)         { File.join(clone_dir, "hello_world_local") }
    let(:repo_dir)           { Pathname.new(Dir.mktmpdir) }
    let(:repos)              { Dir.glob(File.join(repo_dir, "*")) }
    let(:repo_dir_structure) { %w[hello_world.tf] }

    before do
      FileUtils.mkdir_p(local_repo)

      repo = FakeTerraformRepo.new(local_repo, repo_dir_structure)
      repo.generate
      repo.git_branch_create("other_branch")

      GitRepository
      stub_const("GitRepository::GIT_REPO_DIRECTORY", repo_dir)

      EvmSpecHelper.assign_embedded_terraform_role
    end

    # Clean up repo dir after each spec
    after do
      FileUtils.rm_rf(repo_dir)
      FileUtils.rm_rf(clone_dir)
    end

    def files_in_repository(git_repo_dir)
      repo = Rugged::Repository.new(git_repo_dir.to_s)
      repo.ref("HEAD").target.target.tree.find_all.map { |f| f[:name] }
    end

    describe ".create_in_provider" do
      # let(:notify_creation_args) { notification_args('creation') }

      context "with valid params" do
        it "creates a record and initializes a git repo" do
          # expect(Notification).to receive(:create!).with(notify_creation_args)
          # expect(Notification).to receive(:create!).with(notification_args("syncing", {}))

          result = described_class.create_in_provider(manager.id, params)

          expect(result).to be_an(described_class)
          expect(result.scm_type).to eq("git")
          expect(result.scm_branch).to eq("master")
          expect(result.status).to eq("successful")
          expect(result.last_updated_on).to be_an(Time)
          expect(result.last_update_error).to be_nil

          git_repo_dir = repo_dir.join(result.git_repository.id.to_s)
          expect(files_in_repository(git_repo_dir)).to eq ["hello_world.tf"]
        end

        # NOTE:  Second `.notify` stub below prevents `.sync` from getting fired
        it "sets the status to 'new' on create" do
          pending # will fix later

          # expect(Notification).to receive(:create!).with(notify_creation_args)
          # expect(described_class).to receive(:notify).with(any_args).and_call_original
          # expect(described_class).to receive(:notify).with("syncing", any_args).and_return(true)

          result = described_class.create_in_provider(manager.id, params)

          expect(result).to be_an(described_class)
          expect(result.scm_type).to eq("git")
          expect(result.scm_branch).to eq("master")
          expect(result.status).to eq("new")
          expect(result.last_updated_on).to be_nil
          expect(result.last_update_error).to be_nil

          expect(repos).to be_empty
        end
      end
    end

    describe ".create_in_provider_queue" do
      it "creates a task and queue item" do
        EvmSpecHelper.local_miq_server
        task_id = described_class.create_in_provider_queue(manager.id, params)
        expect(MiqTask.find(task_id)).to have_attributes(:name => "Creating #{described_class::FRIENDLY_NAME} (name=#{params[:name]})")
        expect(MiqQueue.first).to have_attributes(
          :args        => [manager.id, params],
          :class_name  => described_class.name,
          :method_name => "create_in_provider",
          :priority    => MiqQueue::HIGH_PRIORITY,
          # :role        => "embedded_terraform",
          :zone        => nil
        )
      end
    end

    describe "#verify_ssl" do
      it "defaults to OpenSSL::SSL::VERIFY_NONE" do
        expect(subject.verify_ssl).to eq(OpenSSL::SSL::VERIFY_NONE)
      end

      it "can be updated to OpenSSL::SSL::VERIFY_PEER" do
        subject.verify_ssl = OpenSSL::SSL::VERIFY_PEER
        expect(subject.verify_ssl).to eq(OpenSSL::SSL::VERIFY_PEER)
      end

      context "with a created record" do
        subject             { described_class.last }
        let(:create_params) { params.merge(:verify_ssl => OpenSSL::SSL::VERIFY_PEER) }

        before do
          allow(Notification).to receive(:create!)

          described_class.create_in_provider(manager.id, create_params)
        end

        it "pulls from the created record" do
          expect(subject.verify_ssl).to eq(OpenSSL::SSL::VERIFY_PEER)
        end

        it "pushes updates from the ConfigurationScriptSource to the GitRepository" do
          subject.update(:verify_ssl => OpenSSL::SSL::VERIFY_NONE)

          expect(described_class.last.verify_ssl).to eq(OpenSSL::SSL::VERIFY_NONE)
          expect(GitRepository.last.verify_ssl).to   eq(OpenSSL::SSL::VERIFY_NONE)
        end

        it "converts true/false values instead of integers" do
          subject.update(:verify_ssl => false)

          expect(described_class.last.verify_ssl).to eq(OpenSSL::SSL::VERIFY_NONE)
          expect(GitRepository.last.verify_ssl).to   eq(OpenSSL::SSL::VERIFY_NONE)

          subject.update(:verify_ssl => true)
          expect(described_class.last.verify_ssl).to eq(OpenSSL::SSL::VERIFY_PEER)
          expect(GitRepository.last.verify_ssl).to   eq(OpenSSL::SSL::VERIFY_PEER)
        end
      end

    end

    describe "#templates_in_git_repository" do
      it "finds top level template" do
        record = build_record

        expect(templates_for(record)).to eq(["hello_world_local(master##{local_repo}/)"])
      end

      it "saves the template payload" do
        record = build_record

        payload = {
          :relative_path => '.',
          :files         => ['hello_world.tf'],
          :input_vars    => nil,
          :output_vars   => nil
        }

        name = described_class.template_name_from_git_repo_url(local_repo, 'master', '.')

        expect(record.configuration_script_payloads.first).to have_attributes(
          :name         => name,
          :payload      => payload.to_json,
          :payload_type => "json"
        )
      end

      context "with a nested templates dir" do
        let(:nested_repo) { File.join(clone_dir, "hello_world_nested") }

        let(:nested_repo_structure) do
          %w[
            templates/hello-world/main.tf
          ]
        end

        it "finds all templates" do
          FakeTerraformRepo.generate(nested_repo, nested_repo_structure)

          params[:scm_url] = "file://#{nested_repo}"
          record           = build_record

          expect(templates_for(record)).to eq(["hello-world(master##{nested_repo}/templates)"])
        end
      end

      context "with a multiple templates" do
        let(:multiple_templates_repo) { File.join(clone_dir, "hello_world_nested") }

        let(:multiple_templates_repo_structure) do
          %w[
            templates/hello-world/main.tf
            templates/single-vm/main.tf
          ]
        end

        it "finds all playbooks" do
          FakeTerraformRepo.generate(multiple_templates_repo, multiple_templates_repo_structure)

          params[:scm_url] = "file://#{multiple_templates_repo}"
          record           = build_record

          expect(templates_for(record)).to eq(
            [
              "hello-world(master##{multiple_templates_repo}/templates)",
              "single-vm(master##{multiple_templates_repo}/templates)"
            ]
          )
        end
      end

    end

    describe "#update_in_provider" do
      let(:update_params)      { {:scm_branch => "other_branch"} }
      # let(:notify_update_args) { notification_args('update', update_params) }

      context "with valid params" do
        it "updates the record and initializes a git repo" do
          record = build_record

          # expect(Notification).to receive(:create!).with(notify_update_args)
          # expect(Notification).to receive(:create!).with(notification_args("syncing", {}))

          result = record.update_in_provider update_params

          expect(result).to be_an(described_class)
          expect(result.scm_branch).to eq("other_branch")

          git_repo_dir = repo_dir.join(result.git_repository.id.to_s)
          expect(files_in_repository(git_repo_dir)).to eq ["hello_world.tf"]

          expect(templates_for(record)).to eq(
            [
              "hello_world_local(other_branch##{local_repo}/)"
            ]
          )
        end
      end

      context "with invalid params" do
        it "does not create a record and does not call git" do
          record                    = build_record
          update_params[:scm_type]  = 'svn' # oh dear god...

          expect(AwesomeSpawn).to receive(:run!).never
          # expect(Notification).to receive(:create!).with(notify_update_args)

          expect do
            record.update_in_provider update_params
          end.to raise_error(ActiveRecord::RecordInvalid)
        end
      end

      context "when there is a network error fetching the repo" do
        before do
          record = build_record

          # sync_notification_args        = notification_args("syncing", {})

          # expect(Notification).to receive(:create!).with(notify_update_args)
          # expect(Notification).to receive(:create!).with(sync_notification_args)
          expect(record.git_repository).to receive(:update_repo).and_raise(Rugged::NetworkError)

          expect do
            # described_class.last.update_in_provider update_params
            record.update_in_provider update_params
          end.to raise_error(Rugged::NetworkError)
        end

        it "sets the status to 'error' if syncing has a network error" do
          result = described_class.last

          expect(result).to be_an(described_class)
          expect(result.scm_type).to eq("git")
          expect(result.scm_branch).to eq("other_branch")
          expect(result.status).to eq("error")
          expect(result.last_updated_on).to be_an(Time)
          expect(result.last_update_error).to start_with("Rugged::NetworkError")
        end

        it "clears last_update_error on re-sync" do
          result = described_class.last

          expect(result.status).to eq("error")
          expect(result.last_updated_on).to be_an(Time)
          expect(result.last_update_error).to start_with("Rugged::NetworkError")

          expect(result.git_repository).to receive(:update_repo).and_call_original

          result.sync

          expect(result.status).to eq("successful")
          expect(result.last_update_error).to be_nil
        end
      end

    end

    def templates_for(repo)
      repo.configuration_script_payloads.pluck(:name)
    end

    def build_record
      # expect(Notification).to receive(:create!).with(any_args).twice
      described_class.create_in_provider manager.id, params
    end
  end


  describe "git_repository interaction" do
    let(:auth) { FactoryBot.create(:embedded_terraform_scm_credential) }
    let(:configuration_script_source) do
      described_class.create!(
        :name           => "foo",
        :scm_url        => "https://example.com/foo.git",
        :authentication => auth
      )
    end

    it "on .create" do
      configuration_script_source

      git_repository = GitRepository.first
      expect(git_repository.name).to eq "foo"
      expect(git_repository.url).to eq "https://example.com/foo.git"
      expect(git_repository.authentication).to eq auth

      expect { configuration_script_source.git_repository }.to_not make_database_queries
      expect(configuration_script_source.git_repository_id).to eq git_repository.id
    end

    it "on .new" do
      configuration_script_source = described_class.new(
        :name           => "foo",
        :scm_url        => "https://example.com/foo.git",
        :authentication => auth
      )

      expect(GitRepository.count).to eq 0

      attached_git_repository = configuration_script_source.git_repository

      git_repository = GitRepository.first
      expect(git_repository).to eq attached_git_repository
      expect(git_repository.name).to eq "foo"
      expect(git_repository.url).to eq "https://example.com/foo.git"
      expect(git_repository.authentication).to eq auth

      expect { configuration_script_source.git_repository }.to_not make_database_queries
      expect(configuration_script_source.git_repository_id).to eq git_repository.id
    end

    it "errors when scm_url is invalid" do
      expect do
        configuration_script_source.update!(:scm_url => "invalid url")
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "syncs attributes down" do
      configuration_script_source.name = "bar"
      expect(configuration_script_source.git_repository.name).to eq "bar"

      configuration_script_source.scm_url = "https://example.com/bar.git"
      expect(configuration_script_source.git_repository.url).to eq "https://example.com/bar.git"

      configuration_script_source.authentication = nil
      expect(configuration_script_source.git_repository.authentication).to be_nil
    end

    it "persists attributes down" do
      configuration_script_source.update!(:name => "bar")
      expect(GitRepository.first.name).to eq "bar"

      configuration_script_source.update!(:scm_url => "https://example.com/bar.git")
      expect(GitRepository.first.url).to eq "https://example.com/bar.git"

      configuration_script_source.update!(:authentication => nil)
      expect(GitRepository.first.authentication).to be_nil
    end
  end
end
