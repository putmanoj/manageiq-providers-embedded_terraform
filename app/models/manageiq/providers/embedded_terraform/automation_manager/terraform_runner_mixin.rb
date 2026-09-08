module ManageIQ::Providers::EmbeddedTerraform::AutomationManager::TerraformRunnerMixin
  TERRAFORM_RUNNER_UNAVAILABLE_TIMEOUT = 10.minutes

  def terraform_runner_available!
    phase_context.delete(:terraform_runner_unavailable_since)
    save!
  end

  def terraform_runner_unavailable_requeue_phase
    # Track when the runner first became unavailable
    phase_context[:terraform_runner_unavailable_since] ||= Time.now.utc

    unavailable_duration = Time.now.utc - phase_context[:terraform_runner_unavailable_since]

    if unavailable_duration > TERRAFORM_RUNNER_UNAVAILABLE_TIMEOUT
      error_message = _("Terraform Runner has been unavailable for %{unavailable} seconds, exceeding timeout of %{timeout} seconds") % {:unavailable => unavailable_duration.to_i, :timeout => TERRAFORM_RUNNER_UNAVAILABLE_TIMEOUT.to_i}
      _log.error(error_message)
      raise MiqException::MiqProvisionError, error_message
    end

    _log.warn("Terraform Runner is unavailable (#{unavailable_duration.to_i}s elapsed), requeueing phase")
    requeue_phase
  end
end
