sudo pacman -S sddm plasma-desktop kwin qt6-wayland systemsettings xdg-desktop-portal-kde bluedevil dolphin konsole plasma-nm plasma-pa sddm-kcm kde-gtk-config colord-kde plasma-disks kinfocenter kscreenlocker ocean-sound-theme breeze-gtk kscreen breeze-icons ark gwenview okular kcalc haruna kwrite vulkan-mesa-layers fwupd kdegraphics-thumbnailers ffmpegthumbs dolphin-plugins kpipewire

# 1. SDDM Wayland nativo
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/10-wayland.conf > /dev/null <<'EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts
EOF

# 2. Deshabilitar Baloo globalmente
sudo mkdir -p /etc/xdg
sudo tee /etc/xdg/baloofilerc > /dev/null <<'EOF'
[Basic Settings]
Indexing-Enabled=false
EOF

# 3. Detectar usuario
export USERNAME=$(getent passwd 1000 | cut -d: -f1)

cat > /home/$USERNAME/kde-setup.sh <<'SCRIPT'
#!/bin/bash
CONF_DIR="$HOME/.config"
mkdir -p "$CONF_DIR"

mkdir -p "$CONF_DIR/pipewire/pipewire.conf.d"
cat > "$CONF_DIR/pipewire/pipewire.conf.d/99-desktop.conf" <<EOF
context.properties = {
    default.clock.rate = 48000
}
EOF

# Deshabilitar Discover Update
mkdir -p "$CONF_DIR/systemd/user"
ln -sf /dev/null "$CONF_DIR/systemd/user/plasma-discover-update.service"
ln -sf /dev/null "$CONF_DIR/systemd/user/plasma-discover-update.timer"

# Deshabilitar DrKonqi
mkdir -p "$CONF_DIR/autostart"
echo -e "[Desktop Entry]\nHidden=true" > "$CONF_DIR/autostart/org.kde.drkonqi.desktop"

# Kdeglobals
cat >> "$CONF_DIR/kdeglobals" <<EOF
[KDE]
AnimationDurationFactor=0
[KCrash]
AutoRestart=false
[General]
font=Inter,10,-1,5,50,0,0,0,0,0
fixed=JetBrains Mono,11,-1,5,50,0,0,0,0,0
smallestReadableFont=Inter,8,-1,5,50,0,0,0,0,0
toolBarFont=Inter,9,-1,5,50,0,0,0,0,0
menuFont=Inter,10,-1,5,50,0,0,0,0,0
activeFont=Inter,10,-1,5,63,0,0,0,0,0
EOF

# Dolphin
cat > "$CONF_DIR/dolphinrc" <<EOF
[General]
ShowSpaceInfo=false
RememberOpenedTabs=false
EOF

# Okular
cat > "$CONF_DIR/okularpartrc" <<EOF
[Core Performance]
MemoryLevel=Low
EOF

# Baloo usuario
balooctl6 disable 2>/dev/null || true

# --- Color scheme OLED-safe para KDE ---
mkdir -p "$HOME/.local/share/color-schemes"
cat > "$HOME/.local/share/color-schemes/OLEDSafe.colors" <<'COLORSCHEME'
[ColorEffects:Disabled]
Color=56,56,56
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=1
IntensityAmount=0.1
IntensityEffect=2

[ColorEffects:Inactive]
ChangeSelectionColor=true
Color=40,40,40
ColorAmount=0.025
ColorEffect=2
ContrastAmount=0.1
ContrastEffect=2
Enable=false
IntensityAmount=0
IntensityEffect=0

[Colors:Button]
BackgroundAlternate=10,10,10
BackgroundNormal=15,15,15
DecorationFocus=74,128,176
DecorationHover=90,144,192
ForegroundActive=74,128,176
ForegroundInactive=100,100,100
ForegroundLink=74,128,176
ForegroundNegative=160,64,64
ForegroundNeutral=160,136,64
ForegroundNormal=153,153,153
ForegroundPositive=90,138,74
ForegroundVisited=154,106,154

[Colors:Selection]
BackgroundAlternate=50,80,120
BackgroundNormal=74,128,176
DecorationFocus=74,128,176
DecorationHover=90,144,192
ForegroundActive=176,176,176
ForegroundInactive=130,130,130
ForegroundLink=176,176,176
ForegroundNegative=160,64,64
ForegroundNeutral=160,136,64
ForegroundNormal=176,176,176
ForegroundPositive=90,138,74
ForegroundVisited=154,106,154

[Colors:Tooltip]
BackgroundAlternate=5,5,5
BackgroundNormal=10,10,10
DecorationFocus=74,128,176
DecorationHover=90,144,192
ForegroundActive=74,128,176
ForegroundInactive=100,100,100
ForegroundLink=74,128,176
ForegroundNegative=160,64,64
ForegroundNeutral=160,136,64
ForegroundNormal=153,153,153
ForegroundPositive=90,138,74
ForegroundVisited=154,106,154

[Colors:View]
BackgroundAlternate=5,5,5
BackgroundNormal=0,0,0
DecorationFocus=74,128,176
DecorationHover=90,144,192
ForegroundActive=74,128,176
ForegroundInactive=100,100,100
ForegroundLink=74,128,176
ForegroundNegative=160,64,64
ForegroundNeutral=160,136,64
ForegroundNormal=153,153,153
ForegroundPositive=90,138,74
ForegroundVisited=154,106,154

[Colors:Window]
BackgroundAlternate=5,5,5
BackgroundNormal=0,0,0
DecorationFocus=74,128,176
DecorationHover=90,144,192
ForegroundActive=74,128,176
ForegroundInactive=100,100,100
ForegroundLink=74,128,176
ForegroundNegative=160,64,64
ForegroundNeutral=160,136,64
ForegroundNormal=153,153,153
ForegroundPositive=90,138,74
ForegroundVisited=154,106,154

[Colors:Header]
BackgroundAlternate=5,5,5
BackgroundNormal=10,10,10
DecorationFocus=74,128,176
DecorationHover=90,144,192
ForegroundActive=74,128,176
ForegroundInactive=100,100,100
ForegroundLink=74,128,176
ForegroundNegative=160,64,64
ForegroundNeutral=160,136,64
ForegroundNormal=153,153,153
ForegroundPositive=90,138,74
ForegroundVisited=154,106,154

[General]
ColorScheme=OLEDSafe
Name=OLED Safe
shadeSortColumn=true

[WM]
activeBackground=0,0,0
activeBlend=0,0,0
activeForeground=153,153,153
inactiveBackground=0,0,0
inactiveBlend=0,0,0
inactiveForeground=80,80,80
COLORSCHEME

# Aplicar color scheme
plasma-apply-colorscheme OLEDSafe 2>/dev/null || true

# --- Script adaptativo OLED para KDE ---
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/kde-oled-adapt" <<'KDEADAPT'
#!/bin/bash
# Adapta colores de texto KDE segun brillo de pantalla
# Usa udev para detectar cambios reales, no polling

PREV_LEVEL=""

update_colors() {
  local BRIGHT LVL HALF
  BRIGHT=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')
  [ -z "$BRIGHT" ] && return

  if [ "$BRIGHT" -le 5 ]; then LVL="176"
  elif [ "$BRIGHT" -le 15 ]; then LVL="153"
  elif [ "$BRIGHT" -le 30 ]; then LVL="128"
  elif [ "$BRIGHT" -le 50 ]; then LVL="106"
  elif [ "$BRIGHT" -le 75 ]; then LVL="85"
  else LVL="69"; fi

  [ "$LVL" = "$PREV_LEVEL" ] && return
  PREV_LEVEL="$LVL"
  HALF=$(( LVL / 2 ))

  kwriteconfig6 --file kdeglobals --group "Colors:View" --key "ForegroundNormal" "$LVL,$LVL,$LVL"
  kwriteconfig6 --file kdeglobals --group "Colors:Window" --key "ForegroundNormal" "$LVL,$LVL,$LVL"
  kwriteconfig6 --file kdeglobals --group "Colors:Button" --key "ForegroundNormal" "$LVL,$LVL,$LVL"
  kwriteconfig6 --file kdeglobals --group "Colors:View" --key "ForegroundInactive" "$HALF,$HALF,$HALF"
  kwriteconfig6 --file kdeglobals --group "Colors:Window" --key "ForegroundInactive" "$HALF,$HALF,$HALF"
  kwriteconfig6 --file kdeglobals --group "WM" --key "activeForeground" "$LVL,$LVL,$LVL"
  kwriteconfig6 --file kdeglobals --group "WM" --key "inactiveForeground" "$HALF,$HALF,$HALF"

  qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null
}

# Aplicar al inicio
update_colors

# Monitorear cambios de brillo via udev
stdbuf -oL udevadm monitor --subsystem-match=backlight --property 2>/dev/null | while read -r line; do
  case "$line" in
    *"change"*) update_colors ;;
  esac
done &

# Fallback: revisar cada 30s
while true; do
  sleep 30
  update_colors
done
KDEADAPT
chmod +x "$HOME/.local/bin/kde-oled-adapt"

# Autostart del adaptativo
mkdir -p "$CONF_DIR/autostart"
cat > "$CONF_DIR/autostart/kde-oled-adapt.desktop" <<'AUTOSTART'
[Desktop Entry]
Type=Application
Name=KDE OLED Adaptive Colors
Exec=kde-oled-adapt
X-KDE-autostart-phase=2
AUTOSTART

echo "Optimización aplicada. Reinicia para ver los cambios."
SCRIPT

chmod +x /home/$USERNAME/kde-setup.sh
chown $USERNAME:users /home/$USERNAME/kde-setup.sh

sudo systemctl enable sddm.service

echo ""
echo "=== Plasma instalado ==="
echo ""
echo "Despues de reiniciar e iniciar sesion, ejecuta:"
echo "  bash ~/kde-setup.sh"
echo ""
echo "Esto aplica: tema OLED, fuentes, Pipewire, Baloo off, colores adaptativos."
echo "Reinicia para iniciar sesion con SDDM."
