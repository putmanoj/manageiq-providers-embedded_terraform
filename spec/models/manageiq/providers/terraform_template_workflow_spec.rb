RSpec.describe(ManageIQ::Providers::TerraformTemplateWorkflow) do
  let(:job)     { described_class.create_job(*options, **job_kwargs).tap { |job| job.state = state } }
  let(:options) { [{"some_key" => "some_value"}, {:template_path => "/path/to/template"}, [{"access_key" => "some_key"}]] }
  let(:job_kwargs) { {:timeout => 2.hours} }
  let(:state)      { "waiting_to_start" }

  context ".create_job" do
    it "leaves job waiting to start" do
      expect(job.state).to(eq("waiting_to_start"))
    end
  end

  context "#signal" do
    %w[start pre_execute execute poll_runner post_execute finish abort_job cancel error].each do |signal|
      shared_examples_for "allows #{signal} signal" do
        it signal.to_s do
          expect(job).to(receive(signal.to_sym))
          job.signal(signal.to_sym)
        end
      end
    end

    %w[start pre_execute execute poll_runner post_execute].each do |signal|
      shared_examples_for "doesn't allow #{signal} signal" do
        it signal.to_s do
          expect { job.signal(signal.to_sym) }.to(raise_error(RuntimeError, /#{signal} is not permitted at state #{job.state}/))
        end
      end
    end

    context "waiting_to_start" do
      let(:state) { "waiting_to_start" }

      it_behaves_like "allows start signal"
      it_behaves_like "allows finish signal"
      it_behaves_like "allows abort_job signal"
      it_behaves_like "allows cancel signal"
      it_behaves_like "allows error signal"

      it_behaves_like "doesn't allow pre_execute signal"
      it_behaves_like "doesn't allow execute signal"
      it_behaves_like "doesn't allow poll_runner signal"
      it_behaves_like "doesn't allow post_execute signal"
    end

    context "pre_execute" do
      let(:state) { "pre_execute" }

      it_behaves_like "allows pre_execute signal"
      it_behaves_like "allows finish signal"
      it_behaves_like "allows abort_job signal"
      it_behaves_like "allows cancel signal"
      it_behaves_like "allows error signal"

      it_behaves_like "doesn't allow start signal"
      it_behaves_like "doesn't allow execute signal"
      it_behaves_like "doesn't allow poll_runner signal"
      it_behaves_like "doesn't allow post_execute signal"
    end

    context "execute" do
      let(:state) { "execute" }

      it_behaves_like "allows execute signal"
      it_behaves_like "allows finish signal"
      it_behaves_like "allows abort_job signal"
      it_behaves_like "allows cancel signal"
      it_behaves_like "allows error signal"

      it_behaves_like "doesn't allow start signal"
      it_behaves_like "doesn't allow pre_execute signal"
      it_behaves_like "doesn't allow poll_runner signal"
      it_behaves_like "doesn't allow post_execute signal"
    end

    context "running" do
      let(:state) { "running" }

      it_behaves_like "allows poll_runner signal"
      it_behaves_like "allows finish signal"
      it_behaves_like "allows abort_job signal"
      it_behaves_like "allows cancel signal"
      it_behaves_like "allows error signal"

      it_behaves_like "doesn't allow start signal"
      it_behaves_like "doesn't allow pre_execute signal"
    end

    context "post_execute" do
      let(:state) { "post_execute" }

      it_behaves_like "allows finish signal"
      it_behaves_like "allows abort_job signal"
      it_behaves_like "allows cancel signal"
      it_behaves_like "allows error signal"

      it_behaves_like "doesn't allow start signal"
      it_behaves_like "doesn't allow pre_execute signal"
      it_behaves_like "doesn't allow execute signal"
      it_behaves_like "doesn't allow poll_runner signal"
      it_behaves_like "doesn't allow post_execute signal"
    end
  end

  context "#pre_execute" do
    let(:state) { "pre_execute" }
    let(:css)   { FactoryBot.create(:embedded_terraform_configuration_script_source) }
    let(:template_relative_path) { "path/to/template" }

    context "with template_path" do
      it "succeeds" do
        expect_any_instance_of(ManageIQ::Providers::EmbeddedTerraform::AutomationManager::ConfigurationScriptSource).to_not(receive(:checkout_git_repository))
        expect(job).to(receive(:queue_signal).with(:execute, :deliver_on => nil))

        job.signal(:pre_execute)

        expect(job.options[:template_path]).to(eq("/path/to/template"))
      end
    end

    context "with configuration_script_source_id + template_relative_path" do
      let(:options) { [{"some_key" => "some_value"}, {:configuration_script_source_id => css.id, :template_relative_path => "path/to/template"}, {:poll_interval => 5.minutes}] }

      it "will checkout the git repository to a temp dir before proceeding" do
        expect_any_instance_of(ManageIQ::Providers::EmbeddedTerraform::AutomationManager::ConfigurationScriptSource).to(receive(:checkout_git_repository))
        expect(job).to(receive(:queue_signal).with(:execute, :deliver_on => nil))

        job.signal(:pre_execute)

        expect(job.options[:template_path]).to(start_with(File.join(Dir.tmpdir, "terraform-runner-git")))
        expect(job.options[:template_path]).to(end_with(template_relative_path))
      end
    end

    context "with neither template_path nor a configuration_script_source_id, template_relative_path pair" do
      let(:options) { [{"some_key" => "some_value"}, {}, {:poll_interval => 5.minutes}] }

      it "fails" do
        expect(job).to_not(receive(:queue_signal).with(:execute))

        expect { job.signal(:pre_execute) }.to(raise_error(ArgumentError))
      end
    end

    context "with only configuration_script_source_id" do
      let(:options) { [{"some_key" => "some_value"}, {:configuration_script_source_id => css.id}, {:poll_interval => 5.minutes}] }

      it "fails" do
        expect(job).to_not(receive(:queue_signal).with(:execute))

        expect { job.signal(:pre_execute) }.to(raise_error(ArgumentError))
      end
    end

    context "with only playbook_relative_path" do
      let(:options) { [{"some_key" => "some_value"}, {:template_relative_path => "path/to/template"}, {:poll_interval => 5.minutes}] }

      it "fails" do
        expect(job).to_not(receive(:queue_signal).with(:execute))

        expect { job.signal(:pre_execute) }.to(raise_error(ArgumentError))
      end
    end
  end

  context "#execute" do
    let(:state) { "execute" }
    let(:css)   { FactoryBot.create(:embedded_terraform_configuration_script_source) }
    let(:response_async) { Terraform::Runner::ResponseAsync.new(:stack_id => "xxxx") }

    it "forwards the options to Terraform::Runner parameters" do
      runner_options = [
        {"some_key" => "some_value"},
        "/path/to/template",
        nil,
        [{"access_key" => "some_key"}]
      ]

      expect(Terraform::Runner).to(receive(:run_async).with(*runner_options).and_return(response_async))
      expect(job).to(receive(:queue_signal).with(:poll_runner, :deliver_on => nil))

      job.signal(:execute)
    end

    it "terraform-runner succeeds" do
      expect(Terraform::Runner).to(receive(:run_async).and_return(response_async))
      expect(job).to(receive(:queue_signal).with(:poll_runner, :deliver_on => nil))

      job.signal(:execute)

      expect(job.context[:terraform_runner_response]).to(eq(response_async.dump))
    end

    it "terraform-runner fails" do
      expect(Terraform::Runner).to(receive(:run_async).and_return(nil))
      expect(job).to(receive(:queue_signal).with(:abort, "Failed to run terraform template", "error", :deliver_on => nil))

      job.signal(:execute)
    end
  end

  context "#poll_runner" do
    let(:state)          { "running" }
    let(:response_async) { Terraform::Runner::ResponseAsync.new(:base_dir => "/path/to/results") }

    before do
      allow(Terraform::Runner::ResponseAsync).to(receive(:new).and_return(response_async))

      job.context[:terraform_runner_response] = response_async.dump
      job.started_on = Time.now.utc
      job.save!
    end

    it "terraform-runner completed" do
      expect(response_async).to(receive(:running?).and_return(false))

      response = Terraform::Runner::Response.new(:stack_id => "99999", **response_async.dump)
      expect(response_async).to(receive(:response).and_return(response))
      expect(job).to(receive(:queue_signal).with(:post_execute, :deliver_on => nil))

      job.signal(:poll_runner)
    end

    it "terraform-runner still running" do
      now = Time.now.utc
      allow(Time).to(receive(:now).and_return(now))
      expect(response_async).to(receive(:running?).and_return(true))
      # expect(job).to(receive(:queue_signal).with(:poll_runner, :deliver_on => now + 1.second))

      job.signal(:poll_runner)
    end

    it "fails if the template has been running too long" do
      time = job.started_on + job.options[:timeout] + 5.minutes

      Timecop.travel(time) do
        expect(response_async).to(receive(:running?).and_return(true))
        expect(response_async).to(receive(:stop))
        expect(job).to(receive(:queue_signal).with(:abort, "terraform template has been running longer than timeout", "error", :deliver_on => nil))

        job.signal(:poll_runner)
      end
    end

    context "deliver_on" do
      let(:options) { [{"some_key" => "some_value"}, {:template_path => "/path/to/template"}, [{"access_key" => "some_key"}]] }
      let(:job_kwargs) { {:poll_interval => 5.minutes} }
      it "uses the option to queue poll_runner" do
        now = Time.now.utc
        allow(Time).to receive(:now).and_return(now)
        expect(response_async).to receive(:running?).and_return(true)
        expect(job).to receive(:queue_signal).with(:poll_runner, :deliver_on => now + 5.minutes)

        job.signal(:poll_runner)
      end
    end
  end
end
