RSpec.describe ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Retire do
  let(:ems) { FactoryBot.create(:embedded_automation_manager_terraform) }
  let(:template) { FactoryBot.create(:terraform_template, :manager => ems) }
  let(:stack) do
    FactoryBot.create(
      :terraform_stack,
      :ext_management_system        => ems,
      :configuration_script_payload => template
    )
  end

  describe ".base_model" do
    it "returns OrchestrationStackRetireTask" do
      expect(described_class.base_model).to eq(OrchestrationStackRetireTask)
    end
  end

  describe ".model_being_retired" do
    it "returns OrchestrationStack" do
      expect(described_class.model_being_retired).to eq(OrchestrationStack)
    end
  end

  describe "inheritance" do
    it "inherits from OrchestrationStackRetireTask" do
      expect(described_class.superclass).to eq(OrchestrationStackRetireTask)
    end
  end

  describe "task creation" do
    let(:request) do
      FactoryBot.create(
        :orchestration_stack_retire_request,
        :source => stack
      )
    end

    it "can be instantiated" do
      task = described_class.new(
        :source      => stack,
        :miq_request => request
      )

      expect(task).to be_a(described_class)
      expect(task.source).to eq(stack)
      expect(task.stack).to eq(stack)
    end
  end
end
