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

      repo = Spec::Support::FakeAnsibleRepo.new(local_repo, repo_dir_structure)
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
      it "creates a record and initializes a git repo" do
        result = described_class.create_in_provider(manager.id, params)

        expect(result).to(be_an(described_class))
        expect(result.scm_type).to eq("git")
        expect(result.scm_branch).to eq("master")
        expect(result.status).to eq("successful")
        expect(result.last_updated_on).to be_an(Time)
        expect(result.last_update_error).to be_nil

        git_repo_dir = repo_dir.join(result.git_repository.id.to_s)
        expect(files_in_repository(git_repo_dir)).to eq ["hello_world.tf"]
      end
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
