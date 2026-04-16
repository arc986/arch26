#!/bin/bash
# nspawn — Clusters K3s en nspawn Alpine
# Uso: k3s.sh [nombre-cluster]
# kubectl se instala DENTRO del master, no en el host
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/profiles.sh"

TEMPLATE=".k3s-template"
K3S_INSTALLER="k3s-install.sh"

# Si se pasa nombre como argumento, crear cluster directo
if [ -n "${1:-}" ]; then
  ACTION=1
else
  cat <<MSG
K3s Cluster:
  1) Crear cluster nuevo
  2) Agregar worker a cluster existente
MSG
  read -rp "Opcion [1/2]: " ACTION
fi

ensure_template() {
  container_exists "$TEMPLATE" && return 0
  create_alpine_base "$TEMPLATE"
  run_in "$TEMPLATE" 'apk add --no-cache curl iptables ip6tables wireguard-tools ca-certificates; rm -rf /var/cache/apk/*'
}

prepare_k3s_installer() {
  local name="$1"
  init_cache
  cache_download "https://get.k3s.io" "$K3S_INSTALLER"
  sudo cp "$CACHE_DIR/$K3S_INSTALLER" "$MACHINES/$name/tmp/k3s-install.sh"
  sudo chmod +x "$MACHINES/$name/tmp/k3s-install.sh"
}

install_k3s_server() {
  local m="$1"
  prepare_k3s_installer "$m"
  run_in "$m" "INSTALL_K3S_EXEC='server --disable traefik --disable servicelb --disable local-storage --disable metrics-server --write-kubeconfig-mode 644 --node-name $m --flannel-backend host-gw --kube-proxy-arg proxy-mode=iptables --kubelet-arg max-pods=30 --kubelet-arg eviction-hard=memory.available<20Mi --kubelet-arg system-reserved=memory=32Mi' sh /tmp/k3s-install.sh"
  run_in "$m" 'apk add --no-cache kubectl; rm -rf /var/cache/apk/*'
}

install_k3s_agent() {
  local w="$1" ip="$2" tok="$3"
  prepare_k3s_installer "$w"
  run_in "$w" "K3S_URL='https://${ip}:6443' K3S_TOKEN='$tok' INSTALL_K3S_EXEC='agent --node-name $w --kube-proxy-arg proxy-mode=iptables --kubelet-arg max-pods=20 --kubelet-arg eviction-hard=memory.available<10Mi --kubelet-arg system-reserved=memory=16Mi' sh /tmp/k3s-install.sh"
}

get_cluster_info() {
  local master="$1"
  MASTER_IP=$(sudo machinectl show "$master" -p Addresses --value | cut -d' ' -f1)
  TOKEN=$(run_in "$master" 'cat /var/lib/rancher/k3s/server/node-token')
}

create_cluster() {
  local CL="${1:-}"
  [ -z "$CL" ] && read -rp "Nombre del cluster: " CL
  validate_name "$CL"
  local M="k3s-${CL}-master" W1="k3s-${CL}-worker1" W2="k3s-${CL}-worker2"
  for N in $M $W1 $W2; do ensure_not_exists "$N"; done
  ensure_template

  for N in $M $W1 $W2; do
    clone_template "$TEMPLATE" "$N"
    local role="${N##*-}"
    profile_k3s "$N" "$CL" "$role"
    sudo machinectl start "$N"
  done
  sleep 5

  install_k3s_server "$M"
  sleep 10
  get_cluster_info "$M"
  install_k3s_agent "$W1" "$MASTER_IP" "$TOKEN"
  install_k3s_agent "$W2" "$MASTER_IP" "$TOKEN"

  local KC_PATH="$MACHINES/$M/etc/rancher/k3s/k3s.yaml"

  cat <<MSG

=== Cluster '$CL' listo ===
  kubectl: sudo machinectl shell $M -- kubectl get nodes
  kubeconfig: $KC_PATH
  nspawn-ctl start k3s-$CL
  nspawn-ctl stop k3s-$CL
MSG
}

add_worker() {
  read -rp "Cluster: " CL; validate_name "$CL"
  local M="k3s-${CL}-master"; ensure_exists "$M"; ensure_template
  local N=1; while container_exists "k3s-${CL}-worker${N}"; do N=$((N+1)); done
  local W="k3s-${CL}-worker${N}"

  clone_template "$TEMPLATE" "$W"; profile_k3s "$W" "$CL" "worker"
  sudo machinectl start "$W"; sleep 3
  get_cluster_info "$M"; install_k3s_agent "$W" "$MASTER_IP" "$TOKEN"
  echo "=== $W agregado a '$CL' ==="
}

case "$ACTION" in 1) create_cluster "${1:-}" ;; 2) add_worker ;; *) echo "Invalido"; exit 1 ;; esac
