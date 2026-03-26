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
end
