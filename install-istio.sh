#!/bin/bash

ISTIO_VERSION=1.8.1


set -eo pipefail

dir=$(dirname $0)

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

helm upgrade istio-ingress --namespace istio-system \
  ${dir}/istio-$ISTIO_VERSION/manifests/charts/gateways/istio-ingress \
  -f ${dir}/istio/istio-ingress-values.yaml \
  --set global.hub="docker.io/istio" --set global.tag="$ISTIO_VERSION" \
  --install --wait --timeout 15m

kubectl apply -f ${dir}/istio/istio-gw.yaml -n istio-system \
  --dry-run=client -o yaml | kubectl apply -f -  

for var in "$@"
do
    if [[ "$var" = "--with-logging" ]]; then

      if [ ! -f ${dir}/../kubernetes-logging-helm/examples/install-elk.sh ]; then
        echo "sync https://github.com/nickytd/kubernetes-logging-helm in ${dir}/.."
        exit
      fi  

      ${dir}/../kubernetes-logging-helm/examples/install-elk.sh


    	kubectl apply -f ${dir}/istio/logging-virtual-services.yaml -n logging \
          --dry-run=client -o yaml | kubectl apply -f -

    elif [[ "$var" = "--with-monitoring" ]]; then


      if [ ! -f ${dir}/../kubernetes-monitoring/install-monitoring.sh ]; then
        echo "sync https://github.com/nickytd/kubernetes-monitoring in ${dir}/.."
        exit
      fi  

      ${dir}/../kubernetes-monitoring/install-monitoring.sh

    	kubectl apply -f ${dir}/istio/monitoring-virtual-services.yaml -n monitoring \
          --dry-run=client -o yaml | kubectl apply -f -

      kubectl apply -f ${dir}/istio-$ISTIO_VERSION/samples/addons/jaeger.yaml \
          -n istio-system --dry-run=client -o yaml | kubectl apply -f -

      kubectl apply -f ${dir}/istio/istio-virtual-services.yaml \
          -n istio-system --dry-run=client -o yaml | kubectl apply -f -    

      kubectl apply -f ${dir}/istio-$ISTIO_VERSION/samples/addons/extras/prometheus-operator.yaml \
          -n istio-system --dry-run=client -o yaml | kubectl apply -f -    

       kubectl apply -f ${dir}/istio/grafana-dashboards.yaml \
          -n monitoring --dry-run=client -o yaml | kubectl apply -f -    

    elif [[ "$var" = "--with-dashboard" ]]; then
      
      kubectl apply -f ${dir}/istio/kubernetes-dashboard-virtual-services.yaml -n kubernetes-dashboard \
          --dry-run=client -o yaml | kubectl apply -f -      
    fi      

done