module Terraform
  class Runner
    class Request
      include Vmdb::Logging

      attr_reader :request_arguments, :action_type

      def self.build_from_hash(values)
        Request.new(values[:action_type])
               .template_path(values[:template_path])
               .name(values[:name])
               .credentials(values[:credentials])
               .input_vars(values[:input_vars], values[:input_vars_type_constraints])
               .tenant_id(values[:tenant_id])
               .tags(values[:tags])
               .env_vars(values[:env_vars])
               .stack_id(values[:stack_id])
               .stack_job_id(values[:stack_job_id])
      end

      def initialize(action_type)
        @action_type = action_type
        @request_arguments = {}
      end

      def build_json_post_arguments
        case @action_type
        when ActionType::CREATE
          @request_arguments[:name] ||= random_stack_name
          @request_arguments[:cloud_providers] ||= []
          @request_arguments[:parameters] ||= []
        when ActionType::UPDATE, ActionType::DELETE
          @request_arguments[:cloud_providers] ||= []
          @request_arguments[:parameters] ||= []
        end
        validate
        json_post_arguments
      end

      def validate
        case @action_type
        when ActionType::CREATE, ActionType::TEMPLATE_VARIABLES
          # 'templateZipFile' is added, if 'template_path' is set
          raise "'template_path' is required for #{@action_type}" unless @request_arguments.key?(:templateZipFile)
        when ActionType::UPDATE, ActionType::DELETE
          # 'templateZipFile' is added, if 'template_path' is set
          raise "'stack_id' and 'template_path' are required for #{@action_type}" unless @request_arguments.key?(:templateZipFile) && @request_arguments.key?(:stack_id)
        when ActionType::CANCEL, ActionType::RETRIEVE
          raise "'stack_id' is required for #{@action_type}" unless @request_arguments.key?(:stack_id)
        else
          raise "Invalid action_type: #{@action_type}"
        end
      end

      def template_path(template_path)
        @request_arguments[:templateZipFile] = encoded_zip_from_directory(template_path) if template_path.present?
        self
      end

      def name(name)
        @request_arguments[:name] = name if name.present?
        self
      end

      def stack_id(stack_id)
        @request_arguments[:stack_id] = stack_id if stack_id.present?
        self
      end

      def stack_job_id(stack_job_id)
        @request_arguments[:stack_job_id] = stack_job_id if stack_job_id.present?
        self
      end

      def tenant_id(tenant_id)
        @request_arguments[:tenant_id] = tenant_id if tenant_id.present?
        self
      end

      def credentials(credentials)
        @request_arguments[:cloud_providers] = provider_connection_parameters(credentials) if credentials.present?
        self
      end

      def input_vars(input_vars, input_vars_type_constraints = {})
        if !input_vars.nil?
          @request_arguments[:parameters] =
            ApiParams.to_normalized_cam_parameters(input_vars, input_vars_type_constraints)
        end
        self
      end

      def tags(tags)
        @request_arguments[:tags] = tags if tags.present?
        self
      end

      def env_vars(env_vars)
        @request_arguments[:env_vars] = env_vars if env_vars.present?
        self
      end

      private

      def json_post_arguments
        return JSON.generate(@request_arguments), "Content-Type" => "application/json".freeze
      end

      def provider_connection_parameters(credentials)
        credentials.collect do |cred|
          {
            'connection_parameters' => Terraform::Runner::Credential.new(cred.id).connection_parameters
          }
        end
      end

      # encode zip of a template directory
      def encoded_zip_from_directory(template_path)
        if !File.directory?(template_path)
          raise "Terraform template path '#{template_path}' does not exits"
        end

        dir_path = template_path # directory to be zipped
        dir_path = dir_path[0...-1] if dir_path.end_with?('/')

        Tempfile.create(%w[opentofu-runner-payload .zip]) do |zip_file_path|
          $embedded_terraform_log.debug("Create #{zip_file_path}")
          Zip::File.open(zip_file_path, Zip::File::CREATE) do |zipfile|
            Dir.glob(File.join(dir_path, "/**/*")).select { |fn| File.file?(fn) }.each do |file|
              $embedded_terraform_log.debug("Adding #{file}")
              zipfile.add(file.sub("#{dir_path}/", ''), file)
            end
          end
          Base64.encode64(File.binread(zip_file_path))
        end
      end

      def random_stack_name
        "stack-#{rand(36**8).to_s(36)}"
      end
    end
  end
end
