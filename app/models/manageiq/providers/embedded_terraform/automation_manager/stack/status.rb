class ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Stack::Status < OrchestrationStack::Status
  LIVE_STATUS_RUNNING = 'running'.freeze
  LIVE_STATUS_CREATED = 'create_complete'.freeze
  LIVE_STATUS_FAILED = 'failed'.freeze
  LIVE_STATUS_DELETED = 'delete_complete'.freeze

  attr_accessor :task_status, :stack

  def initialize(stack)
    self.stack = stack
    miq_task = (stack.delete_miq_task.presence || stack.miq_task)

    super(miq_task.state, miq_task.message)
    self.task_status = miq_task.status
  end

  def retiring?
    stack.retiring? || (stack.delete_miq_task.present? && running?)
  end

  def retired?
    stack.retired? || (stack.delete_miq_task.present? && succeeded?)
  end

  def error_retiring?
    stack.error_retiring? || (stack.delete_miq_task.present? && failed?)
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

    # if created?
    return [LIVE_STATUS_CREATED, reason || 'OK'] if succeeded?

    # if retire failed?
    return [LIVE_STATUS_FAILED, reason || 'Stack deletion failed'] if error_retiring?

    # if provision failed?
    [LIVE_STATUS_FAILED, reason || 'Stack creation failed']
  end
end
