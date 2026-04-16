#!/bin/bash
# Flatpak — Instalacion, hardening y optimizacion
# Apps GUI pesadas aisladas del sistema (sandbox)
# Solo Flathub verified — apps verificadas por sus desarrolladores
#
# Archivos creados:
#   /etc/flatpak/  overrides globales (permisos restrictivos)
#
# Ejecutar despues de cualquier UI (tiling/plasma/gnome)
set -e

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' C='\033[1;36m' N='\033[0m'
info()  { printf "${C}:: %s${N}\n" "$*"; }
ok()    { printf "${G}✓  %s${N}\n" "$*"; }
warn()  { printf "${Y}⚠  %s${N}\n" "$*"; }
die()   { printf "${R}✗  %s${N}\n" "$*"; exit 1; }

[[ $EUID -eq 0 ]] || die "Ejecuta como root"

USERNAME=$(getent passwd 1000 | cut -d: -f1)
[ -z "$USERNAME" ] && die "No se encontro usuario UID 1000"
HOME_DIR="/home/$USERNAME"

# ── Instalar Flatpak ──
if command -v flatpak &>/dev/null; then
  ok "Flatpak ya instalado"
else
  info "Instalando flatpak..."
  pacman -S --needed --noconfirm flatpak
  ok "Flatpak instalado"
fi

# ── Flathub: solo subset verified ──
# Flathub verified = apps cuya identidad fue verificada por Flathub
# Excluye apps subidas sin verificacion de identidad del desarrollador
if flatpak remotes --columns=name | grep -q flathub; then
  info "Flathub ya configurado, aplicando subset verified..."
  flatpak remote-modify --subset=verified flathub
else
  info "Agregando Flathub (verified)..."
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak remote-modify --subset=verified flathub
fi
ok "Flathub configurado (solo apps verificadas)"

# ── Permisos globales restrictivos ──
# Por defecto muchas apps piden acceso completo al home, red, etc.
# Restringimos globalmente y cada app pide lo que necesita via portales
info "Aplicando permisos restrictivos globales..."

# Sin acceso al home completo (apps usan portales xdg para archivos)
flatpak override --nofilesystem=home
# Sin acceso al host filesystem
flatpak override --nofilesystem=host
# Sin acceso a dispositivos por defecto
flatpak override --nodevice=all
# Permitir solo GPU (necesario para rendering)
flatpak override --device=dri

ok "Permisos globales aplicados"

# ── Tema dark (si hay GTK config) ──
if [ -d "$HOME_DIR/.config/gtk-4.0" ] || [ -d "$HOME_DIR/.config/gtk-3.0" ]; then
  flatpak override --filesystem=xdg-config/gtk-3.0:ro
  flatpak override --filesystem=xdg-config/gtk-4.0:ro
  flatpak override --env=GTK_THEME=Adwaita-dark
  ok "Tema dark aplicado a Flatpaks"
fi

# ── Limpiar datos huerfanos ──
# Eliminar runtimes y refs sin app asociada
flatpak uninstall --unused --noninteractive 2>/dev/null || true

echo ""
ok "Flatpak configurado"
echo ""
info "Resumen:"
echo "  Repo:        Flathub (solo apps verificadas)"
echo "  Permisos:    restrictivos (sin home, sin host, solo GPU)"
echo "  Tema:        dark (hereda GTK del host)"
echo ""
echo "  Buscar:      flatpak search nombre"
echo "  Instalar:    flatpak install flathub org.ejemplo.App"
echo "  Ejecutar:    flatpak run org.ejemplo.App"
echo "  Permisos:    flatpak info --show-permissions org.ejemplo.App"
echo "  Actualizar:  flatpak update"
echo "  Eliminar:    flatpak uninstall org.ejemplo.App"
echo "  Limpiar:     flatpak uninstall --unused"
