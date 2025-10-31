# Running LaunchDarkly Relay Proxy in Minikube

This guide walks you through setting up and running the [LaunchDarkly Relay Proxy](https://docs.launchdarkly.com/home/relay-proxy) locally using minikube and Helm.

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

### Step 3: Configure Your Secrets (Local Testing)

**Important:** Never commit your SDK keys to version control!

For local testing, create separate secrets files:

```bash
# Copy the example secrets files
cp ld-secrets.yaml.example ld-relay-secrets.yaml
cp redis-secrets.yaml.example redis-secrets.yaml
```

Edit `ld-relay-secrets.yaml`:
```yaml
relay:
  environment:
    LD_ENV_production: "sdk-your-actual-key-here"
    REDIS_PASSWORD: "your-redis-password"
```

Edit `redis-secrets.yaml`:
```yaml
auth:
  password: "your-redis-password"  # Must match REDIS_PASSWORD above
```

You can name the environment anything you like (e.g., `LD_ENV_production`, `LD_ENV_test`, `LD_ENV_development`).

**Note:** Both secrets files are in `.gitignore` and will not be committed to version control.

### Step 4: Install with Helmfile (Recommended)

Deploy both Redis and the Relay Proxy together:

```bash
# Update Helm repositories
helm repo update

# Deploy everything
helmfile sync
```

**Or install manually with Helm:**

```bash
# Install Redis first
helm install redis bitnami/redis \
  -f redis-values.yaml \
  -f redis-secrets.yaml

# Then install LD Relay
helm install ld-relay launchdarkly-ld-relay/ld-relay \
  -f ld-relay-values.yaml \
  -f ld-relay-secrets.yaml
```

### Step 5: Verify the Deployment

Check that the pod is running:

```bash
kubectl get pods
```

You should see output like:
```
NAME                        READY   STATUS    RESTARTS   AGE
ld-relay-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

View the logs:
```bash
kubectl logs -l app.kubernetes.io/name=ld-relay --follow
```

### Step 6: Access the Relay Proxy

The Relay Proxy runs on port 8030. To access it locally, set up port forwarding:

```bash
kubectl port-forward service/ld-relay 8030:8030
```

Keep this terminal window open. The Relay Proxy is now accessible at `http://localhost:8030/status`.

You could also forward port 8080 to 8030, but ensure to his the `/status` endpoint or else you will get a 404.  The commands to do this are returned after running the helm install command.

### Step 7: Test the Relay Proxy

In a new terminal window, test the status endpoint:

```bash
curl http://localhost:8030/status
```

You should see a response like:
```json
{
  "environments": {
    "production": {
      "status": "connected"
    }
  },
  "status": "healthy"
}
```

**Note:** The relay proxy doesn't serve content at the root path `/`. Always use `/status` or other specific endpoints.

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

Or with Kubernetes secrets:

```bash
kubectl create secret generic ld-relay-secrets \
  --from-literal=LD_ENV_production="sdk-prod-key" \
  --from-literal=LD_ENV_staging="sdk-staging-key" \
  --from-literal=LD_ENV_development="sdk-dev-key"
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

**Python:**
```python
config = Config(
    base_uri='http://localhost:8030',
    stream_uri='http://localhost:8030',
    events_uri='http://localhost:8030'
)
client = ldclient.Client('your-sdk-key', config)
```

**Note:** When using the Relay Proxy in minikube from outside the cluster, you'll need to use `localhost:8030` with port-forwarding. For SDKs running inside the cluster, use the service name: `http://ld-relay:8030`.

## Redis Persistent Store (Optional)

Using Redis with the Relay Proxy provides several benefits:
- **Persistent caching** of flag data
- **Offline mode** - serve flags even if LaunchDarkly is unreachable
- **Better performance** with reduced API calls
- **Shared state** across multiple relay proxy instances

### Installing Redis

The easiest way to run Redis in minikube is using the Bitnami Redis Helm chart:

#### Step 1: Add Bitnami Repository

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

#### Step 2: Configure Redis Password

Edit your `redis-secrets.yaml` and set a Redis password:

```yaml
redis:
  auth:
    password: "your-secure-redis-password"
```

### Deploying

For managing multiple Helm releases together, use [Helmfile](https://github.com/helmfile/helmfile):

1. **Install Helmfile**:
   ```bash
   # macOS
   brew install helmfile
   ```

2. **Deploy both at once**:
   ```bash
   helmfile sync
   ```

   Benefits:
   - Declarative configuration
   - Automatic dependency ordering
   - Easy to version control
   - Single command to deploy everything

#### Option 3: Manual Sequential Deployment

If you prefer manual control:

```bash
# 1. Deploy Redis first
helm install redis bitnami/redis \
  -f redis-values.yaml \
  -f redis-secrets.yaml \
  --wait  # Wait for Redis to be ready

# 2. Wait for Redis pod to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis --timeout=300s

# 3. Deploy Relay Proxy
helm install ld-relay launchdarkly-ld-relay/ld-relay \
  -f ld-relay-values.yaml \
  -f ld-relay-secrets.yaml
```

The `--wait` flag tells Helm to wait until all resources are ready before returning.


## Updating the Deployment

To update your configuration:

1. Edit `ld-relay-values.yaml`, `ld-relay-secrets.yaml`, `redis-values.yaml`, or `redis-secrets.yaml` as needed
2. Upgrade the releases:
   ```bash
   # Using Helmfile (recommended)
   helmfile apply
   
   # Or upgrade individually with Helm
   helm upgrade redis bitnami/redis \
     -f redis-values.yaml \
     -f redis-secrets.yaml
   
   helm upgrade ld-relay launchdarkly-ld-relay/ld-relay \
     -f ld-relay-values.yaml \
     -f ld-relay-secrets.yaml
   ```

## Cleanup

### Uninstall the Relay Proxy

```bash
helm uninstall ld-relay
```

### Uninstall Redis (if installed)

```bash
helm uninstall redis
```

### Stop minikube

```bash
minikube stop
```

### Delete the minikube Cluster

To completely remove the minikube cluster:

```bash
minikube delete
```

## Additional Resources

- [LaunchDarkly Relay Proxy Documentation](https://docs.launchdarkly.com/home/relay-proxy)
- [Relay Proxy Helm Chart Repository](https://github.com/launchdarkly/ld-relay-helm)
- [Relay Proxy Configuration Reference](https://docs.launchdarkly.com/home/relay-proxy/configuration)
- [Using Redis with Relay Proxy](https://docs.launchdarkly.com/home/relay-proxy/using#using-redis)
- [Bitnami Redis Helm Chart](https://github.com/bitnami/charts/tree/main/bitnami/redis)
- [minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)


