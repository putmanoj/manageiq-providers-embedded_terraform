RSpec.describe(ManageIQ::Providers::EmbeddedTerraform::AutomationManager::ConfigurationScriptSource) do
  let(:terraform_runner_url) { "https://1.2.3.4:7000" }

  context "with a local repo" do
    let(:manager) { FactoryBot.create(:embedded_automation_manager_terraform) }

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

    let(:hello_world_vars_response) do
      JSON.parse(File.read(File.join(__dir__, "../../../../../lib/terraform/runner/data/responses/hello-world-variables-success.json")))
    end

    def verify_req(req)
      body = JSON.parse(req.body)
      expect(body).to(have_key('templateZipFile'))
    end

    before do
      stub_const("ENV", ENV.to_h.merge("TERRAFORM_RUNNER_URL" => terraform_runner_url))

      stub_request(:post, "#{terraform_runner_url}/api/template/variables")
        .with { |req| verify_req(req) }
        .to_return(
          :status => 200,
          :body   => hello_world_vars_response.to_json
        )

      FileUtils.mkdir_p(local_repo)

      repo = Spec::Support::FakeTerraformRepo.new(local_repo, repo_dir_structure)
      repo.generate
      repo.git_branch_create("other_branch")
      stub_const("GitRepository::GIT_REPO_DIRECTORY", repo_dir)

      EmbeddedTerraformEvmSpecHelper.assign_embedded_terraform_role
    end

    # Clean up repo dir after each spec
    after do
      FileUtils.rm_rf(repo_dir)
      FileUtils.rm_rf(clone_dir)
    end

    def files_in_repository(git_repo_dir)
      repo = Rugged::Repository.new(git_repo_dir.to_s)
      repo.ref("HEAD").target.target.tree.find_all.pluck(:name)
    end

    describe ".create_in_provider" do
      context "with valid params" do
        it "creates a record and initializes a git repo" do
          result = described_class.create_in_provider(manager.id, params)

          expect(result).to(be_a(described_class))
          expect(result).to(have_attributes(
                              :scm_type          => "git",
                              :scm_branch        => "master",
                              :status            => "successful",
                              :last_update_error => nil
                            ))
          expect(result.last_updated_on).to(be_within(2.seconds).of(Time.now.utc))

          git_repo_dir = repo_dir.join(result.git_repository.id.to_s)
          expect(files_in_repository(git_repo_dir)).to(eq(["hello_world.tf"]))
        end
      end
    end

    describe ".create_in_provider_queue" do
      it "creates a task and queue item" do
        EvmSpecHelper.local_miq_server
        task_id = described_class.create_in_provider_queue(manager.id, params)
        expect(MiqTask.find(task_id)).to(have_attributes(:name => "Creating #{described_class::FRIENDLY_NAME} (name=#{params[:name]})"))
        expect(MiqQueue.first).to(have_attributes(
                                    :args        => [manager.id, params],
                                    :class_name  => described_class.name,
                                    :method_name => "create_in_provider",
                                    :priority    => MiqQueue::HIGH_PRIORITY,
                                    :role        => "embedded_terraform",
                                    :zone        => nil
                                  ))
      end
    end

    describe "create_in_provider runs sync" do
      it "finds top level template" do
        record = build_record

        names_and_payloads = record.configuration_script_payloads.pluck(:name, :payload)

        names = names_and_payloads.collect(&:first)
        payloads = names_and_payloads.collect(&:second)

        expect(names.first).to(eq("/hello_world_local"))

        expected_hash = {
          "relative_path"     => File.dirname(*repo_dir_structure),
          "files"             => [File.basename(*repo_dir_structure)],
          "input_vars"        => hello_world_vars_response['template_input_params'],
          "output_vars"       => hello_world_vars_response['template_output_params'],
          "terraform_version" => hello_world_vars_response['terraform_version']
        }

        expect(payloads.first).to(eq(expected_hash.to_json))
      end

      context "with a nested templates dir" do
        let(:nested_repo) { File.join(clone_dir, "hello_world_nested") }

        let(:nested_repo_structure) do
          %w[
            templates/hello-world/main.tf
          ]
        end

        it "finds all templates" do
          Spec::Support::FakeTerraformRepo.generate(nested_repo, nested_repo_structure)

          params[:scm_url] = "file://#{nested_repo}"
          record           = build_record

          names_and_payloads = record.configuration_script_payloads.pluck(:name, :payload)

          names = names_and_payloads.collect(&:first)
          payloads = names_and_payloads.collect(&:second)

          expect(names.first).to(eq("templates/hello-world"))

          expected_hash = {
            "relative_path"     => File.dirname(*nested_repo_structure),
            "files"             => [File.basename(*nested_repo_structure)],
            "input_vars"        => hello_world_vars_response['template_input_params'],
            "output_vars"       => hello_world_vars_response['template_output_params'],
            "terraform_version" => hello_world_vars_response['terraform_version']
          }

          expect(payloads.first).to(eq(expected_hash.to_json))
        end

        it "deletes existing records" do
          # build using the first fake repo
          record      = build_record
          existing_id = record.configuration_script_payloads.first.id

          # create a new fake repo and associate it with our repo
          Spec::Support::FakeTerraformRepo.generate(nested_repo, nested_repo_structure)
          record.update(:scm_url => "file://#{nested_repo}")
          record.sync

          # verify the original payload is removed
          new_ids = record.configuration_script_payloads.pluck(:id)
          expect(new_ids).to(be_present)
          expect(new_ids).to_not(include(existing_id))
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

        it "finds all templates" do
          Spec::Support::FakeTerraformRepo.generate(multiple_templates_repo, multiple_templates_repo_structure)

          params[:scm_url] = "file://#{multiple_templates_repo}"
          record           = build_record

          names_and_payloads = record.configuration_script_payloads.pluck(:name, :payload)

          names = names_and_payloads.collect(&:first)
          payloads = names_and_payloads.collect(&:second)

          expect(names).to(match_array(["templates/hello-world", "templates/single-vm"]))

          expected_hash1 = {
            "relative_path"     => File.dirname(multiple_templates_repo_structure.first),
            "files"             => [File.basename(multiple_templates_repo_structure.first)],
            "input_vars"        => hello_world_vars_response['template_input_params'],
            "output_vars"       => hello_world_vars_response['template_output_params'],
            "terraform_version" => hello_world_vars_response['terraform_version']
          }

          expected_hash2 = {
            "relative_path"     => File.dirname(multiple_templates_repo_structure.second),
            "files"             => [File.basename(multiple_templates_repo_structure.second)],
            "input_vars"        => hello_world_vars_response['template_input_params'],
            "output_vars"       => hello_world_vars_response['template_output_params'],
            "terraform_version" => hello_world_vars_response['terraform_version']
          }

          expect(payloads).to(match_array([expected_hash1.to_json, expected_hash2.to_json]))
        end
      end

      context "with other files in the template dir" do
        let(:nested_repo) { File.join(clone_dir, "hello_world_nested") }

        let(:nested_repo_structure) do
          %w[
            templates/hello-world/main.tf
            templates/hello-world/outputs.tf
            templates/hello-world/variables.tf
          ]
        end

        it "finds all associated files" do
          Spec::Support::FakeTerraformRepo.generate(nested_repo, nested_repo_structure)

          params[:scm_url] = "file://#{nested_repo}"
          record           = build_record

          names_and_payloads = record.configuration_script_payloads.pluck(:name, :payload)

          names = names_and_payloads.collect(&:first)
          payloads = names_and_payloads.collect(&:second)

          expect(names.first).to(eq("templates/hello-world"))

          files = JSON.parse(payloads.first)["files"]

          expect(files).to(match_array(%w[main.tf outputs.tf variables.tf]))
        end
      end

      context "with directories that don't have terraform templates" do
        let(:nested_repo) { File.join(clone_dir, "hello_world_nested") }

        let(:nested_repo_structure) do
          %w[
            templates/hello-world/main.tf
            templates/hello-world/outputs.tf
            templates/hello-world/variables.tf
            workflows/testing/testing.asl
            docs/README.md
          ]
        end

        it "ignores directories without terraform templates" do
          Spec::Support::FakeTerraformRepo.generate(nested_repo, nested_repo_structure)

          params[:scm_url] = "file://#{nested_repo}"
          record           = build_record

          names = record.configuration_script_payloads.pluck(:name)
          expect(names).to(match_array(["templates/hello-world"]))
        end
      end
    end

    describe "#template_name_from_git_repo_url" do
      let(:git_url_branch_path)   { ["git@example.com:manoj-puthran/sample-scripts.git", "terraform/templates/hello-world"] }
      let(:https_url_branch_path) { ["https://example.com/manoj-puthran/sample-scripts.git", "terraform/templates/hello-world"] }
      let(:expected_result)       { "terraform/templates/hello-world" }

      it "supports https urls" do
        expect(described_class.template_name_from_git_repo_url(*https_url_branch_path)).to(eq(expected_result))
      end

      it "converts git urls" do
        expect(described_class.template_name_from_git_repo_url(*git_url_branch_path)).to(eq(expected_result))
      end
    end

    describe "#update_in_provider" do
      let(:update_params) { {:scm_branch => "other_branch"} }

      context "with valid params" do
        it "updates the record and initializes a git repo" do
          record = build_record
          result = record.update_in_provider(update_params)

          expect(result).to(be_a(described_class))
          expect(result.scm_branch).to(eq("other_branch"))

          git_repo_dir = repo_dir.join(result.git_repository.id.to_s)
          expect(files_in_repository(git_repo_dir)).to(eq(["hello_world.tf"]))

          names_and_payloads = record.configuration_script_payloads.pluck(:name, :payload)

          names = names_and_payloads.collect(&:first)
          payloads = names_and_payloads.collect(&:second)

          expect(names.first).to(eq("/hello_world_local"))

          expected_hash = {
            "relative_path"     => File.dirname(*repo_dir_structure),
            "files"             => [File.basename(*repo_dir_structure)],
            "input_vars"        => hello_world_vars_response['template_input_params'],
            "output_vars"       => hello_world_vars_response['template_output_params'],
            "terraform_version" => hello_world_vars_response['terraform_version']
          }

          expect(payloads.first).to(eq(expected_hash.to_json))
        end
      end

      context "when there is a network error fetching the repo" do
        before do
          record = build_record
          expect(record.git_repository).to(receive(:update_repo).and_raise(Rugged::NetworkError))

          expect { record.update_in_provider(update_params) }.to(raise_error(Rugged::NetworkError))
        end

        it "sets the status to 'error' if syncing has a network error" do
          result = described_class.last

          expect(result).to(be_a(described_class))
          expect(result).to(have_attributes(
                              :scm_type   => "git",
                              :scm_branch => "other_branch",
                              :status     => "error"
                            ))
          expect(result.last_updated_on).to(be_within(2.seconds).of(Time.now.utc))
          expect(result.last_update_error).to(start_with("Rugged::NetworkError"))
        end

        it "clears last_update_error on re-sync" do
          result = described_class.last

          expect(result.status).to(eq("error"))
          expect(result.last_updated_on).to(be_within(2.seconds).of(Time.now.utc))
          expect(result.last_update_error).to(start_with("Rugged::NetworkError"))
          expect(result.git_repository).to(receive(:update_repo).and_call_original)

          result.sync

          expect(result.status).to(eq("successful"))
          expect(result.last_update_error).to(be_nil)
        end
      end
    end

    describe "#update_in_provider_queue" do
      it "creates a task and queue item" do
        record    = build_record
        task_id   = record.update_in_provider_queue({})
        task_name = "Updating #{described_class::FRIENDLY_NAME} (name=#{record.name})"

        expect(MiqTask.find(task_id)).to(have_attributes(:name => task_name))
        expect(MiqQueue.first).to(
          have_attributes(
            :instance_id => record.id,
            :args        => [{:task_id => task_id}],
            :class_name  => described_class.name,
            :method_name => "update_in_provider",
            :priority    => MiqQueue::HIGH_PRIORITY,
            :role        => "embedded_terraform",
            :zone        => nil
          )
        )
      end
    end

    describe "#delete_in_provider_queue" do
      it "creates a task and queue item" do
        record    = build_record
        task_id   = record.delete_in_provider_queue
        task_name = "Deleting #{described_class::FRIENDLY_NAME} (name=#{record.name})"

        expect(MiqTask.find(task_id)).to(have_attributes(:name => task_name))
        expect(MiqQueue.first).to(
          have_attributes(
            :instance_id => record.id,
            :args        => [],
            :class_name  => described_class.name,
            :method_name => "delete_in_provider",
            :priority    => MiqQueue::HIGH_PRIORITY,
            :role        => "embedded_terraform",
            :zone        => nil
          )
        )
      end
    end

    def build_record
      described_class.create_in_provider(manager.id, params)
    end
  end
end
