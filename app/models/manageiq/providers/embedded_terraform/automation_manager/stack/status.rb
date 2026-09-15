class ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Stack::Status < OrchestrationStack::Status
  LIVE_STATUS_RUNNING = 'running'.freeze
  LIVE_STATUS_CREATED = 'create_complete'.freeze
  LIVE_STATUS_FAILED  = 'failed'.freeze
  LIVE_STATUS_DELETED = 'delete_complete'.freeze

  attr_reader :task_status, :stack, :miq_task, :action

  def initialize(stack)
    @stack = stack

    # If delete_miq_task.present?, then Retire started
    # else if reconfigure_miq_task.present? then Reconfigure started
    # else Provision started
    if stack.delete_miq_task.present?
      @miq_task = stack.delete_miq_task
      @action = ResourceAction::RETIREMENT
    elsif stack.reconfigure_miq_task.present?
      @miq_task = stack.reconfigure_miq_task
      @action = ResourceAction::RECONFIGURE
    else
      @miq_task = stack.miq_task
      @action = ResourceAction::PROVISION
    end
    @task_status = miq_task.status

    super(miq_task.state, miq_task.message)
  end

  def retiring?
    action == ResourceAction::RETIREMENT && (stack.retiring? || running?)
  end

  def retired?
    action == ResourceAction::RETIREMENT && (stack.retired? || succeeded?)
  end

  def error_retiring?
    action == ResourceAction::RETIREMENT && (stack.error_retiring? || failed?)
  end

  def reconfiguring?
    action == ResourceAction::RECONFIGURE && running?
  end

  def reconfigured?
    action == ResourceAction::RECONFIGURE && succeeded?
  end

  def error_reconfiguring?
    action == ResourceAction::RECONFIGURE && failed?
  end

  def running?
    !completed?
  end

  def completed?
    status == MiqTask::STATE_FINISHED
  end

  def succeeded?
    completed? && task_status == MiqTask::STATUS_OK
  end

  def failed?
    completed? && task_status != MiqTask::STATUS_OK
  end

  def normalized_live_status
    # if running
    return [LIVE_STATUS_RUNNING, reason || status] if running?

    # if retired?
    return [LIVE_STATUS_DELETED, reason || 'Stack was deleted'] if retired?

    # if created? or reconfigured?
    return [LIVE_STATUS_CREATED, reason || 'OK'] if succeeded?

    # if retire failed?
    return [LIVE_STATUS_FAILED, reason || 'Stack deletion failed'] if error_retiring?

    # if reconfiguration failed?
    return [LIVE_STATUS_FAILED, reason || 'Stack reconfiguration failed'] if error_reconfiguring?

    # if provision failed?
    [LIVE_STATUS_FAILED, reason || 'Stack creation failed']
  end
end
