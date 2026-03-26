FactoryBot.define do
  factory :miq_provision_configuration_script_embedded_terraform_dialogs, :parent => :miq_dialog do
    name        { "miq_provision_configuration_script_embedded_terraform_dialogs" }
    dialog_type { "MiqProvisionConfigurationScriptWorkflow" }
  end
end
