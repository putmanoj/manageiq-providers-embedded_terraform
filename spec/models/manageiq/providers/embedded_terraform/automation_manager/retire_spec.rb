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

  describe ".run_retire" do
    let(:request) do
      FactoryBot.create(
        :orchestration_stack_retire_request,
        :source => stack
      )
    end
    let(:subject) do
      described_class.create!(
        :source      => stack,
        :miq_request => request,
        :phase       => "run_retire",
        :state       => "pending",
        :status      => "Ok"
      )
    end

    context "when Terraform::Runner is available" do
      before do
        allow(Terraform::Runner).to receive(:available?).and_return(true)
      end

      it "signals start_retirement" do
        expect(subject).to receive(:signal).with(:start_retirement)
        subject.run_retire
      end
    end

    context "when Terraform::Runner is not available" do
      before do
        allow(Terraform::Runner).to receive(:available?).and_return(false)
        allow(subject).to receive(:requeue_phase)
      end

      it "requeues the phase" do
        expect(subject).to receive(:requeue_phase)
        subject.run_retire
      end

      it "tracks when runner became unavailable" do
        subject.run_retire

        expect(subject.phase_context[:terraform_runner_unavailable_since]).to be_present
        expect(subject.phase_context[:terraform_runner_unavailable_since]).to be_a(Time)
      end

      it "logs warning with elapsed time on subsequent requeues" do
        # First call - sets the unavailable timestamp
        subject.run_retire

        # Second call - should log elapsed time
        Timecop.freeze(Time.now.utc + 30.seconds) do
          expect(subject._log).to receive(:warn).with(/Terraform Runner is unavailable \(30s elapsed\), requeueing phase/)
          subject.run_retire
        end
      end

      context "when timeout is exceeded" do
        before do
          allow(subject).to receive(:requeue_phase)
        end

        it "raises MiqProvisionError after timeout period" do
          # Set unavailable timestamp to more than 10 minutes ago
          subject.phase_context[:terraform_runner_unavailable_since] = 11.minutes.ago.utc
          subject.save!

          expect(subject._log).to receive(:error).with(/Terraform Runner has been unavailable for \d+ seconds, exceeding timeout/)
          expect { subject.run_retire }.to raise_error(MiqException::MiqProvisionError, /exceeding timeout/)
        end

        it "includes timeout duration in error message" do
          subject.phase_context[:terraform_runner_unavailable_since] = 11.minutes.ago.utc
          subject.save!

          expect { subject.run_retire }.to raise_error(MiqException::MiqProvisionError, /600 seconds/)
        end
      end

      context "when timeout is not exceeded" do
        before do
          allow(subject).to receive(:requeue_phase)
        end

        it "continues to requeue when under timeout" do
          # Set unavailable timestamp to 5 minutes ago (under 10 minute timeout)
          subject.phase_context[:terraform_runner_unavailable_since] = 5.minutes.ago.utc
          subject.save!

          expect(subject).to receive(:requeue_phase)
          expect { subject.run_retire }.not_to raise_error
        end
      end
    end
  end
end
