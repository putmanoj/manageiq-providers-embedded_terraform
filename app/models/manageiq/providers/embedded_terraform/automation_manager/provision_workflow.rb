class ManageIQ::Providers::EmbeddedTerraform::AutomationManager::ProvisionWorkflow < ManageIQ::Providers::AutomationManager::ProvisionWorkflow
  def dialog_name_from_automate(message = 'get_dialog_name', extra_attrs = {})
    extra_attrs['platform'] ||= 'embedded_terraform'
    super
  end

  def allowed_configuration_scripts(*_args)
    self.class.module_parent::ConfigurationScript.all.map do |cs|
      build_ci_hash_struct(cs, %w[name description manager_name])
    end
  end

  def allowed_credentials(*_args)
    ManageIQ::Providers::EmbeddedTerraform::AutomationManager::TemplateCredential.all.map do |auth|
      build_ci_hash_struct(auth, %w[name type])
    end
  end

  def self.default_dialog_file
    'miq_provision_configuration_script_embedded_terraform_dialogs'
  end
end
