RSpec.describe ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Job do
  let(:terraform_template_payload) do
    {
      :input_vars    => [{"name" => "name", "label" => "name", "type" => "string", "description" => "", "required" => true, "secured" => false, "hidden" => false, "immutable" => false}],
      :relative_path => "terraform/templates/aws-instance-ec2-nano",
    }
  end
  let(:template) { FactoryBot.create(:terraform_template, :payload => terraform_template_payload.to_json) }
  let(:git_checkout_tempdir) { "/tmp" }
  let(:job) do
    described_class.create_job(template, env_vars, input_vars, credentials).tap do |job|
      job.state = state
      job.options.store(:git_checkout_tempdir, git_checkout_tempdir)
    end
  end
  let(:state)       { "waiting_to_start" }
  let(:env_vars)    { {} }
  let(:input_vars)  do
    {
      "name" => "stack123"
    }
  end
  let(:job_vars) do
    {
      :execution_ttl => "",
      :verbosity     => "0",
      :input_vars    => input_vars
    }
  end
  let(:credentials) { [] }
  let(:terraform_stack_id) { '999-999-999-999' }

  describe ".create_job" do
    context "with Provision" do
      it "create a job" do
        expect(
          described_class.create_job(
            template, env_vars, job_vars, credentials, :action => ResourceAction::PROVISION, :terraform_stack_id => nil
          )
        ).to have_attributes(
          :type    => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Job",
          :options => {
            :template_id        => template.id,
            :env_vars           => env_vars,
            :job_vars           => job_vars,
            :credentials        => credentials,
            :poll_interval      => 60,
            :action             => ResourceAction::PROVISION,
            :terraform_stack_id => nil
          }
        )
      end
    end

    [
      ResourceAction::RECONFIGURE,
      ResourceAction::RETIREMENT
    ].each do |action|
      context "with #{action} action" do
        it "create a job" do
          expect(
            described_class.create_job(
              template, env_vars, job_vars, credentials, :action => action, :terraform_stack_id => terraform_stack_id
            )
          ).to have_attributes(
            :type    => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Job",
            :options => {
              :template_id        => template.id,
              :env_vars           => env_vars,
              :job_vars           => job_vars,
              :credentials        => credentials,
              :poll_interval      => 60,
              :action             => action,
              :terraform_stack_id => terraform_stack_id
            }
          )
        end
      end
    end
  end

  describe "#execute" do
    let(:template_path) { File.join(job.options[:git_checkout_tempdir], terraform_template_payload[:relative_path]) }

    context "with ResourceAction::PROVISION" do
      let(:job) do
        described_class.create_job(
          template, env_vars, job_vars, credentials, :action => ResourceAction::PROVISION, :terraform_stack_id => nil
        ).tap do |job|
          job.state = state
          job.options.store(:git_checkout_tempdir, git_checkout_tempdir)
        end
      end
      let(:response) { Terraform::Runner::ResponseAsync.new(terraform_stack_id, "1") }
      let(:action_type) { Terraform::Runner::ActionType::CREATE }
      let(:runner_options) do
        {
          :input_vars                  => input_vars,
          :input_vars_type_constraints => {"name" => terraform_template_payload.dig(:input_vars, 0)},
          :credentials                 => [],
          :env_vars                    => {}
        }
      end

      it "execute the job" do
        expect(Terraform::Runner).to receive(:run).with(action_type, template_path, runner_options).and_return(response)

        job.execute

        expect(job.options).to eq({
                                    :template_id            => template.id,
                                    :env_vars               => {},
                                    :job_vars               => job_vars,
                                    :credentials            => [],
                                    :poll_interval          => 1.minute,
                                    :action                 => ResourceAction::PROVISION,
                                    :terraform_stack_id     => response.stack_id,
                                    :git_checkout_tempdir   => git_checkout_tempdir,
                                    :terraform_stack_job_id => response.stack_job_id
                                  })
      end
    end

    [
      ResourceAction::RECONFIGURE,
      ResourceAction::RETIREMENT
    ].each do |action|
      context "with #{action}" do
        let(:job) do
          described_class.create_job(
            template, env_vars, job_vars, credentials, :action => action, :terraform_stack_id => terraform_stack_id
          ).tap do |job|
            job.state = state
            job.options.store(:git_checkout_tempdir, git_checkout_tempdir)
          end
        end
        let(:response) do
          stack_job_id = case action
                         when ResourceAction::RECONFIGURE
                           "2"
                         when ResourceAction::RETIREMENT
                           "3"
                         end
          Terraform::Runner::ResponseAsync.new(terraform_stack_id, stack_job_id)
        end
        let(:action_type) do
          case action
          when ResourceAction::RECONFIGURE
            Terraform::Runner::ActionType::APPLY
          when ResourceAction::RETIREMENT
            Terraform::Runner::ActionType::DELETE
          end
        end
        let(:runner_options) do
          {
            :input_vars                  => input_vars,
            :input_vars_type_constraints => {"name" => terraform_template_payload.dig(:input_vars, 0)},
            :credentials                 => [],
            :env_vars                    => {},
            :stack_id                    => terraform_stack_id
          }
        end

        it "execute the job" do
          expect(Terraform::Runner).to receive(:run).with(action_type, template_path, runner_options).and_return(response)

          job.execute

          expect(job.options).to eq({
                                      :template_id            => template.id,
                                      :env_vars               => {},
                                      :job_vars               => job_vars,
                                      :credentials            => [],
                                      :poll_interval          => 1.minute,
                                      :action                 => action,
                                      :terraform_stack_id     => response.stack_id,
                                      :git_checkout_tempdir   => git_checkout_tempdir,
                                      :terraform_stack_job_id => response.stack_job_id
                                    })
        end
      end
    end
  end

  describe "#signal" do
    %w[start pre_execute execute poll_runner post_execute finish abort_job cancel error].each do |signal|
      shared_examples_for "allows #{signal} signal" do
        it signal.to_s do
          expect(job).to receive(signal.to_sym)
          job.signal(signal.to_sym)
        end
      end
      shared_examples_for "doesn't allow #{signal} signal" do
        it signal.to_s do
          expect { job.signal(signal.to_sym) }.to raise_error(RuntimeError, /#{signal} is not permitted at state #{job.state}/)
        end
      end
    end

    context "waiting_to_start" do
      let(:state) { "waiting_to_start" }

      it_behaves_like "allows start signal"
      it_behaves_like "doesn't allow pre_execute signal"
      it_behaves_like "doesn't allow execute signal"
      it_behaves_like "doesn't allow poll_runner signal"
      it_behaves_like "doesn't allow post_execute signal"
      it_behaves_like "allows finish signal"
      it_behaves_like "allows abort_job signal"
      it_behaves_like "allows cancel signal"
      it_behaves_like "allows error signal"
    end

    context "pre_execute" do
      let(:state) { "pre_execute" }

      it_behaves_like "doesn't allow start signal"
      it_behaves_like "allows pre_execute signal"
      it_behaves_like "doesn't allow execute signal"
      it_behaves_like "doesn't allow poll_runner signal"
      it_behaves_like "doesn't allow post_execute signal"
      it_behaves_like "allows finish signal"
      it_behaves_like "allows abort_job signal"
      it_behaves_like "allows cancel signal"
      it_behaves_like "allows error signal"
    end

    context "running" do
      let(:state) { "running" }

      it_behaves_like "doesn't allow start signal"
      it_behaves_like "doesn't allow pre_execute signal"
      it_behaves_like "doesn't allow execute signal"
      it_behaves_like "allows poll_runner signal"
      it_behaves_like "allows post_execute signal"
      it_behaves_like "allows finish signal"
      it_behaves_like "allows abort_job signal"
      it_behaves_like "allows cancel signal"
      it_behaves_like "allows error signal"
    end

    context "post_execute" do
      let(:state) { "post_execute" }

      it_behaves_like "doesn't allow start signal"
      it_behaves_like "doesn't allow pre_execute signal"
      it_behaves_like "doesn't allow execute signal"
      it_behaves_like "doesn't allow poll_runner signal"
      it_behaves_like "doesn't allow post_execute signal"
      it_behaves_like "allows finish signal"
      it_behaves_like "allows abort_job signal"
      it_behaves_like "allows cancel signal"
      it_behaves_like "allows error signal"
    end

    context "finished" do
      let(:state) { "finished" }

      it_behaves_like "doesn't allow start signal"
      it_behaves_like "doesn't allow pre_execute signal"
      it_behaves_like "doesn't allow execute signal"
      it_behaves_like "doesn't allow poll_runner signal"
      it_behaves_like "doesn't allow post_execute signal"
      it_behaves_like "allows finish signal"
      it_behaves_like "allows abort_job signal"
      it_behaves_like "allows cancel signal"
      it_behaves_like "allows error signal"
    end
  end

  describe "#start" do
    it "moves to state pre_execute" do
      job.signal(:start)
      expect(job.reload.state).to eq("pre_execute")
    end
  end

  describe "#poll_runner" do
    let(:state) { "running" }

    context "still running" do
      before { expect(job).to receive(:running?).and_return(true) }

      it "requeues poll_runner" do
        job.signal(:poll_runner)
        expect(job.reload.state).to eq("running")
      end
    end

    context "completed" do
      before { expect(job).to receive(:running?).and_return(false) }

      it "moves to state finished" do
        job.signal(:poll_runner)
        expect(job.reload.state).to eq("finished")
      end
    end
  end
end
