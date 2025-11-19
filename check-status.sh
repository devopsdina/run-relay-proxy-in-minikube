#!/bin/bash

# Status Check Script for LaunchDarkly Relay Proxy Deployment
# Shows the status of all deployed components

set -e

# Colors
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "${BOLD}=== LaunchDarkly Relay Proxy Status ===${NORMAL}"
echo ""

# Check if gum is available for pretty output
if command -v gum >/dev/null 2>&1; then
    USE_GUM=true
else
    USE_GUM=false
fi

# Function to print section header
section_header() {
    echo ""
    if [ "$USE_GUM" = true ]; then
        gum style --bold --foreground 212 "$1"
    else
        echo "${BOLD}$1${NORMAL}"
    fi
    echo "---"
}

# Check LD Relay
section_header "LD Relay Status"
if kubectl get pods -l app.kubernetes.io/name=ld-relay &>/dev/null; then
    kubectl get pods -l app.kubernetes.io/name=ld-relay
    
    # Check if relay is ready
    RELAY_READY=$(kubectl get pods -l app.kubernetes.io/name=ld-relay -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    
    if [ "$RELAY_READY" = "True" ]; then
        echo -e "${GREEN}✓${NC} LD Relay is ready"
    else
        echo -e "${YELLOW}⚠${NC} LD Relay is not ready yet"
    fi
else
    echo -e "${RED}✗${NC} LD Relay not found"
fi

# Check Redis
section_header "Redis Status"
if kubectl get pods -l app.kubernetes.io/name=redis &>/dev/null; then
    kubectl get pods -l app.kubernetes.io/name=redis
    echo -e "${GREEN}✓${NC} Redis is deployed"
else
    echo "Redis not deployed (using different datastore or none)"
fi

# Check DynamoDB Local
section_header "DynamoDB Local Status"
if kubectl get pods -l app=dynamodb-local &>/dev/null; then
    kubectl get pods -l app=dynamodb-local
    echo -e "${GREEN}✓${NC} DynamoDB Local is deployed"
else
    echo "DynamoDB Local not deployed (using different datastore or none)"
fi

# Check RedisInsight
section_header "RedisInsight Status"
if kubectl get pods -l app=redisinsight &>/dev/null; then
    kubectl get pods -l app=redisinsight
    echo -e "${GREEN}✓${NC} RedisInsight is deployed"
    
    # Check if auto-configuration job exists and its status
    if kubectl get job redisinsight-config &>/dev/null 2>&1; then
        JOB_STATUS=$(kubectl get job redisinsight-config -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "False")
        if [ "$JOB_STATUS" = "True" ]; then
            echo -e "${GREEN}✓${NC} Redis database auto-configured"
        else
            echo -e "${YELLOW}⚠${NC} Auto-configuration in progress"
        fi
    fi
else
    echo "RedisInsight not deployed"
fi

# Check DynamoDB Admin
section_header "DynamoDB Admin Status"
if kubectl get pods -l app=dynamodb-admin &>/dev/null; then
    kubectl get pods -l app=dynamodb-admin
    echo -e "${GREEN}✓${NC} DynamoDB Admin is deployed"
else
    echo "DynamoDB Admin not deployed"
fi

# Check Monitoring Stack
section_header "Monitoring Stack Status"
if kubectl get pods -n monitoring &>/dev/null 2>&1; then
    kubectl get pods -n monitoring
    echo -e "${GREEN}✓${NC} Monitoring stack is deployed"
    
    # Check Grafana
    GRAFANA_READY=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [ "$GRAFANA_READY" = "True" ]; then
        echo -e "${GREEN}✓${NC} Grafana is ready"
    fi
    
    # Check Prometheus
    PROM_READY=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [ "$PROM_READY" = "True" ]; then
        echo -e "${GREEN}✓${NC} Prometheus is ready"
    fi
else
    echo "Monitoring stack not deployed"
fi

# Check Services
section_header "Services"
echo "Default namespace:"
kubectl get svc -n default | grep -E "NAME|ld-relay|redis|dynamodb" || echo "No services found"

if kubectl get ns monitoring &>/dev/null 2>&1; then
    echo ""
    echo "Monitoring namespace:"
    kubectl get svc -n monitoring | head -5
fi

# Quick Access Commands
section_header "Quick Access Commands"
echo "LD Relay Status:"
echo "  kubectl port-forward svc/ld-relay 8030:8030"
echo "  curl http://localhost:8030/status"
echo ""

if kubectl get pods -l app=redisinsight &>/dev/null; then
    echo "RedisInsight:"
    echo "  kubectl port-forward svc/redisinsight 8001:8001"
    echo "  Open: http://localhost:8001"
    echo "  Redis database 'LD Relay Redis' is pre-configured"
    echo ""
fi

if kubectl get pods -l app=dynamodb-admin &>/dev/null; then
    echo "DynamoDB Admin:"
    echo "  kubectl port-forward svc/dynamodb-admin 8001:8001"
    echo "  Open: http://localhost:8001"
    echo ""
fi

if kubectl get pods -n monitoring &>/dev/null 2>&1; then
    echo "Grafana:"
    echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
    echo "  Open: http://localhost:3000 (admin/admin)"
    echo ""
    
    echo "Prometheus:"
    echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
    echo "  Open: http://localhost:9090"
    echo ""
fi

echo "View LD Relay logs:"
echo "  kubectl logs -l app.kubernetes.io/name=ld-relay --follow"
echo ""

