prefix := "oci://localhost:5000/fnndsc/charts/"
actual := "https://fnndsc.github.io/charts"
testing_dir := justfile_directory() / "testing"

# Startup and Shutdown Commands
# --------------------------------------------------------------------------------

kind:
    kind create cluster --name khris --config '{{ testing_dir }}/kind-with-nodeport.yml'

unkind:
    kind delete cluster --name khris

up:
    custom_values='{{ testing_dir }}/custom-values.yaml'; [ -f "$custom_values" ] || touch "$custom_values"
    helmfile apply -f '{{ testing_dir }}/helmfile.yaml' -l name=cacao

down:
    helm uninstall -n kk --wait cacao
    kubectl delete ns kk

# Development Commands
# --------------------------------------------------------------------------------

wait:
    kubectl wait --for=condition=ready pod -n kk -l app.kubernetes.io/name=chris-server --timeout=300s

test:
    helm test -n kk cacao

create-user username password:
    xh :32000/api/v1/users/ username='{{ username }}' password='{{ password }}' email='{{ username }}@example.org'

describe name:
    kubectl describe -n kk pod -l app.kubernetes.io/name={{ name }}

log name:
    kubectl logs -n kk -l app.kubernetes.io/name={{ name }}

loga name:
    kubectl logs -n kk -l app.kubernetes.io/name={{ name }} --all-containers

shell:
    kubectl exec -it -n kk deploy/cacao-chris-server -- bash

clear-pacsfiles:
    ./clear_pacsfiles.sh

openobserve:
    helm repo add vector https://helm.vector.dev
    helm repo update vector
    helm upgrade --install --create-namespace -n monitoring -f openobserve/vector-agent.yml vector-agent vector/vector
    helm upgrade --install -n monitoring -f openobserve/vector-aggregator.yml vector-aggregator vector/vector
    kubectl apply -f openobserve/metrics-reader.yml
    helm upgrade --reuse-values -n monitoring vector-aggregator vector/vector \
        --set customConfig.sources.cadvisor.auth.token="$(kubectl create token -n monitoring --duration=99999h vector-aggregator)" \
        --set customConfig.sources.cadvisor.endpoints="$(./openobserve/_get_cadvisor_endpoints.sh)"

    kubectl apply -f openobserve/openobserve.yml
    kubectl rollout status -n monitoring statefulset openobserve
    sleep 1
    xdg-open "http://localhost:32020/web/logs?stream=k8s&period=5m&refresh=0&sql_mode=false&query=a3ViZXJuZXRlc19wb2RfbmFtZXNwYWNlPSdrayc=&org_identifier=default"

rm-observe:
    kubectl delete ns monitoring

olog name:
    ./openobserve/_get_openobserve_logs.sh '{{ name }}'

metrics-server:
    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
    helm upgrade --install --set args={--kubelet-insecure-tls} metrics-server metrics-server/metrics-server --namespace kube-system

top:
    kubectl top -n kk pod --containers | grep -v POD | grep -v prometheus-proxy

observe:
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add quickwit https://helm.quickwit.io
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
    helm repo update prometheus-community quickwit open-telemetry
    helm upgrade --install --create-namespace -n observe -f observe/prom-stack.yaml prom-stack prometheus-community/kube-prometheus-stack
    kubectl apply -f observe/quickwit.yml
    kubectl wait --for=condition=ready -n observe pod -l app.kubernetes.io/name=grafana --timeout=300s
    helm upgrade --install -n observe -f observe/opentelemetry-collector.yaml otel-collector open-telemetry/opentelemetry-collector

linkerd:
    linkerd check --pre
    linkerd install --crds | kubectl apply -f -
    linkerd install | kubectl apply -f -
    linkerd viz install | kubectl apply -f -
    linkerd check

# Helper Functions
# --------------------------------------------------------------------------------

get-url:
    echo "http://$(hostname):$(just get-nodeport)/api/v1/"

get-nodeport:
    kubectl get service -n kk -l app.kubernetes.io/name=chris-server -o jsonpath='{.items[0].spec.ports[0].nodePort}'

get-su key:
    kubectl get secret -n kk -l app.kubernetes.io/name=chris-superuser -o jsonpath='{.items[0].data.{{key}}}' | base64 -d

get-value query:
    helm get values --all -o json -n kk cacao | jq -r '{{ query }}'

# Local registry
# TODO: do not need anything in this local registry. I can use file://
# --------------------------------------------------------------------------------

[group("Local Registry")]
sync: install-pre-commit
    @just list-local-charts | xargs -n 1 just push

[group("Local Registry")]
list-local-charts:
    @yq '.dependencies[] | .repository | select(test("{{ prefix }}")) | sub("{{ prefix }}", "")' '{{ justfile_directory() }}/charts/chris/Chart.yaml'

[group("Local Registry")]
push name: registry
    helm package ./charts/{{ name }}
    helm push --plain-http ./{{ name }}-*.tgz oci://localhost:5000/fnndsc/charts/{{ name }}
    rm ./{{ name }}-*.tgz

[group("Local Registry")]
registry:
    @status="$(podman container inspect -f '{{{{ .State.Status }}' registry 2> /dev/null)"; \
    if [ "$?" != '0' ]; then   \
      just registry-run;       \
    elif [ "$status" != 'running' ]; then \
      just registry-start;     \
    fi

[group("Local Registry")]
registry-start:
    podman start registry

[group("Local Registry")]
registry-run:
    podman run --name registry -d -p 5000:5000 ghcr.io/distribution/distribution:3

[group("Local Registry")]
registry-down:
    podman rm -f registry

[group("Local Registry")]
substitute-url:
    for file in ./charts/*/Chart.{lock,yaml}; do \
      sed -i 's#{{ prefix }}.*#{{ actual }}#' "$file"; \
    done

# Install git hooks
[group("Git Development")]
[working-directory(".git/hooks")]
install-pre-commit:
    @rm -r pre-commit
    @ln -s ../../hooks/pre-commit.sh pre-commit
