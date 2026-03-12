class ManageIQ::Providers::EmbeddedTerraform::AutomationManager::ConfigurationScript < ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScript
  alias terraform_template parent

  delegate :stacks, :to => :terraform_template
  delegate :run,    :to => :terraform_template

  def self.manager_class
    module_parent
  end

  def my_zone
    manager&.my_zone
  end
end
