class ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Stack < ManageIQ::Providers::EmbeddedAutomationManager::OrchestrationStack
  belongs_to :ext_management_system,        :foreign_key => :ems_id,                       :class_name => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager",           :inverse_of => false
  belongs_to :configuration_script_payload, :foreign_key => :configuration_script_base_id, :class_name => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Template", :inverse_of => :stacks
  belongs_to :miq_task,                     :foreign_key => :ems_ref,                      :inverse_of => false

  class << self
    alias create_job     create_stack
    alias raw_create_job raw_create_stack

    def create_stack(terraform_template, options = {})
      authentications = collect_authentications(terraform_template.manager, options)

      job = raw_create_stack(terraform_template, options)

      miq_task = job&.miq_task

      create!(
        :name                         => terraform_template.name,
        :ext_management_system        => terraform_template.manager,
        :verbosity                    => options[:verbosity].to_i,
        :authentications              => authentications,
        :configuration_script_payload => terraform_template,
        :miq_task                     => miq_task,
        :status                       => miq_task&.state,
        :start_time                   => miq_task&.started_on
      )
    end

    def raw_create_stack(terraform_template, options = {})
      terraform_template.run(options)
    rescue => err
      _log.error("Failed to create job from template(#{terraform_template.name}), error: #{err}")
      raise MiqException::MiqOrchestrationProvisionError, err.to_s, err.backtrace
    end

    private

    def collect_authentications(manager, options)
      credential_ids = options[:credentials] || []

      manager.credentials.where(:id => credential_ids)
    end
  end

  def refresh
    transaction do
      self.status      = miq_task.state
      self.start_time  = miq_task.started_on
      self.finish_time = raw_status.completed? ? miq_task.updated_on : nil
      save!
    end
  end

  def raw_status
    Status.new(miq_task)
  end

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

  private

  def terraform_runner_stack_data
    return if miq_task.nil? || miq_task.job.nil?

    job = miq_task.job
    terraform_stack_id = job.options[:terraform_stack_id]

    return if terraform_stack_id.blank?

    Terraform::Runner.stack(terraform_stack_id)
  end
end
