FactoryBot.define do
  factory :configuration_script_embedded_terraform,
          :class  => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::ConfigurationScript",
          :parent => :configuration_script
  factory :terraform_template,
          :class  => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Template",
          :parent => :configuration_script_payload
end
