describe ManageIQ::Providers::EmbeddedTerraform::AutomationManager do
  describe '#catalog_types' do
    let(:manager) { FactoryBot.create(:embedded_automation_manager_terraform) }

    it "#catalog_types" do
      expect(manager.catalog_types).to eq(
        {
          "generic_terraform_template" => N_("Terraform Template (deprecated)"),
          "embedded_terraform"         => N_("Terraform Template")
        }
      )
    end
  end
end
