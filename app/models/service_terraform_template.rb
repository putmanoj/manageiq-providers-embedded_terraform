class ServiceTerraformTemplate < ServiceGeneric
  delegate :terraform_template, :to => :service_template, :allow_nil => true

  CONFIG_OPTIONS_WHITELIST = %i[
    credential_id
    execution_ttl
    extra_vars
    verbosity
  ].freeze

  def my_zone
    miq_request&.my_zone
  end

  # A chance for taking options from automate script to override options from a service dialog
  def preprocess(action, add_options = {})
    if add_options.present?
      _log.info("Override with new options:")
      $log.log_hashes(add_options)
    end

    save_job_options(action, add_options)
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

    # runs provision or retirement job, based on job_options
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

  def get_job_options(action)
    case action.downcase
    when 'retirement'
      retire_job_options = options[job_option_key('retirement')].deep_dup
      retire_job_options[:action] = action
      prov_job_options = options[job_option_key('provision')].deep_dup
      # if not already available in retirement options, (won't be available for terraform)
      # copy extra_vars,execution_ttl,verbosity,credentials,etc from provision action
      job_options = prov_job_options.deep_merge(retire_job_options)
    else
      job_options = options[job_option_key(action)].deep_dup
    end

    # Add additional vars,
    #  :miq_action              - required for Retirement action
    #  :miq_service_instance_id - use in Provision action to update stack_id in Service, later needed in Retirement action.
    job_options[:extra_vars][:miq_service_instance_id] = id
    job_options[:extra_vars][:miq_action] = action

    job_options
  end

  def config_options(action)
    options.fetch_path(:config_info, action.downcase.to_sym).slice(*CONFIG_OPTIONS_WHITELIST).with_indifferent_access
  end

  def save_job_options(action, overrides)
    job_options = config_options(action)
    job_options[:extra_vars].try(:transform_values!) do |val|
      val.kind_of?(String) ? val : val[:default] # TODO: support Hash only
    end
    job_options.deep_merge!(parse_dialog_options) unless action == ResourceAction::RETIREMENT
    job_options.deep_merge!(overrides)
    translate_credentials!(job_options)

    options[job_option_key(action)] = job_options
    save!
  end

  def job_option_key(action)
    "#{action.downcase}_job_options".to_sym
  end

  def parse_dialog_options
    dialog_options = options[:dialog] || {}

    params = dialog_options.each_with_object({}) do |(attr, val), obj|
      var_key = attr.sub(/^(password::)?dialog_/, '')
      obj[var_key] = val
    end

    params.blank? ? {} : {:extra_vars => params}
  end

  def translate_credentials!(options)
    options[:credentials] = []

    credential_id = options.delete(:credential_id)
    options[:credentials] << Authentication.find(credential_id).native_ref if credential_id.present?
  end
end
