class ManageIQ::Providers::EmbeddedTerraform::AutomationManager::ConfigurationScriptSource < ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScriptSource
  FRIENDLY_NAME = "Embedded Terraform Repository".freeze

  def self.display_name(number = 1)
    n_('Repository (Embedded Terraform)', 'Repositories (Embedded Terraform)', number)
  end

  private_class_method def self.queue_role
    "embedded_terraform"
  end

  def sync
    update!(:status => "running")

    transaction do
      current = configuration_script_payloads.index_by(&:name)

      templates = find_templates_in_git_repo
      templates.each do |template_path, value|
        $embedded_terraform_log.info("Template: #{template_path} => #{value.to_json}")

        found = current.delete(template_path) || self.class.module_parent::Template.new(:configuration_script_source_id => id)
        attrs = {
          :name         => template_path,
          :manager_id   => manager_id,
          :payload      => value.to_json,
          :payload_type => 'json'
        }

        found.update!(attrs)
      end

      current.each_value(&:destroy)
      configuration_script_payloads.reload
    end

    update!(:status => "successful", :last_updated_on => Time.zone.now, :last_update_error => nil)
  rescue => error
    update!(:status => "error", :last_updated_on => Time.zone.now, :last_update_error => error)
    raise
  end

  # Return Template name, using relative_path's basename prefix,
  #   and suffix with git-repo url details
  #     'basename(branch_name):hostname/path/relative_path_parent)'
  # eg.
  #   https://github.ibm.com/manoj-puthran/sample-scripts/tree/v2.0/terraform/templates/hello-world
  #       is converted as
  #   templates/hello-world
  def self.template_name_from_git_repo_url(git_repo_url, relative_path)
    temp_url = git_repo_url
    # URI library cannot handle git urls, so just convert it to a standard url.
    temp_url = temp_url.sub(':', '/').sub('git@', 'https://') if temp_url.start_with?('git@')
    temp_uri = URI.parse(temp_url)
    path = temp_uri.path
    path = path[0...-4] if path.end_with?('.git')
    path = path[0...-5] if path.end_with?('.git/')
    # if template dir is root, then use repo name as basename
    if relative_path == '.'
      basename = File.basename(path)
      parent_path = ''
    else
      basename = File.basename(relative_path)
      parent_path = File.dirname(relative_path)
    end
    "#{parent_path}/#{basename}"
  end

  private

  # Find Terraform Templates(dir) in the git repo.
  # Iterate through git repo worktree, and collate all terraform template dir's (dirs with .tf or .tf.json files).
  #
  # Returns [Hash] of template directories and files within it.
  def find_templates_in_git_repo
    template_dirs = {}

    # checkout repo, for sending files to terraform-runner to parse for input/ouput vars.
    checkout_git_repository do |git_checkout_tempdir|
      # traverse through files in git-worktree
      git_repository.with_worktree do |worktree|
        worktree.ref = scm_branch

        # Find all dir's with .tf/.tf.json files
        worktree.blob_list
                .group_by          { |file| File.dirname(file) }
                .select            { |_dir, files| files.any? { |f| f.end_with?(".tf", ".tf.json") } }
                .transform_values! { |files| files.map { |f| File.basename(f) } }
                .each do |relative_path, files|
          name = self.class.template_name_from_git_repo_url(git_repository.url, relative_path)

          template_full_path = File.join(git_checkout_tempdir, relative_path)

          input_vars, output_vars, terraform_version = parse_vars_in_template(template_full_path)

          template_dirs[name] = {
            :relative_path     => relative_path,
            :files             => files,
            :input_vars        => input_vars,
            :output_vars       => output_vars,
            :terraform_version => terraform_version,
          }
        end
      end
    end

    template_dirs
  rescue => error
    $embedded_terraform_log.error("Failing scaning for terraform templates in the git repo: #{error}")
    raise
  end

  # Parse template and return input-vars, output-vars & terraform-version
  def parse_vars_in_template(template_path)
    response = Terraform::Runner.parse_template_variables(template_path)
    return response['template_input_params'], response['template_output_params'], response['terraform_version']
  end
end
