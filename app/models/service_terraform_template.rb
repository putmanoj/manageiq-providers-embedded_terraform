class ServiceTerraformTemplate < ServiceGeneric
  delegate :terraform_template, :to => :service_template, :allow_nil => true

  CONFIG_OPTIONS_WHITELIST = %i[
    credential_id
    execution_ttl
    input_vars
    # extra_vars
    verbosity
  ].freeze

  def my_zone
    miq_request&.my_zone
  end

  # A chance for taking options from automate script to override options from a service dialog
  def preprocess(action, update_options = {})
    if update_options.present?
      $embedded_terraform_log.info("Override with new options:")
      $embedded_terraform_log.log_hashes(update_options)
    end

    save_job_options(action, update_options)
  end

  # this is essentially launch_terraform_template_queue
  #
  # @returns [Numeric] task_id (passed into wait_for_taskid)
  def execute_async(action)
    $embedded_terraform_log.debug("Service(#{id}).execute(#{action}) starts")
    task_opts = {
      :action => "Launching Terraform Template",
      :userid => "system"
    }

    queue_opts = {
      :args        => [action],
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => "launch_terraform_template",
      :role        => "embedded_terraform",
      :zone        => my_zone
    }
    MiqTask.generic_action_with_callback(task_opts, queue_opts)
  end

  def execute(action)
    task_id = execute_async(action)
    task    = MiqTask.wait_for_taskid(task_id)

    $embedded_terraform_log.debug("Service(#{id}).execute(#{action}) ends, with task/#{task_id}:#{task}")
    raise task.message unless task.status_ok?
  end

  def postprocess(action)
    $embedded_terraform_log.debug("Service(#{id}).postprocess(#{action}) starts")
    case action
    when ResourceAction::RECONFIGURE
      # As we have reached here, so the action was successful.
      # Now we update the Service with dialog options from Reconfiguration
      $embedded_terraform_log.info("successfully reconfiguired, save reconfigure job options, to service dialog options")
      job_options = get_job_options(action)
      params = job_options[:input_vars] || {}
      update_service_dialog_options(params)
    end
    $embedded_terraform_log.debug("Service(#{id}).postprocess(#{action}) ends")
  end

  def check_completed(action)
    status = stack(action).raw_status
    done   = status.completed?

    # If the stack is completed the message has to be nil otherwise the stack
    # will get marked as failed
    _, message = status.normalized_status unless status.succeeded?
    [done, message]
  rescue MiqException::MiqOrchestrationStackNotExistError, MiqException::MiqOrchestrationStatusError => err
    [true, err.message] # consider done with an error when exception is caught
  end

  def launch_terraform_template(action)
    $embedded_terraform_log.debug("Service(#{id}).launch_terraform_template(#{action}) starts")
    terraform_template = terraform_template(action)

    # runs provision or retirement or reconfigure job, based on job_options
    stack = ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Stack.create_stack(terraform_template, get_job_options(action))

    add_resource!(stack, :name => action)

    $embedded_terraform_log.debug("Service(#{id}).launch_terraform_template(#{action}) ends")
  end

  def add_resource!(stack, options = {})
    super # call super-class method to add resource

    # Save the newly created Job/OrchestrationStack.id, with job options, to identify the current running Job/OrchestrationStack.
    # This especially is needed for Reconfigure action, as the action can run multiple times for same service instance,
    # which creates multiple OrchestrationStack(job)s, unlike Provision or Retirement actions, each having single OrchestrationStack(job).
    save_orchestration_stack_id(options[:name], stack.id)
  end

  def stack(action)
    # we need to reload, to pull updates to options from db, because the stack_id was saved in service instance in a queue job
    reload unless options[job_option_key(action)]&.key?(:orchestration_stack_id)
    orchestration_stack_id = options.dig(job_option_key(action), :orchestration_stack_id)
    $embedded_terraform_log.debug("find OrchestrationStack by resource_id:#{orchestration_stack_id} for #{action}")
    # We query also by :resource_id, because in case of Reconfigure action, it could have run multiple times, so there can be multiple OrchestrationStack(Job)s.
    service_resources.find_by(:resource_id => orchestration_stack_id, :name => action, :resource_type => 'OrchestrationStack').try(:resource)
  end

  def refresh(action)
    stack(action).refresh
  end

  def check_refreshed(_action)
    [true, nil]
  end

  private

  def job(action)
    stack(action)&.miq_task&.job
  end

  def get_job_options(action)
    job_options = options[job_option_key(action)].deep_dup

    # current action, required to identify Retirement or Reconfigure action
    job_options[:action] = action

    job_options
  end

  def config_options(action)
    options.fetch_path(:config_info, action.downcase.to_sym).slice(*CONFIG_OPTIONS_WHITELIST).with_indifferent_access
  end

  def save_job_options(action, overrides)
    job_options = config_options(action)

    # # TODO: check extra_vars
    # job_options[:extra_vars].try(:transform_values!) do |val|
    #   val.kind_of?(String) ? val : val[:default] # TODO: support Hash only
    # end

    case action
    when ResourceAction::RETIREMENT
      # The Retirement(terraform destroy) action, itself does have dialog-options,
      # so will use input-vars/values from Provision/Reconfiguration.
      # Copy input-vars from Provision & Reconfiguration (terraform apply),
      prov_job_options = copy_terraform_stack_id_and_input_vars_from_job_options(ResourceAction::PROVISION)
      job_options.deep_merge!(prov_job_options)

      reconfigure_job_options = copy_terraform_stack_id_and_input_vars_from_job_options(ResourceAction::RECONFIGURE)
      job_options.deep_merge!(reconfigure_job_options) unless reconfigure_job_options.nil?
    when ResourceAction::RECONFIGURE
      # We need the stack_id from Provision, then we override with update_options from Reconfiguration request
      prov_job_options = copy_terraform_stack_id_and_input_vars_from_job_options(ResourceAction::PROVISION)
      job_options.deep_merge!(prov_job_options)
      job_options.deep_merge!(parse_dialog_options_only(overrides))
    else
      # For Provision
      job_options.deep_merge!(parse_dialog_options(options))
    end

    #  job_options.deep_merge!(overrides)
    translate_credentials!(job_options)

    options[job_option_key(action)] = job_options
    save!
  end

  def job_option_key(action)
    "#{action.downcase}_job_options".to_sym
  end

  # We only want keys starting with 'dialog_', as these are user inputs, don't want other key/value pairs.
  # Particularly in case of Reconfigure action, we want to remove keys like,
  # - request => "service_reconfigure"
  # - Service::service => ##
  def parse_dialog_options_only(action_options)
    dialog_options = action_options[:dialog] || {}
    params = {}
    dialog_options.each do |attr, val|
      if attr.start_with?("dialog_")
        var_key = attr.sub(/^(password::)?dialog_/, '')
        params[var_key] = val
      end
    end
    params.blank? ? {} : {:input_vars => params}
  end

  def parse_dialog_options(action_options)
    dialog_options = action_options[:dialog] || {}

    params = dialog_options.each_with_object({}) do |(attr, val), obj|
      var_key = attr.sub(/^(password::)?dialog_/, '')
      obj[var_key] = val
    end

    params.blank? ? {} : {:input_vars => params}
  end

  def translate_credentials!(options)
    options[:credentials] = []

    credential_id = options.delete(:credential_id)
    options[:credentials] << Authentication.find(credential_id).native_ref if credential_id.present?
  end

  def copy_terraform_stack_id_and_input_vars_from_job_options(action)
    action_job = job(action)
    return if action_job&.options.blank?

    {
      :terraform_stack_id => action_job.options[:terraform_stack_id],
      # :extra_vars         => action_job.options.dig(:input_vars, :extra_vars).deep_dup,
      :input_vars         => action_job.options.dig(:input_vars, :input_vars).deep_dup
    }
  end

  def update_service_dialog_options(params)
    dialog_options = options[:dialog] || {}
    params.each do |attr, val|
      dialog_key = "dialog_#{attr}"
      dialog_options[dialog_key] = val
    end
    options[:dialog] = dialog_options
    save!
  end

  def save_orchestration_stack_id(action, stack_id)
    job_options = options[job_option_key(action)] || {}
    job_options[:orchestration_stack_id] = stack_id

    $embedded_terraform_log.info("save orchestration_stack_id:#{stack_id} with job_options for #{action}")
    options[job_option_key(action)] = job_options
    save!
  end
end
