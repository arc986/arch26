#!/bin/bash

# =============================================================================
# Instalador de Visual Studio Code para Arch Linux
# Fuente: .tar.gz oficial de Microsoft (sin AUR, sin dpkg)
# =============================================================================

INSTALL_DIR="/opt/vscode"
BIN_LINK="/usr/local/bin/code"
DESKTOP_FILE="/usr/share/applications/code.desktop"
ICON_DIR="/usr/share/icons/hicolor/512x512/apps"
TEMP_DIR="/tmp/vscode-install"

# Detectar arquitectura del sistema
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  VSCODE_ARCH="linux-x64"   ;;
    aarch64) VSCODE_ARCH="linux-arm64"  ;;
    armv7l)  VSCODE_ARCH="linux-armhf"  ;;
    *) echo "Error: Arquitectura no soportada: $ARCH"; exit 1 ;;
esac

API_URL="https://update.code.visualstudio.com/api/update/${VSCODE_ARCH}/stable/latest"
DOWNLOAD_URL="https://update.code.visualstudio.com/latest/${VSCODE_ARCH}/stable"

# -----------------------------------------------------------------------------

error() {
    echo "Error: $1"
    exit 1
}

require_superuser() {
    if [ "$EUID" -ne 0 ]; then
        error "Por favor, ejecuta este script como superusuario (sudo)."
    fi
}

install_dependencies() {
    echo "Verificando dependencias necesarias..."
    if ! pacman -Q curl &>/dev/null; then
        echo "Instalando curl..."
        pacman -S --needed --noconfirm curl || error "No se pudo instalar curl."
    else
        echo "curl ya está instalado."
    fi
}

get_installed_version() {
    if [ -f "$INSTALL_DIR/bin/code" ]; then
        "$INSTALL_DIR/bin/code" --version 2>/dev/null | head -n 1
    fi
}

get_latest_version() {
    curl -sf "$API_URL" | grep -oP '"name"\s*:\s*"\K[^"]+' | head -n 1
}

install_vscode() {
    echo "Consultando la última versión de VS Code para: $VSCODE_ARCH..."
    local latest_version
    latest_version=$(get_latest_version) || error "No se pudo consultar la versión más reciente."
    [ -z "$latest_version" ] && error "No se pudo obtener la versión desde la API de Microsoft."

    local current_version
    current_version=$(get_installed_version)

    if [ "$current_version" = "$latest_version" ]; then
        echo "VS Code ya está actualizado (versión $current_version). No se necesita nada."
        return
    fi

    if [ -n "$current_version" ]; then
        echo "Actualizando VS Code: $current_version → $latest_version"
    else
        echo "Instalando VS Code versión $latest_version..."
    fi

    echo "Preparando directorio temporal..."
    mkdir -p "$TEMP_DIR"

    local tarball="$TEMP_DIR/vscode.tar.gz"
    echo "Descargando VS Code..."
    curl -L --progress-bar "$DOWNLOAD_URL" -o "$tarball" \
        || error "No se pudo descargar VS Code desde Microsoft."

    echo "Extrayendo archivos en $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    tar -xzf "$tarball" -C "$INSTALL_DIR" --strip-components=1 \
        || error "No se pudo extraer el paquete."

    echo "Creando enlace simbólico: $BIN_LINK → $INSTALL_DIR/bin/code"
    ln -sf "$INSTALL_DIR/bin/code" "$BIN_LINK"

    echo "Instalando ícono del sistema..."
    mkdir -p "$ICON_DIR"
    local icon_src="$INSTALL_DIR/resources/app/resources/linux/code.png"
    if [ -f "$icon_src" ]; then
        cp "$icon_src" "$ICON_DIR/code.png"
        gtk-update-icon-cache -f -t /usr/share/icons/hicolor &>/dev/null || true
    fi

    echo "Creando acceso directo en el menú de aplicaciones..."
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Visual Studio Code
Comment=Code Editing. Redefined.
GenericName=Text Editor
Exec=$BIN_LINK --unity-launch %F
Icon=code
Type=Application
StartupNotify=false
StartupWMClass=Code
Categories=TextEditor;Development;IDE;
MimeType=text/plain;inode/directory;application/x-code-workspace;
Actions=new-empty-window;
Keywords=vscode;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=$BIN_LINK --new-window %F
Icon=code
EOF

    echo "Limpiando archivos temporales..."
    rm -rf "$TEMP_DIR"

    echo ""
    echo "✔ VS Code $latest_version instalado correctamente."
    echo "  Ejecuta con: code"
}

# -----------------------------------------------------------------------------

require_superuser
install_dependencies
install_vscode