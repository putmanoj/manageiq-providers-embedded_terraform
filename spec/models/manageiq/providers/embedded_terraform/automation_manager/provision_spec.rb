describe ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Provision do
  let(:admin)        { FactoryBot.create(:user_admin) }
  let(:zone)         { EvmSpecHelper.local_miq_server.zone }
  let(:ems)          { FactoryBot.create(:embedded_automation_manager_terraform, :zone => zone) }
  let(:terraform_template) { FactoryBot.create(:terraform_template, :manager => ems) }
  let(:configuration_script) { FactoryBot.create(:configuration_script_embedded_terraform, :manager => ems, :parent => terraform_template) }
  let!(:service) { FactoryBot.create(:service_embedded_terraform) }
  let(:miq_request)  { FactoryBot.create(:miq_provision_request, :requester => admin, :source => configuration_script) }
  let(:options)      { {:source => [terraform_template.id, terraform_template.name]} }
  let(:miq_task_state) { MiqTask::STATE_ACTIVE }
  let(:miq_task_status) { MiqTask::STATUS_OK }
  let(:miq_task) { FactoryBot.create(:miq_task, :state => miq_task_state, :status => miq_task_status) }
  let(:new_stack) { FactoryBot.create(:terraform_stack, :ext_management_system => ems, :miq_task => miq_task) }
  let(:phase) { nil }
  let(:subject) do
    FactoryBot.create(
      :miq_provision_embedded_terraform,
      :userid       => admin.userid,
      :miq_request  => miq_request,
      :source       => configuration_script,
      :request_type => 'template',
      :state        => "pending",
      :status       => 'Ok',
      :options      => options,
      :phase        => phase
    )
  end
  let(:stack_options) { {:action => ResourceAction::PROVISION, :input_vars => {}, :credentials => []} }

  it ".my_role" do
    expect(subject.my_role).to eq("ems_operations")
  end

  it ".my_queue_name" do
    expect(subject.my_queue_name).to eq(ems.queue_name_for_ems_operations)
  end

  describe ".run_provision" do
    before do
      allow(Service).to receive(:find_by).and_return(service)
      allow(described_class.module_parent::Stack).to receive(:create_stack).with(terraform_template, stack_options).and_return(new_stack)
    end

    it "calls create_stack" do
      expect(described_class.module_parent::Stack).to receive(:create_stack)

      subject.run_provision
    end

    it "sets stack_id" do
      subject.run_provision

      expect(subject.reload.phase_context).to include(:stack_id => new_stack.id)
    end

    it "queues check_provisioned" do
      subject.instance_variable_set(:@stack, new_stack)
      allow(new_stack).to receive(:raw_status).and_return(new_stack.class.status_class.new(miq_task))

      subject.run_provision

      expect(subject.reload.phase).to eq("check_provisioned")
    end

    context "when create_stack fails" do
      before do
        expect(described_class.module_parent::Stack).to receive(:create_stack).and_raise
      end

      it "marks the job as failed" do
        subject.run_provision

        expect(subject.reload).to have_attributes(:state => "finished", :status => "Error")
      end
    end
  end

  describe "check_provisioned" do
    let(:phase) { "check_provisioned" }

    before do
      allow(new_stack).to receive(:raw_status).and_return(new_stack.class.status_class.new(miq_task))
      subject.instance_variable_set(:@stack, new_stack)
      subject.phase_context[:stack_id] = new_stack.id
    end

    context "when the plan is still running" do
      let(:miq_task_state) { MiqTask::STATE_ACTIVE }
      let(:miq_task_status) { MiqTask::STATUS_OK }

      it "requeues check_provisioned" do
        subject.check_provisioned

        expect(subject.reload).to have_attributes(
          :phase  => "check_provisioned",
          :state  => "pending",
          :status => "Ok"
        )
      end
    end

    context "when the plan is finished" do
      let(:miq_task_state) { MiqTask::STATE_FINISHED }
      let(:miq_task_status) { MiqTask::STATUS_OK }

      it "finishes the job" do
        subject.check_provisioned

        expect(subject.reload).to have_attributes(
          :phase  => "finish",
          :state  => "finished",
          :status => "Ok"
        )
      end
    end

    context "when the plan is errored" do
      let(:miq_task_state) { MiqTask::STATE_FINISHED }
      let(:miq_task_status) { MiqTask::STATUS_ERROR }

      it "finishes the job" do
        subject.phase_context[:stack_id] = new_stack.id
        subject.check_provisioned

        expect(subject.reload).to have_attributes(
          :phase  => "finish",
          :state  => "finished",
          :status => "Error"
        )
      end
    end
  end
end
