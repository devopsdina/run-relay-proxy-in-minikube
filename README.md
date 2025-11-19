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
- ✅ Datastore selection (Redis, DynamoDB, or in-memory)
- ✅ Relay mode (Proxy or Daemon mode)
- ✅ Monitoring stack (optional Prometheus & Grafana)
- ✅ Database viewer UI (optional RedisInsight or DynamoDB Admin)
- ✅ Automatic configuration and deployment
- ✅ Optional port forwarding for all services

The script will end with asking you if you'd like to forward the ports for the configuration selected.  It is highly recommended to select `yes` so you can access the pods on your local machine.

### 4. Access Your Services

After deployment completes, you can run also `./check-status.sh` or any kubectl commands to see the status of pods and their URLs with port numbers.

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

The LaunchDarkly Relay Proxy exposes Prometheus metrics on port 8031. To view them directly:

**Common metrics to monitor:**

- `ld_connections` - Number of active connections to LaunchDarkly
- `ld_requests_total` - Total number of HTTP requests received
- `ld_stream_connections` - Number of active streaming connections
- `ld_requests_duration_seconds` - Request duration histogram

### Health Check Monitoring with Blackbox Exporter

The monitoring stack includes Prometheus Blackbox Exporter, which actively probes the LD Relay `/status` endpoint to validate actual service health. This provides more accurate monitoring than just checking if the metrics endpoint responds.

**How it works:**
- Blackbox Exporter makes HTTP requests to `http://ld-relay:8030/status` every 30 seconds
- It validates the response contains `"status":"healthy"` in the JSON
- The result is exposed as a Prometheus metric: `probe_success{service="ld-relay"}`
- Alerts trigger when the probe fails for more than 2 minutes

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

- **Connection count over time**: Track `ld_connections` metric
- **Request rate**: Query `rate(ld_requests_total[5m])`
- **Error rate**: Track failed requests
- **Response time percentiles**: Use `ld_requests_duration_seconds` histogram

### Checking Monitoring Stack Status

Monitoring components run in the monitoring namespace.

```bash
kubectl get pods -n monitoring
```

## Setting Up Alerts

### Deploy Alert Rules

Alert rules for LD Relay and Redis are defined in `ld-relay-alerts.yaml`.

**Pre-configured alerts include:**

**Core LD Relay alerts (always active):**
- `LDRelayUnhealthy` - Relay proxy /status endpoint health check failed (uses blackbox exporter)
- `LDRelayMetricsDown` - Relay proxy metrics endpoint is not responding
- `LDRelayNoConnections` - No active connections to LaunchDarkly
- `LDRelayHighErrorRate` - Error rate above 5%
- `LDRelayFrequentRestarts` - Pod restarting frequently

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
CACHE_TTL: "-1"  # Infinite cache (never expire)
IGNORE_CONNECTION_ERRORS: "true"  # Continue serving from cache if LaunchDarkly is unreachable
INIT_TIMEOUT: "5s"  # Initial connection timeout
LOG_LEVEL: "debug"  # Verbose logging for development
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
| LD Relay | 8031 | Prometheus metrics |
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

---

## Additional Resources

- [LaunchDarkly Relay Proxy Documentation](https://docs.launchdarkly.com/home/relay-proxy)
- [Relay Proxy Helm Chart Repository](https://github.com/launchdarkly/ld-relay-helm)
- [Relay Proxy Configuration Reference](https://docs.launchdarkly.com/home/relay-proxy/configuration)
- [Using Redis with Relay Proxy](https://docs.launchdarkly.com/home/relay-proxy/using#using-redis)
- [Bitnami Redis Helm Chart](https://github.com/bitnami/charts/tree/main/bitnami/redis)
- [kube-prometheus-stack Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)


