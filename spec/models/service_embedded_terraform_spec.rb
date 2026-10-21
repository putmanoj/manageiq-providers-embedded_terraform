describe ServiceEmbeddedTerraform do
  let(:zone) { EvmSpecHelper.local_miq_server.zone }
  let(:ems) { FactoryBot.create(:embedded_automation_manager_terraform, :zone => zone) }
  let(:service) { FactoryBot.create(:service_embedded_terraform) }

  describe "#stack" do
    let!(:stack) { FactoryBot.create(:terraform_stack, :ext_management_system => ems) }
    let!(:service_resource) do
      FactoryBot.create(
        :service_resource,
        :service       => service,
        :resource      => stack,
        :name          => ResourceAction::PROVISION,
        :resource_type => 'OrchestrationStack'
      )
    end

    it "returns the stack for the given action" do
      expect(service.stack(ResourceAction::PROVISION)).to eq(stack)
    end
  end
end
