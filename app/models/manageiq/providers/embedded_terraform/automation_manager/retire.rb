class ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Retire < OrchestrationStackRetireTask
  include module_parent::TerraformRunnerMixin
  include StateMachine
end
