module ManageIQ::Providers::EmbeddedTerraform::AutomationManager::TerraformRunnerMixin
  TERRAFORM_RUNNER_UNAVAILABLE_TIMEOUT = 10.minutes

  def terraform_runner_unavailable_requeue_phase
    # Track when the runner first became unavailable
    phase_context[:terraform_runner_unavailable_since] ||= Time.now.utc

    unavailable_duration = Time.now.utc - phase_context[:terraform_runner_unavailable_since]

    if unavailable_duration > TERRAFORM_RUNNER_UNAVAILABLE_TIMEOUT
      error_message = "Terraform Runner has been unavailable for #{unavailable_duration.to_i} seconds, exceeding timeout of #{TERRAFORM_RUNNER_UNAVAILABLE_TIMEOUT.to_i} seconds"
      _log.error(error_message)
      raise MiqException::MiqProvisionError, error_message
    end

    _log.warn("Terraform Runner is unavailable (#{unavailable_duration.to_i}s elapsed), requeueing phase")
    requeue_phase
  end
end
