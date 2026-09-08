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
    unavailable_timeout  = Settings.ems.ems_embedded_terraform.terraform_runner.unavailable_timeout.to_i_with_method
    if unavailable_duration > unavailable_timeout
      error_message = _("Terraform Runner has been unavailable for %{unavailable} seconds, exceeding timeout of %{timeout} seconds") % {:unavailable => unavailable_duration.to_i, :timeout => unavailable_timeout}
      _log.error(error_message)
      raise MiqException::MiqProvisionError, error_message
    end

    _log.warn("Terraform Runner is unavailable (#{unavailable_duration.to_i}s elapsed), requeueing phase")
    requeue_phase
  end
end
