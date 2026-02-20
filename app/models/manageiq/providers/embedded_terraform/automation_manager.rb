class ManageIQ::Providers::EmbeddedTerraform::AutomationManager < ManageIQ::Providers::EmbeddedAutomationManager
  supports     :catalog
  supports_not :refresh_ems

  def self.hostname_required?
    # TODO: ExtManagementSystem is validating this
    false
  end

  def self.ems_type
    @ems_type ||= "embedded_terraform".freeze
  end

  def self.description
    @description ||= "Embedded Terraform".freeze
  end

  def self.catalog_types
    {
      "generic_terraform_template" => N_("Terraform Template (deprecated)"),
      "embedded_terraform"         => N_("Terraform Template")
    }
  end
end
