describe ManageIQ::Providers::EmbeddedTerraform::AutomationManager::ProvisionWorkflow do
  let(:admin)        { FactoryBot.create(:user_with_group) }
  let(:manager)      { FactoryBot.create(:embedded_automation_manager_terraform) }
  let(:dialog)       { FactoryBot.create(:miq_provision_configuration_script_embedded_terraform_dialogs) }

  describe "#allowed_configuration_scripts" do
    context "with no configuration_scripts" do
      it "returns an empty set" do
        workflow = described_class.new({:provision_dialog_name => dialog.name}, admin.userid)
        expect(workflow.allowed_configuration_scripts).to be_empty
      end
    end

    context "with a configuration_script" do
      let!(:configuration_script) { FactoryBot.create(:configuration_script_embedded_terraform, :manager => manager) }

      it "returns the configuration script" do
        workflow = described_class.new({:provision_dialog_name => dialog.name}, admin.userid)

        allowed = workflow.allowed_configuration_scripts
        expect(allowed.count).to eq(1)
        expect(allowed.first).to have_attributes(:id => configuration_script.id, :name => configuration_script.name)
      end
    end
  end

  describe "#allowed_credentials" do
    context "with no credentials" do
      it "returns an empty hash" do
        workflow = described_class.new({:provision_dialog_name => dialog.name}, admin.userid)
        expect(workflow.allowed_credentials).to eq({})
      end
    end

    context "with multiple credentials and no credential_type filter" do
      let!(:amazon_cred)  { FactoryBot.create(:embedded_terraform_amazon_credential, :name => "AWS Prod") }
      let!(:azure_cred)   { FactoryBot.create(:embedded_terraform_azure_credential, :name => "Azure Dev") }
      let!(:vsphere_cred) { FactoryBot.create(:embedded_terraform_vsphere_credential, :name => "vSphere Test") }

      it "returns all TemplateCredential instances" do
        workflow = described_class.new({:provision_dialog_name => dialog.name}, admin.userid)
        allowed = workflow.allowed_credentials

        expect(allowed).to be_a(Hash)
        expect(allowed.keys).to contain_exactly(amazon_cred.id, azure_cred.id, vsphere_cred.id)
        expect(allowed[amazon_cred.id]).to eq("AWS Prod")
        expect(allowed[azure_cred.id]).to eq("Azure Dev")
        expect(allowed[vsphere_cred.id]).to eq("vSphere Test")
      end
    end

    context "with credential_type filter for AmazonCredential" do
      let!(:amazon_cred)  { FactoryBot.create(:embedded_terraform_amazon_credential, :name => "AWS Prod") }
      let!(:azure_cred)   { FactoryBot.create(:embedded_terraform_azure_credential, :name => "Azure Dev") }
      let!(:vsphere_cred) { FactoryBot.create(:embedded_terraform_vsphere_credential, :name => "vSphere Test") }

      it "returns only Amazon credentials" do
        workflow = described_class.new({:provision_dialog_name => dialog.name}, admin.userid)
        workflow.values[:credential_type] = ["ManageIQ::Providers::EmbeddedTerraform::AutomationManager::AmazonCredential", nil]
        allowed = workflow.allowed_credentials

        expect(allowed).to be_a(Hash)
        expect(allowed.keys).to contain_exactly(amazon_cred.id)
        expect(allowed[amazon_cred.id]).to eq("AWS Prod")
      end
    end

    context "with credential_type filter for AzureCredential" do
      let!(:amazon_cred)  { FactoryBot.create(:embedded_terraform_amazon_credential, :name => "AWS Prod") }
      let!(:azure_cred)   { FactoryBot.create(:embedded_terraform_azure_credential, :name => "Azure Dev") }
      let!(:vsphere_cred) { FactoryBot.create(:embedded_terraform_vsphere_credential, :name => "vSphere Test") }

      it "returns only Azure credentials" do
        workflow = described_class.new({:provision_dialog_name => dialog.name}, admin.userid)
        workflow.values[:credential_type] = ["ManageIQ::Providers::EmbeddedTerraform::AutomationManager::AzureCredential", nil]
        allowed = workflow.allowed_credentials

        expect(allowed).to be_a(Hash)
        expect(allowed.keys).to contain_exactly(azure_cred.id)
        expect(allowed[azure_cred.id]).to eq("Azure Dev")
      end
    end

    context "with invalid credential_type" do
      let!(:amazon_cred)  { FactoryBot.create(:embedded_terraform_amazon_credential, :name => "AWS Prod") }
      let!(:azure_cred)   { FactoryBot.create(:embedded_terraform_azure_credential, :name => "Azure Dev") }

      it "falls back to all TemplateCredentials" do
        workflow = described_class.new({:provision_dialog_name => dialog.name}, admin.userid)
        workflow.values[:credential_type] = ["InvalidClassName", nil]
        allowed = workflow.allowed_credentials

        expect(allowed).to be_a(Hash)
        expect(allowed.keys).to contain_exactly(amazon_cred.id, azure_cred.id)
      end
    end
  end

  describe "#allowed_credential_types" do
    context "with no credential_id specified" do
      it "returns all TemplateCredential descendant types with API_OPTIONS" do
        workflow = described_class.new({:provision_dialog_name => dialog.name}, admin.userid)
        allowed = workflow.allowed_credential_types

        expect(allowed).to be_a(Hash)
        expect(allowed.keys).to include(
          "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::AmazonCredential",
          "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::AzureCredential",
          "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::VsphereCredential",
          "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::GoogleCredential",
          "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::OpenstackCredential",
          "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::IbmCloudCredential",
          "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::IbmClassicInfrastructureCredential"
        )
      end

      it "returns correct labels for each credential type" do
        workflow = described_class.new({:provision_dialog_name => dialog.name}, admin.userid)
        allowed = workflow.allowed_credential_types

        expect(allowed["ManageIQ::Providers::EmbeddedTerraform::AutomationManager::AmazonCredential"]).to eq("Amazon")
        expect(allowed["ManageIQ::Providers::EmbeddedTerraform::AutomationManager::AzureCredential"]).to eq("Azure")
      end
    end

    context "with credential_id for AmazonCredential" do
      let!(:amazon_cred) { FactoryBot.create(:embedded_terraform_amazon_credential, :name => "AWS Prod") }

      it "returns only the AmazonCredential type" do
        workflow = described_class.new({:provision_dialog_name => dialog.name}, admin.userid)
        workflow.values[:credential_id] = [amazon_cred.id, nil]
        allowed = workflow.allowed_credential_types

        expect(allowed).to be_a(Hash)
        expect(allowed.keys).to contain_exactly("ManageIQ::Providers::EmbeddedTerraform::AutomationManager::AmazonCredential")
        expect(allowed["ManageIQ::Providers::EmbeddedTerraform::AutomationManager::AmazonCredential"]).to eq("Amazon")
      end
    end

    context "with credential_id for AzureCredential" do
      let!(:azure_cred) { FactoryBot.create(:embedded_terraform_azure_credential, :name => "Azure Dev") }

      it "returns only the AzureCredential type" do
        workflow = described_class.new({:provision_dialog_name => dialog.name}, admin.userid)
        workflow.values[:credential_id] = [azure_cred.id, nil]
        allowed = workflow.allowed_credential_types

        expect(allowed).to be_a(Hash)
        expect(allowed.keys).to contain_exactly("ManageIQ::Providers::EmbeddedTerraform::AutomationManager::AzureCredential")
        expect(allowed["ManageIQ::Providers::EmbeddedTerraform::AutomationManager::AzureCredential"]).to eq("Azure")
      end
    end

    context "with credential_id for VsphereCredential" do
      let!(:vsphere_cred) { FactoryBot.create(:embedded_terraform_vsphere_credential, :name => "vSphere Test") }

      it "returns only the VsphereCredential type" do
        workflow = described_class.new({:provision_dialog_name => dialog.name}, admin.userid)
        workflow.values[:credential_id] = [vsphere_cred.id, nil]
        allowed = workflow.allowed_credential_types

        expect(allowed).to be_a(Hash)
        expect(allowed.keys).to contain_exactly("ManageIQ::Providers::EmbeddedTerraform::AutomationManager::VsphereCredential")
      end
    end

    context "with invalid credential_id" do
      it "falls back to all TemplateCredential descendants" do
        workflow = described_class.new({:provision_dialog_name => dialog.name}, admin.userid)
        workflow.values[:credential_id] = [99_999, nil]
        allowed = workflow.allowed_credential_types

        expect(allowed).to be_a(Hash)
        expect(allowed.keys).to include(
          "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::AmazonCredential",
          "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::AzureCredential"
        )
      end
    end
  end
end
