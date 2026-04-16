#!/bin/bash
# nspawn/lib/common.sh — Funciones compartidas

MACHINES="/var/lib/machines"
ALPINE_VER="3.21"
ALPINE_TARBALL="alpine-minirootfs-${ALPINE_VER}.3-x86_64.tar.gz"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/releases/x86_64/${ALPINE_TARBALL}"
ALPINE_REPOS="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/community"

# ── Usuarios (se resuelve una sola vez) ──

USERNAME=""
HOME_DIR=""

get_user() {
  [ -n "$USERNAME" ] && return 0
  USERNAME=$(getent passwd 1000 | cut -d: -f1)
  [ -z "$USERNAME" ] && echo "Error: no se encontro usuario UID 1000" && exit 1
  HOME_DIR="/home/$USERNAME"
}

validate_name() {
  local name="$1"
  [ -z "$name" ] && echo "Error: nombre requerido" && exit 1
  [[ ! "$name" =~ ^[a-z0-9-]+$ ]] && echo "Error: solo minusculas, numeros y guiones" && exit 1
}

# ── Cache ──

CACHE_DIR=""

init_cache() {
  [ -n "$CACHE_DIR" ] && return 0
  get_user
  CACHE_DIR="$HOME_DIR/.nspawn/cache"
  sudo -u "$USERNAME" mkdir -p "$CACHE_DIR"
}

cache_download() {
  local url="$1" filename="$2"
  init_cache
  local path="$CACHE_DIR/$filename"
  if [ -f "$path" ]; then
    echo "  Cache: $filename"
  else
    echo "  Descargando: $filename"
    curl -fSL "$url" -o "$path.tmp" && mv "$path.tmp" "$path"
  fi
}

# ── Contenedores ──

container_exists() { [ -d "$MACHINES/$1" ]; }

ensure_not_exists() {
  container_exists "$1" && echo "Error: $1 ya existe" && exit 1
  return 0
}

ensure_exists() {
  container_exists "$1" || { echo "Error: $1 no existe"; exit 1; }
}

# Sin forks: glob de bash puro
list_names() {
  local filter="${1:-}" name
  for d in "$MACHINES"/*/; do
    [ -d "$d" ] || continue
    name="${d%/}"; name="${name##*/}"
    [[ "$name" == .* ]] && continue
    [ -n "$filter" ] && [[ "$name" != ${filter}* ]] && continue
    echo "$name"
  done
}

create_alpine_base() {
  local name="$1"
  [ -d "$MACHINES/$name" ] && echo "Error: $name ya existe" && exit 1
  init_cache
  cache_download "$ALPINE_URL" "$ALPINE_TARBALL"
  sudo btrfs subvolume create "$MACHINES/$name"
  sudo tar -xzf "$CACHE_DIR/$ALPINE_TARBALL" -C "$MACHINES/$name"
  # Un solo sudo para los 3 archivos
  sudo sh -c "
    cat > '$MACHINES/$name/etc/apk/repositories' <<'REPOS'
$ALPINE_REPOS
REPOS
    echo '$name' > '$MACHINES/$name/etc/hostname'
    echo 'nameserver 1.1.1.1' > '$MACHINES/$name/etc/resolv.conf'
  "
}

clone_template() {
  local template="$1" name="$2"
  [ ! -d "$MACHINES/$template" ] && echo "Error: template $template no existe" && exit 1
  [ -d "$MACHINES/$name" ] && echo "Error: $name ya existe" && exit 1
  sudo btrfs subvolume snapshot "$MACHINES/$template" "$MACHINES/$name"
  echo "$name" | sudo tee "$MACHINES/$name/etc/hostname" > /dev/null
}

run_in() {
  local name="$1"; shift
  sudo systemd-nspawn -D "$MACHINES/$name" --pipe sh -c "$*"
}

write_nspawn_config() {
  local name="$1" content="$2"
  sudo mkdir -p /etc/systemd/nspawn
  printf '%s\n' "$content" | sudo tee "/etc/systemd/nspawn/${name}.nspawn" > /dev/null
}

optional_binds() {
  get_user
  local binds=""
  [ -d "$HOME_DIR/.ssh" ] && binds="${binds}BindReadOnly=$HOME_DIR/.ssh:/root/.ssh
"
  [ -f "$HOME_DIR/.gitconfig" ] && binds="${binds}BindReadOnly=$HOME_DIR/.gitconfig:/root/.gitconfig
"
  printf '%s' "$binds"
}

# ── Recursos via systemd service override ──
# .nspawn NO soporta [Resource]. Limites van en el service unit.

apply_resources() {
  local name="$1" weight="$2" mhigh="$3" mmax="$4" tasks="${5:-64}"
  local dir="/etc/systemd/system/systemd-nspawn@${name}.service.d"
  sudo mkdir -p "$dir"
  sudo tee "$dir/resources.conf" > /dev/null <<EOF
[Service]
CPUWeight=$weight
MemoryHigh=$mhigh
MemoryMax=$mmax
MemorySwapMax=0
TasksMax=$tasks
EOF
}

apply_device_allow() {
  local name="$1"; shift
  local dir="/etc/systemd/system/systemd-nspawn@${name}.service.d"
  # dir ya existe si apply_resources se llamo antes
  [ ! -d "$dir" ] && sudo mkdir -p "$dir"
  local content="[Service]"
  for dev in "$@"; do
    content="${content}
DeviceAllow=$dev"
  done
  sudo tee "$dir/devices.conf" > /dev/null <<< "$content"
}

cleanup_container() {
  local name="$1"
  sudo machinectl stop "$name" 2>/dev/null || true
  sudo btrfs subvolume delete "$MACHINES/$name" 2>/dev/null || sudo rm -rf "$MACHINES/$name"
  sudo rm -f "/etc/systemd/nspawn/${name}.nspawn"
  sudo rm -rf "/etc/systemd/system/systemd-nspawn@${name}.service.d"
  sudo systemctl daemon-reload 2>/dev/null || true
}
