RSpec.describe ServiceTerraformTemplate do
  let(:terraform_stack_id) { "000-000-000-000" }

  let(:terraform_template) { FactoryBot.create(:terraform_template) }

  let(:service_options) do
    {
      :config_info => {
        :provision   => {
          :repository_id                   => 1,
          :execution_ttl                   => "",
          :log_output                      => "on_error",
          :verbosity                       => "0",
          :extra_vars                      => {},
          :configuration_script_payload_id => terraform_template.id,
          :dialog_id                       => 123,
          :fqname                          => ServiceTemplateTerraformTemplate.default_provisioning_entry_point
        },
        :reconfigure => {
          :repository_id                   => 1,
          :execution_ttl                   => "",
          :log_output                      => "on_error",
          :verbosity                       => "0",
          :extra_vars                      => {},
          :configuration_script_payload_id => terraform_template.id,
          :dialog_id                       => 123,
          :fqname                          => ServiceTemplateTerraformTemplate.default_reconfiguration_entry_point
        },
        :retirement  => {
          :repository_id                   => 1,
          :execution_ttl                   => "",
          :log_output                      => "on_error",
          :verbosity                       => "0",
          :extra_vars                      => {},
          :configuration_script_payload_id => terraform_template.id,
          :dialog_id                       => 123,
          :fqname                          => ServiceTemplateTerraformTemplate.default_retirement_entry_point
        }
      },
      :dialog      => {"dialog_name" => "World"},
    }
  end

  describe "#stack" do
    let!(:service) do
      FactoryBot.create(:service_terraform_template).tap do |s|
        s.add_resource!(stack1, :name => ResourceAction::PROVISION)
        s.add_resource!(stack2, :name => ResourceAction::RECONFIGURE)
        s.add_resource!(stack3, :name => ResourceAction::RETIREMENT)
      end
    end

    let(:stack1) { FactoryBot.create(:terraform_stack) }
    let(:stack2) { FactoryBot.create(:terraform_stack) }
    let(:stack3) { FactoryBot.create(:terraform_stack) }

    it "returns the associated orchestration_stack" do
      expect(service.stack(ResourceAction::PROVISION)).to eq(stack1)
      expect(service.stack(ResourceAction::RECONFIGURE)).to eq(stack2)
      expect(service.stack(ResourceAction::RETIREMENT)).to eq(stack3)
    end
  end

  describe "#preprocess" do
    context "with ResourceAction::PROVISION" do
      let!(:service) { FactoryBot.create(:service_terraform_template, :options => service_options) }

      it "save job_options for Provision action" do
        service.preprocess(ResourceAction::PROVISION, {})

        expect(service.options[:provision_job_options]).to eq({
                                                                "execution_ttl" => "",
                                                                "extra_vars"    => {},
                                                                "verbosity"     => "0",
                                                                "input_vars"    => {
                                                                  "name" => "World"
                                                                },
                                                                "credentials"   => []
                                                              })
      end
    end

    context "with ResourceAction::RECONFIGURE" do
      let!(:service) do
        FactoryBot.create(:service_terraform_template, :options => service_options).tap do |s|
          s.add_resource!(stack, :name => ResourceAction::PROVISION)
          s.options.store(
            :provision_job_options, {"execution_ttl"          => "",
                                     "extra_vars"             => {},
                                     "verbosity"              => "0",
                                     "input_vars"             => {
                                       "name" => "World"
                                     },
                                     "credentials"            => [],
                                     "terraform_stack_id"     => terraform_stack_id,
                                     "orchestration_stack_id" => stack.id}
          )
        end
      end

      let(:stack) { FactoryBot.create(:terraform_stack, :miq_task => miq_task) }
      let(:miq_task) { FactoryBot.create(:miq_task, :job => job) }
      let(:job) do
        FactoryBot.create(:embedded_terraform_job).tap do |j|
          j.options = {
            :terraform_stack_id => terraform_stack_id,
            :input_vars         => {
              :extra_vars => {},
              :input_vars => {
                "name" => "World"
              }
            }
          }
        end
      end

      let(:update_opts) do
        {
          :dialog => {
            "dialog_name"      => "New World",
            "request"          => "service_reconfigure",
            "Service::service" => service.id,
          },
        }
      end

      it "save job_options for Reconfigure action with update_options" do
        service.preprocess(ResourceAction::RECONFIGURE, update_opts)

        expect(service.options[:reconfigure_job_options]).to eq({
                                                                  "execution_ttl"      => "",
                                                                  "extra_vars"         => {},
                                                                  "verbosity"          => "0",
                                                                  "input_vars"         => {
                                                                    "name" => "New World"
                                                                  },
                                                                  "credentials"        => [],
                                                                  "terraform_stack_id" => terraform_stack_id,
                                                                })
      end
    end

    context "with ResourceAction::RETIREMENT, when provisioned & reconfigured" do
      let!(:service) do
        FactoryBot.create(:service_terraform_template, :options => service_options).tap do |s|
          s.add_resource!(stack1, :name => ResourceAction::PROVISION)
          s.add_resource!(stack2, :name => ResourceAction::RECONFIGURE)

          s.options[:provision_job_options] = {
            :execution_ttl          => "",
            :extra_vars             => {},
            :verbosity              => "0",
            :input_vars             => {
              "name" => "World"
            },
            :credentials            => [],
            :terraform_stack_id     => terraform_stack_id,
            :orchestration_stack_id => stack1.id
          }
          s.options[:reconfigure_job_options] = {
            :execution_ttl          => "",
            :extra_vars             => {},
            :verbosity              => "0",
            :input_vars             => {
              "name" => "New World"
            },
            :credentials            => [],
            :terraform_stack_id     => terraform_stack_id,
            :orchestration_stack_id => stack2.id
          }
        end
      end

      let(:stack1) { FactoryBot.create(:terraform_stack, :miq_task => miq_task1) }
      let(:miq_task1) { FactoryBot.create(:miq_task, :job => job1) }
      let(:job1) do
        FactoryBot.create(:embedded_terraform_job).tap do |j|
          j.options = {
            :terraform_stack_id => terraform_stack_id,
            :input_vars         => {
              :extra_vars => {},
              :input_vars => {
                "name" => "World"
              }
            }
          }
        end
      end

      let(:stack2) { FactoryBot.create(:terraform_stack, :miq_task => miq_task2) }
      let(:miq_task2) { FactoryBot.create(:miq_task, :job => job2) }
      let(:job2) do
        FactoryBot.create(:embedded_terraform_job).tap do |j|
          j.options = {
            :terraform_stack_id => terraform_stack_id,
            :input_vars         => {
              :extra_vars => {},
              :input_vars => {
                "name" => "New World"
              }
            }
          }
        end
      end

      it "save job_options for Retirement action" do
        service.preprocess(ResourceAction::RETIREMENT, {})

        expect(service.options[:retirement_job_options]).to eq({
                                                                 "execution_ttl"      => "",
                                                                 "extra_vars"         => {},
                                                                 "verbosity"          => "0",
                                                                 "input_vars"         => {
                                                                   "name" => "New World"
                                                                 },
                                                                 "credentials"        => [],
                                                                 "terraform_stack_id" => terraform_stack_id,
                                                               })
      end
    end

    context "with ResourceAction::RETIREMENT, when provisioned but not reconfigured" do
      let!(:service) do
        FactoryBot.create(:service_terraform_template, :options => service_options).tap do |s|
          s.add_resource!(stack, :name => ResourceAction::PROVISION)
          s.options[:provision_job_options] = {
            :execution_ttl          => "",
            :extra_vars             => {},
            :verbosity              => "0",
            :input_vars             => {
              "name" => "World"
            },
            :credentials            => [],
            :terraform_stack_id     => terraform_stack_id,
            :orchestration_stack_id => stack.id
          }
        end
      end

      let(:stack) { FactoryBot.create(:terraform_stack, :miq_task => miq_task) }
      let(:miq_task) { FactoryBot.create(:miq_task, :job => job) }
      let(:job) do
        FactoryBot.create(:embedded_terraform_job).tap do |j|
          j.options = {
            :terraform_stack_id => terraform_stack_id,
            :input_vars         => {
              :extra_vars => {},
              :input_vars => {
                "name" => "World"
              }
            }
          }
        end
      end

      it "save job_options for Retirement action" do
        service.preprocess(ResourceAction::RETIREMENT, {})

        expect(service.options[:retirement_job_options]).to eq({
                                                                 "execution_ttl"      => "",
                                                                 "extra_vars"         => {},
                                                                 "verbosity"          => "0",
                                                                 "input_vars"         => {
                                                                   "name" => "World"
                                                                 },
                                                                 "credentials"        => [],
                                                                 "terraform_stack_id" => terraform_stack_id,
                                                               })
      end
    end
  end

  describe "#execute" do
    [
      ResourceAction::PROVISION,
      ResourceAction::RECONFIGURE,
      ResourceAction::RETIREMENT
    ].each do |action|
      describe "with #{action} action" do
        let!(:service) do
          FactoryBot.create(:service_terraform_template).tap do |s|
            s.add_resource!(stack1, :name => ResourceAction::PROVISION)
            case action
            when ResourceAction::RECONFIGURE
              s.add_resource!(stack2, :name => ResourceAction::RECONFIGURE)
            when ResourceAction::RETIREMENT
              s.add_resource!(stack2, :name => ResourceAction::RECONFIGURE)
              s.add_resource!(stack3, :name => ResourceAction::RETIREMENT)
            end
          end
        end

        let(:stack1) { FactoryBot.create(:terraform_stack, :miq_task => miq_task) }
        let(:stack2) { FactoryBot.create(:terraform_stack, :miq_task => miq_task) }
        let(:stack3) { FactoryBot.create(:terraform_stack, :miq_task => miq_task) }

        let(:task_opts) do
          {
            :action => "Launching Terraform Template",
            :userid => "system"
          }
        end

        let(:queue_opts) do
          {
            :args        => [action],
            :class_name  => described_class.name,
            :instance_id => service.id,
            :method_name => "launch_terraform_template",
            :role        => "embedded_terraform",
            :zone        => service.my_zone
          }
        end

        context "creates a task" do
          let(:miq_task) { FactoryBot.create(:miq_task, :state => "Running", :status => "Ok", :message => "process initiated") }

          it "creates task" do
            expect(MiqTask).to receive(:generic_action_with_callback).with(task_opts, queue_opts).and_return(miq_task.id)
            expect(MiqTask).to receive(:wait_for_taskid).with(miq_task.id).and_return(miq_task)

            service.execute(action)
          end
        end
      end
    end
  end

  describe "#execute_async" do
    [
      ResourceAction::PROVISION,
      ResourceAction::RECONFIGURE,
      ResourceAction::RETIREMENT
    ].each do |action|
      describe "with #{action} action" do
        let!(:service) do
          FactoryBot.create(:service_terraform_template).tap do |s|
            s.add_resource!(stack1, :name => ResourceAction::PROVISION)
            case action
            when ResourceAction::RECONFIGURE
              s.add_resource!(stack2, :name => ResourceAction::RECONFIGURE)
            when ResourceAction::RETIREMENT
              s.add_resource!(stack2, :name => ResourceAction::RECONFIGURE)
              s.add_resource!(stack3, :name => ResourceAction::RETIREMENT)
            end
          end
        end

        let(:stack1) { FactoryBot.create(:terraform_stack, :miq_task => miq_task) }
        let(:stack2) { FactoryBot.create(:terraform_stack, :miq_task => miq_task) }
        let(:stack3) { FactoryBot.create(:terraform_stack, :miq_task => miq_task) }

        let(:task_opts) do
          {
            :action => "Launching Terraform Template",
            :userid => "system"
          }
        end

        let(:queue_opts) do
          {
            :args        => [action],
            :class_name  => described_class.name,
            :instance_id => service.id,
            :method_name => "launch_terraform_template",
            :role        => "embedded_terraform",
            :zone        => service.my_zone
          }
        end

        context "creates a task" do
          let(:miq_task) { FactoryBot.create(:miq_task, :state => "Running", :status => "Ok", :message => "process initiated") }

          it "creates task" do
            expect(MiqTask).to receive(:generic_action_with_callback).with(task_opts, queue_opts).and_return(miq_task.id)
            expect(MiqTask).not_to receive(:wait_for_taskid)

            expect(service.execute_async(action)).to eq(miq_task.id)
          end
        end
      end
    end
  end

  describe "#check_completed" do
    [
      ResourceAction::PROVISION,
      ResourceAction::RECONFIGURE,
      ResourceAction::RETIREMENT
    ].each do |action|
      describe "with #{action} action" do
        let!(:service) do
          FactoryBot.create(:service_terraform_template).tap do |s|
            s.add_resource!(stack1, :name => ResourceAction::PROVISION)
            case action
            when ResourceAction::RECONFIGURE
              s.add_resource!(stack2, :name => ResourceAction::RECONFIGURE)
            when ResourceAction::RETIREMENT
              s.add_resource!(stack2, :name => ResourceAction::RECONFIGURE)
              s.add_resource!(stack3, :name => ResourceAction::RETIREMENT)
            end
          end
        end
        let(:stack1) { FactoryBot.create(:terraform_stack, :miq_task => miq_task) }
        let(:stack2) { FactoryBot.create(:terraform_stack, :miq_task => miq_task) }
        let(:stack3) { FactoryBot.create(:terraform_stack, :miq_task => miq_task) }

        context "with a running process" do
          let(:miq_task) { FactoryBot.create(:miq_task, :state => "Running", :status => "Ok", :message => "process initiated") }

          it "returns not done" do
            done, _message = service.check_completed(action)
            expect(done).to be_falsey
          end
        end

        context "with a successful process" do
          let(:miq_task) { FactoryBot.create(:miq_task, :state => "Finished", :status => "Ok", :message => "Task completed successfully") }

          it "returns done" do
            done, _message = service.check_completed(action)
            expect(done).to be_truthy
          end

          it "returns a nil message" do
            _done, message = service.check_completed(action)
            expect(message).to be_nil
          end
        end

        context "with a failed process" do
          let(:miq_task) { FactoryBot.create(:miq_task, :state => "Finished", :status => "Error", :message => "Failed to run template") }

          it "returns done" do
            done, _message = service.check_completed(action)
            expect(done).to be_truthy
          end

          it "returns the task message" do
            _done, message = service.check_completed(action)
            expect(message).to eq("Failed to run template")
          end
        end
      end
    end
  end

  describe "#postprocess" do
    context "with ResourceAction::PROVISION" do
      let!(:service) { FactoryBot.create(:service_terraform_template, :options => service_options) }

      it "service dialog options for Provision action" do
        service.postprocess(ResourceAction::PROVISION)
        expect(service.options[:dialog]).to eq({
                                                 "dialog_name" => "World"
                                               })
      end
    end

    context "with ResourceAction::RECONFIGURE" do
      let!(:service) do
        FactoryBot.create(:service_terraform_template).tap do |s|
          s.add_resource!(stack, :name => ResourceAction::RECONFIGURE)

          s.options[:reconfigure_job_options] = {
            :execution_ttl          => "",
            :extra_vars             => {},
            :verbosity              => "0",
            :input_vars             => {
              "name" => "New World"
            },
            :credentials            => [],
            :terraform_stack_id     => terraform_stack_id,
            :orchestration_stack_id => stack.id
          }
        end
      end

      let(:stack) { FactoryBot.create(:terraform_stack) }

      it "update service dialog options for Reconfigure action" do
        service.postprocess(ResourceAction::RECONFIGURE)

        expect(service.options[:dialog]).to eq({
                                                 "dialog_name" => "New World"
                                               })
      end
    end
  end
end
