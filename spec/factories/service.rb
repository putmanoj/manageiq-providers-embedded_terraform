FactoryBot.define do
  factory :service_terraform_template,
          :class  => "ServiceTerraformTemplate",
          :parent => :service do
    options { {} }
  end
  factory :service_embedded_terraform,
          :class  => "ServiceEmbeddedTerraform",
          :parent => :service do
    options { {} }
  end
end
