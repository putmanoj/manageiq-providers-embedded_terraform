module ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Retire::StateMachine
  extend ActiveSupport::Concern

  # If the Terraform::Runner isn't available then don't start the retirement process
  def run_retire
    return requeue_phase unless Terraform::Runner.available?

    signal :start_retirement
  end

  def remove_from_provider
    super
  rescue Terraform::Runner::TemporarilyUnavailable
    requeue_phase
  end
end
