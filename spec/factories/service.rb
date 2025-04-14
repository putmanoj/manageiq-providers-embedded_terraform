FactoryBot.define do
  factory :service_terraform_template,
          :class  => "ServiceTerraformTemplate",
          :parent => :service do
    options do
      {
        :config_info => {
          :provision   => {
            :repository_id                   => "2",
            :execution_ttl                   => "",
            :log_output                      => "on_error",
            :verbosity                       => "0",
            :extra_vars                      => {},
            :configuration_script_payload_id => "13",
            :dialog_id                       => "27",
            :fqname                          => "/Service/Generic/StateMachines/GenericLifecycle/provision"
          },
          :reconfigure => {
            :repository_id                   => "2",
            :execution_ttl                   => "",
            :log_output                      => "on_error",
            :verbosity                       => "0",
            :extra_vars                      => {},
            :configuration_script_payload_id => "13",
            :dialog_id                       => "27",
            :fqname                          => "/Service/Generic/StateMachines/GenericLifecycle/reconfigure"
          },
          :retirement  => {
            :repository_id                   => "2",
            :execution_ttl                   => "",
            :log_output                      => "on_error",
            :verbosity                       => "0",
            :extra_vars                      => {},
            :configuration_script_payload_id => "13",
            :dialog_id                       => "27",
            :fqname                          => "/Service/Generic/StateMachines/GenericLifecycle/Retire_Advanced_Resource_None"
          }
        },
        :dialog      => {"dialog_name" => "World"},
      }
    end
  end
end
