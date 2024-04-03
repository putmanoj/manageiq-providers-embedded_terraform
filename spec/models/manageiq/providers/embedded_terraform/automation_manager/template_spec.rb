RSpec.describe(ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Template) do
  let(:manager) do
    FactoryBot.create(:provider_embedded_terraform, :default_organization => 1).managers.first
  end
  let(:terraform_script_source) do
    FactoryBot.create(:embedded_terraform_configuration_script_source, :manager_id => manager.id)
  end
  let(:template) do
    FactoryBot.create(:embedded_template, :configuration_script_source => terraform_script_source)
  end

  context "#run" do
    describe "runs the referenced terraform template" do
      it "template.run" do
        puts("launches template")
        job = template.run({})

        expect(job).to(be_a(ManageIQ::Providers::TerraformTemplateWorkflow))
        expect(job.options[:input_vars]).to(eq({}))
        expect(job.options[:configuration_script_source_id]).to(eq(terraform_script_source.id))
        payload_json = JSON.parse(template.payload)
        expect(job.options[:template_relative_path]).to(eq(payload_json['relative_path']))
        expect(job.options[:timeout]).to(eq(2.hours))
      end

      it "accepts inputs parameters to run template against" do
        job = template.run({:some_key => :some_value})

        expect(job).to(be_a(ManageIQ::Providers::TerraformTemplateWorkflow))
        expect(job.options[:input_vars]).to(eq(:some_key => :some_value))
      end

      it "accepts credentials to run template against" do
        job = template.run({}, [{:access_key => :some_key}])

        expect(job).to(be_a(ManageIQ::Providers::TerraformTemplateWorkflow))
        expect(job.options[:credentials]).to(eq([{:access_key => :some_key}]))
      end
    end
  end
end
