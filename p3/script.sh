#!/bin/bash

NAMESPACE_ARGOCD="argocd"
NAMESPACE_APP="dev"
APP_NAME="my-app"
ARGOCD_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
GITHUB_REPO="https://github.com/Doboy9/Inception_of_Things/"
MANIFEST_PATH="k8s-manifests/deployment.yaml"

RED='\033[0;31m'
NC='\033[0m' # No Color

function install_argocd() {
    echo "🔹 Creating namespaces..."
    kubectl create namespace $NAMESPACE_ARGOCD --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace $NAMESPACE_APP --dry-run=client -o yaml | kubectl apply -f -

    echo "🚀 Installing Argo CD..."
    kubectl apply -n $NAMESPACE_ARGOCD -f $ARGOCD_MANIFEST

    echo "⏳ Waiting for Argo CD to be ready..."
    if ! kubectl wait --for=condition=available deployment/argocd-server -n $NAMESPACE_ARGOCD --timeout=300s; then
        echo -e "${RED}❌ Argo CD is not ready after waiting.${NC}"
        exit 1
    fi

    echo "🔧 Starting Argo CD port forwarding..."
    start_port_forwarding

    echo "🔑 Retrieving Argo CD admin password..."
    sleep 10  # Wait for the secret to be created
    PASSWORD=$(kubectl -n $NAMESPACE_ARGOCD get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

    if [ -z "$PASSWORD" ]; then
        echo "⚠️ Failed to retrieve admin password. You may need to manually reset it."
    else
        echo "✅ Argo CD is installed!"
        echo "🔑 Admin Login: admin"
        echo "🔑 Password: $PASSWORD"
    fi
}

function start_port_forwarding() {
    echo "🔄 Starting port-forwarding for Argo CD..."

    # Kill any existing port-forward process to avoid conflicts
    pkill -f "kubectl port-forward svc/argocd-server -n argocd" 2>/dev/null

    # Start port forwarding in the background
    nohup kubectl port-forward svc/argocd-server -n $NAMESPACE_ARGOCD 8080:80 >/dev/null 2>&1 &

    echo "✅ Port forwarding started! Access Argo CD at: http://localhost:8080"
}

function check_argocd_server() {
    echo "🔄 Checking if Argo CD is accessible at http://localhost:8080..."
    timeout=60
    elapsed=0

    while ! curl -k --max-time 5 http://localhost:8080 &>/dev/null; do
        echo "❌ Argo CD not accessible yet. Retrying in 5s..."
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $elapsed -ge $timeout ]; then
            echo -e "${RED}❌ Argo CD is still not accessible after $timeout seconds.${NC}"
            exit 1
        fi
    done

    echo "✅ Argo CD is accessible at http://localhost:8080"
}

function login_to_argocd() {
    check_argocd_server
    echo "🔐 Logging in to Argo CD CLI..."
    argocd login localhost:8080 --username admin --password "$PASSWORD" --insecure
}

function deploy_application() {
    echo "🚀 Deploying Argo CD application..."

    cat <<EOF | kubectl apply -n $NAMESPACE_ARGOCD -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE_ARGOCD
spec:
  project: default
  source:
    repoURL: $GITHUB_REPO
    targetRevision: main
    path: p3/k8s-manifests  # ✅ Corrected path
  destination:
    server: https://kubernetes.default.svc
    namespace: $NAMESPACE_APP
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

    echo "✅ Application created in Argo CD!"
    echo "🔄 Syncing Argo CD application..."
    sleep 5
    argocd app sync $APP_NAME
}

function uninstall_all() {
    echo "❌ Deleting Argo CD and application namespaces..."
    kubectl delete namespace $NAMESPACE_ARGOCD --ignore-not-found
    kubectl delete namespace $NAMESPACE_APP --ignore-not-found
    echo "✅ Argo CD and application namespaces deleted."
}

case "$1" in
    install)
        install_argocd
        login_to_argocd
        deploy_application
        ;;
    uninstall)
        uninstall_all
        ;;
    *)
        echo "Usage: $0 {install|uninstall}"
        exit 1
        ;;
esac
