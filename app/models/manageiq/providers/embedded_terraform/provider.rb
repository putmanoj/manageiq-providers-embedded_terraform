class ManageIQ::Providers::EmbeddedTerraform::Provider < Provider
  include DefaultTerraformObjects

  has_one :automation_manager,
          :foreign_key => "provider_id",
          :class_name  => "ManageIQ::Providers::EmbeddedTerraform::AutomationManager",
          :autosave    => true

end
