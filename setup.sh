#!/usr/bin/env bash
brewcmd=$(which brew)

if [ -z "${brewcmd}" ]; then
    echo "No Homebrew: try https://brew.sh"
    echo "See https://crossplane.io/docs for other Crossplane install options"
    exit 1
fi
containerCMD=""
podman=$(which podman)
docker=$(which docker)


if [ -z "${podman}" ] && [ -z "${docker}" ]; then
    echo "YOU NEED TO INSTALL DOCKER OR PODMAN"
    echo "Podman: https://podman.io/getting-started/installation.html"
    echo "Docker: https://docs.docker.com/desktop/install/mac-install/"

    exit 1
fi
if [ -n "${podman}" ]; then
    containerCMD=$podman
fi
if [ -n "${docker}" ]; then
    containerCMD=$docker
fi


executables="kind kubectl helm git"
for e in $executables; do
    [ -z "$(which "$e")" ] && missing+="$e "
done

missing=
for e in $executables; do
    [ -z "$(which "$e")" ] && missing+="$e "
done

[ -n "${brewcmd}" ] && for m in $missing; do
    case $m in
    kind)
        echo "Installing Kind"
        env -i bash -c 'brew install kind'
        echo "Kind install complete"
        ;;
    kubectl)
        echo "Installing kubectl"
        env -i bash -c 'brew install kubectl'
        echo "Kubectl install complete"
        ;;
    helm)
        echo "Installing helm"
        env -i bash -c 'brew install helm'
        echo "Helm install complete"
        ;;
    esac
done

echo "Starting local Kubernetes cluser with Kind..."
kind create cluster --name kind-kubecon-2023 --config=./init/kind-config.yaml --image kindest/node:v1.26.0 --wait 5m || \
    { echo "Start failed--try 'kind delete cluster kind-kubecon-2023'"; exit 1; }

echo "Using Helm to install Crossplane on local Kubernetes cluster..."

kubectl create namespace crossplane-system
kubectl apply -f ./init/pv.yaml

helm install crossplane \
    https://charts.crossplane.io/stable/crossplane-1.11.3.tgz \
    --namespace crossplane-system \
    --wait \
    --set packageCache.pvc=package-cache \
    --set args='{"--enable-environment-configs", "--debug"}' \

kubectl -n crossplane-system patch deployment/crossplane --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/1","value":{"image":"alpine","name":"dev","command":["sleep","infinity"],"volumeMounts":[{"mountPath":"/tmp/cache","name":"package-cache"}]}},{"op":"add","path":"/spec/template/metadata/labels/patched","value":"true"}]'

echo "$ kubectl get pods -n crossplane-system"
kubectl get pods -n crossplane-system

echo "Waiting for Crossplane resources to become available..."
kubectl -n crossplane-system wait deploy crossplane --for condition=Available --timeout=60s
kubectl -n crossplane-system wait pods -l app=crossplane,patched=true --for condition=Ready --timeout=60s

kind export  kubeconfig  --name kind-kubecon-2023

kubectl apply -f init/provider.yaml
echo "Waiting for Crossplane AWS-Provider to become available..."
kubectl wait "provider.pkg.crossplane.io/provider-aws" --for=condition=healthy --timeout=300s

kubectl create secret generic aws-secret -n crossplane-system --from-file=creds=./init/aws-credentials.txt
kubectl apply -f init/providerconfig.yaml
