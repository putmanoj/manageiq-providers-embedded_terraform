class ManageIQ::Providers::EmbeddedTerraform::AutomationManager::Template < ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScriptPayload
  has_many :jobs, :class_name => 'OrchestrationStack', :foreign_key => :configuration_script_base_id

  def self.display_name(number = 1)
    n_('Template (Embedded Terraform)', 'Templates (Embedded Terraform)', number)
  end

  def run(vars = {}, userid = "system")
    _log.info("Template.run| Run for #{userid} terraform-template: #{name}, with inputs: #{vars}")

    input_vars = vars[:input_vars] || {}

    payload_json = JSON.parse(payload)
    template_options = {
      :configuration_script_source_id => configuration_script_source_id,
      :template_relative_path         => payload_json['relative_path'],
    }

    credentials = vars[:credentials] || []

    kwargs = {}
    if vars.key?('execution_ttl')
      kwargs[:timeout] = vars['execution_ttl'].to_i.minutes
    end
    if vars.key?('poll_interval')
      kwargs[:poll_interval] = vars['poll_interval'].to_i.minutes
    end

    _log.info("#{__method__}| with options: #{template_options}")
    _log.info("#{__method__}| with kwargs: #{kwargs}")
    # _log.debug("#{__method__}| with credentials: #{credentials}")

    workflow = ManageIQ::Providers::TerraformTemplateWorkflow
    workflow.create_job(input_vars, template_options, credentials, **kwargs).tap(&:signal_start)
  rescue => err
    route_signal(:abort, "Failed to run terraform #{name}: #{err}", "error")
  end
end
