class ServiceTemplateTerraformTemplate < ServiceTemplate
  def self.default_provisioning_entry_point(_service_type)
    '/Service/Generic/StateMachines/GenericLifecycle/provision'
  end

  def self.default_reconfiguration_entry_point
    nil
  end

  def self.default_retirement_entry_point
    '/Service/Generic/StateMachines/GenericLifecycle/Retire_Basic_Resource'
  end

  def self.create_catalog_item(options, _auth_user)
    options      = options.merge(:service_type => SERVICE_TYPE_ATOMIC, :prov_type => 'generic_terraform_template')
    config_info  = validate_config_info(options[:config_info])

    transaction do
      create_from_options(options).tap do |service_template|
        service_template.create_resource_actions(config_info)
      end
    end
  end

  def self.validate_config_info(info)
    info[:provision][:fqname]   ||= default_provisioning_entry_point(SERVICE_TYPE_ATOMIC) if info.key?(:provision)
    info[:reconfigure][:fqname] ||= default_reconfiguration_entry_point if info.key?(:reconfigure)

    info[:retirement] ||= {}
    info[:retirement][:fqname] ||= default_retirement_entry_point

    raise _("Must provide a configuration_script_payload_id") if info[:provision][:configuration_script_payload_id].nil?

    info
  end
  private_class_method :validate_config_info

  def terraform_template(action)
    template_id = config_info.dig(action.downcase.to_sym, :configuration_script_payload_id)
    if template_id.nil? && action.downcase == 'retirement'
      template_id = config_info.dig(:provision, :configuration_script_payload_id)
    end
    return if template_id.nil?

    ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Template.find(template_id)
  end
end
