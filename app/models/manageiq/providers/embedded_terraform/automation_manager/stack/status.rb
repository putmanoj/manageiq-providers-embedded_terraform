class ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Stack::Status < OrchestrationStack::Status
  LIVE_STATUS_RUNNING = 'running'.freeze
  LIVE_STATUS_FINISHED = 'finished'.freeze
  LIVE_STATUS_FAILED = 'failed'.freeze

  attr_accessor :task_status

  def initialize(miq_task)
    super(miq_task.state, miq_task.message)
    self.task_status = miq_task.status
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
    return [LIVE_STATUS_RUNNING, reason || status] unless completed?
    return [LIVE_STATUS_FINISHED, reason || 'OK'] if succeeded?

    [LIVE_STATUS_FAILED, reason || 'Stack creation failed']
  end
end
