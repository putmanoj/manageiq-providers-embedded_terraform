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
    credential_type          = get_value(values[:credential_type])
    allowed_credential_klass = credential_type&.safe_constantize || self.class.module_parent::TemplateCredential
    allowed_credential_klass.all.to_h do |auth|
      [auth.id, auth.name]
    end
  end

  def allowed_credential_types(*_args)
    credential_id = get_value(values[:credential_id])
    credential    = self.class.module_parent::TemplateCredential.find_by(:id => credential_id) if credential_id

    credential_classes = credential.present? ? [credential.class] : ManageIQ::Providers::EmbeddedTerraform::AutomationManager::TemplateCredential.descendants
    credential_classes.to_h do |klass|
      next unless klass.const_defined?(:API_OPTIONS)

      api_options = klass::API_OPTIONS
      next unless api_options[:label]

      [klass.name, api_options[:label]]
    end
  end

  def self.default_dialog_file
    'miq_provision_configuration_script_embedded_terraform_dialogs'
  end
end
