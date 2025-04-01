class ServiceTerraformTemplate < ServiceGeneric
  delegate :terraform_template, :to => :service_template, :allow_nil => true

  CONFIG_OPTIONS_WHITELIST = %i[
    credential_id
    execution_ttl
    input_vars
    extra_vars
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

  def execute(action)
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

    task_id = MiqTask.generic_action_with_callback(task_opts, queue_opts)
    task    = MiqTask.wait_for_taskid(task_id)
    raise task.message unless task.status_ok?
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
    terraform_template = terraform_template(action)

    # runs provision or retirement or reconfigure job, based on job_options
    stack = ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Stack.create_stack(terraform_template, get_job_options(action))
    add_resource!(stack, :name => action)
  end

  def stack(action)
    service_resources.find_by(:name => action, :resource_type => 'OrchestrationStack').try(:resource)
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
    # TODO: check extra_vars
    job_options[:extra_vars].try(:transform_values!) do |val|
      val.kind_of?(String) ? val : val[:default] # TODO: support Hash only
    end

    case action
    when ResourceAction::RETIREMENT
      # The Retirement(terraform destroy) action, itself does have dialog-options,
      # so will use input-vars/values from Provision/Reconfiguration.
      # Copy input-vars from Provision & Reconfiguration (terraform apply),
      prov_job_options = copy_terraform_stack_id_and_input_vars_from_job_options(ResourceAction::PROVISION)
      reconfigure_job_options = copy_terraform_stack_id_and_input_vars_from_job_options(ResourceAction::RECONFIGURE)
      job_options.deep_merge!(prov_job_options)
      job_options.deep_merge!(reconfigure_job_options)
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
    if action_job.present? && action_job.options.present?
      job_options = {}
      job_options[:terraform_stack_id] = action_job.options[:terraform_stack_id] if action_job.options.key?(:terraform_stack_id)
      job_options[:extra_vars] = action_job.options.dig(:input_vars, :extra_vars).deep_dup
      job_options[:input_vars] = action_job.options.dig(:input_vars, :input_vars).deep_dup
      job_options
    else
      {}
    end
  end
end
