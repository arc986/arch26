#!/bin/bash
# Arch Linux — GNOME 50 optimizado
# OLED safe, minimal, post archlinux2.md base install
set -e

USERNAME=$(getent passwd 1000 | cut -d: -f1)
HOME_DIR="/home/$USERNAME"
CFG="$HOME_DIR/.config"

# --- Paquetes: GNOME minimal (sin bloat) ---
sudo pacman -S --needed \
  gdm \
  gnome-shell \
  gnome-control-center \
  gnome-keyring \
  gnome-text-editor \
  gnome-console \
  gnome-calculator \
  gnome-disk-utility \
  nautilus \
  file-roller \
  evince \
  eog \
  xdg-desktop-portal-gnome \
  xdg-user-dirs-gtk \
  gvfs \
  gvfs-mtp \
  papirus-icon-theme

# --- Crear directorios ---
sudo -u "$USERNAME" xdg-user-dirs-update

# --- GDM Wayland (ya es default en GNOME 50, reforzar) ---
sudo mkdir -p /etc/gdm
if [ -f /etc/gdm/custom.conf ]; then
  sudo sed -i 's/^#\?WaylandEnable=.*/WaylandEnable=true/' /etc/gdm/custom.conf
else
  sudo tee /etc/gdm/custom.conf > /dev/null <<'EOF'
[daemon]
WaylandEnable=true
EOF
fi

# --- dconf: configuracion global OLED safe ---
sudo mkdir -p /etc/dconf/profile /etc/dconf/db/local.d

sudo tee /etc/dconf/profile/user > /dev/null <<'EOF'
user-db:user
system-db:local
EOF

sudo tee /etc/dconf/db/local.d/00-oled-defaults > /dev/null <<'DCONF'
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'
icon-theme='Papirus-Dark'
font-name='Inter 10'
monospace-font-name='JetBrains Mono 11'
document-font-name='Inter 10'
cursor-theme='Adwaita'
enable-animations=true
clock-format='12h'
clock-show-weekday=true

[org/gnome/desktop/wm/preferences]
titlebar-font='Inter Bold 10'
button-layout='close,minimize,maximize:'

[org/gnome/desktop/peripherals/touchpad]
tap-to-click=true
natural-scroll=true
two-finger-scrolling-enabled=true
disable-while-typing=true
speed=0.1

[org/gnome/desktop/peripherals/mouse]
natural-scroll=true

[org/gnome/desktop/session]
idle-delay=uint32 300

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-battery-timeout=600
sleep-inactive-ac-timeout=1800
power-button-action='interactive'

[org/gnome/desktop/notifications]
show-in-lock-screen=false

[org/gnome/desktop/privacy]
remove-old-trash-files=true
remove-old-temp-files=true
old-files-age=uint32 7

[org/gnome/system/location]
enabled=false

[org/gnome/desktop/search-providers]
disable-external=true

[org/gnome/desktop/background]
primary-color='#000000'
secondary-color='#000000'
color-shading-type='solid'

[org/gnome/desktop/screensaver]
primary-color='#000000'
secondary-color='#000000'
color-shading-type='solid'

[org/gnome/shell]
disable-user-extensions=false

[org/gnome/mutter]
experimental-features=['variable-refresh-rate']

[org/gnome/Console]
font-scale=1.0
theme='auto'
DCONF

sudo dconf update

# --- Desactivar tracker/localsearch (indexador de archivos) ---
# Equivalente a Baloo off en KDE. Reduce CPU idle 12-34%, extiende bateria.
# Renombrado a localsearch en GNOME 47+, pero los services mantienen nombre tracker.
sudo -u "$USERNAME" systemctl --user mask \
  tracker-miner-fs-3.service \
  tracker-extract-3.service \
  tracker-miner-fs-control-3.service \
  tracker-writeback-3.service 2>/dev/null || true

# --- Desactivar evolution-data-server (calendario/contactos en background) ---
# Solo necesario si usas GNOME Calendar o contactos integrados.
# Sin esto, el reloj del panel no muestra eventos pero ahorra wakeups.
sudo -u "$USERNAME" systemctl --user mask \
  evolution-addressbook-factory.service \
  evolution-calendar-factory.service \
  evolution-source-registry.service 2>/dev/null || true

# --- Script de usuario ---
cat > "$HOME_DIR/gnome-setup.sh" <<'SCRIPT'
#!/bin/bash
CONF_DIR="$HOME/.config"
mkdir -p "$CONF_DIR"

# Pipewire: solo fijar rate, quantum default es optimo para desktop
mkdir -p "$CONF_DIR/pipewire/pipewire.conf.d"
cat > "$CONF_DIR/pipewire/pipewire.conf.d/99-desktop.conf" <<EOF
context.properties = {
    default.clock.rate = 48000
}
EOF

# GTK CSS OLED override (negro puro en fondos)
mkdir -p "$CONF_DIR/gtk-4.0"
cat > "$CONF_DIR/gtk-4.0/gtk.css" <<'GTKCSS'
/* OLED: fondo negro puro = pixeles apagados */
window, .background {
  background-color: #000000;
}
headerbar, .titlebar {
  background-color: #0a0a0a;
  color: #999999;
}
tooltip {
  background-color: #0a0a0a;
  color: #999999;
  border: 1px solid #1a1a1a;
}
GTKCSS

# Desactivar GNOME Online Accounts daemon (si no usas cuentas Google/Microsoft)
systemctl --user mask goa-daemon.service 2>/dev/null || true

# --- OLED adaptive: ajusta brillo de texto via dconf segun brillo de pantalla ---
# Nota: GTK4/libadwaita no relee gtk.css en caliente.
# Usamos dconf para ajustar el cursor-size como indicador visual
# y el CSS se aplica al inicio de sesion.
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/gnome-oled-adapt" <<'GNOMEADAPT'
#!/bin/bash
# Ajusta CSS de GTK4 segun brillo — aplica a apps nuevas que se abran
# Para apps ya abiertas, el cambio se ve al reiniciar la app

PREV_LEVEL=""

update_css() {
  local BRIGHT LVL
  BRIGHT=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')
  [ -z "$BRIGHT" ] && return

  if [ "$BRIGHT" -le 5 ]; then LVL="b0"
  elif [ "$BRIGHT" -le 15 ]; then LVL="99"
  elif [ "$BRIGHT" -le 30 ]; then LVL="80"
  elif [ "$BRIGHT" -le 50 ]; then LVL="6a"
  elif [ "$BRIGHT" -le 75 ]; then LVL="55"
  else LVL="45"; fi

  [ "$LVL" = "$PREV_LEVEL" ] && return
  PREV_LEVEL="$LVL"

  cat > "$HOME/.config/gtk-4.0/gtk.css" <<CSSEOF
window, .background {
  background-color: #000000;
}
headerbar, .titlebar {
  background-color: #0a0a0a;
  color: #${LVL}${LVL}${LVL};
}
tooltip {
  background-color: #0a0a0a;
  color: #${LVL}${LVL}${LVL};
  border: 1px solid #1a1a1a;
}
CSSEOF
}

# Aplicar al inicio
update_css

# Monitorear cambios de brillo via udev
stdbuf -oL udevadm monitor --subsystem-match=backlight --property 2>/dev/null | while read -r line; do
  case "$line" in
    *"change"*) update_css ;;
  esac
done &

# Fallback cada 30s
while true; do
  sleep 30
  update_css
done
GNOMEADAPT
chmod +x "$HOME/.local/bin/gnome-oled-adapt"

# Autostart
mkdir -p "$CONF_DIR/autostart"
cat > "$CONF_DIR/autostart/gnome-oled-adapt.desktop" <<'AUTOSTART'
[Desktop Entry]
Type=Application
Name=GNOME OLED Adaptive
Exec=gnome-oled-adapt
X-GNOME-Autostart-Phase=Applications
AUTOSTART

echo "Optimización GNOME aplicada. Reinicia sesión."
SCRIPT

chmod +x "$HOME_DIR/gnome-setup.sh"
chown "$USERNAME:users" "$HOME_DIR/gnome-setup.sh"

sudo systemctl enable gdm.service

echo ""
echo "=== GNOME 50 instalado ==="
echo "Ejecutar ~/gnome-setup.sh después del primer login"
echo "Reinicia para iniciar sesión."
