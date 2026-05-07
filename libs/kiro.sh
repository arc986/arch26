#!/bin/bash
# Kiro IDE — Gestor de instalacion (instalar/actualizar/eliminar/estado)
# Se instala en ~/.local/share/kiro (sin tocar el sistema)
# Descarga oficial de AWS via HTTPS
#
# NOTA: Kiro no esta en repos oficiales de Arch ni en Flathub.
# Binario oficial de AWS (prod.download.desktop.kiro.dev).
#
# Uso:
#   bash kiro.sh              Menu interactivo
#   bash kiro.sh install      Instalar o actualizar
#   bash kiro.sh update       Verificar y aplicar actualizacion
#   bash kiro.sh remove       Eliminar completamente
#   bash kiro.sh status       Ver version y estado
#   bash kiro.sh deps         Verificar dependencias
set -euo pipefail

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' C='\033[1;36m' N='\033[0m'
info()  { printf "${C}:: %s${N}\n" "$*"; }
ok()    { printf "${G}✓  %s${N}\n" "$*"; }
warn()  { printf "${Y}⚠  %s${N}\n" "$*"; }
die()   { printf "${R}✗  %s${N}\n" "$*" >&2; exit 1; }

# ── Detectar usuario ──
USERNAME=$(getent passwd 1000 | cut -d: -f1)
[ -z "$USERNAME" ] && die "No se encontro usuario UID 1000"
USER_GROUP=$(id -gn "$USERNAME")
HOME_DIR=$(getent passwd 1000 | cut -d: -f6)

INSTALL_DIR="$HOME_DIR/.local/share/kiro"
BIN_DIR="$HOME_DIR/.local/bin"
DESKTOP_DIR="$HOME_DIR/.local/share/applications"
DATA_DIR="$HOME_DIR/.config/Kiro"
METADATA_URL="https://prod.download.desktop.kiro.dev/stable/metadata-linux-x64-stable.json"
VERSION_FILE="$INSTALL_DIR/.kiro-version"

# Variables globales para fetch_metadata
REMOTE_VERSION=""
DOWNLOAD_URL=""

# ── Dependencias (Electron/VS Code fork + herramientas del script) ──
# Todas disponibles en repos oficiales de Arch (extra)
DEPS=(
  gtk3          # UI toolkit
  nss           # Network Security Services
  alsa-lib      # Audio
  libsecret     # Keychain (API keys)
  libxss        # X11 Screen Saver (requerido por Electron)
  xdg-utils     # xdg-open para links
  libnotify     # Notificaciones
  mesa          # GPU rendering
  jq            # Parseo de metadata JSON (usado por este script)
)

# ══════════════════════════════════════════
# Funciones auxiliares
# ══════════════════════════════════════════

as_user() {
  sudo -u "$USERNAME" -- "$@"
}

set_owner() {
  chown -R "$USERNAME:$USER_GROUP" "$@"
}

# ══════════════════════════════════════════
# Funciones principales
# ══════════════════════════════════════════

check_deps() {
  info "Verificando dependencias..."
  local missing=()
  for dep in "${DEPS[@]}"; do
    if pacman -Qi "$dep" &>/dev/null; then
      ok "  $dep"
    else
      warn "  $dep — NO instalado"
      missing+=("$dep")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    echo ""
    warn "Dependencias faltantes: ${missing[*]}"
    local INSTALL_DEPS=""
    read -rp "  Instalar ahora? [s/N]: " INSTALL_DEPS || true
    if [[ "$INSTALL_DEPS" == "s" ]]; then
      sudo pacman -S --needed --noconfirm "${missing[@]}"
      ok "Dependencias instaladas"
    else
      die "Dependencias requeridas no instaladas"
    fi
  else
    ok "Todas las dependencias presentes"
  fi
}

get_installed_version() {
  if [ -f "$VERSION_FILE" ]; then
    cat "$VERSION_FILE"
  elif [ -f "$INSTALL_DIR/resources/app/package.json" ]; then
    # Preferir jq, fallback a python3
    if command -v jq &>/dev/null; then
      jq -r '.version' "$INSTALL_DIR/resources/app/package.json" 2>/dev/null || echo "desconocida"
    elif command -v python3 &>/dev/null; then
      python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['version'])" \
        "$INSTALL_DIR/resources/app/package.json" 2>/dev/null || echo "desconocida"
    else
      echo "desconocida"
    fi
  else
    echo ""
  fi
}

fetch_metadata() {
  # Descarga metadata JSON y extrae URL del tarball y version remota
  local meta
  info "Consultando metadata de Kiro..."
  meta=$(curl --proto '=https' --tlsv1.2 -sS --connect-timeout 10 "$METADATA_URL") || {
    die "No se pudo obtener metadata de Kiro (sin conexion o URL inaccesible)"
  }

  if [ -z "$meta" ]; then
    die "Metadata vacia — verifica tu conexion a internet"
  fi

  if command -v jq &>/dev/null; then
    REMOTE_VERSION=$(echo "$meta" | jq -r '.currentRelease // empty')
    DOWNLOAD_URL=$(echo "$meta" | jq -r '[.releases[].updateTo.url | select(endswith(".tar.gz"))][0] // empty')
  elif command -v python3 &>/dev/null; then
    REMOTE_VERSION=$(echo "$meta" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('currentRelease',''))
")
    DOWNLOAD_URL=$(echo "$meta" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('releases',[]):
    url=r.get('updateTo',{}).get('url','')
    if url.endswith('.tar.gz'):
        print(url); break
")
  else
    die "Se requiere jq o python3 para parsear metadata"
  fi

  if [ -z "$DOWNLOAD_URL" ]; then
    die "No se encontro URL del tarball en metadata (estructura inesperada)"
  fi

  ok "URL de descarga obtenida"
}

save_version_info() {
  # Guardar version desde package.json
  if [ -f "$INSTALL_DIR/resources/app/package.json" ]; then
    if command -v jq &>/dev/null; then
      jq -r '.version' "$INSTALL_DIR/resources/app/package.json" > "$VERSION_FILE" 2>/dev/null || true
    elif command -v python3 &>/dev/null; then
      python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['version'])" \
        "$INSTALL_DIR/resources/app/package.json" > "$VERSION_FILE" 2>/dev/null || true
    fi
  fi
}

do_install() {
  check_deps

  local current_ver
  current_ver=$(get_installed_version)
  if [ -n "$current_ver" ]; then
    warn "Kiro ya instalado (version: $current_ver)"
    read -rp "  Reinstalar/actualizar? [s/N]: " CONFIRM
    [[ "$CONFIRM" == "s" ]] || return 0
  fi

  # Obtener URL de descarga desde metadata
  fetch_metadata
  info "Version remota: $REMOTE_VERSION"

  local TMP_DIR
  TMP_DIR=$(as_user mktemp -d)
  # Limpiar temporal al salir (exito o error)
  trap "rm -rf '$TMP_DIR'" EXIT

  info "Descargando Kiro IDE desde AWS..."
  as_user curl --proto '=https' --tlsv1.2 -fSL \
    --connect-timeout 15 --retry 3 \
    "$DOWNLOAD_URL" -o "$TMP_DIR/kiro.tar.gz"
  ok "Descarga completada"

  # Verificar que el tarball es valido
  if ! tar -tzf "$TMP_DIR/kiro.tar.gz" &>/dev/null; then
    die "El archivo descargado esta corrupto o no es un tarball valido"
  fi

  # Limpiar instalacion anterior si existe
  [ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"

  info "Instalando en $INSTALL_DIR..."
  as_user mkdir -p "$INSTALL_DIR"
  as_user tar -xzf "$TMP_DIR/kiro.tar.gz" -C "$INSTALL_DIR" --strip-components=1 --no-same-owner

  save_version_info

  # Limpiar temporal (trap tambien lo hara, pero por claridad)
  rm -rf "$TMP_DIR"
  trap - EXIT

  # Symlink al ejecutable
  as_user mkdir -p "$BIN_DIR"
  ln -sf "$INSTALL_DIR/kiro" "$BIN_DIR/kiro"

  # Desktop entry
  as_user mkdir -p "$DESKTOP_DIR"
  local ICON="$INSTALL_DIR/resources/app/resources/linux/code.png"
  [ ! -f "$ICON" ] && ICON="kiro"

  cat > "$DESKTOP_DIR/kiro.desktop" <<EOF
[Desktop Entry]
Name=Kiro
Comment=Agentic AI IDE by AWS
Exec=$INSTALL_DIR/kiro %F
Icon=$ICON
Terminal=false
Type=Application
MimeType=text/plain;inode/directory;
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=kiro
EOF

  # Electron flags para Wayland nativo + GPU
  # ELECTRON_OZONE_PLATFORM_HINT=wayland ya esta en /etc/environment
  # Estos flags complementan: aceleracion GPU y rendering nativo
  as_user mkdir -p "$HOME_DIR/.config"
  cat > "$HOME_DIR/.config/kiro-flags.conf" <<'FLAGS'
--enable-features=UseOzonePlatform,WaylandWindowDecorations,WebRTCPipeWireCapturer
--ozone-platform-hint=wayland
--enable-wayland-ime
--disable-gpu-sandbox
FLAGS

  # Permisos consistentes
  set_owner "$INSTALL_DIR" "$BIN_DIR/kiro" "$DESKTOP_DIR/kiro.desktop"
  [ -f "$HOME_DIR/.config/kiro-flags.conf" ] && set_owner "$HOME_DIR/.config/kiro-flags.conf"

  ok "Kiro IDE instalado (version: $(get_installed_version))"
}

do_update() {
  [ ! -d "$INSTALL_DIR" ] && die "Kiro no esta instalado"

  local current_ver
  current_ver=$(get_installed_version)
  info "Version instalada: ${current_ver:-desconocida}"

  info "Verificando actualizaciones..."
  fetch_metadata || { warn "No se pudo verificar — intenta mas tarde"; return 1; }

  if [ -n "$current_ver" ] && [ "$current_ver" = "$REMOTE_VERSION" ]; then
    ok "Ya tienes la ultima version ($current_ver)"
    return 0
  fi

  if [ -n "$REMOTE_VERSION" ]; then
    info "Actualizacion disponible: $current_ver → $REMOTE_VERSION"
  else
    warn "No se pudo determinar version remota — reinstalando por seguridad"
  fi

  read -rp "  Actualizar ahora? [s/N]: " CONFIRM
  [[ "$CONFIRM" == "s" ]] || return 0

  do_install
}

do_remove() {
  if [ ! -d "$INSTALL_DIR" ] && [ ! -f "$BIN_DIR/kiro" ]; then
    warn "Kiro no esta instalado"
    return 0
  fi

  echo ""
  echo "  Se eliminara:"
  [ -d "$INSTALL_DIR" ] && echo "    $INSTALL_DIR"
  [ -f "$BIN_DIR/kiro" ] && echo "    $BIN_DIR/kiro"
  [ -f "$DESKTOP_DIR/kiro.desktop" ] && echo "    $DESKTOP_DIR/kiro.desktop"
  echo ""
  echo "  Datos de usuario (config, extensiones):"
  echo "    $DATA_DIR"
  echo ""
  read -rp "  Eliminar tambien datos de usuario? [s/N]: " CLEAN_DATA
  read -rp "  Confirmar eliminacion? [s/N]: " CONFIRM
  [[ "$CONFIRM" == "s" ]] || return 0

  info "Eliminando Kiro..."
  rm -rf "$INSTALL_DIR"
  rm -f "$BIN_DIR/kiro"
  rm -f "$DESKTOP_DIR/kiro.desktop"

  if [[ "$CLEAN_DATA" == "s" ]]; then
    rm -rf "$DATA_DIR"
    rm -rf "$HOME_DIR/.kiro"
    ok "Datos de usuario eliminados"
  fi

  ok "Kiro eliminado"
}

do_status() {
  echo ""
  if [ -d "$INSTALL_DIR" ]; then
    local ver
    ver=$(get_installed_version)
    ok "Kiro instalado"
    echo "  Version:     ${ver:-desconocida}"
    echo "  Ubicacion:   $INSTALL_DIR"
    echo "  Ejecutable:  $BIN_DIR/kiro"
    echo "  Datos:       $DATA_DIR"
    echo "  Disco:       $(du -sh "$INSTALL_DIR" 2>/dev/null | cut -f1)"
    [ -d "$DATA_DIR" ] && echo "  Config:      $(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)"
  else
    warn "Kiro no esta instalado"
  fi
  echo ""
}

# ══════════════════════════════════════════
# Menu / CLI
# ══════════════════════════════════════════

show_help() {
  cat <<'MSG'

  Kiro IDE — Gestor de instalacion

  Uso: bash kiro.sh <accion>

  Acciones:
    install     Instalar o reinstalar (verifica dependencias)
    update      Verificar y aplicar actualizacion
    remove      Eliminar (binarios + opcionalmente datos)
    status      Version, ubicacion, uso de disco
    deps        Verificar dependencias del sistema
    help        Mostrar esta ayuda

  Sin argumentos abre el menu interactivo.

  Ubicaciones:
    Binarios:   ~/.local/share/kiro/
    Ejecutable: ~/.local/bin/kiro
    Config:     ~/.config/Kiro/
    Desktop:    ~/.local/share/applications/kiro.desktop

  Origen: prod.download.desktop.kiro.dev (AWS oficial, HTTPS)
  Dependencias: todas de repos oficiales de Arch (extra)

MSG
}

case "${1:-}" in
  install) do_install ;;
  update)  do_update ;;
  remove)  do_remove ;;
  status)  do_status ;;
  deps)    check_deps ;;
  help|-h|--help) show_help ;;
  "")
    echo ""
    info "Kiro IDE — Gestor"
    do_status
    echo "  1) Instalar / Reinstalar"
    echo "  2) Verificar actualizaciones"
    echo "  3) Eliminar"
    echo "  4) Verificar dependencias"
    echo "  5) Salir"
    echo ""
    read -rp "  Opcion [1-5]: " CHOICE
    case "$CHOICE" in
      1) do_install ;;
      2) do_update ;;
      3) do_remove ;;
      4) check_deps ;;
      5) exit 0 ;;
      *) die "Opcion invalida" ;;
    esac
    ;;
  *) show_help; exit 1 ;;
esac
