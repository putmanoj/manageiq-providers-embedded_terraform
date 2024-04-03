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
        job = template.run

        expect(job).to(be_a(ManageIQ::Providers::TerraformTemplateWorkflow))
        expect(job.options[:input_vars]).to(eq({}))
        expect(job.options[:configuration_script_source_id]).to(eq(terraform_script_source.id))
        payload_json = JSON.parse(template.payload)
        expect(job.options[:template_relative_path]).to(eq(payload_json['relative_path']))
        expect(job.options[:credentials]).to(eq([]))
        expect(job.options[:timeout]).to(eq(2.hours))
        expect(job.options[:poll_interval]).to(eq(10.seconds))
      end

      it "accepts input_vars to run template against" do
        job = template.run(:input_vars => {:some_key => :some_value})

        expect(job).to(be_a(ManageIQ::Providers::TerraformTemplateWorkflow))
        expect(job.options[:input_vars]).to(eq(:some_key => :some_value))

        expect(job.options[:configuration_script_source_id]).to(eq(terraform_script_source.id))
        payload_json = JSON.parse(template.payload)
        expect(job.options[:template_relative_path]).to(eq(payload_json['relative_path']))
        expect(job.options[:credentials]).to(eq([]))
        expect(job.options[:timeout]).to(eq(2.hours))
        expect(job.options[:poll_interval]).to(eq(10.seconds))
      end

      it "accepts credentials to run template against" do
        job = template.run(:credentials => [{:access_key => :some_key}])

        expect(job).to(be_a(ManageIQ::Providers::TerraformTemplateWorkflow))
        expect(job.options[:credentials]).to(eq([{:access_key => :some_key}]))

        expect(job.options[:input_vars]).to(eq({}))
      end

      it "accepts inputs_vars & credentials to run template against" do
        job = template.run(:input_vars => {:some_key => :some_value}, :credentials => [{:access_key => :some_key}])

        expect(job).to(be_a(ManageIQ::Providers::TerraformTemplateWorkflow))
        expect(job.options[:input_vars]).to(eq(:some_key => :some_value))
        expect(job.options[:credentials]).to(eq([{:access_key => :some_key}]))
      end

      it "passes execution_ttl to the job as its timeout" do
        pending "Fix later, not passed to terraform-runner yet .."

        job = template.run(:execution_ttl => "5")

        expect(job).to(be_a(ManageIQ::Providers::TerraformTemplateWorkflow))
        expect(job.options[:timeout]).to(eq(5.minutes))

        expect(job.options[:input_vars]).to(eq({}))
      end
    end
  end
end
