class ServiceTemplateTerraformTemplate < ServiceTemplate
  def self.default_provisioning_entry_point(_service_type = nil)
    '/Service/Generic/StateMachines/GenericLifecycle/provision'
  end

  def self.default_reconfiguration_entry_point
    '/Service/Generic/StateMachines/GenericLifecycle/reconfigure'
  end

  def self.default_retirement_entry_point
    '/Service/Generic/StateMachines/GenericLifecycle/Retire_Advanced_Resource_None'
  end

  def self.create_catalog_item(options, _auth_user)
    options      = options.merge(:service_type => SERVICE_TYPE_ATOMIC, :prov_type => 'generic_terraform_template')
    config_info  = validate_config_info(options[:config_info])

    transaction do
      create_from_options(options).tap do |service_template|
        dialog_ids = service_template.send(:create_dialogs, config_info)
        config_info.deep_merge!(dialog_ids)
        service_template.options[:config_info] = config_info
        service_template.create_resource_actions(config_info)
      end
    end
  end

  def update_catalog_item(options, auth_user = nil)
    config_info = validate_update_config_info(options)
    unless config_info
      update!(options)
      return reload
    end

    config_info.deep_merge!(create_dialogs(config_info))

    options[:config_info] = config_info

    super
  end

  private_class_method def self.validate_config_info(config_info)
    raise _("Must provide a configuration_script_payload_id") if config_info.dig(:provision, :configuration_script_payload_id).nil?

    config_info[:provision][:fqname] ||= default_provisioning_entry_point(SERVICE_TYPE_ATOMIC)

    prov_info_copy = config_info[:provision].except(:fqname)

    # By default, for Reconfigure(terraform apply) will have same config as Provision,
    # though the input parameters values, can be changed by the user
    config_info[:reconfigure] ||= prov_info_copy.deep_dup
    config_info[:reconfigure][:fqname] ||= default_reconfiguration_entry_point

    # By default, for Retirement(terraform destroy) will have same config as Provision config,
    # because retirement(terraform destroy) action is run in-reverse order with same terraform template.
    config_info[:retirement] ||= prov_info_copy.deep_dup
    config_info[:retirement][:fqname] ||= default_retirement_entry_point

    config_info
  end

  def terraform_template(action)
    template_id = config_info.dig(action.downcase.to_sym, :configuration_script_payload_id)
    return if template_id.nil?

    ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Template.find(template_id)
  end

  def create_dialogs(config_info)
    dialog_hash = {}

    info = config_info[:provision]
    if info
      # create new dialog, if required for :provision action
      if info.key?(:new_dialog_name) && !info.key?(:dialog_id)
        provision_dialog_id = create_new_dialog(
          info[:new_dialog_name],
          terraform_template(:provision)
        ).id
        dialog_hash[:provision] = {:dialog_id => provision_dialog_id}
      else
        provision_dialog_id = info[:dialog_id]
      end

      # For :retirement & :reconfigure,  we use the same dialog as in :provision action
      dialog_hash = [:retirement, :reconfigure].each_with_object(dialog_hash) do |action, hash|
        hash[action] = {:dialog_id => provision_dialog_id}
      end
    end

    dialog_hash
  end

  private

  def create_new_dialog(dialog_name, terraform_template)
    Dialog::TerraformTemplateServiceDialog.create_dialog(dialog_name, terraform_template)
  end

  def validate_update_config_info(options)
    opts = super
    return unless options.key?(:config_info)

    self.class.send(:validate_config_info, opts)
  end
end
