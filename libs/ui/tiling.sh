#!/bin/bash
# Arch Linux — Tiling Compositor (Sway / Niri)
# Dark macOS aesthetic, minimal RAM, full desktop experience
# Ejecutar después de archlinux2.md base install + reboot

set -e

# --- Selector ---
echo "Selecciona compositor:"
echo "  1) Sway  (tiling manual, maduro)"
echo "  2) Niri  (auto-scroll, moderno)"
read -rp "Opcion [1/2]: " WM_CHOICE

case "$WM_CHOICE" in
  1) WM="sway" ;;
  2) WM="niri" ;;
  *) echo "Opcion invalida"; exit 1 ;;
esac

USERNAME=$(getent passwd 1000 | cut -d: -f1)
HOME_DIR="/home/$USERNAME"

# --- Paquetes comunes ---
COMMON_PKGS=(
  # Wayland core — sin X11, todo nativo Wayland
  xdg-desktop-portal-gtk
  xdg-desktop-portal-wlr
  xorg-xwayland
  qt6-wayland
  qt5-wayland

  # Qt dark theme
  kvantum
  qt5ct
  qt6ct

  # Barra + launcher + notificaciones
  waybar
  fuzzel
  mako

  # Terminal
  foot

  # Archivos
  thunar
  thunar-volman
  gvfs
  gvfs-mtp
  tumbler

  # Apps graficas ligeras (neovim ya viene en install.sh — sin editor GUI)
  imv
  zathura
  zathura-pdf-mupdf

  # Screenshots + clipboard
  grim
  slurp
  wl-clipboard
  cliphist

  # Lock + idle
  swaylock
  swayidle

  # Systray apps
  blueman
  network-manager-applet
  pavucontrol
  polkit-gnome

  # Tema dark
  papirus-icon-theme

  # Utilidades
  brightnessctl
  playerctl
  jq
  bc
  xdg-user-dirs
  libnotify
  wdisplays
  kanshi
)

# --- Paquetes por compositor ---
if [ "$WM" = "sway" ]; then
  WM_PKGS=(sway swaybg)
else
  WM_PKGS=(niri xwayland-satellite)
fi

# --- Instalar ---
sudo pacman -S --needed --noconfirm "${COMMON_PKGS[@]}" "${WM_PKGS[@]}"

# --- Crear directorios de usuario ---
sudo -u "$USERNAME" xdg-user-dirs-update

# --- Directorios de config ---
CFG="$HOME_DIR/.config"
sudo -u "$USERNAME" mkdir -p "$CFG"/{waybar,foot,fuzzel,mako,swaylock,thunar,kanshi}
if [ "$WM" = "sway" ]; then
  sudo -u "$USERNAME" mkdir -p "$CFG/sway"
else
  sudo -u "$USERNAME" mkdir -p "$CFG/niri"
fi

# --- GTK dark theme global (OLED optimized) ---
sudo -u "$USERNAME" mkdir -p "$CFG/gtk-3.0" "$CFG/gtk-4.0"

cat > "$CFG/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Inter 10
gtk-cursor-theme-name=Adwaita
gtk-application-prefer-dark-theme=true
gtk-decoration-layout=close,minimize,maximize:
EOF

cat > "$CFG/gtk-4.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Inter 10
gtk-cursor-theme-name=Adwaita
gtk-application-prefer-dark-theme=true
gtk-decoration-layout=close,minimize,maximize:
EOF

# --- GTK CSS override: forzar negro puro en fondos (OLED) ---
cat > "$CFG/gtk-3.0/gtk.css" <<'EOF'
/* OLED: fondo negro puro = pixeles apagados */
window, .background {
  background-color: #000000;
}
headerbar, .titlebar {
  background-color: #0a0a0a;
  color: #999999;
  min-height: 0;
  padding: 2px 6px;
  margin: 0;
}
headerbar .title, .titlebar .title {
  font-size: 0.9em;
  color: #808080;
}
tooltip {
  background-color: #0a0a0a;
  color: #999999;
  border: 1px solid #1a1a1a;
}
EOF

cat > "$CFG/gtk-4.0/gtk.css" <<'EOF'
/* OLED: fondo negro puro = pixeles apagados */
window, .background {
  background-color: #000000;
}
headerbar, .titlebar {
  background-color: #0a0a0a;
  color: #999999;
  min-height: 0;
  padding: 2px 6px;
  margin: 0;
}
headerbar .title, .titlebar .title {
  font-size: 0.9em;
  color: #808080;
}
tooltip {
  background-color: #0a0a0a;
  color: #999999;
  border: 1px solid #1a1a1a;
}
EOF

# --- dconf: GTK4/libadwaita dark (apps GNOME modernas) ---
sudo pacman -S --needed --noconfirm dconf
sudo -u "$USERNAME" dbus-launch dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
sudo -u "$USERNAME" dbus-launch dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita-dark'"
sudo -u "$USERNAME" dbus-launch dconf write /org/gnome/desktop/interface/icon-theme "'Papirus-Dark'"
sudo -u "$USERNAME" dbus-launch dconf write /org/gnome/desktop/interface/font-name "'Inter 10'"
sudo -u "$USERNAME" dbus-launch dconf write /org/gnome/desktop/interface/monospace-font-name "'JetBrains Mono 11'"

# --- Qt5/Qt6 dark (apps KDE) via Kvantum ---
sudo -u "$USERNAME" mkdir -p "$CFG/qt5ct" "$CFG/qt6ct" "$CFG/Kvantum"

# Default es el tema oscuro incluido con el paquete kvantum (repos oficiales)
# KvArcDark era AUR-only y causaba que Qt quedara sin tema
cat > "$CFG/Kvantum/kvantum.kvconfig" <<'EOF'
[General]
theme=Default
EOF

cat > "$CFG/qt5ct/qt5ct.conf" <<'EOF'
[Appearance]
style=kvantum
icon_theme=Papirus-Dark
color_scheme_path=
standard_dialogs=default

[Fonts]
fixed="JetBrains Mono,11,-1,5,50,0,0,0,0,0"
general="Inter,10,-1,5,50,0,0,0,0,0"
EOF

cat > "$CFG/qt6ct/qt6ct.conf" <<'EOF'
[Appearance]
style=kvantum
icon_theme=Papirus-Dark
color_scheme_path=
standard_dialogs=default

[Fonts]
fixed="JetBrains Mono,11,-1,5,50,0,0,0,0,0"
general="Inter,10,-1,5,50,0,0,0,0,0"
EOF

# --- Variables Qt para dark theme (solo tiling WM) ---
sudo -u "$USERNAME" mkdir -p "$CFG/environment.d"
cat > "$CFG/environment.d/qt-theme.conf" <<'EOF'
QT_QPA_PLATFORMTHEME=qt5ct
QT_STYLE_OVERRIDE=kvantum
PATH=$HOME/.local/bin:$PATH
EOF

# --- Foot terminal (OLED black) ---
# [tweak] eliminado: grapheme-shaping, overflowing-glyphs y grapheme-width-method
# son funciones experimentales que causan rayas horizontales (artifacts) al
# renderizar, especialmente al hacer scroll. blink=no: cursor solido OLED safe.
cat > "$CFG/foot/foot.ini" <<'EOF'
[main]
font=JetBrains Mono:size=11
font-bold=JetBrains Mono:weight=bold:size=11
font-italic=JetBrains Mono:slant=italic:size=11
font-bold-italic=JetBrains Mono:weight=bold:slant=italic:size=11
line-height=1.4
pad=10x10
dpi-aware=yes
bold-text-in-bright=no
word-delimiters=,|:"'()[]{}<>

[scrollback]
lines=10000
multiplier=3.0

[cursor]
style=beam
blink=no
beam-thickness=1.5
color=000000 999999

[mouse]
hide-when-typing=yes

[key-bindings]
clipboard-copy=Control+Shift+c
clipboard-paste=Control+Shift+v
font-increase=Control+plus
font-decrease=Control+minus
font-reset=Control+0
search-start=Control+Shift+f

[colors]
alpha=1.0
background=000000
foreground=999999
selection-foreground=b0b0b0
selection-background=1a1a1a
urls=4a80b0
regular0=000000
regular1=a04040
regular2=5a8a4a
regular3=a08840
regular4=4a80b0
regular5=9a6a9a
regular6=4a9a8a
regular7=999999
bright0=505050
bright1=b05050
bright2=6a9a5a
bright3=b09850
bright4=5a90c0
bright5=aa7aaa
bright6=5aaa9a
bright7=b0b0b0
EOF

# --- Fuzzel (launcher estilo Alfred, OLED) ---
cat > "$CFG/fuzzel/fuzzel.ini" <<'EOF'
[main]
font=Inter:size=13
prompt=  
icon-theme=Papirus-Dark
terminal=foot
layer=overlay
width=50
lines=10
horizontal-pad=16
vertical-pad=12
inner-pad=8

[colors]
background=000000ee
text=999999ff
selection=4a80b022
selection-text=b0b0b0ff
match=4a80b0ff
border=1a1a1aff

[border]
width=1
radius=16
EOF

# --- Launcher inteligente (Alfred-like) ---
cat > "$HOME_DIR/.local/bin/launcher" <<'LAUNCHER'
#!/bin/bash
# Alfred-like launcher: calculadora, comandos rapidos, apps

SPECIALS=":lock  Bloquear pantalla
:off  Apagar
:reboot  Reiniciar
:suspend  Suspender
:wifi  Configurar Wi-Fi
:bt  Bluetooth
:audio  Control de audio
:display  Configurar pantallas
:files  Archivos
:term  Terminal
:clip  Historial clipboard"

CHOICE=$(printf '%s\n' "$SPECIALS" | fuzzel -d -p "  ")

[ -z "$CHOICE" ] && exit 0

# Detectar expresion matematica
if echo "$CHOICE" | grep -qE '^[0-9 \+\-\*\/\.\(\)%]+$'; then
  RESULT=$(echo "$CHOICE" | bc -l 2>/dev/null | sed '/\..*[^0]$/s/0*$//;s/\.$//')
  if [ -n "$RESULT" ]; then
    echo "$RESULT" | wl-copy
    notify-send -t 2000 "󰃬 Calculadora" "$CHOICE = $RESULT (copiado)"
    exit 0
  fi
fi

case "$CHOICE" in
  :lock*) swaylock -f ;;
  :off*) systemctl poweroff ;;
  :reboot*) systemctl reboot ;;
  :suspend*) systemctl suspend ;;
  :wifi*) nm-connection-editor ;;
  :bt*) blueman-manager ;;
  :audio*) pavucontrol ;;
  :display*) wdisplays ;;
  :files*) thunar ;;
  :term*) foot ;;
  :clip*) cliphist list | fuzzel -d | cliphist decode | wl-copy ;;
esac
LAUNCHER

chmod +x "$HOME_DIR/.local/bin/launcher"

# --- Ocultar apps inutiles del launcher ---
HIDE_DIR="$HOME_DIR/.local/share/applications"
sudo -u "$USERNAME" mkdir -p "$HIDE_DIR"
for app in avahi-discover bssh bvnc lstopo nm-connection-editor qv4l2 qvidcap \
  xdg-desktop-portal-gtk org.freedesktop.IBus.Panel.Extension.Gtk3 \
  thunar-bulk-rename thunar-settings vim; do
  echo -e "[Desktop Entry]\nNoDisplay=true" > "$HIDE_DIR/${app}.desktop"
done

# --- Mako (notificaciones OLED safe) ---
cat > "$CFG/mako/config" <<'EOF'
default-timeout=5000
font=Inter 10
background-color=#000000ee
text-color=#999999
border-color=#1a1a1a
border-size=1
border-radius=12
padding=12
margin=10
width=350
anchor=top-right
layer=overlay
icons=1
icon-path=/usr/share/icons/Papirus-Dark
max-icon-size=48
EOF

# --- Swaylock (OLED black) ---
cat > "$CFG/swaylock/config" <<'EOF'
color=000000
inside-color=000000
ring-color=4a80b0
key-hl-color=5a8a4a
line-color=00000000
separator-color=00000000
text-color=999999
indicator-radius=80
indicator-thickness=8
EOF

# --- Waybar config (topbar estilo macOS, OLED safe) ---
cat > "$CFG/waybar/config" <<'WBCONF'
{
  "layer": "top",
  "position": "top",
  "height": 30,
  "spacing": 0,

  "modules-left": ["sway/workspaces", "niri/workspaces"],
  "modules-center": ["clock"],
  "modules-right": ["mpris", "custom/sep", "network", "custom/sep", "pulseaudio", "custom/sep", "battery", "tray"],

  "clock": {
    "format": "{:%a %d %b  %I:%M %p}",
    "tooltip-format": "{:%A, %B %d, %Y}"
  },

  "mpris": {
    "format": "{player_icon} {title}",
    "format-paused": "{player_icon} {title} 󰏤",
    "player-icons": { "default": "󰎈" },
    "max-length": 30,
    "tooltip-format": "{artist} — {title} ({album})"
  },

  "battery": {
    "format": "{icon}  {capacity}%",
    "format-charging": "󰂄 {capacity}%",
    "format-icons": ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"],
    "interval": 30,
    "states": { "warning": 25, "critical": 10 }
  },

  "network": {
    "format-wifi": "󰤨",
    "format-ethernet": "󰈀",
    "format-disconnected": "󰤭",
    "tooltip-format-wifi": "{essid} ({signalStrength}%)",
    "on-click": "nm-connection-editor"
  },

  "pulseaudio": {
    "format": "{icon}",
    "format-muted": "󰝟",
    "format-icons": { "default": ["󰕿", "󰖀", "󰕾"] },
    "tooltip-format": "{volume}%",
    "on-click": "pavucontrol",
    "scroll-step": 5
  },

  "custom/sep": {
    "format": "|",
    "interval": "once",
    "tooltip": false
  },

  "tray": {
    "icon-size": 16,
    "spacing": 8
  }
}
WBCONF

# --- Waybar style (OLED black macOS topbar) ---
cat > "$CFG/waybar/style.css" <<'WBCSS'
* {
  font-family: "Inter", sans-serif;
  font-size: 13px;
  min-height: 0;
}

window#waybar {
  background-color: rgba(0, 0, 0, 0.88);
  color: #909090;
  border: none;
}

#workspaces button {
  padding: 0 6px;
  color: #505050;
  background: transparent;
  border: none;
}
#workspaces button.active,
#workspaces button.focused {
  color: #b0b0b0;
}

#clock {
  font-weight: 500;
  color: #b0b0b0;
}

#mpris {
  color: #707070;
  font-size: 12px;
  padding: 0 8px;
}

#custom-sep {
  color: #1a1a1a;
  padding: 0 4px;
  font-size: 10px;
}

#battery, #network, #pulseaudio, #tray {
  padding: 0 8px;
  color: #909090;
}

#battery.warning { color: #a08840; }
#battery.critical { color: #a04040; }
#pulseaudio.muted { color: #a04040; }
#network.disconnected { color: #a04040; }

tooltip {
  background-color: rgba(0, 0, 0, 0.95);
  color: #909090;
  border: 1px solid #1a1a1a;
  border-radius: 8px;
  padding: 6px 10px;
}
WBCSS

# --- Sway config ---
if [ "$WM" = "sway" ]; then
cat > "$CFG/sway/config" <<'SWAYCONF'
# Variables
set $mod Mod4
set $term foot
set $menu launcher
set $files thunar

# Apariencia
default_border pixel 1
default_floating_border pixel 1
titlebar_padding 0
titlebar_border_thickness 0
font pango:Inter 0
gaps inner 4
gaps outer 0
client.focused #4a80b0 #000000 #999999 #5a8a4a #4a80b0
client.unfocused #000000 #000000 #505050 #000000 #000000
client.focused_inactive #000000 #000000 #505050 #000000 #000000

# Input
input type:keyboard {
    xkb_layout latam
    repeat_delay 300
    repeat_rate 40
}
input type:pointer {
    natural_scroll enabled
}
input type:touchpad {
    dwt enabled
    tap enabled
    natural_scroll enabled
    middle_emulation enabled
    scroll_factor 0.75
    pointer_accel 0.1
}

# Gestos touchpad (Sway 1.8+)
bindgesture swipe:right workspace prev
bindgesture swipe:left workspace next
bindgesture swipe:up exec fuzzel
bindgesture swipe:down exec foot
bindgesture pinch:inward exec pinch-zoom in
bindgesture pinch:outward exec pinch-zoom out

# Keybindings — esenciales
bindsym $mod+Return exec $term
bindsym $mod+Space exec $menu
bindsym $mod+d exec fuzzel
bindsym $mod+e exec $files
bindsym $mod+q kill
bindsym $mod+Shift+c reload
bindsym $mod+Shift+e exec swaynag -t warning -m 'Salir de Sway?' -B 'Si' 'swaymsg exit'
bindsym $mod+l exec swaylock -f
bindsym $mod+p exec wdisplays
bindsym $mod+slash exec keybinds

# Navegacion
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

# Layout
bindsym $mod+h splith
bindsym $mod+v splitv
bindsym $mod+f fullscreen toggle
bindsym $mod+Shift+space floating toggle
bindsym $mod+Tab focus mode_toggle

# Workspaces
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5
bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+5 move container to workspace number 5

# Resize mode
mode "resize" {
    bindsym Left resize shrink width 20px
    bindsym Down resize grow height 20px
    bindsym Up resize shrink height 20px
    bindsym Right resize grow width 20px
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

# Media keys
bindsym XF86AudioRaiseVolume exec osd-volume set-sink-volume @DEFAULT_SINK@ +5%
bindsym XF86AudioLowerVolume exec osd-volume set-sink-volume @DEFAULT_SINK@ -5%
bindsym XF86AudioMute exec osd-volume set-sink-mute @DEFAULT_SINK@ toggle
bindsym XF86MonBrightnessUp exec osd-brightness set +10%
bindsym XF86MonBrightnessDown exec osd-brightness set 10%-
bindsym XF86KbdBrightnessUp exec osd-kbd-brightness set +33%
bindsym XF86KbdBrightnessDown exec osd-kbd-brightness set 33%-
bindsym XF86AudioPlay exec playerctl play-pause
bindsym XF86AudioNext exec playerctl next
bindsym XF86AudioPrev exec playerctl previous

# Screenshots con notificacion
bindsym Print exec grim ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png && notify-send -t 2000 "󰄀 Screenshot" "Pantalla completa guardada"
bindsym $mod+Print exec slurp | grim -g - ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png && notify-send -t 2000 "󰄀 Screenshot" "Region guardada"

# Clipboard
exec wl-paste --watch cliphist store
bindsym $mod+Shift+v exec cliphist list | fuzzel -d | cliphist decode | wl-copy

# Autostart
exec waybar
exec mako
exec /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec nm-applet --indicator
exec blueman-applet
exec idle-manager
exec battery-monitor
exec usb-monitor
exec waybar-oled-adapt
exec kanshi
# Perfil de energia: powersave siempre (equivalente a PowerDevil en plasma.sh)
exec powerprofilesctl set power-saver
SWAYCONF
fi

# --- Niri config ---
if [ "$WM" = "niri" ]; then
cat > "$CFG/niri/config.kdl" <<'NIRICONF'
input {
    keyboard {
        xkb {
            layout "latam"
        }
        repeat-delay 300
        repeat-rate 40
    }
    touchpad {
        tap
        dwt
        natural-scroll
        accel-speed 0.1
        scroll-method "two-finger"
    }
    mouse {
        natural-scroll
    }
}

output "eDP-1" {
    // scale 1.0
}

layout {
    gaps 4
    center-focused-column "never"
    default-column-width { proportion 0.5; }

    focus-ring {
        width 1
        active-color "#4a80b0"
        inactive-color "#000000"
    }

    border {
        off
    }
}

spawn-at-startup "waybar"
spawn-at-startup "mako"
spawn-at-startup "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
spawn-at-startup "nm-applet" "--indicator"
spawn-at-startup "blueman-applet"
spawn-at-startup "idle-manager"
spawn-at-startup "wl-paste" "--watch" "cliphist" "store"
spawn-at-startup "xwayland-satellite"
spawn-at-startup "battery-monitor"
spawn-at-startup "usb-monitor"
spawn-at-startup "waybar-oled-adapt"
spawn-at-startup "kanshi"
// Perfil de energia: powersave siempre (equivalente a PowerDevil en plasma.sh)
spawn-at-startup "sh" "-c" "powerprofilesctl set power-saver"

binds {
    Mod+Return { spawn "foot"; }
    Mod+Space { spawn "launcher"; }
    Mod+D { spawn "fuzzel"; }
    Mod+E { spawn "thunar"; }
    Mod+Q { close-window; }
    Mod+L { spawn "swaylock" "-f"; }
    Mod+P { spawn "wdisplays"; }
    Mod+Slash { spawn "keybinds"; }

    Mod+Left { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+Up { focus-window-up; }
    Mod+Down { focus-window-down; }
    Mod+Shift+Left { move-column-left; }
    Mod+Shift+Right { move-column-right; }

    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    Mod+Shift+1 { move-column-to-workspace 1; }
    Mod+Shift+2 { move-column-to-workspace 2; }
    Mod+Shift+3 { move-column-to-workspace 3; }
    Mod+Shift+4 { move-column-to-workspace 4; }
    Mod+Shift+5 { move-column-to-workspace 5; }

    Mod+F { maximize-column; }
    Mod+Shift+F { fullscreen-window; }
    Mod+Shift+Space { toggle-window-floating; }
    Mod+R { switch-preset-column-width; }
    Mod+Shift+R { reset-window-height; }
    Mod+Minus { set-column-width "-10%"; }
    Mod+Equal { set-column-width "+10%"; }

    XF86AudioRaiseVolume { spawn "osd-volume" "set-sink-volume" "@DEFAULT_SINK@" "+5%"; }
    XF86AudioLowerVolume { spawn "osd-volume" "set-sink-volume" "@DEFAULT_SINK@" "-5%"; }
    XF86AudioMute { spawn "osd-volume" "set-sink-mute" "@DEFAULT_SINK@" "toggle"; }
    XF86MonBrightnessUp { spawn "osd-brightness" "set" "+10%"; }
    XF86MonBrightnessDown { spawn "osd-brightness" "set" "10%-"; }
    XF86KbdBrightnessUp { spawn "osd-kbd-brightness" "set" "+33%"; }
    XF86KbdBrightnessDown { spawn "osd-kbd-brightness" "set" "33%-"; }
    XF86AudioPlay { spawn "playerctl" "play-pause"; }
    XF86AudioNext { spawn "playerctl" "next"; }
    XF86AudioPrev { spawn "playerctl" "previous"; }

    Print { screenshot; }
    Mod+Print { screenshot-window; }
    Mod+Shift+Print { screenshot-screen; }

    Mod+Shift+V { spawn "sh" "-c" "cliphist list | fuzzel -d | cliphist decode | wl-copy"; }
    Mod+Shift+E { quit; }
    Mod+Shift+C { spawn "niri" "msg" "action" "reload-config"; }
}
NIRICONF
fi

# --- Scripts OSD (notificaciones de volumen/brillo/teclado) ---
sudo -u "$USERNAME" mkdir -p "$HOME_DIR/.local/bin"

cat > "$HOME_DIR/.local/bin/osd-volume" <<'OSDVOL'
#!/bin/bash
pactl "$@"
VOL=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -oE '[0-9]+%' | head -1)
MUTE=$(pactl get-sink-mute @DEFAULT_SINK@ | grep -oE 'yes|no')
if [ "$MUTE" = "yes" ]; then
  notify-send -h string:x-canonical-private-synchronous:osd -h int:value:0 -t 1500 "󰝟 Silenciado"
else
  notify-send -h string:x-canonical-private-synchronous:osd -h int:value:${VOL%\%} -t 1500 "󰕾 Volumen: $VOL"
fi
OSDVOL

cat > "$HOME_DIR/.local/bin/osd-brightness" <<'OSDBRI'
#!/bin/bash
brightnessctl "$@"
BRIGHT=$(brightnessctl -m | cut -d, -f4)
notify-send -h string:x-canonical-private-synchronous:osd -h int:value:${BRIGHT%\%} -t 1500 "󰃟 Brillo: $BRIGHT"
# Forzar adaptacion inmediata de waybar
pkill -SIGUSR1 -f waybar-oled-adapt 2>/dev/null
OSDBRI

cat > "$HOME_DIR/.local/bin/osd-kbd-brightness" <<'OSDKBD'
#!/bin/bash
brightnessctl -d '*::kbd_backlight' "$@"
BRIGHT=$(brightnessctl -d '*::kbd_backlight' -m | cut -d, -f4)
notify-send -h string:x-canonical-private-synchronous:osd -h int:value:${BRIGHT%\%} -t 1500 "󰌌 Teclado: $BRIGHT"
OSDKBD

chmod +x "$HOME_DIR/.local/bin"/osd-*

# --- Monitor de bateria (notificaciones baja/critica/cargada) ---
cat > "$HOME_DIR/.local/bin/battery-monitor" <<'BATMON'
#!/bin/bash
PREV_STATUS=""
WARNED_25=0
WARNED_10=0
WARNED_5=0
while true; do
  CAP=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
  STATUS=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1)
  [ -z "$CAP" ] && sleep 60 && continue

  if [ "$STATUS" = "Discharging" ]; then
    if [ "$CAP" -le 5 ] && [ "$WARNED_5" -eq 0 ]; then
      notify-send -u critical -t 0 "󰂃 Bateria critica" "${CAP}% — Conecta el cargador"
      WARNED_5=1
    elif [ "$CAP" -le 10 ] && [ "$WARNED_10" -eq 0 ]; then
      notify-send -u critical -t 10000 "󰁺 Bateria muy baja" "${CAP}%"
      WARNED_10=1
    elif [ "$CAP" -le 25 ] && [ "$WARNED_25" -eq 0 ]; then
      notify-send -u normal -t 5000 "󰁻 Bateria baja" "${CAP}%"
      WARNED_25=1
    fi
  fi

  if [ "$STATUS" = "Full" ] && [ "$PREV_STATUS" != "Full" ]; then
    notify-send -t 5000 "󰁹 Bateria completa" "Puedes desconectar el cargador"
  fi

  if [ "$STATUS" != "Discharging" ]; then
    WARNED_25=0; WARNED_10=0; WARNED_5=0
  fi

  PREV_STATUS="$STATUS"
  sleep 30
done
BATMON

# --- Monitor USB (notificacion conectar/desconectar) ---
cat > "$HOME_DIR/.local/bin/usb-monitor" <<'USBMON'
#!/bin/bash
# Solo notificar dispositivos USB reales (no hubs ni interfaces internas)
stdbuf -oL udevadm monitor --subsystem-match=usb --property | while read -r line; do
  case "$line" in
    DEVTYPE=usb_device) ACTION="$PREV_ACTION" ;;
    ACTION=add) PREV_ACTION="add" ; continue ;;
    ACTION=remove) PREV_ACTION="remove" ; continue ;;
    "") # Bloque vacio = fin de evento
      case "$ACTION" in
        add) notify-send -t 3000 "󰗜 USB" "Dispositivo conectado" ;;
        remove) notify-send -t 3000 "󰗝 USB" "Dispositivo desconectado" ;;
      esac
      ACTION=""; PREV_ACTION=""
      ;;
    *) continue ;;
  esac
done
USBMON

chmod +x "$HOME_DIR/.local/bin"/{battery-monitor,usb-monitor}

# OLED: pantalla se apaga 30s despues del lock (no 5min mas)
# before-sleep: bloquear antes de suspender (lid close)
cat > "$HOME_DIR/.local/bin/idle-manager" << 'IDLE'
#!/bin/bash
exec swayidle -w \
    timeout 300  'swaylock -f' \
    timeout 330  'swaymsg "output * dpms off" 2>/dev/null || niri msg action power-off-monitors 2>/dev/null' \
    resume       'swaymsg "output * dpms on"  2>/dev/null || niri msg action power-on-monitors  2>/dev/null' \
    before-sleep 'swaylock -f'
IDLE
chmod +x "$HOME_DIR/.local/bin/idle-manager"

# --- Pinch zoom (Sway) ---
cat > "$HOME_DIR/.local/bin/pinch-zoom" <<'PINCH'
#!/bin/bash
CURRENT=$(swaymsg -t get_outputs | jq '.[0].scale')
case "$1" in
  in)  NEW=$(echo "$CURRENT + 0.25" | bc) ;;
  out) NEW=$(echo "$CURRENT - 0.25" | bc) ;;
esac
# Clamp entre 0.5 y 3.0
if (( $(echo "$NEW >= 0.5" | bc -l) )) && (( $(echo "$NEW <= 3.0" | bc -l) )); then
  swaymsg output '*' scale "$NEW"   # '*' aplica a todos los outputs activos
fi
PINCH
chmod +x "$HOME_DIR/.local/bin/pinch-zoom"

# --- Waybar OLED adaptive: ajusta colores segun brillo ---
cat > "$HOME_DIR/.local/bin/waybar-oled-adapt" <<'ADAPT'
#!/bin/bash
# Ajusta colores de waybar inversamente al brillo de pantalla
# Solo actua cuando el brillo cambia realmente (via señal o udev)

CFG="$HOME/.config/waybar/style.css"
PREV_LEVEL=""

update_waybar() {
  local BRIGHT TXT INACTIVE ACCENT WARN
  BRIGHT=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')
  [ -z "$BRIGHT" ] && return

  if [ "$BRIGHT" -le 5 ]; then TXT="b0"
  elif [ "$BRIGHT" -le 15 ]; then TXT="99"
  elif [ "$BRIGHT" -le 30 ]; then TXT="80"
  elif [ "$BRIGHT" -le 50 ]; then TXT="6a"
  elif [ "$BRIGHT" -le 75 ]; then TXT="55"
  else TXT="45"; fi

  [ "$TXT" = "$PREV_LEVEL" ] && return
  PREV_LEVEL="$TXT"

  INACTIVE=$(printf '%02x' $(( 16#$TXT / 2 )) )
  ACCENT=$(printf '%02x' $(( 16#$TXT * 7 / 10 )) )
  WARN=$(printf '%02x' $(( 16#$TXT * 6 / 10 )) )

  cat > "$CFG" <<CSSEOF
* {
  font-family: "Inter", sans-serif;
  font-size: 13px;
  min-height: 0;
}
window#waybar {
  background-color: rgba(0, 0, 0, 0.88);
  color: #${TXT}${TXT}${TXT};
  border: none;
}
#workspaces button {
  padding: 0 6px;
  color: #${INACTIVE}${INACTIVE}${INACTIVE};
  background: transparent;
  border: none;
}
#workspaces button.active,
#workspaces button.focused {
  color: #${TXT}${TXT}${TXT};
}
#clock {
  font-weight: 500;
  color: #${TXT}${TXT}${TXT};
}
#mpris {
  color: #${ACCENT}${ACCENT}${ACCENT};
  font-size: 12px;
  padding: 0 8px;
}
#custom-sep {
  color: #1a1a1a;
  padding: 0 4px;
  font-size: 10px;
}
#battery, #network, #pulseaudio, #tray {
  padding: 0 8px;
  color: #${TXT}${TXT}${TXT};
}
#battery.warning { color: #${WARN}8840; }
#battery.critical { color: #${WARN}4040; }
#pulseaudio.muted { color: #${WARN}4040; }
#network.disconnected { color: #${WARN}4040; }
tooltip {
  background-color: rgba(0, 0, 0, 0.95);
  color: #${TXT}${TXT}${TXT};
  border: 1px solid #1a1a1a;
  border-radius: 8px;
  padding: 6px 10px;
}
CSSEOF

  pkill -SIGUSR2 waybar 2>/dev/null
}

# Señal desde osd-brightness para actualizacion inmediata
trap 'update_waybar' USR1

# Aplicar al inicio
update_waybar

# Event-driven via udev; polling solo si udev no disponible
# Fix: antes ambos corrian simultaneamente (udev en & + polling en foreground)
if command -v udevadm &>/dev/null; then
  stdbuf -oL udevadm monitor \
    --subsystem-match=backlight --property 2>/dev/null | while read -r line; do
    case "$line" in
      *"change"*) update_waybar ;;
    esac
  done
else
  # Fallback: polling cada 30s solo si udev no esta disponible
  while true; do
    sleep 30
    update_waybar
  done
fi
ADAPT

chmod +x "$HOME_DIR/.local/bin/waybar-oled-adapt"

# --- Kanshi: perfiles de pantalla automaticos ---
# Perfil base: solo laptop
cat > "$CFG/kanshi/config" <<'KANSHI'
# Perfil: solo laptop
profile laptop {
    output eDP-1 enable scale 1.0 position 0,0
}

# Perfil: laptop + monitor externo a la derecha
# Editar con nombres reales de tus monitores (ver: swaymsg -t get_outputs)
# profile docked {
#     output eDP-1 enable scale 1.0 position 0,0
#     output "HDMI-A-1" enable scale 1.0 position 1920,0
# }

# Perfil: solo monitor externo (laptop cerrada)
# profile external {
#     output eDP-1 disable
#     output "HDMI-A-1" enable scale 1.0 position 0,0
# }
KANSHI

# --- Cheatsheet de atajos (Super+/) ---
cat > "$HOME_DIR/.local/bin/keybinds" <<'KEYS'
#!/bin/bash
BINDS="Super + Enter        Terminal
Super + Space        Launcher (Alfred)
Super + D            Apps
Super + E            Archivos
Super + Q            Cerrar ventana
Super + L            Bloquear
Super + P            Pantallas
Super + F            Fullscreen
Super + R            Resize mode
Super + H            Split horizontal
Super + V            Split vertical
Super + Tab          Alternar tiling/float focus
Super + Shift+Space  Flotar ventana
Super + Shift+V      Clipboard
Super + Shift+C      Recargar config
Super + Shift+E      Salir
Super + 1-5          Workspace 1-5
Super + Shift+1-5    Mover a workspace
Super + Flechas      Navegar ventanas
Super + Shift+Flechas  Mover ventana
Print                Screenshot completo
Super + Print        Screenshot region
Vol ↑↓ / Mute        Volumen + OSD
Brillo ↑↓            Brillo + OSD
Teclado brillo ↑↓    Luz teclado + OSD
Play/Next/Prev       Media controls"

echo "$BINDS" | fuzzel -d -p "  " --width=55 --lines=28 > /dev/null 2>&1
KEYS
chmod +x "$HOME_DIR/.local/bin/keybinds"

# --- Pipewire: coherente con plasma.sh ---
sudo -u "$USERNAME" mkdir -p "$CFG/pipewire/pipewire.conf.d"
cat > "$CFG/pipewire/pipewire.conf.d/99-desktop.conf" << 'EOF'
context.properties = {
    default.clock.rate          = 48000
    default.clock.allowed-rates = [ 44100 48000 96000 ]
    default.clock.quantum       = 1024
    default.clock.min-quantum   = 32
    default.clock.max-quantum   = 8192
    log.level                   = 2
}
EOF

# --- Permisos finales ---
chown -R "$USERNAME:" "$CFG" "$HOME_DIR/.local"   # grupo primario del usuario

# --- Login manager: lemurs (TUI puro, oficial extra repo, OLED safe) ---
# lemurs si esta en los repos oficiales de Arch (extra).
# Los scripts de sesion van en /etc/lemurs/wayland/ (no wayland-sessions).
sudo pacman -S --needed --noconfirm lemurs

# Config OLED: fondo negro, sin animaciones
sudo mkdir -p /etc/lemurs
sudo tee /etc/lemurs/config.toml > /dev/null << 'LEMURSCFG'
[ui]
show_box         = true
remember_username = true

[ui.colors]
input_color = "DarkGray"
error_color = "Red"
LEMURSCFG

# Script de sesion Wayland para el compositor elegido
sudo mkdir -p /etc/lemurs/wayland
cat << WMSESSION | sudo tee "/etc/lemurs/wayland/$WM" > /dev/null
#!/bin/sh
exec $WM
WMSESSION
sudo chmod +x "/etc/lemurs/wayland/$WM"

sudo systemctl enable lemurs.service

echo ""
echo "=== Instalacion completa ==="
echo "Compositor: $WM"
echo ""
echo "Atajos principales:"
echo "  Super + Enter     → Terminal"
echo "  Super + Space     → Launcher (Alfred)"
echo "  Super + D         → Apps"
echo "  Super + E         → Archivos"
echo "  Super + Q         → Cerrar ventana"
echo "  Super + L         → Bloquear"
echo "  Super + P         → Configurar pantallas"
echo "  Super + Shift+V   → Clipboard"
echo "  Super + Print     → Screenshot region"
echo "  Print             → Screenshot completo"
echo ""
echo "Reinicia para iniciar sesion."
