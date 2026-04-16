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
set -e

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' C='\033[1;36m' N='\033[0m'
info()  { printf "${C}:: %s${N}\n" "$*"; }
ok()    { printf "${G}✓  %s${N}\n" "$*"; }
warn()  { printf "${Y}⚠  %s${N}\n" "$*"; }
die()   { printf "${R}✗  %s${N}\n" "$*"; exit 1; }

USERNAME=$(getent passwd 1000 | cut -d: -f1)
[ -z "$USERNAME" ] && die "No se encontro usuario UID 1000"
HOME_DIR="/home/$USERNAME"

INSTALL_DIR="$HOME_DIR/.local/share/kiro"
BIN_DIR="$HOME_DIR/.local/bin"
DESKTOP_DIR="$HOME_DIR/.local/share/applications"
DATA_DIR="$HOME_DIR/.config/Kiro"
DOWNLOAD_URL="https://prod.download.desktop.kiro.dev/releases/stable/linux-x64/kiro-ide-stable-linux-x64.tar.gz"
VERSION_FILE="$INSTALL_DIR/.kiro-version"

# ── Dependencias (Electron/VS Code fork) ──
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
)

# ══════════════════════════════════════════
# Funciones
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
    read -rp "  Instalar ahora? [s/N]: " INSTALL_DEPS
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
    python3 -c "import json;print(json.load(open('$INSTALL_DIR/resources/app/package.json'))['version'])" 2>/dev/null || echo "desconocida"
  else
    echo ""
  fi
}

get_remote_version() {
  # HEAD request para obtener el ETag o Last-Modified como indicador de version
  local headers
  headers=$(curl --proto '=https' --tlsv1.2 -sfI "$DOWNLOAD_URL" 2>/dev/null)
  echo "$headers" | grep -i 'etag' | tr -d '"' | awk '{print $2}' | tr -d '\r'
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

  local TMP_DIR
  TMP_DIR=$(sudo -u "$USERNAME" mktemp -d)

  info "Descargando Kiro IDE desde AWS..."
  sudo -u "$USERNAME" curl --proto '=https' --tlsv1.2 -fSL \
    --connect-timeout 15 --retry 3 \
    "$DOWNLOAD_URL" -o "$TMP_DIR/kiro.tar.gz"
  ok "Descarga completada"

  # Limpiar instalacion anterior si existe
  [ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"

  info "Instalando en $INSTALL_DIR..."
  sudo -u "$USERNAME" mkdir -p "$INSTALL_DIR"
  sudo -u "$USERNAME" tar -xzf "$TMP_DIR/kiro.tar.gz" -C "$INSTALL_DIR" --strip-components=1

  # Guardar version
  if [ -f "$INSTALL_DIR/resources/app/package.json" ]; then
    python3 -c "import json;print(json.load(open('$INSTALL_DIR/resources/app/package.json'))['version'])" > "$VERSION_FILE" 2>/dev/null
  fi

  # Guardar ETag para comparar en updates
  curl --proto '=https' --tlsv1.2 -sfI "$DOWNLOAD_URL" 2>/dev/null | \
    grep -i 'etag' > "$INSTALL_DIR/.kiro-etag" 2>/dev/null || true

  rm -rf "$TMP_DIR"

  # Symlink
  sudo -u "$USERNAME" mkdir -p "$BIN_DIR"
  ln -sf "$INSTALL_DIR/kiro" "$BIN_DIR/kiro"

  # Desktop entry
  sudo -u "$USERNAME" mkdir -p "$DESKTOP_DIR"
  # Buscar icono en ubicaciones conocidas
  local ICON="$INSTALL_DIR/resources/app/resources/linux/code.png"
  [ ! -f "$ICON" ] && ICON="kiro"

  cat > "$DESKTOP_DIR/kiro.desktop" <<EOF
[Desktop Entry]
Name=Kiro
Comment=Agentic AI IDE by AWS
Exec=$INSTALL_DIR/kiro --ozone-platform-hint=auto %F
Icon=$ICON
Terminal=false
Type=Application
MimeType=text/plain;inode/directory;
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=kiro
EOF
  chown "$USERNAME:users" "$DESKTOP_DIR/kiro.desktop"

  chown -R "$USERNAME:users" "$INSTALL_DIR" "$BIN_DIR/kiro"

  ok "Kiro IDE instalado (version: $(get_installed_version))"
}

do_update() {
  [ ! -d "$INSTALL_DIR" ] && die "Kiro no esta instalado"

  local current_ver
  current_ver=$(get_installed_version)
  info "Version instalada: $current_ver"

  info "Verificando actualizaciones..."
  local remote_etag local_etag
  remote_etag=$(get_remote_version)
  local_etag=""
  [ -f "$INSTALL_DIR/.kiro-etag" ] && local_etag=$(grep -i 'etag' "$INSTALL_DIR/.kiro-etag" | tr -d '"' | awk '{print $2}' | tr -d '\r')

  if [ -n "$remote_etag" ] && [ "$remote_etag" = "$local_etag" ]; then
    ok "Ya tienes la ultima version"
    return 0
  fi

  if [ -n "$remote_etag" ]; then
    info "Actualizacion disponible"
  else
    warn "No se pudo verificar version remota — reinstalando por seguridad"
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
