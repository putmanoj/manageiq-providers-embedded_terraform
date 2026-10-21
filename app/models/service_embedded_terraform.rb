class ServiceEmbeddedTerraform < Service
  AUTOMATE_DRIVES = false

  def stack(action)
    service_resources.find_by(:name => action, :resource_type => 'OrchestrationStack').try(:resource)
  end
end
