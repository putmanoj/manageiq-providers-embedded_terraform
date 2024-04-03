FactoryBot.define do
  # factory :configuration_script_source do
  #   sequence(:name) { |n| "configuration_script_source#{seq_padded_for_sorting(n)}" }
  # end

  factory :template_configuration_script_base do
    sequence(:name) { |n| "HelloWorld(1.0)#{seq_padded_for_sorting(n)}" }
    sequence(:manager_ref) { SecureRandom.random_number(100) }
    payload { '{"relative_path":"terraform/templates/hello-world","files":["camtemplate.json","camvariables.json","main.tf"],"input_vars":null,"output_vars":null}' }
    payload_type { 'json' }
  end

  factory :template_configuration_script_payload, :class => "ConfigurationScriptPayload", :parent => :template_configuration_script_base

  factory :embedded_terraform_configuration_script_source,
          :parent => :configuration_script_source,
          :class  => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::ConfigurationScriptSource" do
    scm_url { "https://example.com/foo.git" }
  end

  factory :teraform_template,
          :class  => "ManageIQ::Providers::AutomationManager::ConfigurationScriptPayload",
          :parent => :template_configuration_script_payload

  factory :embedded_terraform_configuration_script,
          :class  => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::ConfigurationScript",
          :parent => :configuration_script
  factory :embedded_template,
          :class  => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Template",
          :parent => :template_configuration_script_payload
end
