#!/bin/bash

# plasma.sh — Plasma 6 + OLED + Rendimiento
# Sistema: Arch Linux, Plasma 6 (KDE6), Wayland, SDDM
#
# Sección 1: root  → instala y configura a nivel sistema
# Sección 2: usuario → kde-setup.sh (ejecutar tras primer login)

# ─────────────────────────────────────────────────────────────────────────────
# 1. PAQUETES
# ─────────────────────────────────────────────────────────────────────────────
# Nota: los siguientes ya los instala install.sh (pacstrap) y no se repiten aquí:
# pipewire wireplumber pipewire-pulse bluez mesa vulkan-radeon wayland
# nushell inter-font ttf-jetbrains-mono htop git neovim
# power-profiles-daemon upower noto-fonts noto-fonts-emoji
sudo pacman -S --needed --noconfirm \
    sddm plasma-desktop kwin qt6-wayland systemsettings \
    xdg-desktop-portal-kde bluedevil dolphin konsole \
    plasma-nm plasma-pa sddm-kcm kde-gtk-config colord-kde \
    plasma-disks kinfocenter kscreenlocker breeze-gtk kscreen \
    breeze-icons ark gwenview okular kcalc haruna kwrite \
    vulkan-mesa-layers fwupd kdegraphics-thumbnailers \
    ffmpegthumbs dolphin-plugins kpipewire powerdevil \
    brightnessctl plasma-systemmonitor

# ─────────────────────────────────────────────────────────────────────────────
# 2. SDDM — Wayland nativo
# ─────────────────────────────────────────────────────────────────────────────
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/10-wayland.conf > /dev/null << 'EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts

[Theme]
Current=breeze
EOF

# ─────────────────────────────────────────────────────────────────────────────
# 3. BALOO global — deshabilitar indexación en todo el sistema
# ─────────────────────────────────────────────────────────────────────────────
sudo mkdir -p /etc/xdg
sudo tee /etc/xdg/baloofilerc > /dev/null << 'EOF'
[Basic Settings]
Indexing-Enabled=false
EOF

# ─────────────────────────────────────────────────────────────────────────────
# 4. Detectar usuario (UID 1000)
# ─────────────────────────────────────────────────────────────────────────────
USERNAME=$(getent passwd 1000 | cut -d: -f1)

# ─────────────────────────────────────────────────────────────────────────────
# 5. kde-setup.sh — configuración de usuario (ejecutar tras primer login)
# ─────────────────────────────────────────────────────────────────────────────
cat > /home/$USERNAME/kde-setup.sh << 'SCRIPT'
#!/bin/bash

CONF_DIR="$HOME/.config"
mkdir -p "$CONF_DIR"

echo "Aplicando optimizaciones KDE OLED..."

# ── PipeWire ─────────────────────────────────────────────────────────────────
# clock.quantum: latencia vs CPU. 1024 = balance. Bajar a 512 si hay dropouts.
mkdir -p "$CONF_DIR/pipewire/pipewire.conf.d"
cat > "$CONF_DIR/pipewire/pipewire.conf.d/99-desktop.conf" << EOF
context.properties = {
    default.clock.rate          = 48000
    default.clock.allowed-rates = [ 44100 48000 96000 ]
    default.clock.quantum       = 1024
    default.clock.min-quantum   = 32
    default.clock.max-quantum   = 8192
    log.level                   = 2
}
EOF

# ── Servicios innecesarios ────────────────────────────────────────────────────
# Discover: gestor de paquetes GUI con pollers en background
mkdir -p "$CONF_DIR/systemd/user"
ln -sf /dev/null "$CONF_DIR/systemd/user/plasma-discover-update.service"
ln -sf /dev/null "$CONF_DIR/systemd/user/plasma-discover-update.timer"
systemctl --user mask plasma-discover-update.service 2>/dev/null || true
systemctl --user mask plasma-discover-update.timer   2>/dev/null || true

# DrKonqi: reporter de crashes (background daemon)
mkdir -p "$CONF_DIR/autostart"
echo -e "[Desktop Entry]\nHidden=true" > "$CONF_DIR/autostart/org.kde.drkonqi.desktop"

# ── kdeglobals ────────────────────────────────────────────────────────────────
# AnimationDurationFactor=0 → elimina todas las animaciones de KDE
cat > "$CONF_DIR/kdeglobals" << EOF
[KDE]
AnimationDurationFactor=0
SingleClick=false

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

# ── KWin ─────────────────────────────────────────────────────────────────────
# Compositor con latencia baja, sin efectos visuales, sin blur
# GLTextureFilter=1 → bilinear (balance calidad/rendimiento), no trilinear
# HiddenPreviews=5  → no genera thumbnails de ventanas ocultas
# WindowsBlockCompositing → apps fullscreen pausan el compositor
cat > "$CONF_DIR/kwinrc" << EOF
[Compositing]
AnimationSpeed=0
Backend=OpenGL
Enabled=true
GLPreferBufferSwap=a
GLTextureFilter=1
HiddenPreviews=5
LatencyPolicy=Low
WindowsBlockCompositing=true

[Effect-blur]
Enabled=false

[Plugins]
blurEnabled=false
contrastEnabled=false
backgroundcontrastEnabled=false
slidingpopupsEnabled=false
fadeEnabled=false
fadedesktopEnabled=false
loginEnabled=false
logoutEnabled=false
scaleEnabled=false
squashEnabled=false
slidebackEnabled=false
zoomEnabled=false
minimizeanimationEnabled=false

[Windows]
BorderSnapZone=10
CenterSnapZone=0
WindowSnapZone=10
EOF

# ── Dolphin ──────────────────────────────────────────────────────────────────
cat > "$CONF_DIR/dolphinrc" << EOF
[General]
ShowSpaceInfo=false
RememberOpenedTabs=false
ShowFullPathInTitlebar=true

[DetailsMode]
PreviewSize=22

[IconsMode]
PreviewSize=48
EOF

# ── Okular ───────────────────────────────────────────────────────────────────
cat > "$CONF_DIR/okularpartrc" << EOF
[Core Performance]
MemoryLevel=Low
EOF

# ── Screen locker — OLED safe ────────────────────────────────────────────────
# Fondo negro puro en la pantalla de bloqueo
cat > "$CONF_DIR/kscreenlockerrc" << EOF
[Greeter]
WallpaperPlugin=org.kde.color

[Greeter][Wallpaper][org.kde.color][General]
Color=#000000
EOF

# ── PowerDevil ────────────────────────────────────────────────────────────────
# Modo preferido: powersave en todos los perfiles (incluyendo AC)
# power-profiles-daemon (instalado en install.sh) gestiona el governor del CPU
# en conjunto con PowerDevil — GovernorProfiles aquí es el fallback si PPD no
# está activo; con PPD corriendo, PowerDevil llama su D-Bus API directamente.
#
# AC:        powersave + pantalla larga (10min) + sin auto-suspend
# Battery:   powersave + dim 60s + suspend 10min
# LowBattery: powersave + dim 30s + suspend 5min + hibernate
cat > "$CONF_DIR/powermanagementprofilesrc" << EOF
[AC][Display]
DimDisplayWhenIdle=true
DimDisplayIdleTimeoutSec=300
TurnOffDisplayIdleTimeoutSec=600
TurnOffDisplayIdleTimeoutWhenLockedSec=60

[AC][Performance]
GovernorProfiles=powersave

[AC][SuspendSession]
idleTime=0
suspendType=0

[Battery][Display]
DimDisplayIdleTimeoutSec=60
DimDisplayWhenIdle=true
TurnOffDisplayIdleTimeoutSec=180
TurnOffDisplayIdleTimeoutWhenLockedSec=30

[Battery][Performance]
GovernorProfiles=powersave

[Battery][SuspendSession]
idleTime=600000
suspendThenHibernate=false
suspendType=1

[LowBattery][Display]
DimDisplayIdleTimeoutSec=30
DimDisplayWhenIdle=true
TurnOffDisplayIdleTimeoutSec=60
TurnOffDisplayIdleTimeoutWhenLockedSec=10

[LowBattery][Performance]
GovernorProfiles=powersave

[LowBattery][SuspendSession]
idleTime=300000
suspendThenHibernate=true
suspendType=1
EOF

# ── Konsole — color scheme OLED ───────────────────────────────────────────────
# Paleta coherente con OLEDSafe: mismos roles semánticos
mkdir -p "$HOME/.local/share/konsole"
cat > "$HOME/.local/share/konsole/OLED.colorscheme" << 'COLORSCHEME'
[Background]
Color=0,0,0

[BackgroundIntense]
Color=10,10,10

[BackgroundFaint]
Color=0,0,0

[Color0]
Color=26,26,26

[Color0Intense]
Color=51,51,51

[Color0Faint]
Color=13,13,13

[Color1]
Color=139,50,50

[Color1Intense]
Color=176,80,80

[Color1Faint]
Color=90,32,32

[Color2]
Color=90,138,74

[Color2Intense]
Color=110,168,94

[Color2Faint]
Color=58,88,47

[Color3]
Color=160,136,64

[Color3Intense]
Color=180,156,84

[Color3Faint]
Color=104,88,41

[Color4]
Color=74,128,176

[Color4Intense]
Color=94,148,196

[Color4Faint]
Color=47,82,112

[Color5]
Color=154,106,154

[Color5Intense]
Color=174,126,174

[Color5Faint]
Color=99,68,99

[Color6]
Color=90,138,120

[Color6Intense]
Color=110,168,140

[Color6Faint]
Color=58,88,77

[Color7]
Color=153,153,153

[Color7Intense]
Color=180,180,180

[Color7Faint]
Color=100,100,100

[Foreground]
Color=153,153,153

[ForegroundIntense]
Color=180,180,180

[ForegroundFaint]
Color=100,100,100

[General]
Blur=false
ColorRandomization=false
Description=OLED Safe
Opacity=1
Wallpaper=
COLORSCHEME

# Konsole — perfil OLED
# BlinkingCursorEnabled=false → cursor sólido (OLED burn-in safe)
cat > "$HOME/.local/share/konsole/OLED.profile" << 'PROFILE'
[Appearance]
ColorScheme=OLED
Font=JetBrains Mono,11,-1,5,50,0,0,0,0,0
LineSpacing=0

[Cursor Options]
CursorShape=1
UseCustomCursorColor=false

[General]
Name=OLED
Parent=FALLBACK/
StartInCurrentSessionDir=true

[Scrolling]
HistoryMode=1
HistorySize=1000

[Terminal Features]
BlinkingCursorEnabled=false
PROFILE

# konsolerc — perfil por defecto
cat > "$CONF_DIR/konsolerc" << 'KONSOLERC'
[Desktop Entry]
DefaultProfile=OLED.profile

[General]
ConfigVersion=1
KONSOLERC

# ── Baloo usuario ─────────────────────────────────────────────────────────────
balooctl6 disable 2>/dev/null || balooctl disable 2>/dev/null || true

# ── Color scheme KDE — OLEDSafe ───────────────────────────────────────────────
mkdir -p "$HOME/.local/share/color-schemes"
cat > "$HOME/.local/share/color-schemes/OLEDSafe.colors" << 'COLORSCHEME'
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

[Colors:Complementary]
BackgroundAlternate=10,10,10
BackgroundNormal=0,0,0
DecorationFocus=74,128,176
DecorationHover=90,144,192
ForegroundActive=74,128,176
ForegroundInactive=80,80,80
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

plasma-apply-colorscheme OLEDSafe 2>/dev/null || true

# ── OLED Adaptive Color Script (corregido) ───────────────────────────────────
# Ajusta ForegroundNormal al nivel de brillo de la pantalla.
#
# Fix vs versión anterior:
#   - Antes: udev en background + polling en foreground (AMBOS siempre activos)
#   - Ahora: udev primero (event-driven), polling SOLO si udev no disponible
#   - Notificación: qdbus6 KGlobalSettings (sin KWin reconfigure = sin glitch)
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/kde-oled-adapt" << 'KDEADAPT'
#!/bin/bash
# kde-oled-adapt — Adapta colores de texto al brillo de pantalla (OLED safe)

PREV_LEVEL=""

update_colors() {
    local BRIGHT LVL HALF
    BRIGHT=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')
    [ -z "$BRIGHT" ] && return

    if   [ "$BRIGHT" -le 5  ]; then LVL=180
    elif [ "$BRIGHT" -le 15 ]; then LVL=153
    elif [ "$BRIGHT" -le 30 ]; then LVL=128
    elif [ "$BRIGHT" -le 50 ]; then LVL=106
    elif [ "$BRIGHT" -le 75 ]; then LVL=85
    else                             LVL=69; fi

    [ "$LVL" = "$PREV_LEVEL" ] && return
    PREV_LEVEL="$LVL"
    HALF=$(( LVL / 2 ))

    for group in "Colors:View" "Colors:Window" "Colors:Button"; do
        kwriteconfig6 --file kdeglobals --group "$group" \
            --key "ForegroundNormal"   "$LVL,$LVL,$LVL"
        kwriteconfig6 --file kdeglobals --group "$group" \
            --key "ForegroundInactive" "$HALF,$HALF,$HALF"
    done

    # Notificar apps Qt/KDE sin reconfigurar KWin (evita micro-glitch visual)
    qdbus6 org.kde.KGlobalSettings /KGlobalSettings \
        notifyChange 0 0 2>/dev/null || true
}

# Aplicar al inicio
update_colors

# Monitoreo event-driven via udev (no polling constante)
if command -v udevadm &>/dev/null; then
    stdbuf -oL udevadm monitor \
        --subsystem-match=backlight --property 2>/dev/null \
    | while read -r line; do
        case "$line" in
            *"change"*) update_colors ;;
        esac
    done
else
    # Fallback: polling solo si udev no está disponible
    while true; do
        sleep 30
        update_colors
    done
fi
KDEADAPT
chmod +x "$HOME/.local/bin/kde-oled-adapt"

# Autostart del adaptativo OLED
cat > "$CONF_DIR/autostart/kde-oled-adapt.desktop" << 'AUTOSTART'
[Desktop Entry]
Type=Application
Name=KDE OLED Adaptive Colors
Exec=kde-oled-adapt
StartupNotify=false
X-KDE-autostart-phase=2
AUTOSTART

echo ""
echo "✔ Optimizaciones OLED aplicadas:"
echo "  · KWin: sin blur/efectos, latencia baja, compositing optimizado"
echo "  · Konsole: tema OLED + cursor sólido (no parpadeo)"
echo "  · PowerDevil: todos los perfiles en powersave (AC/Battery/LowBattery)"
echo "  · Screen locker: fondo negro puro"
echo "  · plasma-systemmonitor: monitor de recursos KDE6 instalado"
echo "  · OLED adapt: event-driven via udev (sin polling constante)"
echo "  · Baloo: deshabilitado"
echo "  · Discover: servicios enmascarados"
echo ""
echo "  Reinicia la sesión para que todos los cambios tomen efecto."
SCRIPT

chmod +x /home/$USERNAME/kde-setup.sh
chown "$USERNAME:" /home/$USERNAME/kde-setup.sh

sudo systemctl enable sddm.service

echo ""
echo "=== Plasma instalado ==="
echo ""
echo "Después de reiniciar e iniciar sesión, ejecuta:"
echo "  bash ~/kde-setup.sh"
echo ""
echo "Aplica: OLED, KWin sin efectos, Konsole OLED, PowerDevil,"
echo "        screen locker negro, colores adaptativos, Baloo off."
echo ""
echo "Reinicia para iniciar sesión con SDDM."
