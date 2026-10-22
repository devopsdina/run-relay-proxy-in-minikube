# Running LaunchDarkly Relay Proxy in Minikube

This guide walks you through setting up and running the [LaunchDarkly Relay Proxy](https://docs.launchdarkly.com/home/relay-proxy) locally using minikube and Helm.

## Quick Start (Interactive Setup) ⚡

The easiest way to get started is using the interactive setup script with automatic configuration:

### 1. Prerequisites

**Install required tools:**
```bash
# macOS
brew install minikube kubectl helm helmfile gum

# Start minikube
minikube start
```

### 2. Configure LaunchDarkly SDK Keys

```bash
cp ld-relay-secrets.yaml.example ld-relay-secrets.yaml
# Edit ld-relay-secrets.yaml and add your LaunchDarkly SDK keys
```

You must create this file and update it accordingly for the relay-proxy to start

### 3. Run Interactive Setup

```bash
./setup.sh
```

**The script will guide you through:**
- ✅ Pre-flight checks for all dependencies
- ✅ Relay version (v8 GA or the v9 release candidate, see [Relay Versions](#relay-versions-v8-and-v9))
- ✅ Datastore selection (Redis, DynamoDB, or in-memory)
- ✅ Monitoring stack (optional Prometheus & Grafana, plus an OpenTelemetry Collector for v9)
- ✅ Database viewer UI (optional RedisInsight or DynamoDB Admin)
- ✅ Automatic configuration and deployment
- ✅ Optional port forwarding for all services

The script will end with asking you if you'd like to forward the ports for the configuration selected.  It is highly recommended to select `yes` so you can access the pods on your local machine.

### 4. Access Your Services

After deployment completes, you can run also `./check-status.sh` or any kubectl commands to see the status of pods and their URLs with port numbers.

---

## Relay Versions (v8 and v9)

This repo can deploy either of two LD Relay versions. Pick one in `./setup.sh`, or set `RELAY_VERSION` when running helmfile directly:

| | v8 (default) | v9 |
|---|---|---|
| Image | `launchdarkly/ld-relay`, GA (tag pinned in `ld-relay-values-v8.yaml`) | `launchdarkly/ld-relay`, release candidate (tag pinned in `ld-relay-values-v9.yaml`) |
| Values overlay | `ld-relay-values-v8.yaml` | `ld-relay-values-v9.yaml` |
| Metrics | Prometheus `/metrics` on port 8031, scraped directly | OTLP push only, no `/metrics` endpoint. Relay sends metrics, traces and logs to an OpenTelemetry Collector, and Prometheus scrapes the collector on port 8889 |
| Metric names | `launchdarkly_relay_connections`, `launchdarkly_relay_requests`, ... | `http_server_active_requests`, `launchdarkly_relay_requests_total`, `http_server_request_duration_seconds`, ... |
| `/status` | Full status document | Same document, without the v8-only `sdkKeys`, `mobileKeys` and `autoConfigStatus` fields. Adds per-environment routes (`/status/<env>`) and `?expect=` health assertions |
| Probes | `exec` probes that grep `/status` for `"status":"healthy"` | `httpGet /status?expect=status=healthy` (200 or 412) |
| Alerts | `ld-relay-alerts.yaml` + `ld-relay-alerts-v8.yaml` | `ld-relay-alerts.yaml` + `ld-relay-alerts-v9.yaml` |

```bash
# v8 (default)
DATASTORE=redis MONITORING=full helmfile sync

# v9 release candidate
RELAY_VERSION=v9 DATASTORE=redis MONITORING=full helmfile sync
```

To switch versions, tear down the current deployment first (`./setup.sh` offers this), or run `RELAY_VERSION=v9 helmfile destroy`. `RELAY_VERSION=v9` renders every release, including the collector, so it removes either version.

Everything else is shared between the two versions: SDK keys, datastore overlays, cache and connection settings, the blackbox health check, and the pod restart alert.

**About v9:** it's a release candidate and each RC has renamed metrics or attributes, so the image is pinned to an exact RC. rc.6 still serves payload filters and doesn't yet have every v8 feature (multiple concurrent SDK keys, the Redis connect and read timeouts). See [Known issues](#known-issues) and the [v9.0.0-rc.6 docs](https://github.com/launchdarkly/ld-relay/tree/v9.0.0-rc.6/docs).

### Using a different v8 or v9 release

`RELAY_VERSION` only picks the major version. The exact image tag comes from the `image.tag` in that version's values overlay:

| `RELAY_VERSION` | Tag set in |
|---|---|
| `v8` | `ld-relay-values-v8.yaml` |
| `v9` | `ld-relay-values-v9.yaml` |

To change the version for every deployment, edit the tag in the overlay. `./setup.sh` and `helmfile sync` both pick it up:

```yaml
# ld-relay-values-v8.yaml
image:
  tag: "8.22.0"
```

To try a version once without editing files, set `RELAY_IMAGE_TAG`. It works with `./setup.sh` and with helmfile. With helmfile, `-l name=ld-relay` syncs only the Relay release. Use the same `RELAY_VERSION`, `DATASTORE` and `MONITORING` values as the running deployment:

```bash
# A different v8 release
RELAY_VERSION=v8 RELAY_IMAGE_TAG=8.22.0 DATASTORE=redis MONITORING=full \
  helmfile -l name=ld-relay sync

# A different v9 release candidate
RELAY_VERSION=v9 RELAY_IMAGE_TAG=9.0.0-rc.5 DATASTORE=redis MONITORING=full \
  helmfile -l name=ld-relay sync

# Or through the interactive setup
RELAY_IMAGE_TAG=8.22.0 ./setup.sh
```

The tag must belong to the selected major version: an 8.x tag for `v8`, a 9.x tag for `v9`. Each overlay carries its version's probes, metrics and config, so a mismatch isn't a valid deployment. `./setup.sh` and helmfile both stop with an error if the tag in the overlay or in `RELAY_IMAGE_TAG` doesn't match:

```
Relay image tag "9.0.0-rc.6" is not a v8 release. Use a v8 tag, or set RELAY_VERSION to match the tag.
```

Don't override the tag with `helmfile sync --set image.tag=...`. Helmfile can't see `--set` values, so they skip this check.

To see which tag is running:

```bash
kubectl get deployment ld-relay -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Notes:

- A `RELAY_IMAGE_TAG` override lasts only until the next `./setup.sh` or `helmfile sync` without it, which goes back to the tag in the overlay file.
- The `./setup.sh` version menu shows the overlay tags. The summary shows the tag that will deploy, including a `RELAY_IMAGE_TAG` override.
- For v9, metric and attribute names change between RCs. The alert rules in `ld-relay-alerts-v9.yaml` and the collector config follow rc.6, so check the [ld-relay release notes](https://github.com/launchdarkly/ld-relay/releases) before switching to another RC.

---


## Overview

The LaunchDarkly Relay Proxy is a small application that connects to LaunchDarkly's streaming API and acts as a local proxy for LaunchDarkly SDKs. This is useful for:

- Reducing outbound connections from your network to LaunchDarkly
- Supporting SDKs in environments that cannot directly connect to LaunchDarkly
- Improving performance by caching flag data closer to your applications
- Testing LaunchDarkly integrations in a local Kubernetes environment

## Prerequisites

Before you begin, you'll need to install the following tools:

### 1. minikube

minikube runs a local Kubernetes cluster for development and testing.

**macOS:**
```bash
# Using Homebrew
brew install minikube

# Or using direct download
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-darwin-amd64
sudo install minikube-darwin-amd64 /usr/local/bin/minikube
```

### 2. kubectl

kubectl is the Kubernetes command-line tool.

**macOS:**
```bash
brew install kubectl
```

### 3. Helm

Helm is the package manager for Kubernetes.

**macOS:**
```bash
brew install helm
```

### 4. LaunchDarkly SDK Key

You'll need an SDK key from your LaunchDarkly environment:

1. Log in to [LaunchDarkly](https://app.launchdarkly.com)
2. Navigate to **Project settings** → **Environments**
3. Select your project
4. Copy the **SDK key** for the environment you want to use (e.g., Production, Test)

## Getting Started

### Step 1: Start minikube

Start your local Kubernetes cluster:

```bash
minikube start
```

This will:
- Download the minikube ISO (if first time)
- Create a VM with Kubernetes
- Configure kubectl to use the minikube cluster

Verify minikube is running:
```bash
minikube status
```

### Step 2: Add the LaunchDarkly Helm Repository

Add the official LaunchDarkly Relay Proxy Helm chart repository:

```bash
helm repo add launchdarkly-ld-relay https://launchdarkly.github.io/ld-relay-helm
helm repo update
```

### Step 3: REQUIRED! Configure Your Secrets

**Important:** Never commit your SDK keys to version control!

For local testing, create separate secrets files:

```bash
# Copy the example secrets files
cp ld-relay-secrets.yaml.example ld-relay-secrets.yaml
cp redis-secrets.yaml.example redis-secrets.yaml
```

Edit `ld-relay-secrets.yaml`:
```yaml
relay:
  environment:
    LD_ENV_production: "sdk-your-actual-key-here"
    REDIS_PASSWORD: "your-redis-password" # MUST MATCH PASSWORD SET IN redis-secrets.yaml
```

Edit `redis-secrets.yaml`:
```yaml
auth:
  password: "your-redis-password"  # MUST MATCH REDIS_PASSWORD SET IN ld-relay-secrets.yaml
```

NOTE: For DynamoDB, we do not need a separate secrets file for local, fake values can be passed and are already set.

You can name the environment anything you like (e.g., `LD_ENV_production`, `LD_ENV_test`, `LD_ENV_development`).

## Configuration

The `ld-relay-values.yaml` and `redis-values.yaml` files contain non-sensitive configuration. Below are common configuration options you can add as needed. For the complete list of available options, see the [official chart values.yaml](https://github.com/launchdarkly/ld-relay-helm/blob/main/values.yaml).

### Multiple Environments

You can configure multiple LaunchDarkly environments in your `ld-relay-secrets.yaml`:

```yaml
relay:
  environment:
    LD_ENV_production: "sdk-prod-key"
    LD_ENV_staging: "sdk-staging-key"
    LD_ENV_development: "sdk-dev-key"
```

### Resource Limits

Set CPU and memory limits:

```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi
```

### Replicas and Auto-scaling

Run multiple replicas:

```yaml
replicaCount: 3

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
```

### Additional Configuration

For more configuration options:
- **LD Relay**: See the [official ld-relay chart values.yaml](https://github.com/launchdarkly/ld-relay-helm/blob/main/values.yaml)
- **Redis**: See the [Bitnami Redis chart values.yaml](https://github.com/bitnami/charts/tree/main/bitnami/redis)

## Using the Relay Proxy with SDKs

Configure your LaunchDarkly SDKs to use the Relay Proxy by setting the base URI:

**JavaScript:**
```javascript
const client = LDClient.initialize('your-client-side-id', user, {
  baseUrl: 'http://localhost:8030',
  streamUrl: 'http://localhost:8030',
  eventsUrl: 'http://localhost:8030'
});
```

**Note:** When using the Relay Proxy in minikube from outside the cluster, you'll need to use `localhost:8030` with port-forwarding. For SDKs running inside the cluster, use the service name: `http://ld-relay:8030`.

## Persistent Datastore Options

The LD Relay can be configured with different persistent datastores:

- Redis
- DynamoDB

DynamoDB uses fake AWS credentials.

### In-Memory Only

No persistent storage - minimal setup for testing.

---

## Database Viewer UI (Optional)

Optional web-based management interfaces for your datastore:

- RedisInsight (for Redis)
- DynamoDB Admin


**✨ Zero Configuration:** Database connection to `redis-master:6379` is automatically configured on deployment. Just open the UI and start browsing!

The `ld-relay` table is automatically connected if you select `yes` for the Database Management UI

---

## Monitoring with Prometheus and Grafana

This setup includes Prometheus and Grafana for monitoring your LaunchDarkly Relay Proxy and Redis instances.

### Accessing Grafana Dashboard

To access the Grafana web interface:

- open your browser to http://localhost:3000

**Default Credentials:**
- Username: `admin`
- Password: `admin`

### Accessing Prometheus UI

To access the Prometheus web interface:

- open your browser to http://localhost:9090

### LD Relay Metrics

Metrics only appear once Relay has served SDK traffic.

**v8:** Relay serves Prometheus metrics on port 8031 (`kubectl port-forward svc/ld-relay 8031:8031`, then `curl http://localhost:8031/metrics`). Prometheus scrapes them with the `ld-relay` job.

- `launchdarkly_relay_connections` - Number of SDK stream connections currently open to Relay
- `launchdarkly_relay_newconnections` - Cumulative number of SDK stream connections
- `launchdarkly_relay_requests` - Cumulative number of requests, by `route`, `method` and `env`
- `launchdarkly_relay_request_duration` - Request duration histogram, in **microseconds**

The v8 request metrics have no status-code label, so you can't calculate an error rate on v8.

**v9:** Relay pushes OTLP to the OpenTelemetry Collector (`otel-collector-values.yaml`). The collector converts it to Prometheus metrics on port 8889 (`kubectl port-forward -n monitoring svc/otel-collector 8889:8889`), and Prometheus scrapes them with the `ld-relay-otel` job. Relay's own series keep `job="ld-relay"`.

- `http_server_active_requests` - Requests in flight on every endpoint. Filter `launchdarkly_relay_endpoint_type="stream"` to get the v8 `connections` value
- `launchdarkly_relay_requests_total` - Cumulative requests. Filter `launchdarkly_relay_endpoint_type="stream"` to get the v8 `newconnections` value
- `http_server_request_duration_seconds` - Request duration histogram in seconds, with `http_response_status_code` (not recorded for streams)
- `launchdarkly_relay_events_*` - Event pipeline: received, sent, failed, dropped, pending (these require `USE_EVENTS`, see [Known issues](#known-issues))
- `target_info` - One series per Relay process (its OTel resource attributes)

v9 renamed the attributes: `env` is now `launchdarkly_environment_name`, `route` is `http_route`, `method` is `http_request_method` and `userAgent` is `user_agent_original`. `platformCategory`, `sdkWrapper` and `relayId` are no longer reported on metrics. v9 traces and logs go to the collector's `debug` exporter (`kubectl logs -n monitoring deploy/otel-collector`).

### Health Check Monitoring with Blackbox Exporter

The monitoring stack includes Prometheus Blackbox Exporter, which actively probes the LD Relay `/status` endpoint to validate actual service health. This provides more accurate monitoring than just checking if the metrics endpoint responds.

**How it works:**
- Blackbox Exporter makes HTTP requests to `http://ld-relay:8030/status` every 30 seconds
- It validates the response contains `"status":"healthy"` in the JSON
- The result is exposed as a Prometheus metric: `probe_success{target="ld-relay-status"}`
- Alerts trigger when the probe fails for more than 2 minutes

`"healthy"` only means every environment is connected to LaunchDarkly. **It doesn't reflect the data store:** Relay still reports `healthy` while Redis or DynamoDB is down.

**v9 per-environment probes** (`blackbox-exporter-values-v9.yaml.gotmpl`): v9 can check its own status and answer with an HTTP status code: 200 when every `expect` clause holds, 412 when one doesn't, 404 for an unknown environment, and 503 before Relay has initialized. For every `LD_ENV_<name>` key in `ld-relay-secrets.yaml`, the blackbox exporter probes:
- `ld-relay-env-<name>`: `/status/<name>?expect=status=connected&expect=connectionStatus.state=VALID`
- `ld-relay-datastore-<name>`: `/status/<name>?expect=dataStoreStatus.state=VALID` (only with Redis or DynamoDB)

v8 ignores `?expect=` and always returns 200, so these probes are only deployed for v9.

```bash
curl -i 'http://localhost:8030/status?expect=status=healthy'   # 200, or 412 if degraded
curl http://localhost:8030/status/<env>                        # one environment (v9)
```

Relay only marks the store `INTERRUPTED` after a store operation fails. With the infinite cache (`CACHE_TTL=-1s`), an idle Relay doesn't touch the store, so it can take a flag change or a Relay restart before an outage shows up.

**View blackbox exporter targets:**
```bash
kubectl port-forward -n monitoring svc/prometheus-blackbox-exporter 9115:9115
# Open: http://localhost:9115/targets
```

### Redis Metrics

Redis metrics are automatically collected by the Prometheus exporter and available in Prometheus/Grafana.

**To import a pre-built Redis dashboard in Grafana:**

1. Log in to Grafana (http://localhost:3000) - **Username:** `admin` **Password:** `admin`
2. Click the "+" icon in the sidebar → Import
3. Enter dashboard ID: `11835` or `14091` (popular Redis dashboards)
4. Click "Load"
5. Select the Prometheus data source
6. Click "Import"

### Creating Custom LD Relay Dashboards

In Grafana, you can create custom dashboards to visualize:

| Panel | v8 query | v9 query |
|---|---|---|
| SDK stream connections | `sum(launchdarkly_relay_connections)` | `sum(http_server_active_requests{launchdarkly_relay_endpoint_type="stream"})` |
| Request rate | `sum(rate(launchdarkly_relay_requests[5m]))` | `sum(rate(launchdarkly_relay_requests_total[5m]))` |
| Error rate | n/a (no status label) | `sum(rate(http_server_request_duration_seconds_count{http_response_status_code=~"5.."}[5m])) / sum(rate(http_server_request_duration_seconds_count[5m]))` |
| p95 latency | `histogram_quantile(0.95, sum by (le) (rate(launchdarkly_relay_request_duration_bucket[5m])))` (µs) | `histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_seconds_bucket[5m])))` (s) |

### Checking Monitoring Stack Status

Monitoring components run in the monitoring namespace.

```bash
kubectl get pods -n monitoring
```

## Setting Up Alerts

### Deploy Alert Rules

Alert rules are `PrometheusRule` resources that the helmfile applies after the monitoring stack syncs. It applies the shared rules, plus the selected version's rules and the datastore's rules, and deletes the other version's rules.

**Pre-configured alerts include:**

**Shared (`ld-relay-alerts.yaml`):**
- `LDRelayUnhealthy` - `/status` is not `healthy` (blackbox exporter)
- `LDRelayFrequentRestarts` - Pod restarting frequently

**v8 (`ld-relay-alerts-v8.yaml`):**
- `LDRelayMetricsDown` - The `:8031/metrics` scrape is failing
- `LDRelayNoSDKStreams` - No SDKs hold a stream connection (severity `info`, normal when idle)

**v9 (`ld-relay-alerts-v9.yaml`):**
- `LDRelayEnvironmentUnhealthy` - An environment is not connected with a VALID data source (per-environment probe)
- `LDRelayDataStoreUnhealthy` - An environment's persistent store is not VALID (per-environment probe)
- `LDRelayTelemetryMissing` - No Relay metrics are reaching Prometheus through the collector
- `LDRelayOTelCollectorDown` - Prometheus can't scrape the collector
- `LDRelayNoSDKStreams` - No SDKs hold a stream connection (severity `info`)
- `LDRelayHighErrorRate` - More than 5% of requests returned 5xx
- `LDRelayEventsFailed` / `LDRelayEventsDropped` - Analytics events failed or were dropped
- `LDRelayMetricCardinalityOverflow` - Series merged into the `otel_metric_overflow` series (raise `OTEL_METRICS_CARDINALITY_LIMIT`)

**Datastore-specific alerts (conditional based on DATASTORE selection):**
- `RedisDown` - Redis is not responding (only when `DATASTORE=redis`)
- `RedisHighMemoryUsage` - Redis memory above 80% (only when `DATASTORE=redis`)
- `DynamoDBLocalDown` - DynamoDB Local is not responding (only when `DATASTORE=dynamodb`)

> **Note:** Datastore alerts are automatically applied based on your deployment configuration. This prevents false positives when a datastore isn't deployed.

### Configure Notification Channels

To receive alerts via email, Slack, PagerDuty, etc., update `prometheus-values.yaml`:

**Example: Slack notifications**
```yaml
alertmanager:
  config:
    receivers:
      - name: 'slack'
        slack_configs:
          - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
            channel: '#alerts'
            title: 'LD Relay Alert'
```

**Example: Email notifications**
```yaml
alertmanager:
  config:
    global:
      smtp_smarthost: 'smtp.gmail.com:587'
      smtp_from: 'alerts@example.com'
      smtp_auth_username: 'your-email@gmail.com'
      smtp_auth_password: 'your-app-password'
    receivers:
      - name: 'email'
        email_configs:
          - to: 'team@example.com'
```

**Example: Webhook notifications**
```yaml
alertmanager:
  config:
    receivers:
      - name: 'webhook'
        webhook_configs:
          - url: 'http://your-webhook-endpoint'
```

## Configuration Reference

### Default LD Relay Settings

The relay is configured with optimized settings for local development:

```yaml
CACHE_TTL: "-1s"  # Infinite cache (never expire)
IGNORE_CONNECTION_ERRORS: "true"  # Continue serving from cache if LaunchDarkly is unreachable
INIT_TIMEOUT: "5s"  # Initial connection timeout
LOG_LEVEL: "debug"  # Verbose logging for development
MAX_CLIENT_REQUEST_BODY_SIZE: "5MiB"  # REPORT body limit; v9's default, set explicitly so v8 matches
```

### Datastore Configuration

**Redis:**
- Infinite cache TTL configured
- Connection: `redis-master:6379`
- Password configured via `redis-secrets.yaml`

**DynamoDB:**
- Table name: `ld-relay`
- Key schema: `namespace` (HASH) + `key` (RANGE)
- Endpoint: `http://dynamodb-local:8000`
- Fake credentials: `fakeAccessKeyId` / `fakeSecretAccessKey`

### Port Reference

Select `yes` for port forwarding during the setup.sh to automatically have all ports forwarded for what you chose to deploy.

| Service | Port | Purpose |
|---------|------|---------|
| LD Relay | 8030 | API/Status endpoint |
| LD Relay | 8031 | Prometheus metrics (v8 only) |
| OpenTelemetry Collector | 4317 / 8889 | OTLP gRPC in / Prometheus metrics out (v9 only) |
| Redis | 6379 | Redis server |
| RedisInsight | 8001 | Web UI |
| DynamoDB Local | 8000 | DynamoDB API |
| DynamoDB Admin | 8001 | Web UI |
| Grafana | 3000 | Monitoring dashboard |
| Prometheus | 9090 | Metrics UI |

### Troubleshooting

**LD Relay not starting:**
```bash
# Check logs
kubectl logs -l app.kubernetes.io/name=ld-relay --tail=50

# Check status
kubectl get pods -l app.kubernetes.io/name=ld-relay
```

**Clean up everything:**
```bash
# Delete all deployments
./setup.sh  # Will detect existing deployments and prompt for cleanup
```

**`kubectl` version skew:** Docker Desktop puts its own `kubectl` at `/usr/local/bin/kubectl`, and it can be several minor versions behind the cluster minikube creates. Check with `which -a kubectl` and `kubectl version`. Putting `/opt/homebrew/bin` first in `PATH` uses the Homebrew `kubectl`.

### Known issues

- **v9.0.0-rc.6 doesn't repopulate Redis after a Redis outage at startup.** If Redis isn't accepting connections when Relay starts, Relay logs `Persistent store is available again` once Redis is back, but doesn't write its flag data. Redis stays empty until the next flag change, while `/status` reports the store `VALID`. v8 re-writes its data within a second. The helmfile avoids this by waiting for Redis to be Ready before installing Relay (`wait: true`).
- **Analytics events are not forwarded.** `USE_EVENTS` defaults to `false` and isn't set here, so Relay answers SDK event posts with `503`, and the v9 event metrics and alerts stay empty. To forward events to LaunchDarkly, set `USE_EVENTS: "true"` in `ld-relay-values.yaml`.
- **The v9 OTLP exporters fail for up to about a minute if Relay starts before the collector.** The helmfile installs the collector first. A Relay started earlier recovers on its own.

---

## Additional Resources

- [LaunchDarkly Relay Proxy Documentation](https://docs.launchdarkly.com/home/relay-proxy)
- [Relay Proxy Helm Chart Repository](https://github.com/launchdarkly/ld-relay-helm)
- [Relay Proxy Configuration Reference](https://docs.launchdarkly.com/home/relay-proxy/configuration)
- [Relay Proxy v9.0.0-rc.6 docs](https://github.com/launchdarkly/ld-relay/tree/v9.0.0-rc.6/docs) (configuration, metrics, endpoints, tracing)
- [OpenTelemetry Collector Helm Chart](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-collector)
- [Using Redis with Relay Proxy](https://docs.launchdarkly.com/home/relay-proxy/using#using-redis)
- [Bitnami Redis Helm Chart](https://github.com/bitnami/charts/tree/main/bitnami/redis)
- [kube-prometheus-stack Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)


