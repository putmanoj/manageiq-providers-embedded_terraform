class OpentofuWorker < MiqWorker
  include MiqWorker::ServiceWorker

  self.required_roles        = ["embedded_terraform"]
  self.rails_worker          = false
  self.maximum_workers_count = 1

  self.worker_settings_paths = [
    %i[log level_embedded_terraform],
    %i[workers worker_base opentofu_worker]
  ]

  MIQ_CONTAINERS_ROOT_DIR = "/var/lib/manageiq/containers/storage".freeze
  OPENTOFU_RUNTIME_DIR    = "/var/lib/manageiq/opentofu-runner".freeze
  SERVICE_PORT = 6000

  def self.service_base_name
    "opentofu-runner"
  end

  def self.service_file
    "#{service_base_name}.service"
  end

  def self.kill_priority
    MiqWorkerType::KILL_PRIORITY_GENERIC_WORKERS
  end

  def self.start_worker(*params)
    create_worker_record(*params).tap(&:start)
  end

  def worker_deployment_name
    @worker_deployment_name ||= "#{deployment_prefix}opentofu-runner"
  end

  def container_port
    SERVICE_PORT
  end

  def add_liveness_probe(container_definition)
    container_definition[:livenessProbe] = container_definition[:livenessProbe].except(:exec).merge(:httpGet => {:path => "/live", :port => SERVICE_PORT, :scheme => "HTTPS"})
  end

  def add_readiness_probe(container_definition)
    container_definition[:readinessProbe] = {
      :httpGet             => {:path => "/ready", :port => SERVICE_PORT, :scheme => "HTTPS"},
      :initialDelaySeconds => 60,
      :timeoutSeconds      => 3
    }
  end

  # The opentofu-runner pod is a service worker but isn't scalable so the
  # stop_container method should delete_container_objects like a deployment-per-worker
  # not scale_deployment like a service_worker.
  def stop_container
    delete_container_objects
  end

  private

  # There can only be a single instance running so the unit name can just be
  # "opentofu-runner.service"
  def unit_instance
    ""
  end

  def container_image_name
    "opentofu-runner"
  end

  def container_image
    ENV["OPENTOFU_RUNNER_IMAGE"] || worker_settings[:container_image] || default_image
  end

  def enable_systemd_unit
    super
    create_tls_certs
    create_podman_secret
  end

  def environment_variables
    super.merge(
      "PORT"         => container_port.to_s,
      "LOG4JS_LEVEL" => ::Settings.log.level_embedded_terraform,
      "TF_OFFLINE"   => worker_settings[:opentofu_offline].to_s
    )
  end

  def systemd_environment_variables
    {
      "DATABASE_HOSTNAME"     => database_configuration[:host],
      "DATABASE_NAME"         => database_configuration[:database],
      "DATABASE_USERNAME"     => database_configuration[:username],
      "MEMCACHE_SERVERS"      => ::Settings.session.memcache_server,
      "OPENTOFU_RUNNER_IMAGE" => container_image
    }
  end

  def container_environment_variables
    super.merge("HOME" => "/home/node")
  end

  def configure_service_worker_deployment(definition)
    super
    # overwriting container port to be same as opentofu-runner service port i.e. in this case 6000
    definition[:spec][:template][:spec][:containers].first[:ports] = [{:containerPort => container_port}]

    # these volume mounts are require by terraform runner to create the stack, mentioned it as {} so that it can be writable
    definition[:spec][:template][:spec][:containers].first[:volumeMounts] << {:name => "terraform-bin-empty", :mountPath => "/home/node/terraform/bin"}
    definition[:spec][:template][:spec][:volumes] << {:name => "stacks-empty", :emptyDir => {}}
    definition[:spec][:template][:spec][:containers].first[:volumeMounts] << {:name => "terraform-d-empty", :mountPath => "/home/node/terraform/.terraform.d"}
    definition[:spec][:template][:spec][:volumes] << {:name => "terraform-bin-empty", :emptyDir => {}}
    definition[:spec][:template][:spec][:containers].first[:volumeMounts] << {:name => "stacks-empty", :mountPath => "/stacks"}
    definition[:spec][:template][:spec][:volumes] << {:name => "terraform-d-empty", :emptyDir => {}}

    if ENV["API_SSL_SECRET_NAME"].present?
      # mounting secret for opentofu-runner SSL usage
      definition[:spec][:template][:spec][:containers].first[:volumeMounts] << {:name => "cert-path", :mountPath => "/opt/app-root/src/config/cert"}
      definition[:spec][:template][:spec][:volumes] << {:name => "cert-path", :secret => {:secretName => ENV["API_SSL_SECRET_NAME"], :items => [{:key => "tf_runner_crt", :path => "tls.crt"}, {:key => "tf_runner_key", :path => "tls.key"}], :defaultMode => 420}}
    end
  end

  def create_tls_certs
    opentofu_runner_certs_dir = Pathname.new("#{OPENTOFU_RUNTIME_DIR}/certs")
    unless opentofu_runner_certs_dir.exist?
      opentofu_runner_certs_dir.mkpath
      opentofu_runner_certs_dir.chown(manageiq_uid, manageiq_gid)
    end

    opentofu_runner_tls_key = opentofu_runner_certs_dir.join("tls.key")
    opentofu_runner_tls_crt = opentofu_runner_certs_dir.join("tls.crt")

    return if opentofu_runner_tls_key.exist? && opentofu_runner_tls_crt.exist?

    AwesomeSpawn.run!("/usr/bin/generate_miq_server_cert.sh", :env => {"NEW_CERT_FILE" => opentofu_runner_tls_crt.to_s, "NEW_KEY_FILE" => opentofu_runner_tls_key.to_s})

    # NOTE: non-root podman pods run as a random ID mapped user and don't belong to
    # the normal manageiq user/group so we have to allow read for other
    opentofu_runner_tls_key.chmod(0o644)
    opentofu_runner_tls_key.chown(manageiq_uid, manageiq_gid)
    opentofu_runner_tls_crt.chmod(0o644)
    opentofu_runner_tls_crt.chown(manageiq_uid, manageiq_gid)
  end

  def create_podman_secret
    return if AwesomeSpawn.run("runuser", :params => [[:login, "manageiq"], [:command, "podman secret exists --root=#{MIQ_CONTAINERS_ROOT_DIR} opentofu-runner-secret"]]).success?

    secret = {"DATABASE_PASSWORD" => database_configuration[:password]}

    AwesomeSpawn.run!("runuser", :params => [[:login, "manageiq"], [:command, "podman secret create --root=#{MIQ_CONTAINERS_ROOT_DIR} opentofu-runner-secret -"]], :in_data => secret.to_json)
  end

  def database_configuration
    ActiveRecord::Base.connection_db_config.configuration_hash
  end

  def manageiq_uid
    @manageiq_uid ||= Process::UID.from_name("manageiq")
  end

  def manageiq_gid
    @manageiq_gid ||= Process::GID.from_name("manageiq")
  end
end
