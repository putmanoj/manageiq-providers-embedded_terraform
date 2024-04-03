class ManageIQ::Providers::TerraformTemplateWorkflow < ManageIQ::Providers::TerraformRunnerWorkflow
  def self.create_job(*args, **kwargs)
    role_or_template_options = args[1]
    args[1] = role_or_template_options.merge(:role => "embedded_terraform")
    super(*args, **kwargs)
  end

  def execution_type
    "terraform-template"
  end

  def launch_runner
    inputs, credentials, template_path = options.values_at(:input_vars, :credentials, :template_path)
    _log.debug("#{__method__}: run_sync with inputs: #{inputs}, #{template_path}, nil, #{credentials}")
    Terraform::Runner.run_async(inputs, template_path, nil, credentials)
  end

  private

  def verify_options
    if !(options.has_key("configuration_script_source_id") && options.has_key("template_relative_path"))
      raise ArgumentError, "must pass :configuration_script_source_id, :template_relative_path pair"
    end
  end

  def adjust_options_for_git_checkout_tempdir!
    options[:template_path] = File.join(options[:git_checkout_tempdir], options[:template_relative_path])
    _log.info("#{__method__}| template_path: #{options[:template_path]}")
    save!
  end
end
