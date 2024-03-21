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
end
