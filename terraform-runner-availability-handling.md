# Embedded Terraform Runner Availability Handling

This document explains how the Embedded Terraform provider handles temporary unavailability of the Terraform Runner service (e.g., during OOM restarts, data migrations after upgrades, or network issues).

## Design Principles

1. **Never block a worker** — No `sleep` loops or waiting in the HTTP layer. Workers remain free to process other requests including UI actions.
2. **Requeue at the job level** — When the Terraform Runner is unavailable, jobs requeue themselves via MiqQueue with a delay, freeing the worker immediately.
3. **Fail fast at the HTTP layer** — The `Terraform::Runner.post` method makes one attempt. On 503 or connection failure, it raises `Terraform::Runner::TemporarilyUnavailable` immediately.
4. **Availability-cache TTL** — `Terraform::Runner.available?` caches `false` results for a configurable duration (default 30 seconds) to avoid hammering the `/ready` endpoint when the service is down.
5. **Give up after TTL** — Jobs track how long they've been waiting and abort after a configurable maximum (default 10 minutes).

## How It Works

### `Terraform::Runner.available?`

- Calls the `/ready` health endpoint on the Terraform Runner service.
- Returns `true` if the service responds with `{"status": "UP"}`.
- Caches `true` indefinitely (until reset by a failed API call).
- Caches `false` for a availability-cache TTL (default 30 seconds, configurable via `TERRAFORM_RUNNER_AVAILABILITY_CACHE_TTL`).
- After the availability-cache TTL expires, the next call re-checks `/ready`.

### `Terraform::Runner::TemporarilyUnavailable`

A custom exception raised by `Terraform::Runner.post` when:
- The API returns HTTP 503 (Service Unavailable)
- A `Faraday::ConnectionFailed` or `Faraday::TimeoutError` occurs

When raised, the availability cache is immediately reset (both `@available` and `@available_checked_at` cleared) so the next `available?` call re-checks.

### Job State Machine (Provision/Reconfigure/Retire)

The Job lifecycle includes availability checks at key points:

1. **`poll_execute`** — Before executing, checks `available?`. If unavailable, requeues itself with a delay.
2. **`execute`** — Double-checks `available?` before calling `Terraform::Runner.run(...)`. Also rescues `TemporarilyUnavailable` (race condition window) and requeues.
3. **`poll_runner`** — Checks `available?` before polling stack status. Also rescues `TemporarilyUnavailable` from `retrieve_stack` and requeues.

### Provision State Machine (ServiceEmbeddedTerraform)

1. **`run_provision`** — Checks `available?` before signaling provision. If unavailable, requeues phase.
2. **`provision`** — Double-checks `available?` and rescues `TemporarilyUnavailable` from `Stack.create_stack`.

### Stack Deletion (Retirement)

1. **`delete_stack`** — Checks `available?` before calling `raw_delete_stack`. If unavailable, requeues via `MiqQueue`.
2. **`raw_delete_stack`** — Rescues `TemporarilyUnavailable` and requeues.

### TTL-Based Give-Up

All requeue paths track a `runner_wait_started_at` timestamp:
- **Job**: stored in `options[:runner_wait_started_at]`
- **Provision**: stored in `phase_context[:runner_wait_started_at]`
- **Stack delete**: stored in `options[:runner_wait_started_at]`

On each requeue cycle, elapsed time is checked. If it exceeds `TERRAFORM_RUNNER_AVAILABILITY_MAX_WAIT_TIME` (default 600 seconds / 10 minutes), the operation is aborted/failed rather than requeuing forever.

When the runner becomes available again, the timestamp is cleared.

## Scenarios

### Scenario 1: ManageIQ and Terraform Runner upgraded together

Both services restart. ManageIQ's cached availability state is cleared. Jobs check `available?`, find the runner not ready, and requeue. Once the runner finishes migration and reports `UP`, jobs proceed normally.

### Scenario 2: Only Terraform Runner is upgraded (ManageIQ not restarted)

ManageIQ may have `available?` cached as `true`. A job attempts an API call. If the runner returns 503 or is unreachable, `TemporarilyUnavailable` is raised. The job catches it, resets the cache, and requeues. Subsequent jobs see `available? == false` (from availability cache) and requeue without making API calls.

### Scenario 3: Terraform Runner restarts unexpectedly (OOM)

Same as Scenario 2. The first job to encounter the failure resets the cache. Other jobs benefit from the availability-cache TTL and requeue immediately.

### Scenario 4: UI requests (parse_template_variables, retrieve_stack)

These calls go through `Terraform::Runner.post` which fails fast. If the runner is unavailable, `TemporarilyUnavailable` is raised to the caller immediately — no blocking. The UI should handle this gracefully (display an error message).

## Configuration (Environment Variables)

| Variable | Default | Description |
|----------|---------|-------------|
| `TERRAFORM_RUNNER_URL` | `https://opentofu-runner:6000` | Terraform Runner service URL |
| `TERRAFORM_RUNNER_AVAILABILITY_CACHE_TTL` | `30` | Seconds to cache `available? == false` before re-checking |
| `TERRAFORM_RUNNER_AVAILABILITY_MAX_WAIT_TIME` | `600` | Maximum seconds a job will wait (via requeue) for the runner before giving up |

## Summary

- Workers are never blocked by Terraform Runner unavailability.
- UI requests fail fast with an error.
- Background jobs requeue themselves with a 30-second delay, up to 10 minutes total.
- If the runner doesn't recover within the TTL, jobs are aborted with a clear error message.
- The availability-cache TTL prevents excessive health-check traffic during outages.
