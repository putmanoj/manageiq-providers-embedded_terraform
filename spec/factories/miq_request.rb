FactoryBot.define do
  factory :miq_provision_embedded_terraform, :parent => :miq_provision, :class => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Provision"
end
