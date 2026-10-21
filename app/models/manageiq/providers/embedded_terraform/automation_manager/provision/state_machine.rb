module ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Provision::StateMachine
  # If the Terraform::Runner isn't available then don't start the provisioning process.
  #
  # Mark the Terraform::Runner as available in our phase_context to reset the time if
  # it becomes unavailable again during this state machine
  def run_provision
    return terraform_runner_unavailable_requeue_phase unless Terraform::Runner.available?

    terraform_runner_available!

    signal :provision
  end

  def provision
    stack_opts = build_stack_opts
    stack      = stack_klass.create_stack(source.terraform_template, stack_opts.dup)

    phase_context[:stack_id] = stack.id
    connect_to_service!(stack, {:name => "Provision", :options => stack_opts})

    save!

    signal :check_provisioned
  end

  def check_provisioned
    if running?
      requeue_phase
    else
      signal :post_provision
    end
  end

  def post_provision
    update_stack_resource_data!

    if succeeded?
      signal :mark_as_completed
    else
      raise MiqException::MiqProvisionError, "Failed to provision stack"
    end
  end

  def running?
    !stack.raw_status.completed?
  end

  def succeeded?
    stack.raw_status.succeeded?
  end

  def mark_as_completed
    update_and_notify_parent(:state => "finished", :message => "Stack provision is complete")
    signal :finish
  end

  def finish
    mark_execution_servers
  end

  def stack_klass
    ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Stack
  end

  def stack
    @stack ||= stack_klass.find(phase_context[:stack_id])
  end

  private

  def build_stack_opts
    {
      :action      => ResourceAction::PROVISION,
      :credentials => credentials_from_options,
      :input_vars  => input_vars_from_dialog
    }
  end

  def credentials_from_options
    credential_id = get_option(:credential_id)
    return [] if credential_id.blank?

    [Authentication.find_by(:id => credential_id)&.native_ref].compact
  end

  def input_vars_from_dialog
    dialog_option_keys = options.keys.select { |k| k.to_s.start_with?("dialog_") }
    dialog_options     = options.slice(*dialog_option_keys).merge(options.fetch("dialog", {}))

    dialog_options.to_h do |key, val|
      [key.to_s.sub(/\A(?:password::)?dialog_/, ''), val]
    end.except(nil)
  end

  # Updates the service resource with terraform runner stack information
  # that will be used during retirement actions.
  #
  # @return [void]
  # @note This method is called during post_provision phase
  def update_stack_resource_data!
    return if stack.nil? || service.nil?

    job_options = stack.miq_task&.job&.options
    return if job_options.nil?

    terraform_runner_stack_id = job_options[:terraform_stack_id]
    terraform_runner_stack_job_id = job_options[:terraform_stack_job_id]
    return if terraform_runner_stack_id.blank?

    stack_resource = service.service_resources.find_by(:resource => stack)
    return if stack_resource.nil?

    stack_resource.update!(
      :options => stack_resource.options.merge(
        "terraform_runner_stack_id"     => terraform_runner_stack_id,
        "terraform_runner_stack_job_id" => terraform_runner_stack_job_id
      )
    )
  rescue => err
    $embedded_terraform_log.warn("Failed to update stack resource options: #{err.message}")
  end
end
