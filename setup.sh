#!/bin/bash

ISTIO_VERSION=1.9.4

set -eo pipefail


if [[ "$1" == "-h" ]]; then
   echo "## installs istio $ISTIO_VERSION ##"
   echo "   supported options:"
   echo "     --with-virtual-services"
   echo "       adds monitoring and logging applicaitons virtual services"
   exit
fi


dir=$(dirname $0)

external_domain=local

echo "setting up istio $ISTIO_VERSION"

if [[ ! -f ./istio-$ISTIO_VERSION/bin/istioctl ]]; then
    echo "downloading istio $ISTIO_VERSION"
	curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
fi
    
kubectl create namespace istio-system \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade istio-base --namespace istio-system \
  ${dir}/istio-$ISTIO_VERSION/manifests/charts/base \
  --install --wait --timeout 15m

helm upgrade istiod --namespace istio-system \
  ${dir}/istio-$ISTIO_VERSION/manifests/charts/istio-control/istio-discovery \
  --set global.hub="docker.io/istio" --set global.tag="$ISTIO_VERSION" \
  --install --wait --timeout 15m

if [ -d $dir/ssl ]; then
  kubectl create secret tls istio-ingressgateway-certs --namespace istio-system \
    --cert=${dir}/ssl/_wildcard.local.dev.pem \
    --key=${dir}/ssl/_wildcard.local.dev-key.pem \
    --dry-run=client -o yaml | kubectl apply -f -
fi 

helm upgrade istio-ingress --namespace istio-system \
  ${dir}/istio-$ISTIO_VERSION/manifests/charts/gateways/istio-ingress \
  -f ${dir}/istio-ingress-values.yaml \
  --set global.hub="docker.io/istio" --set global.tag="$ISTIO_VERSION" \
  --install --wait --timeout 15m

kubectl apply -f ${dir}/istio-gateway.yaml -n istio-system \
  --dry-run=client -o yaml | kubectl apply -f - 

for var in "$@"
do
    kubectl create namespace kubernetes-dashboard \
      --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace logging \
      --dry-run=client -o yaml | kubectl apply -f -  
    kubectl create namespace monitoring \
      --dry-run=client -o yaml | kubectl apply -f -  

    if [[ "$var" = "--with-virtual-services" ]]; then      
    	for vss in ${dir}/virtual-services/*.yaml ; do
        kubectl apply -f ${vss}
       done
    fi 



done