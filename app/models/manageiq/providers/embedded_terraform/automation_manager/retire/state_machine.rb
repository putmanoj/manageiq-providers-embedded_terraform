module ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Retire::StateMachine
  extend ActiveSupport::Concern

  # If the Terraform::Runner isn't available then don't start the retirement process
  def run_retire
    return terraform_runner_unavailable_requeue_phase unless Terraform::Runner.available?

    terraform_runner_available!

    signal :start_retirement
  end
end
