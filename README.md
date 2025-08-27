# ManageIQ::Providers::EmbeddedTerraform

[![CI](https://github.com/ManageIQ/manageiq-providers-embedded_terraform/actions/workflows/ci.yaml/badge.svg?branch=master)](https://github.com/ManageIQ/manageiq-providers-embedded_terraform/actions/workflows/ci.yaml)
[![Code Climate](https://codeclimate.com/github/ManageIQ/manageiq-providers-embedded_terraform.svg)](https://codeclimate.com/github/ManageIQ/manageiq-providers-embedded_terraform)
[![Test Coverage](https://codeclimate.com/github/ManageIQ/manageiq-providers-embedded_terraform/badges/coverage.svg)](https://codeclimate.com/github/ManageIQ/manageiq-providers-embedded_terraform/coverage)
[![Chat](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/ManageIQ/manageiq-providers-embedded_terraform?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)


ManageIQ plugin for the Embedded Terraform provider.

## Development

See the section on plugins in the [ManageIQ Developer Setup](http://manageiq.org/docs/guides/developer_setup/plugins)

For quick local setup run `bin/setup`, which will clone the core ManageIQ repository under the *spec* directory and setup necessary config files. If you have already cloned it, you can run `bin/update` to bring the core ManageIQ code up to date.

### Running Opentofu Runner locally

First ensure that you have the opentofu-runner image pulled locally:
```
docker pull docker.io/manageiq/opentofu-runner:latest
```

If your database connection requires a password then create a secret:
```
echo '{"DATABASE_PASSWORD":"mypassword"}' | docker secret create opentofu-runner-secret -
```

And add `--secret opentofu-runner-secret` to the command below

Now you can start your opentofu-runner:
```
docker run --name=opentofu-runner --rm --network=host --env NODE_ENV=development --env DATABASE_HOSTNAME=localhost --env DATABASE_NAME=vmdb_development --env DATABASE_USERNAME=root --env MEMCACHE_SERVERS=127.0.0.1:11211 --env PORT=6000 --expose=6000 docker.io/manageiq/opentofu-runner:latest
```

Verify that everything is working by checking `Terraform::Runner.available?` with a rails console:
```
$ TERRAFORM_RUNNER_URL=http://localhost:6000 rails c
>> Terraform::Runner.available?
=> true
```

To stop the opentofu-runner `docker stop opentofu-runner` in another terminal.

## License

The gem is available as open source under the terms of the [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0).

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
