class ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Job < Job
  def self.create_job(template, env_vars, job_vars, credentials, action: ResourceAction::PROVISION, terraform_stack_id: nil, poll_interval: 1.minute)
    super(
      :template_id        => template.id,
      :env_vars           => env_vars,
      :job_vars           => job_vars,
      :credentials        => credentials,
      :poll_interval      => poll_interval,
      :action             => action,
      :terraform_stack_id => terraform_stack_id
    )
  end

  def start
    queue_signal(:pre_execute)
  end

  def pre_execute
    checkout_git_repository
    signal(:execute)
  end

  def execute
    template_path = File.join(options[:git_checkout_tempdir], template_relative_path)
    credentials   = Authentication.where(:id => options[:credentials])
    action        = options[:action]

    runner_options = {
      :input_vars                  => decrypt_vars(input_vars),
      :input_vars_type_constraints => input_vars_type_constraints,
      :credentials                 => credentials,
      :env_vars                    => options[:env_vars]
    }

    # required for ResourceAction::RECONFIGURE, ResourceAction::RETIREMENT
    unless action == ResourceAction::PROVISION
      runner_options = runner_options.merge(
        :stack_id => options[:terraform_stack_id]
      )
    end

    response = Terraform::Runner.run(
      terraform_runner_action_type(action),
      template_path,
      runner_options
    )

    # save stack_id from the created stack
    options[:terraform_stack_id] = response.stack_id
    # and we need terraform_stack_job_id especially, when running Reconfigure action
    options[:terraform_stack_job_id] = response.stack_job_id
    save!

    queue_poll_runner
  end

  def poll_runner
    if running?
      queue_poll_runner
    else
      signal(:post_execute)
    end
  end

  def post_execute
    cleanup_git_repository

    return queue_signal(:finish, message, status) if success?

    $embedded_terraform_log.error("Failed to run template: [#{error_message}]")

    abort_job("Failed to run template", "error")
  end

  alias initializing dispatch_start
  alias finish       process_finished
  alias abort_job    process_abort
  alias cancel       process_cancel
  alias error        process_error

  protected

  def running?
    stack_response&.running?
  end

  def success?
    stack_response&.response&.success?
  end

  def error_message
    stack_response&.response&.error_message
  end

  def load_transitions
    self.state ||= 'initialize'

    {
      :initializing => {'initialize'       => 'waiting_to_start'},
      :start        => {'waiting_to_start' => 'pre_execute'},
      :pre_execute  => {'pre_execute'      => 'execute'},
      :execute      => {'execute'          => 'running'},
      :poll_runner  => {'running'          => 'running'},
      :post_execute => {'running'          => 'post_execute'},
      :finish       => {'*'                => 'finished'},
      :abort_job    => {'*'                => 'aborting'},
      :cancel       => {'*'                => 'canceling'},
      :error        => {'*'                => '*'}
    }
  end

  def poll_interval
    options.fetch(:poll_interval, 1.minute).to_i
  end

  private

  def template
    @template ||= self.class.module_parent::Template.find(options[:template_id])
  end

  def template_relative_path
    JSON.parse(template.payload)["relative_path"]
  end

  def stack_response
    action                 = options[:action]
    terraform_stack_id     = options[:terraform_stack_id]
    terraform_stack_job_id = options[:terraform_stack_job_id]
    $embedded_terraform_log.debug("ResponseAsync stack/#{terraform_stack_id}/#{terraform_stack_job_id} for #{action}")

    return if terraform_stack_id.nil?

    @stack_response ||= Terraform::Runner::ResponseAsync.new(terraform_stack_id, terraform_stack_job_id)
  end

  def decrypt_vars(input_vars)
    input_vars.transform_values { |val| val.kind_of?(String) ? ManageIQ::Password.try_decrypt(val) : val }
  end

  def configuration_script_source
    @configuration_script_source ||= template.configuration_script_source
  end

  def queue_poll_runner
    queue_signal(:poll_runner, :deliver_on => Time.now.utc + poll_interval)
  end

  def checkout_git_repository
    options[:git_checkout_tempdir] = Dir.mktmpdir("embedded-terraform-runner-git")
    save!

    $embedded_terraform_log.info("Checking out git repository to #{options[:git_checkout_tempdir].inspect}...")
    configuration_script_source.checkout_git_repository(options[:git_checkout_tempdir])
  rescue MiqException::MiqUnreachableError => err
    miq_task.job.timeout!
    raise "Failed to connect with [#{err.class}: #{err}], job aborted"
  end

  def cleanup_git_repository
    return unless options[:git_checkout_tempdir]

    $embedded_terraform_log.info("Cleaning up git repository checkout at #{options[:git_checkout_tempdir].inspect}...")
    FileUtils.rm_rf(options[:git_checkout_tempdir])
  rescue Errno::ENOENT
    nil
  end

  # Returns key/value(type constraints object, from Terraform Runner) pair.
  # @return [Hash]
  def input_vars_type_constraints
    require 'json'
    payload = JSON.parse(template.payload)
    (payload['input_vars'] || []).index_by { |v| v['name'] }
  rescue => error
    $embedded_terraform_log.error("Failure in parsing payload for template/#{template.id}, caused by #{error.message}")
    {}
  end

  def input_vars
    options.dig(:job_vars, :input_vars) || {}
  end

  def terraform_runner_action_type(resource_action)
    case resource_action
    when ResourceAction::RECONFIGURE
      Terraform::Runner::ActionType::UPDATE
    when ResourceAction::RETIREMENT
      Terraform::Runner::ActionType::DELETE
    when ResourceAction::PROVISION
      Terraform::Runner::ActionType::CREATE
    else
      raise "Invalid resource_action type #{resource_action}"
    end
  end
end
