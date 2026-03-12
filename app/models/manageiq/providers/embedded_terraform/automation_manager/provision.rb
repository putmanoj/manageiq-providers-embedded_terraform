class ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Provision < ManageIQ::Providers::AutomationManager::Provision
  include StateMachine

  TASK_DESCRIPTION = N_("Terraform Template Provision")
end
