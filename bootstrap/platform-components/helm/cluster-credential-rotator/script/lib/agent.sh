#!/bin/sh

build_kubeconfig() (
  kubeconfig_path=$1
  server=$2
  ca_data=$3
  insecure=$4
  token=$5

  case "$insecure" in
    true)
      cat >"$kubeconfig_path" <<EOF_KUBECONFIG
apiVersion: v1
kind: Config
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: ${server}
  name: managed-cluster
contexts:
- context:
    cluster: managed-cluster
    user: kubara-agent
  name: managed-cluster
current-context: managed-cluster
users:
- name: kubara-agent
  user:
    token: ${token}
EOF_KUBECONFIG
      ;;
    false)
      if [ -n "$ca_data" ]; then
        cat >"$kubeconfig_path" <<EOF_KUBECONFIG
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${ca_data}
    server: ${server}
  name: managed-cluster
contexts:
- context:
    cluster: managed-cluster
    user: kubara-agent
  name: managed-cluster
current-context: managed-cluster
users:
- name: kubara-agent
  user:
    token: ${token}
EOF_KUBECONFIG
      else
        cat >"$kubeconfig_path" <<EOF_KUBECONFIG
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: ${server}
  name: managed-cluster
contexts:
- context:
    cluster: managed-cluster
    user: kubara-agent
  name: managed-cluster
current-context: managed-cluster
users:
- name: kubara-agent
  user:
    token: ${token}
EOF_KUBECONFIG
      fi
      ;;
    *)
      return 1
      ;;
  esac
)

validate_kubeconfig() (
  kubeconfig_path=$1

  kubectl \
    --kubeconfig "$kubeconfig_path" \
    get namespace kube-system \
    >/dev/null
)

ensure_agent_identity() (
  bootstrap_kubeconfig=$1
  agent_namespace=$2

  cat <<EOF_AGENT | kubectl --kubeconfig "$bootstrap_kubeconfig" apply -f - >/dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: ${agent_namespace}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${AGENT_SERVICE_ACCOUNT_NAME}
  namespace: ${agent_namespace}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${AGENT_CLUSTER_ROLE_BINDING_NAME}
subjects:
  - kind: ServiceAccount
    name: ${AGENT_SERVICE_ACCOUNT_NAME}
    namespace: ${agent_namespace}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${AGENT_CLUSTER_ROLE_NAME}
EOF_AGENT
)

mint_agent_token() (
  kubeconfig=$1
  agent_namespace=$2
  output_file=$3

  kubectl \
    --kubeconfig "$kubeconfig" \
    -n "$agent_namespace" \
    create token "$AGENT_SERVICE_ACCOUNT_NAME" \
    --duration="${TOKEN_DURATION_SECONDS}s" \
    -o jsonpath='{.status.token}{"\n"}{.status.expirationTimestamp}{"\n"}' \
    >"$output_file"
)

extract_bootstrap_cluster_info() (
  bootstrap_kubeconfig_file=$1
  output_file=$2

  server="$(
    kubectl \
      --kubeconfig "$bootstrap_kubeconfig_file" \
      config view \
      --raw \
      --flatten \
      --minify \
      -o jsonpath='{.clusters[0].cluster.server}'
  )" || return 1

  [ -n "$server" ] || return 1

  ca_data="$(
    kubectl \
      --kubeconfig "$bootstrap_kubeconfig_file" \
      config view \
      --raw \
      --flatten \
      --minify \
      -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'
  )" || return 1

  insecure="$(
    kubectl \
      --kubeconfig "$bootstrap_kubeconfig_file" \
      config view \
      --raw \
      --flatten \
      --minify \
      -o jsonpath='{.clusters[0].cluster.insecure-skip-tls-verify}'
  )" || return 1

  [ -n "$insecure" ] || insecure="false"

  case "$insecure" in
    true|false)
      ;;
    *)
      return 1
      ;;
  esac

  printf '%s\n%s\n%s\n' "$server" "$ca_data" "$insecure" >"$output_file"
)
