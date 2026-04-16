#!/bin/bash
# nspawn-ctl — CLI para gestionar contenedores nspawn
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

show_help() {
  cat <<'MSG'

  nspawn-ctl <accion> [filtro]

  Gestion:     list start stop shell logs resources
  Ciclo vida:  create snapshot ephemeral delete
  Info:        status config commands

  Crear rapido:
    nspawn-ctl create venv go|python|web|rust|all
    nspawn-ctl create k3s <nombre>
    nspawn-ctl create kvm [cockpit|virt|cli]
    nspawn-ctl create box <nombre> [alpine|arch|debian]

  Filtros: venv, k3s, k3s-lab, kvm, box

MSG
}

pick() {
  local F="${1:-}"
  mapfile -t _names < <(list_names "$F")
  [ ${#_names[@]} -eq 0 ] && echo "  (sin contenedores)" && exit 0

  if [ ${#_names[@]} -eq 1 ]; then
    SELECTED="${_names[0]}"
    return
  fi

  echo ""
  local c state
  for c in "${_names[@]}"; do
    state=$(machinectl show "$c" -p State --value 2>/dev/null || echo "stopped")
    printf "    %-25s %s\n" "$c" "[$state]"
  done
  echo ""
  read -rp "  Nombre: " SELECTED
  [ -z "$SELECTED" ] && echo "  Cancelado" && exit 0
}

print_table() {
  local F="${1:-}"
  printf "\n  %-4s  %-26s %-10s %-8s %s\n" "Tipo" "Nombre" "Estado" "RAM" "Disco"
  printf "  ────  ────────────────────────  ─────────  ──────  ─────\n"

  local name type state ram size cg
  for d in "$MACHINES"/*/; do
    [ -d "$d" ] || continue
    name="${d%/}"; name="${name##*/}"
    [[ "$name" == .* ]] && continue
    [ -n "$F" ] && [[ "$name" != ${F}* ]] && continue

    type="${name%%-*}"
    state=$(machinectl show "$name" -p State --value 2>/dev/null || echo "stopped")
    ram="-"
    if [ "$state" = "running" ]; then
      cg="/sys/fs/cgroup/machine.slice/systemd-nspawn@${name}.service/memory.current"
      [ -f "$cg" ] && ram=$(numfmt --to=iec < "$cg" 2>/dev/null || echo "-")
    fi
    # du solo si hay contenedores (evitar sudo innecesario en stopped)
    size=$(du -sh "$d" 2>/dev/null | cut -f1 || echo "?")
    printf "  %-4s  %-26s %-10s %-8s %s\n" "$type" "$name" "[$state]" "$ram" "$size"
  done
  echo ""
}

batch_action() {
  local action="$1" filter="$2" verb="$3" c
  for c in $(list_names "$filter"); do
    echo "  # sudo machinectl $action $c"
    sudo machinectl "$action" "$c" 2>/dev/null && echo "    ok" || echo "    ya ${verb}"
  done
}

# start/stop con filtro inteligente: 1 = directo, N = batch, 0 = pick
filtered_action() {
  local action="$1" verb="$2" F="${3:-}"
  if [ -n "$F" ]; then
    mapfile -t _matched < <(list_names "$F")
    case ${#_matched[@]} in
      0) echo "  (sin contenedores con filtro '$F')" ;;
      1) echo "  # sudo machinectl $action ${_matched[0]}"
         sudo machinectl "$action" "${_matched[0]}" ;;
      *) batch_action "$action" "$F" "$verb" ;;
    esac
  else
    pick
    echo "  # sudo machinectl $action $SELECTED"
    sudo machinectl "$action" "$SELECTED"
  fi
}

case "${1:-help}" in

  create)
    case "${2:-}" in
      venv) bash "$SCRIPT_DIR/setup/venv.sh" "${3:-}" ;;
      k3s)  bash "$SCRIPT_DIR/setup/k3s.sh"  "${3:-}" ;;
      kvm)  bash "$SCRIPT_DIR/setup/kvm.sh"  "${3:-}" ;;
      box)  bash "$SCRIPT_DIR/setup/box.sh"  "${3:-}" "${4:-}" ;;
      "")
        cat <<MSG

  Setups:
    1) venv        Desarrollo (Go/Python/Web/Rust)
    2) k3s         Cluster K3s
    3) kvm         KVM/QEMU aislado
    4) box         Generico (con/sin Podman)

MSG
        read -rp "  Opcion [1/2/3/4]: " S
        case "$S" in
          1) bash "$SCRIPT_DIR/setup/venv.sh" ;;
          2) bash "$SCRIPT_DIR/setup/k3s.sh" ;;
          3) bash "$SCRIPT_DIR/setup/kvm.sh" ;;
          4) bash "$SCRIPT_DIR/setup/box.sh" ;;
          *) echo "  Invalido" ;;
        esac ;;
      *) echo "  Tipo desconocido: ${2:-}"; show_help ;;
    esac ;;

  list) print_table "${2:-}" ;;

  status)
    pick "${2:-}"
    echo "  # machinectl status $SELECTED"
    machinectl status "$SELECTED" 2>/dev/null || echo "  (detenido)"
    conf="/etc/systemd/nspawn/${SELECTED}.nspawn"
    [ -f "$conf" ] && echo "" && cat "$conf"
    svc_dir="/etc/systemd/system/systemd-nspawn@${SELECTED}.service.d"
    [ -d "$svc_dir" ] && echo "" && echo "  === Recursos ===" && cat "$svc_dir"/*.conf 2>/dev/null ;;

  resources) systemd-cgtop -m ;;

  start) filtered_action start "activo" "${2:-}" ;;
  stop)  filtered_action stop "detenido" "${2:-}" ;;

  shell)
    pick "${2:-}"
    sudo machinectl shell "$SELECTED" ;;

  logs)
    pick "${2:-}"
    journalctl -M "$SELECTED" -n 50 2>/dev/null || {
      echo "  (sin journal — Alpine usa OpenRC)"
      sudo machinectl shell "$SELECTED" -- ls /var/log/ 2>/dev/null || echo "  (contenedor detenido)"
    } ;;

  snapshot)
    pick "${2:-}"
    SNAP="${MACHINES}/${SELECTED}-snap-$(date +%Y%m%d-%H%M)"
    sudo btrfs subvolume snapshot "$MACHINES/$SELECTED" "$SNAP"
    echo "  Creado: $SNAP" ;;

  ephemeral)
    pick "${2:-}"
    sudo systemd-nspawn -xD "$MACHINES/$SELECTED" ;;

  delete)
    pick "${2:-}"
    echo "  Eliminar $SELECTED?"
    read -rp "  [s/N]: " C
    [ "$C" = "s" ] && cleanup_container "$SELECTED" && echo "  Eliminado" ;;

  config)
    pick "${2:-}"
    conf="/etc/systemd/nspawn/${SELECTED}.nspawn"
    [ -f "$conf" ] && cat "$conf" || echo "  (sin config)" ;;

  commands) cat <<'MSG'

  === Comandos nspawn/machinectl ===

  machinectl list-images / list / status <n>
  sudo machinectl start/stop/shell/enable <n>
  systemd-cgtop / journalctl -M <n> / systemd-cgls -M <n>
  sudo btrfs subvolume snapshot/delete <path>
  sudo systemd-nspawn -xD/-D/-bD <path>
  Config:    /etc/systemd/nspawn/<n>.nspawn
  Recursos:  /etc/systemd/system/systemd-nspawn@<n>.service.d/

MSG
    ;;

  *) show_help ;;
esac
