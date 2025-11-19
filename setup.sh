#!/bin/bash

# Interactive Setup Script for LaunchDarkly Relay Proxy
# Uses gum for beautiful TUI interactions

set -e

# Colors and styling
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Pre-flight Checklist
echo "${BOLD}╔════════════════════════════════════════╗${NORMAL}"
echo "${BOLD}║     Pre-Flight Checklist               ║${NORMAL}"
echo "${BOLD}╚════════════════════════════════════════╝${NORMAL}"

PREFLIGHT_FAILED=0

# Check for required CLI tools (only show failures)
command_exists gum || { echo -e "${RED}✗${NC} gum not installed (brew install gum)"; PREFLIGHT_FAILED=1; }
command_exists kubectl || { echo -e "${RED}✗${NC} kubectl not installed (brew install kubectl)"; PREFLIGHT_FAILED=1; }
command_exists helm || { echo -e "${RED}✗${NC} helm not installed (brew install helm)"; PREFLIGHT_FAILED=1; }
command_exists helmfile || { echo -e "${RED}✗${NC} helmfile not installed (brew install helmfile)"; PREFLIGHT_FAILED=1; }
command_exists minikube || echo -e "${YELLOW}⚠${NC} minikube not found (optional)"

# Check Kubernetes cluster
kubectl cluster-info &>/dev/null || { echo -e "${RED}✗${NC} Kubernetes cluster not accessible (try: minikube start)"; PREFLIGHT_FAILED=1; }

# Check required files (only show missing)
[ -f "helmfile.yaml.gotmpl" ] || { echo -e "${RED}✗${NC} helmfile.yaml.gotmpl not found"; PREFLIGHT_FAILED=1; }
[ -f "ld-relay-values.yaml" ] || { echo -e "${RED}✗${NC} ld-relay-values.yaml not found"; PREFLIGHT_FAILED=1; }
[ -f "redis-values.yaml" ] || { echo -e "${RED}✗${NC} redis-values.yaml not found"; PREFLIGHT_FAILED=1; }

# Optional files (warnings)
[ -f "prometheus-values.yaml" ] || echo -e "${YELLOW}⚠${NC} prometheus-values.yaml not found (only needed for monitoring)"
[ -f "dynamodb-local.yaml" ] || echo -e "${YELLOW}⚠${NC} dynamodb-local.yaml not found (only needed for DynamoDB)"
[ -f "ld-relay-secrets.yaml" ] || echo -e "${YELLOW}⚠${NC} ld-relay-secrets.yaml.example not found"
[ -f "redis-secrets.yaml.example" ] || echo -e "${YELLOW}⚠${NC} redis-secrets.yaml.example not found"
[ -f "dynamodb-secrets.yaml.example" ] || echo -e "${YELLOW}⚠${NC} dynamodb-secrets.yaml.example not found"
[ -f "ld-relay-secrets.yaml" ] || echo -e "${YELLOW}⚠${NC} ld-relay-secrets.yaml not found (required - will check later)"
[ -f "redis-secrets.yaml" ] || echo -e "${YELLOW}⚠${NC} redis-secrets.yaml not found (needed only if using Redis)"
[ -f "dynamodb-secrets.yaml" ] || echo -e "${YELLOW}⚠${NC} dynamodb-secrets.yaml not found (will be created if using DynamoDB)"

# Check Helm repositories
helm repo list 2>/dev/null | grep -q launchdarkly-ld-relay || echo -e "${YELLOW}⚠${NC} launchdarkly-ld-relay repo not added (helmfile will add it)"
helm repo list 2>/dev/null | grep -q bitnami || echo -e "${YELLOW}⚠${NC} bitnami repo not added (helmfile will add it)"
helm repo list 2>/dev/null | grep -q prometheus-community || echo -e "${YELLOW}⚠${NC} prometheus-community repo not added (helmfile will add it)"

# Check for existing deployments
EXISTING_DEPLOYMENTS=()
EXISTING_FOUND=0
kubectl get deployment ld-relay &>/dev/null && { echo -e "${YELLOW}⚠${NC} LD Relay deployment already exists"; EXISTING_DEPLOYMENTS+=("ld-relay"); EXISTING_FOUND=1; }
{ kubectl get deployment redis-master &>/dev/null || kubectl get statefulset redis-master &>/dev/null; } && { echo -e "${YELLOW}⚠${NC} Redis deployment already exists"; EXISTING_DEPLOYMENTS+=("redis"); EXISTING_FOUND=1; }
kubectl get deployment dynamodb-local &>/dev/null && { echo -e "${YELLOW}⚠${NC} DynamoDB Local already exists"; EXISTING_DEPLOYMENTS+=("dynamodb-local"); EXISTING_FOUND=1; }
kubectl get deployment redisinsight &>/dev/null && { echo -e "${YELLOW}⚠${NC} RedisInsight already exists"; EXISTING_DEPLOYMENTS+=("redisinsight"); EXISTING_FOUND=1; }
kubectl get job redisinsight-config &>/dev/null && { echo -e "${YELLOW}⚠${NC} RedisInsight config job already exists"; EXISTING_DEPLOYMENTS+=("redisinsight-config"); EXISTING_FOUND=1; }
kubectl get deployment dynamodb-admin &>/dev/null && { echo -e "${YELLOW}⚠${NC} DynamoDB Admin already exists"; EXISTING_DEPLOYMENTS+=("dynamodb-admin"); EXISTING_FOUND=1; }
kubectl get job dynamodb-config &>/dev/null && { echo -e "${YELLOW}⚠${NC} DynamoDB config job already exists"; EXISTING_DEPLOYMENTS+=("dynamodb-config"); EXISTING_FOUND=1; }

# Check for monitoring stack
if kubectl get namespace monitoring &>/dev/null 2>&1; then
    MONITORING_EXISTS=0
    kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -q . && MONITORING_EXISTS=1
    kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -q . && MONITORING_EXISTS=1
    
    if [ $MONITORING_EXISTS -eq 1 ]; then
        echo -e "${YELLOW}⚠${NC} Monitoring stack (Prometheus/Grafana) already exists"
        EXISTING_DEPLOYMENTS+=("kube-prometheus-stack")
        EXISTING_FOUND=1
    fi
fi

# Show summary
if [ $PREFLIGHT_FAILED -eq 0 ] && [ $EXISTING_FOUND -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓${NC} All pre-flight checks passed!"
fi

echo ""
echo "${BOLD}════════════════════════════════════════${NORMAL}"
echo ""

# Exit if any critical checks failed
if [ $PREFLIGHT_FAILED -eq 1 ]; then
    echo -e "${RED}Pre-flight checks failed!${NC}"
    echo "Please install missing dependencies and try again."
    exit 1
fi

# Handle existing deployments if found
if [ $EXISTING_FOUND -eq 1 ]; then
    gum style \
        --border double \
        --margin "1" \
        --padding "1 2" \
        --border-foreground 214 \
        "⚠️  Existing Deployment Detected" \
        "" \
        "Found existing components:" \
        "$(printf '  • %s\n' "${EXISTING_DEPLOYMENTS[@]}")" \
        "" \
        "These must be removed before proceeding."
    
    echo ""
    
    # Prompt user for action
    gum style --bold "What would you like to do?"
    ACTION=$(gum choose \
        "Delete everything and start fresh" \
        "Cancel setup")
    
    if [ "$ACTION" = "Cancel setup" ]; then
        echo ""
        echo "Setup cancelled."
        echo ""
        echo "To manually clean up, run:"
        echo "  helmfile destroy"
        echo "  kubectl delete -f dynamodb-local.yaml --ignore-not-found=true"
        echo "  kubectl delete -f redisinsight.yaml --ignore-not-found=true"
        echo "  kubectl delete -f dynamodb-admin.yaml --ignore-not-found=true"
        exit 0
    fi
    
    # Delete existing deployments
    echo ""
    gum style --bold "Cleaning up existing deployments..."
    echo ""
    
    # Run helmfile destroy
    echo "Removing Helm releases..."
    if gum spin --spinner dot --title "Running helmfile destroy..." -- \
        helmfile destroy 2>&1 | tee /tmp/helmfile-destroy.log; then
        echo -e "${GREEN}✓${NC} Helm releases removed"
    else
        echo -e "${YELLOW}⚠${NC} Helmfile destroy encountered issues (this is sometimes normal)"
    fi
    
    # Also clean up DynamoDB if it exists
    if kubectl get deployment dynamodb-local &>/dev/null 2>&1; then
        echo "Removing DynamoDB Local..."
        kubectl delete -f dynamodb-local.yaml --ignore-not-found=true &>/dev/null || true
        echo -e "${GREEN}✓${NC} DynamoDB Local removed"
    fi
    
    # Clean up RedisInsight if it exists
    if kubectl get deployment redisinsight &>/dev/null 2>&1; then
        echo "Removing RedisInsight..."
        kubectl delete -f redisinsight.yaml --ignore-not-found=true &>/dev/null || true
        kubectl delete -f redisinsight-config-job.yaml --ignore-not-found=true &>/dev/null || true
        echo -e "${GREEN}✓${NC} RedisInsight removed"
    fi
    
    # Clean up RedisInsight config job if it exists (even if RedisInsight is gone)
    if kubectl get job redisinsight-config &>/dev/null 2>&1; then
        echo "Removing RedisInsight configuration job..."
        kubectl delete job redisinsight-config --ignore-not-found=true &>/dev/null || true
        echo -e "${GREEN}✓${NC} RedisInsight config job removed"
    fi
    
    # Clean up DynamoDB Admin if it exists
    if kubectl get deployment dynamodb-admin &>/dev/null 2>&1; then
        echo "Removing DynamoDB Admin..."
        kubectl delete -f dynamodb-admin.yaml --ignore-not-found=true &>/dev/null || true
        echo -e "${GREEN}✓${NC} DynamoDB Admin removed"
    fi
    
    # Clean up DynamoDB config job if it exists
    if kubectl get job dynamodb-config &>/dev/null 2>&1; then
        echo "Removing DynamoDB configuration job..."
        kubectl delete -f dynamodb-config-job.yaml --ignore-not-found=true &>/dev/null || true
        echo -e "${GREEN}✓${NC} DynamoDB config job removed"
    fi
    
    # Force cleanup monitoring namespace if it exists and has resources
    if kubectl get namespace monitoring &>/dev/null 2>&1; then
        echo "Cleaning up monitoring namespace..."
        
        # Delete all PrometheusRule CRDs in monitoring namespace
        kubectl delete prometheusrule --all -n monitoring --ignore-not-found=true &>/dev/null || true
        
        # Delete all ServiceMonitor CRDs in monitoring namespace
        kubectl delete servicemonitor --all -n monitoring --ignore-not-found=true &>/dev/null || true
        
        # Delete all PodMonitor CRDs in monitoring namespace
        kubectl delete podmonitor --all -n monitoring --ignore-not-found=true &>/dev/null || true
        
        # Force delete any remaining resources in monitoring namespace
        kubectl delete all --all -n monitoring --grace-period=0 --force &>/dev/null || true
        
        # Try to delete the namespace
        kubectl delete namespace monitoring --timeout=30s &>/dev/null || true
        
        echo -e "${GREEN}✓${NC} Monitoring namespace cleanup initiated"
    fi
    
    # Force cleanup any stuck resources in default namespace
    echo "Cleaning up default namespace..."
    kubectl delete deployment ld-relay --ignore-not-found=true --grace-period=0 --force &>/dev/null || true
    kubectl delete statefulset redis-master redis-replicas --ignore-not-found=true --grace-period=0 --force &>/dev/null || true
    
    echo ""
    echo -e "${GREEN}✓${NC} Cleanup commands executed!"
    echo ""
    
    # Give Kubernetes time to fully clean up
    echo "Waiting for resources to terminate..."
    for i in {1..10}; do
        # Check if monitoring namespace is gone
        if ! kubectl get namespace monitoring &>/dev/null 2>&1; then
            MONITORING_GONE=1
        else
            MONITORING_GONE=0
        fi
        
        # Check if ld-relay is gone
        if ! kubectl get deployment ld-relay &>/dev/null 2>&1; then
            RELAY_GONE=1
        else
            RELAY_GONE=0
        fi
        
        if [ $MONITORING_GONE -eq 1 ] && [ $RELAY_GONE -eq 1 ]; then
            echo -e "${GREEN}✓${NC} All resources terminated"
            break
        fi
        
        echo "  Still terminating... ($i/10)"
        sleep 3
    done
    
    echo ""
    
    # Show what's still running if anything
    STILL_RUNNING=0
    if kubectl get deployment ld-relay &>/dev/null 2>&1; then
        echo -e "${YELLOW}⚠${NC} ld-relay still exists (will be replaced)"
        STILL_RUNNING=1
    fi
    if kubectl get namespace monitoring &>/dev/null 2>&1; then
        echo -e "${YELLOW}⚠${NC} monitoring namespace still exists (will be replaced)"
        STILL_RUNNING=1
    fi
    
    if [ $STILL_RUNNING -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Cleanup complete - ready for fresh deployment"
    else
        echo ""
        echo "Some resources are still terminating. This is normal."
        echo "The new deployment will proceed and replace them."
    fi
    
    echo ""
fi

# Display welcome header
gum style \
    --border normal \
    --margin "1" \
    --padding "1 2" \
    --border-foreground 212 \
    "LaunchDarkly Relay Proxy Setup" \
    "" \
    "Interactive configuration for local development"

echo ""

# Prompt for datastore selection
gum style --bold "Select Persistent Datastore:"
DATASTORE_CHOICE=$(gum choose \
    "Redis (local)" \
    "DynamoDB (local)" \
    "No Persistent Store (In-Memory Only)")

echo ""

# Prompt for monitoring selection
gum style --bold "Select Monitoring Stack:"
MONITORING_CHOICE=$(gum choose \
    "Prometheus & Grafana (Full Monitoring)" \
    "No Monitoring")

echo ""

# Map choices to environment variables
case "$DATASTORE_CHOICE" in
    "Redis (local)")
        export DATASTORE="redis"
        DATASTORE_DISPLAY="Redis"
        ;;
    "DynamoDB (local)")
        export DATASTORE="dynamodb"
        DATASTORE_DISPLAY="Local DynamoDB"
        ;;
    "No Persistent Store (In-Memory Only)")
        export DATASTORE="none"
        DATASTORE_DISPLAY="None (In-Memory)"
        ;;
esac



echo ""

case "$MONITORING_CHOICE" in
    "Prometheus & Grafana (Full Monitoring)")
        export MONITORING="full"
        MONITORING_DISPLAY="Prometheus & Grafana"
        ;;
    "No Monitoring")
        export MONITORING="none"
        MONITORING_DISPLAY="None"
        ;;
esac

# Prompt for DB viewer only if a datastore was selected
if [ "$DATASTORE" != "none" ]; then
    gum style --bold "Do you want to install a Database Management UI?"
    if gum confirm "This will deploy a web-based viewer for your datastore"; then
        export DB_VIEWER="true"
        if [ "$DATASTORE" = "redis" ]; then
            DB_VIEWER_DISPLAY="RedisInsight"
        else
            DB_VIEWER_DISPLAY="DynamoDB Admin"
        fi
    else
        export DB_VIEWER="false"
        DB_VIEWER_DISPLAY="None"
    fi
else
    export DB_VIEWER="false"
    DB_VIEWER_DISPLAY="None"
fi

# Display selected configuration
gum style \
    --border double \
    --margin "1" \
    --padding "1 2" \
    --border-foreground 212 \
    "Configuration Summary" \
    "" \
    "Components to Deploy:" \
    "  • LaunchDarkly Relay Proxy (always included)" \
    "  • Datastore: $DATASTORE_DISPLAY" \
    "  • Monitoring: $MONITORING_DISPLAY" \
    "  • DB Viewer: $DB_VIEWER_DISPLAY"

echo ""

# Confirm before proceeding
if ! gum confirm "Proceed with deployment?"; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""

# Check for secrets files
gum style --bold "Checking for required secrets files..."

if [ ! -f "ld-relay-secrets.yaml" ]; then
    echo -e "${RED}Error: ld-relay-secrets.yaml not found${NC}"
    echo "Copy ld-relay-secrets.yaml.example to ld-relay-secrets.yaml and add your SDK keys"
    exit 1
fi

if [ "$DATASTORE" = "redis" ] && [ ! -f "redis-secrets.yaml" ]; then
    echo -e "${RED}Error: redis-secrets.yaml not found${NC}"
    echo "Copy redis-secrets.yaml.example to redis-secrets.yaml and set password"
    exit 1
fi

if [ "$DATASTORE" = "dynamodb" ] && [ ! -f "dynamodb-secrets.yaml" ]; then
    echo "Creating dynamodb-secrets.yaml from example..."
    cp dynamodb-secrets.yaml.example dynamodb-secrets.yaml
fi

echo -e "${GREEN}✓${NC} All secrets files present"
echo ""

# Deploy using helmfile
gum style --bold "Deploying components..."
echo ""

if gum spin --spinner dot --title "Running helmfile sync..." -- \
    helmfile sync --concurrency 1 2>&1 | tee /tmp/helmfile-output.log; then
    
    echo ""
    
    gum style \
        --border double \
        --margin "1" \
        --padding "1 2" \
        --border-foreground 46 \
        "✨ Deployment Complete! ✨"
    
    echo ""
    
    # Wait a moment for pods to start
    echo "Waiting for pods to start..."
    sleep 5
    
    echo ""
    gum style --bold "Deployment Status:"
    echo ""
    
    # Check LD Relay status
    echo "${BOLD}LD Relay:${NORMAL}"
    if kubectl get pods -l app.kubernetes.io/name=ld-relay &>/dev/null; then
        kubectl get pods -l app.kubernetes.io/name=ld-relay
        RELAY_READY=$(kubectl get pods -l app.kubernetes.io/name=ld-relay -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        if [ "$RELAY_READY" = "True" ]; then
            echo -e "  ${GREEN}✓${NC} LD Relay is ready"
        else
            echo -e "  ${YELLOW}⚠${NC} LD Relay is starting..."
        fi
    else
        echo -e "  ${RED}✗${NC} LD Relay not found"
    fi
    echo ""
    
    # Check datastore status
    if [ "$DATASTORE" = "redis" ]; then
        echo "${BOLD}Redis:${NORMAL}"
        if kubectl get pods -l app.kubernetes.io/name=redis &>/dev/null; then
            kubectl get pods -l app.kubernetes.io/name=redis
            echo -e "  ${GREEN}✓${NC} Redis is deployed"
        else
            echo -e "  ${RED}✗${NC} Redis not found"
        fi
        echo ""
    elif [ "$DATASTORE" = "dynamodb" ]; then
        echo "${BOLD}DynamoDB Local:${NORMAL}"
        if kubectl get pods -l app=dynamodb-local &>/dev/null; then
            kubectl get pods -l app=dynamodb-local
            echo -e "  ${GREEN}✓${NC} DynamoDB Local is deployed"
        else
            echo -e "  ${RED}✗${NC} DynamoDB Local not found"
        fi
        echo ""
    fi
    
    # Check monitoring status
    if [ "$MONITORING" = "full" ]; then
        echo "${BOLD}Monitoring Stack:${NORMAL}"
        if kubectl get pods -n monitoring &>/dev/null 2>&1; then
            kubectl get pods -n monitoring | head -6
            echo -e "  ${GREEN}✓${NC} Monitoring stack is deployed"
        else
            echo -e "  ${YELLOW}⚠${NC} Monitoring stack is starting..."
        fi
        echo ""
    fi
    
    # Check DB viewer status
    if [ "$DB_VIEWER" = "true" ]; then
        if [ "$DATASTORE" = "redis" ]; then
            echo "${BOLD}RedisInsight:${NORMAL}"
            if kubectl get pods -l app=redisinsight &>/dev/null; then
                kubectl get pods -l app=redisinsight
                echo -e "  ${GREEN}✓${NC} RedisInsight is deployed"
                
                # Check if auto-configuration job completed
                if kubectl get job redisinsight-config &>/dev/null 2>&1; then
                    JOB_STATUS=$(kubectl get job redisinsight-config -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "False")
                    if [ "$JOB_STATUS" = "True" ]; then
                        echo -e "  ${GREEN}✓${NC} Redis database auto-configured"
                    else
                        echo -e "  ${YELLOW}⚠${NC} Auto-configuration in progress..."
                    fi
                fi
            else
                echo -e "  ${YELLOW}⚠${NC} RedisInsight is starting..."
            fi
        else
            echo "${BOLD}DynamoDB Admin:${NORMAL}"
            if kubectl get pods -l app=dynamodb-admin &>/dev/null; then
                kubectl get pods -l app=dynamodb-admin
                echo -e "  ${GREEN}✓${NC} DynamoDB Admin is deployed"
                
                # Check if auto-verification job completed
                if kubectl get job dynamodb-config &>/dev/null 2>&1; then
                    JOB_STATUS=$(kubectl get job dynamodb-config -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "False")
                    if [ "$JOB_STATUS" = "True" ]; then
                        echo -e "  ${GREEN}✓${NC} ld-relay table verified"
                    else
                        echo -e "  ${YELLOW}⚠${NC} Table verification in progress..."
                    fi
                fi
            else
                echo -e "  ${YELLOW}⚠${NC} DynamoDB Admin is starting..."
            fi
        fi
        echo ""
    fi
    
    echo ""
    gum style \
        --border normal \
        --margin "0" \
        --padding "1 2" \
        --border-foreground 212 \
        "Quick Access Commands"
    
    echo ""
    echo "${BOLD}LD Relay Status:${NORMAL}"
    echo "  kubectl port-forward svc/ld-relay 8030:8030"
    echo "  curl http://localhost:8030/status"
    echo ""
    
    echo "${BOLD}LD Relay Metrics:${NORMAL}"
    echo "  kubectl port-forward svc/ld-relay 8031:8031"
    echo "  curl http://localhost:8031/metrics"
    echo ""
    
    echo "${BOLD}View LD Relay logs:${NORMAL}"
    echo "  kubectl logs -l app.kubernetes.io/name=ld-relay --follow"
    echo ""
    
    if [ "$DB_VIEWER" = "true" ]; then
        if [ "$DATASTORE" = "redis" ]; then
            # Extract Redis password from secrets file
            REDIS_PASSWORD=$(grep "password:" redis-secrets.yaml 2>/dev/null | sed 's/.*password: *"\?\([^"]*\)"\?.*/\1/' | tr -d '"')
            
            echo "${BOLD}Access RedisInsight:${NORMAL}"
            echo "  kubectl port-forward svc/redisinsight 8001:8001"
            echo "  Open: http://localhost:8001"
            echo -e "  ${GREEN}✓${NC} Redis database 'LD Relay Redis' is pre-configured!"
            if [ -n "$REDIS_PASSWORD" ]; then
                echo -e "  ${YELLOW}Note:${NC} Connected to redis-master:6379 with password: $REDIS_PASSWORD"
            else
                echo -e "  ${YELLOW}Note:${NC} Connected to redis-master:6379"
            fi
            echo ""
        else
            echo "${BOLD}Access DynamoDB Admin:${NORMAL}"
            echo "  kubectl port-forward svc/dynamodb-admin 8001:8001"
            echo "  Open: http://localhost:8001"
            echo -e "  ${GREEN}✓${NC} The 'ld-relay' table is auto-verified and ready!"
            echo -e "  ${YELLOW}(No login required)${NC}"
            echo ""
        fi
    fi
    
    if [ "$MONITORING" = "full" ]; then
        echo "${BOLD}Access Grafana:${NORMAL}"
        echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
        echo "  Open: http://localhost:3000"
        echo -e "  ${YELLOW}Username:${NC} admin"
        echo -e "  ${YELLOW}Password:${NC} admin"
        echo ""
        
        echo "${BOLD}Access Prometheus:${NORMAL}"
        echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
        echo "  Open: http://localhost:9090"
        echo -e "  ${YELLOW}(No login required)${NC}"
        echo ""
    fi
    
    echo "${BOLD}Check status anytime:${NORMAL}"
    echo "  ./check-status.sh"
    echo ""
    
    # Run RedisInsight auto-configuration job if DB viewer was selected
    if [ "$DB_VIEWER" = "true" ] && [ "$DATASTORE" = "redis" ]; then
        echo ""
        gum style --bold "Configuring RedisInsight database connection..."
        echo ""
        
        # Wait for RedisInsight pod to be Running and Ready
        WAIT_COUNT=0
        REDISINSIGHT_READY=0
        while [ $WAIT_COUNT -lt 60 ]; do
            POD_STATUS=$(kubectl get pods -l app=redisinsight -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
            POD_READY=$(kubectl get pods -l app=redisinsight -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
            
            if [ "$POD_STATUS" = "Running" ] && [ "$POD_READY" = "True" ]; then
                REDISINSIGHT_READY=1
                echo -e "${GREEN}✓${NC} RedisInsight is ready!"
                echo ""
                break
            fi
            
            if [ $((WAIT_COUNT % 10)) -eq 0 ]; then
                echo "  Waiting for RedisInsight pod to be ready (status: $POD_STATUS, ready: $POD_READY)..."
            fi
            sleep 2
            WAIT_COUNT=$((WAIT_COUNT + 1))
        done
        
        if [ $REDISINSIGHT_READY -eq 0 ]; then
            echo -e "${RED}✗${NC} RedisInsight did not become ready in time (waited 2 minutes)"
            echo "Check pod status: kubectl get pods -l app=redisinsight"
            exit 1
        fi
        
        # Now create and run the configuration job
        echo "Creating auto-configuration job..."
        kubectl apply -f redisinsight-config-job.yaml &>/dev/null
        
        echo "Waiting for configuration job to start..."
        sleep 3
        
        # Check if job was created successfully
        if ! kubectl get job redisinsight-config &>/dev/null 2>&1; then
            echo -e "${RED}✗${NC} Failed to create configuration job"
            echo "Check: kubectl get pods -l app=redisinsight"
            exit 1
        fi
        
        # Job created successfully - follow its progress
        echo "Auto-configuration job created, following progress..."
        echo ""
        
        # Wait for job pod to be in Running state
        WAIT_COUNT=0
        POD_RUNNING=0
        while [ $WAIT_COUNT -lt 60 ]; do
            if kubectl get pods -l app=redisinsight-config &>/dev/null 2>&1; then
                POD_STATUS=$(kubectl get pods -l app=redisinsight-config -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
                if [ "$POD_STATUS" = "Running" ]; then
                    POD_RUNNING=1
                    echo "Auto-configuration job running, following progress:"
                    echo ""
                    break
                elif [ "$POD_STATUS" = "Succeeded" ]; then
                    echo -e "${GREEN}✓${NC} Job already succeeded!"
                    break
                fi
            fi
            sleep 2
            WAIT_COUNT=$((WAIT_COUNT + 1))
        done
        
        if [ $POD_RUNNING -eq 1 ]; then
            # Stream logs and wait for completion
            echo "Following job logs (this may take up to 3 minutes):"
            echo ""
            
            # Check if we can get logs
            if kubectl logs -l app=redisinsight-config --tail=1 &>/dev/null; then
                kubectl logs -l app=redisinsight-config --follow 2>&1 | while IFS= read -r line; do
                    echo "  $line"
                done
            else
                echo "  (No logs available yet, job is initializing...)"
                sleep 5
                kubectl logs -l app=redisinsight-config --follow 2>&1 | while IFS= read -r line; do
                    echo "  $line"
                done
            fi
            
            echo ""
            
            # Wait for job to be marked as Complete (logs may finish before job status updates)
            echo "Job logs complete. Verifying job status..."
            WAIT_COUNT=0
            JOB_COMPLETE=0
            while [ $WAIT_COUNT -lt 90 ]; do
                JOB_STATUS=$(kubectl get job redisinsight-config -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "False")
                if [ "$JOB_STATUS" = "True" ]; then
                    JOB_COMPLETE=1
                    break
                fi
                
                # Show progress every 10 seconds
                if [ $((WAIT_COUNT % 5)) -eq 0 ] && [ $WAIT_COUNT -gt 0 ]; then
                    echo "  Still waiting for job to complete... ($((WAIT_COUNT * 2))s elapsed)"
                fi
                
                sleep 2
                WAIT_COUNT=$((WAIT_COUNT + 1))
            done
            
            if [ $JOB_COMPLETE -eq 1 ]; then
                echo -e "${GREEN}✓${NC} RedisInsight database auto-configured successfully!"
            else
                echo -e "${RED}✗${NC} Auto-configuration job did not complete in time (waited 3 minutes)"
                echo ""
                echo "Last 30 lines from configuration job:"
                kubectl logs -l app=redisinsight-config --tail=30 2>&1 | while IFS= read -r line; do
                    echo "  $line"
                done
                echo ""
                echo "The RedisInsight database was not configured."
                exit 1
            fi
        else
            echo -e "${RED}✗${NC} Auto-configuration job pod did not start running in time"
            echo ""
            if kubectl get pods -l app=redisinsight-config &>/dev/null 2>&1; then
                echo "Pod logs:"
                kubectl logs -l app=redisinsight-config 2>&1 | while IFS= read -r line; do
                    echo "  $line"
                done
                echo ""
            fi
            echo "Check pod status: kubectl get pods -l app=redisinsight-config"
            exit 1
        fi
        
        echo ""
    fi
    
    # Note: DynamoDB table creation is handled automatically by helmfile postsync hook
    # Just verify the table creation job completed if DynamoDB was selected
    if [ "$DATASTORE" = "dynamodb" ]; then
        echo ""
        if kubectl get job dynamodb-config &>/dev/null 2>&1; then
            JOB_STATUS=$(kubectl get job dynamodb-config -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "False")
            if [ "$JOB_STATUS" = "True" ]; then
                echo -e "${GREEN}✓${NC} DynamoDB table created and ready for LD Relay"
            else
                echo -e "${YELLOW}⚠${NC} DynamoDB table creation is still in progress"
                echo "Check status: kubectl get job dynamodb-config"
            fi
        fi
        echo ""
    fi
    
    # Ask if user wants to start port forwarding
    echo ""
    if gum confirm "Start port forwarding for all services?"; then
        echo ""
        gum style --bold "Starting port forwards..."
        echo ""
        
        # Start LD Relay port forwards
        kubectl port-forward svc/ld-relay 8030:8030 >/dev/null 2>&1 &
        sleep 1
        echo -e "${GREEN}✓${NC} LD Relay Status: http://localhost:8030/status"
        
        kubectl port-forward svc/ld-relay 8031:8031 >/dev/null 2>&1 &
        sleep 1
        echo -e "${GREEN}✓${NC} LD Relay Metrics: http://localhost:8031/metrics"
        
        # Start DB viewer port forward if enabled
        if [ "$DB_VIEWER" = "true" ]; then
            if [ "$DATASTORE" = "redis" ]; then
                kubectl port-forward svc/redisinsight 8001:8001 >/dev/null 2>&1 &
                sleep 1
                echo -e "${GREEN}✓${NC} RedisInsight: http://localhost:8001"
            else
                kubectl port-forward svc/dynamodb-admin 8001:8001 >/dev/null 2>&1 &
                sleep 1
                echo -e "${GREEN}✓${NC} DynamoDB Admin: http://localhost:8001"
            fi
        fi
        
        # Start monitoring port forwards if enabled
        if [ "$MONITORING" = "full" ]; then
            kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 >/dev/null 2>&1 &
            sleep 1
            echo -e "${GREEN}✓${NC} Grafana: http://localhost:3000 (admin/admin)"
            
            kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 >/dev/null 2>&1 &
            sleep 1
            echo -e "${GREEN}✓${NC} Prometheus: http://localhost:9090"
        fi
        
        echo ""
        echo -e "${YELLOW}Note:${NC} Port forwards are running in the background"
        echo "To stop all port forwards, run: ${BOLD}killall kubectl${NORMAL}"
        echo ""
    fi
    
else
    echo ""
    gum style \
        --border double \
        --margin "1" \
        --padding "1 2" \
        --border-foreground 196 \
        "❌ Deployment Failed"
    
    echo ""
    echo "Check the output above for errors."
    echo "Log file: /tmp/helmfile-output.log"
    exit 1
fi

