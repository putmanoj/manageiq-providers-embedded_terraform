class ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Stack < ManageIQ::Providers::EmbeddedAutomationManager::OrchestrationStack
  belongs_to :ext_management_system,        :foreign_key => :ems_id, :class_name => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager", :inverse_of => false
  belongs_to :configuration_script_payload, :foreign_key => :configuration_script_base_id, :class_name => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Template", :inverse_of => :stacks
  belongs_to :miq_task,                     :foreign_key => :ems_ref, :inverse_of => false
  belongs_to :configuration_script

  class << self
    alias create_job     create_stack
    alias raw_create_job raw_create_stack

    def create_stack(terraform_template, options = {})
      $embedded_terraform_log.debug("Creating job from template(#{terraform_template.name}) with options: #{options}")

      authentications = collect_authentications(terraform_template.manager, options)

      job = raw_create_stack(terraform_template, options)

      miq_task = job&.miq_task

      create!(
        :name                         => terraform_template.name,
        :ext_management_system        => terraform_template.manager,
        :verbosity                    => options[:verbosity].to_i,
        :authentications              => authentications,
        :configuration_script         => terraform_template.configuration_script,
        :configuration_script_payload => terraform_template,
        :miq_task                     => miq_task,
        :status                       => miq_task&.state,
        :start_time                   => miq_task&.started_on
      ).tap do |stack|
        job.update!(:target => stack)
      end
    end

    def raw_create_stack(terraform_template, options = {})
      terraform_template.run(options)
    rescue => err
      handle_stack_operation_error("create job from template(#{terraform_template.name})", err)
    end

    def status_class
      "#{name}::Status".constantize
    end

    private

    def collect_authentications(manager, options)
      credential_ids = options[:credentials] || []

      manager.credentials.where(:id => credential_ids)
    end
  end

  def retireable?
    # return false, if service is a ServiceTerraformTemplate, handles retire itself, raw_delete_stack should not be called.
    # return true, if service is ServiceEmbeddedTerraform, raw_delete_stack should be called.
    service.instance_of?(ServiceEmbeddedTerraform)
  end

  def raw_delete_stack
    raise MiqException::Error, "Cannot delete stack, service_resource not found for stack:#{id}" if service_resource.nil?
    raise MiqException::Error, "Cannot delete stack, service_resource.options is empty for stack:#{id}" if service_resource.options.blank?

    terraform_runner_stack_id = service_resource.options["terraform_runner_stack_id"]
    raise MiqException::MiqOrchestrationProvisionError, "Cannot delete stack, did not find terraform_runner_stack_id for stack:#{id}" if terraform_runner_stack_id.blank?

    terraform_template = configuration_script_payload
    raise MiqException::Error, "Cannot delete stack, configuration script payload not found for stack:#{id}" if terraform_template.nil?

    job_options = service_resource.options.slice("input_vars", "credentials").transform_keys(&:to_sym)
    job_options[:action] = ResourceAction::RETIREMENT
    job_options[:terraform_stack_id] = terraform_runner_stack_id

    $embedded_terraform_log.debug("Run job to delete stack(#{id}) for template(#{terraform_template.name}) with options: #{job_options}")

    @delete_job = terraform_template.run(job_options)
    delete_job.target = self
    delete_job.save!

    $embedded_terraform_log.debug("Delete job created : #{delete_job.id}")

    delete_job
  rescue => err
    handle_stack_operation_error("delete stack for stack:#{id}", err)
  end

  def refresh
    # when retired or retirement-failed, no further action required
    return if retired? || error_retiring?

    # where retirement is running
    if retiring?
      return if delete_miq_task.nil?

      if raw_status.running? # delete_job&.is_active?
        delete_job&.poll_runner
      end
    else
      # when provisioning
      return unless miq_task

      transaction do
        self.status      = miq_task.state
        self.start_time  = miq_task.started_on
        self.finish_time = raw_status.completed? ? miq_task.updated_on : nil
        save!
      end
    end
  end

  def queue_refresh
    MiqQueue.put(:class_name => self.class.name, :instance_id => id, :method_name => "refresh", :role => "embedded_terraform")
  end

  def raw_status
    return nil unless miq_task

    Status.new(self)
  end

  delegate :normalized_live_status, :to => :raw_status, :allow_nil => true

  # Intend to be called by UI to display stdout. The stdout is stored in TerraformRunner(api/stack#message)
  def raw_stdout_via_worker(userid, format = 'txt')
    unless MiqRegion.my_region.role_active?("embedded_terraform")
      msg = "Cannot get standard output of this terraform-template because the embedded terraform role is not enabled"
      return MiqTask.create(
        :name    => 'terraform_stdout',
        :userid  => userid || 'system',
        :state   => MiqTask::STATE_FINISHED,
        :status  => MiqTask::STATUS_ERROR,
        :message => msg
      ).id
    end

    options = {:userid => userid || 'system', :action => 'terraform_stdout'}
    queue_options = {
      :class_name  => self.class,
      :method_name => 'raw_stdout',
      :instance_id => id,
      :args        => [format],
      :priority    => MiqQueue::HIGH_PRIORITY,
      :role        => nil
    }

    MiqTask.generic_action_with_callback(options, queue_options)
  end

  def raw_stdout(format = 'txt')
    case format
    when "html" then raw_stdout_html
    else             raw_stdout_txt
    end
  end

  def raw_stdout_txt
    data = terraform_runner_stack_data
    data&.message
  end

  def raw_stdout_html
    text = raw_stdout_txt
    text = _("No output available") if text.blank?
    TerminalToHtml.render(text)
  end

  def service_resource
    return @service_resource if defined?(@service_resource)

    @service_resource = service_resources.find_by(:resource => self)
  end

  def delete_job
    return @delete_job if defined?(@delete_job)

    @delete_job = ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Job.find_by(:target_id => id, :target_class => self.class.name)
  end

  def delete_miq_task
    @delete_miq_task ||= delete_job&.miq_task
  end

  private

  def terraform_runner_stack_data
    if service_resource.present?
      terraform_runner_stack_id = service_resource.options&.dig("terraform_runner_stack_id")

      return Terraform::Runner.stack(terraform_runner_stack_id) if terraform_runner_stack_id.present?
    else
      $embedded_terraform_log.warn("Unable to retrieve stack data for stack(#{id}): service_resource is nil")
    end

    # This means, it is a legacy stack, before we introduced the workflow provision
    if miq_task.nil?
      $embedded_terraform_log.warn("Unable to retrieve stack data for stack(#{id}): miq_task is nil")
      return
    end

    if miq_task.job.nil?
      $embedded_terraform_log.warn("Unable to retrieve stack data for stack(#{id}): miq_task.job is nil")
      return
    end

    job = miq_task.job
    terraform_stack_id = job.options[:terraform_stack_id]

    if terraform_stack_id.blank?
      $embedded_terraform_log.warn("Unable to retrieve stack data for stack(#{id}): terraform_stack_id is blank in job options")
      return
    end

    Terraform::Runner.stack(terraform_stack_id)
  end

  def handle_stack_operation_error(operation, err)
    $embedded_terraform_log.error("Failed to #{operation}, error: #{err}")
    raise MiqException::MiqOrchestrationProvisionError, err.message, err.backtrace
  end
end
