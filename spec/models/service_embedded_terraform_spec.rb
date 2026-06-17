describe ServiceEmbeddedTerraform do
  let(:zone) { EvmSpecHelper.local_miq_server.zone }
  let(:ems) { FactoryBot.create(:embedded_automation_manager_terraform, :zone => zone) }
  let(:service) { FactoryBot.create(:service_embedded_terraform) }
  let!(:auth) { FactoryBot.create(:authentication) }

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

  describe "#stack_opts with credential_id handling" do
    context "when credential_id is provided as array [id, name]" do
      it "extracts the id and includes it in stack options" do
        overrides = {:credential_id => [auth.id, "AWS Credential"]}
        result = service.stack_opts(ResourceAction::PROVISION, overrides)

        expect(result[:credentials]).to include(auth.native_ref)
      end
    end

    context "when credential_id is provided as array [nil, nil]" do
      it "does not include credentials in stack options" do
        overrides = {:credential_id => [nil, nil]}
        result = service.stack_opts(ResourceAction::PROVISION, overrides)

        expect(result[:credentials]).to be_empty
      end
    end

    context "when credential_id is provided as single value" do
      it "includes the credential in stack options" do
        overrides = {:credential_id => auth.id}
        result = service.stack_opts(ResourceAction::PROVISION, overrides)

        expect(result[:credentials]).to include(auth.native_ref)
      end
    end

    context "when no credential_id is provided" do
      it "does not include credentials in stack options" do
        overrides = {}
        result = service.stack_opts(ResourceAction::PROVISION, overrides)

        expect(result[:credentials]).to be_empty
      end
    end

    context "with dialog input variables" do
      before do
        service.options = {
          :dialog => {
            "dialog_var1" => "value1",
            "dialog_var2" => "value2"
          }
        }
      end

      it "includes input_vars from dialog in stack options" do
        result = service.stack_opts(ResourceAction::PROVISION)

        expect(result[:input_vars]).to include("var1" => "value1", "var2" => "value2")
      end

      it "includes both input_vars and credentials when credential_id is provided" do
        overrides = {:credential_id => auth.id}
        result = service.stack_opts(ResourceAction::PROVISION, overrides)

        expect(result[:input_vars]).to include("var1" => "value1", "var2" => "value2")
        expect(result[:credentials]).to include(auth.native_ref)
      end

      it "includes input_vars but no credentials when credential_id is [nil, nil]" do
        overrides = {:credential_id => [nil, nil]}
        result = service.stack_opts(ResourceAction::PROVISION, overrides)

        expect(result[:input_vars]).to include("var1" => "value1", "var2" => "value2")
        expect(result[:credentials]).to be_empty
      end
    end
  end
end
