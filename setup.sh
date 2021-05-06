#!/bin/bash

ISTIO_VERSION=1.9.4


set -eo pipefail

dir=$(dirname $0)

external_domain=local

echo "setting up istio $ISTIO_VERSION"

if [[ ! -f ./istio-$ISTIO_VERSION/bin/istioctl ]]; then
    echo "downloading istio $ISTIO_VERSION"
	curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
fi

if [[ ! -f ${dir}/ssl/wildcard.${external_domain}.crt ]]; then
  mkdir -p ${dir}/ssl
  openssl req -nodes -newkey rsa:2048 -new -sha256 \
    -keyout ${dir}/ssl/wildcard.${external_domain}.key \
    -out ${dir}/ssl/wildcard.${external_domain}.csr \
    -subj "/C=/O=kind/OU=local/CN=*.${external_domain}"
  openssl x509 -req -days 365 -in ${dir}/ssl/wildcard.${external_domain}.csr \
    -signkey ${dir}/ssl/wildcard.${external_domain}.key \
    -out ${dir}/ssl/wildcard.${external_domain}.crt  
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


kubectl create secret tls istio-ingressgateway-certs --namespace istio-system \
  --cert=${dir}/ssl/wildcard.${external_domain}.crt --key=${dir}/ssl/wildcard.${external_domain}.key \
  --dry-run=client -o yaml | kubectl apply -f -

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


    	kubectl apply -f ${dir}/istio/virtual-services/logging.yaml -n logging \
          --dry-run=client -o yaml | kubectl apply -f -

    elif [[ "$var" = "--with-monitoring" ]]; then


      if [ ! -f ${dir}/../kubernetes-monitoring/install-monitoring.sh ]; then
        echo "sync https://github.com/nickytd/kubernetes-monitoring in ${dir}/.."
        exit
      fi  

      ${dir}/../kubernetes-monitoring/install-monitoring.sh

    	kubectl apply -f ${dir}/istio/virtual-services/monitoring.yaml -n monitoring \
          --dry-run=client -o yaml | kubectl apply -f -

      kubectl apply -f ${dir}/istio-$ISTIO_VERSION/samples/addons/extras/prometheus-operator.yaml \
          -n istio-system --dry-run=client -o yaml | kubectl apply -f -    

      kubectl apply -f ${dir}/istio/grafana/grafana-dashboards.yaml \
          -n monitoring --dry-run=client -o yaml | kubectl apply -f -    

    elif [[ "$var" = "--with-tracing" ]]; then

      kubectl apply -f ${dir}/istio/virtual-services/tracing.yaml -n istio-system \
          --dry-run=client -o yaml | kubectl apply -f -

      kubectl apply -f ${dir}/istio-$ISTIO_VERSION/samples/addons/jaeger.yaml \
          -n istio-system --dry-run=client -o yaml | kubectl apply -f -

    elif [[ "$var" = "--with-kiali" ]]; then
      
      kubectl apply -f ${dir}/istio-$ISTIO_VERSION/samples/addons/kiali.yaml \
          -n istio-system --dry-run=client -o yaml | kubectl apply -f -      

    elif [[ "$var" = "--with-dashboard" ]]; then

      if [ ! -f ${dir}/../kubernetes-dashboard/install-kubernetes-dashboard.sh ]; then
        echo "sync https://github.com/nickytd/kubernetes-dashboard in ${dir}/.."
        exit
      fi  

      ${dir}/../kubernetes-dashboard/install-kubernetes-dashboard.sh

      kubectl apply -f ${dir}/istio/virtual-services/kubernetes-dashboard.yaml -n kubernetes-dashboard \
          --dry-run=client -o yaml | kubectl apply -f -

    fi      

done