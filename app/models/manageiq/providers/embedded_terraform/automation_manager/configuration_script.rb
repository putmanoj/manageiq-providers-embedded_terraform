class ManageIQ::Providers::EmbeddedTerraform::AutomationManager::ConfigurationScript < ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScript
  has_many :stacks, :class_name => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Stack", :inverse_of => :configuration_script, :dependent => :nullify

  def self.manager_class
    module_parent
  end

  def my_zone
    manager&.my_zone
  end

  def run(vars = {}, _userid = nil)
    env_vars    = vars.delete(:env) || {}
    credentials = vars.delete(:credentials)
    action = vars.delete(:action) || ResourceAction::PROVISION
    terraform_stack_id = vars.delete(:terraform_stack_id)

    self.class.module_parent::Job.create_job(
      self, env_vars, vars, credentials, :action => action, :terraform_stack_id => terraform_stack_id
    ).tap(&:signal_start)
  end
end
