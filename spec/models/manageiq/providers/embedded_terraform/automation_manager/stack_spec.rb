RSpec.describe ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Stack do
  describe "#raw_status" do
    let(:stack) { FactoryBot.create(:terraform_stack, :miq_task => miq_task) }

    context "with a running deployment" do
      let(:miq_task) { FactoryBot.create(:miq_task, :state => "Running", :status => "Ok", :message => "process initiated") }

      it "returns a status that is running" do
        expect(stack.raw_status.completed?).to be_falsey
      end
    end

    context "with a successful deployment" do
      let(:miq_task) { FactoryBot.create(:miq_task, :state => "Finished", :status => "Ok", :message => "Task completed successfully") }

      it "returns a status that is completed" do
        expect(stack.raw_status.completed?).to be_truthy
      end
    end

    context "with a failed deployment" do
      let(:miq_task) { FactoryBot.create(:miq_task, :state => "Finished", :status => "Error", :message => "Failed to run template") }

      it "returns a status that is failed" do
        expect(stack.raw_status.failed?).to be_truthy
      end

      it "returns a normalized_status with a reason" do
        expect(stack.raw_status.normalized_status).to eq(["failed", "Failed to run template"])
      end
    end
  end

  describe "#raw_stdout" do
    let(:stack) { FactoryBot.create(:terraform_stack, :miq_task => miq_task) }
    let(:template) { FactoryBot.create(:terraform_template) }

    context "when miq_task.job present" do
      let(:terraform_runner_url) { "https://1.2.3.4:7000" }
      let(:hello_world_retrieve_response) do
        require 'json'
        JSON.parse(File.read(File.join(__dir__, "../../../../../lib/terraform/runner/data/responses/hello-world-retrieve-create-success.json")))
      end
      let(:miq_task) { FactoryBot.create(:miq_task, :job => job) }

      let(:job) { FactoryBot.create(:embedded_terraform_job, :state => "finished", :options => {:terraform_stack_id => hello_world_retrieve_response['stack_id']}) }
      let(:terraform_runner_stdout) { hello_world_retrieve_response['message'] }
      let(:terraform_runner_stdout_html) { TerminalToHtml.render(terraform_runner_stdout) }

      before do
        stub_const("ENV", ENV.to_h.merge("TERRAFORM_RUNNER_URL" => terraform_runner_url))

        stub_request(:post, "#{terraform_runner_url}/api/stack/retrieve")
          .with(:body => hash_including({:stack_id => hello_world_retrieve_response['stack_id']}))
          .to_return(
            :status => 200,
            :body   => hello_world_retrieve_response.to_json
          )
      end

      it "json" do
        expect(stack.raw_stdout("json")).to eq terraform_runner_stdout
      end

      it "txt" do
        expect(stack.raw_stdout("txt")).to eq terraform_runner_stdout
      end

      it "html" do
        expect(stack.raw_stdout("html")).to eq terraform_runner_stdout_html
      end

      it "nil" do
        expect(stack.raw_stdout).to eq terraform_runner_stdout
      end
    end

    shared_examples_for "terraform runner stdout not available from miq_task" do
      it "json" do
        expect(stack.raw_stdout("json")).to be_nil
      end

      it "txt" do
        expect(stack.raw_stdout("txt")).to be_nil
      end

      it "html" do
        expect(stack.raw_stdout("html")).to include <<~EOHTML
          <div class='term-container'>
          No output available
          </div>
        EOHTML
      end

      it "nil" do
        expect(stack.raw_stdout).to be_nil
      end
    end

    context "when miq_task is missing" do
      let(:miq_task) { nil }

      it_behaves_like "terraform runner stdout not available from miq_task"
    end

    context "when miq_task present, but missing miq_task.job" do
      let(:miq_task) { FactoryBot.create(:miq_task, :job => nil) }

      it_behaves_like "terraform runner stdout not available from miq_task"
    end

    context "when miq_task.job.options present but missing terraform_stack_id" do
      let(:job)      { FactoryBot.create(:embedded_terraform_job) }
      let(:miq_task) { FactoryBot.create(:miq_task, :job => job) }

      it_behaves_like "terraform runner stdout not available from miq_task"
    end
  end

  describe "#raw_stdout_via_worker" do
    let(:stack) { FactoryBot.create(:terraform_stack) }

    context "when embedded_terraform role is enabled" do
      before do
        EmbeddedTerraformEvmSpecHelper.assign_embedded_terraform_role

        allow_any_instance_of(ManageIQ::Providers::EmbeddedTerraform::AutomationManager::ConfigurationScriptSource).to receive(:checkout_git_repository)
      end

      describe "#raw_stdout_via_worker with no errors" do
        before do
          EvmSpecHelper.local_miq_server
          allow(described_class).to receive(:find).and_return(stack)

          allow(MiqTask).to receive(:wait_for_taskid) do
            request = MiqQueue.find_by(:class_name => described_class.name)
            request.update(:state => MiqQueue::STATE_DEQUEUE)
            request.deliver_and_process
          end
        end

        it "gets stdout from the job" do
          expect(stack).to receive(:raw_stdout).and_return("A stdout from the job")
          taskid = stack.raw_stdout_via_worker("user")
          MiqTask.wait_for_taskid(taskid)
          expect(MiqTask.find(taskid)).to have_attributes(
            :task_results => "A stdout from the job",
            :status       => "Ok"
          )
        end

        it "returns the error message" do
          expect(stack).to receive(:raw_stdout).and_throw("Failed to get stdout from the job")
          taskid = stack.raw_stdout_via_worker("user")
          MiqTask.wait_for_taskid(taskid)
          expect(MiqTask.find(taskid).message).to include("Failed to get stdout from the job")
          expect(MiqTask.find(taskid).status).to eq("Error")
        end
      end
    end

    context "when embedded_terraform role is disabled" do
      describe "#raw_stdout_via_worker return error" do
        let(:role_enabled) { false }

        it "returns an error message" do
          taskid = stack.raw_stdout_via_worker("user")
          expect(MiqTask.find(taskid)).to have_attributes(
            :message => "Cannot get standard output of this terraform-template because the embedded terraform role is not enabled",
            :status  => "Error"
          )
        end
      end
    end

    describe "#raw_delete_stack" do
      let(:stack) { FactoryBot.create(:terraform_stack) }
      let(:terraform_template) { FactoryBot.create(:terraform_template) }
      let(:delete_job) { FactoryBot.create(:embedded_terraform_job) }

      before do
        allow(stack).to receive(:configuration_script_payload).and_return(terraform_template)
      end

      context "when service_resource is nil" do
        before do
          allow(stack).to receive(:service_resource).and_return(nil)
        end

        it "raises an error" do
          expect { stack.raw_delete_stack }.to raise_error(
            MiqException::Error,
            /Cannot delete stack, service_resource not found for stack:/
          )
        end
      end

      context "when service_resource.options is blank" do
        let(:service_resource) { double("ServiceResource", :options => nil) }

        before do
          allow(stack).to receive(:service_resource).and_return(service_resource)
        end

        it "raises an error" do
          expect { stack.raw_delete_stack }.to raise_error(
            MiqException::Error,
            /Cannot delete stack, service_resource.options is empty for stack:/
          )
        end
      end

      context "when terraform_runner_stack_id is missing" do
        let(:service_resource) { double("ServiceResource", :options => {"other_key" => "value"}) }

        before do
          allow(stack).to receive(:service_resource).and_return(service_resource)
        end

        it "raises an error" do
          expect { stack.raw_delete_stack }.to raise_error(
            MiqException::MiqOrchestrationProvisionError,
            /Cannot delete stack, did not find terraform_runner_stack_id for stack:/
          )
        end
      end

      context "when configuration_script_payload is nil" do
        let(:service_resource) do
          double("ServiceResource", :options => {"terraform_runner_stack_id" => "stack-123"})
        end

        before do
          allow(stack).to receive(:service_resource).and_return(service_resource)
          allow(stack).to receive(:configuration_script_payload).and_return(nil)
        end

        it "raises an error" do
          expect { stack.raw_delete_stack }.to raise_error(
            MiqException::Error,
            /Cannot delete stack, configuration script payload not found for stack:/
          )
        end
      end

      context "when all required data is present" do
        let(:service_resource) do
          double("ServiceResource", :options => {
                   "terraform_runner_stack_id" => "stack-123",
                   "input_vars"                => {"key" => "value"},
                   "credentials"               => [999]
                 })
        end

        before do
          allow(stack).to receive(:service_resource).and_return(service_resource)
          allow(terraform_template).to receive(:run).and_return(delete_job)
        end

        it "creates a delete job with correct options" do
          expected_options = {
            :input_vars         => {"key" => "value"},
            :credentials        => [999],
            :action             => ResourceAction::RETIREMENT,
            :terraform_stack_id => "stack-123"
          }

          expect(terraform_template).to receive(:run).with(expected_options).and_return(delete_job)
          result = stack.raw_delete_stack
          expect(result).to eq(delete_job)
        end

        it "returns the delete job" do
          result = stack.raw_delete_stack
          expect(result).to eq(delete_job)
        end
      end

      context "when an unexpected error occurs" do
        let(:service_resource) do
          double("ServiceResource", :options => {"terraform_runner_stack_id" => "stack-123"})
        end

        before do
          allow(stack).to receive(:service_resource).and_return(service_resource)
          allow(terraform_template).to receive(:run).and_raise(StandardError, "Unexpected error")
        end

        it "raises MiqOrchestrationProvisionError" do
          expect { stack.raw_delete_stack }.to raise_error(
            MiqException::MiqOrchestrationProvisionError,
            /Unexpected error/
          )
        end
      end
    end
  end
end
