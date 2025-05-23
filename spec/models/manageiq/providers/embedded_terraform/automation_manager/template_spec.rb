RSpec.describe ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Template do
  let(:template) { FactoryBot.create(:terraform_template) }
  let(:env_vars)    { {} }
  let(:credentials) { [] }
  let(:terraform_stack_id) { '999-999-999-999' }

  let(:provision_options) do
    {
      :env         => env_vars,
      :credentials => credentials
    }
  end
  let(:retirement_options) do
    {
      :env                => env_vars,
      :credentials        => credentials,
      :action             => ResourceAction::RETIREMENT,
      :terraform_stack_id => terraform_stack_id
    }
  end

  describe "#run" do
    it "run template for a provision job" do
      job = template.run(provision_options)

      expect(job).to have_attributes(
        :type    => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Job",
        :options => {
          :template_id        => template.id,
          :env_vars           => env_vars,
          :input_vars         => {},
          :credentials        => credentials,
          :poll_interval      => 60,
          :action             => ResourceAction::PROVISION,
          :terraform_stack_id => nil
        }
      )
    end

    it "run template for a retirement job" do
      job = template.run(retirement_options)
      expect(job).to have_attributes(
        :type    => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Job",
        :options => {
          :template_id        => template.id,
          :env_vars           => env_vars,
          :input_vars         => {},
          :credentials        => credentials,
          :poll_interval      => 60,
          :action             => ResourceAction::RETIREMENT,
          :terraform_stack_id => terraform_stack_id
        }
      )
    end
  end
end
