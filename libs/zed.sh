#!/bin/bash
# Arch Linux — Zed editor optimizado
# Post archlinux2.md base install
set -e

USERNAME=$(getent passwd 1000 | cut -d: -f1)
HOME_DIR="/home/$USERNAME"
CFG="$HOME_DIR/.config/zed"

# --- Instalar ---
sudo pacman -S --needed zed

# --- Config optimizada ---
sudo -u "$USERNAME" mkdir -p "$CFG"

cat > "$CFG/settings.json" <<'EOF'
{
  // Fuentes (hereda fontconfig del base: hintnone, antialias, sin subpixel)
  "buffer_font_family": "JetBrains Mono",
  "buffer_font_size": 14,
  "buffer_line_height": 1.6,
  "ui_font_family": "Inter",
  "ui_font_size": 14,

  // Tema OLED
  "theme": {
    "mode": "dark",
    "dark": "One Dark",
    "light": "One Dark"
  },

  // Rendering GPU (Vulkan AMD)
  "gpu": true,

  // Editor
  "tab_size": 2,
  "hard_tabs": false,
  "format_on_save": "on",
  "autosave": "off",
  "cursor_blink": true,
  "relative_line_numbers": false,
  "scroll_beyond_last_line": "off",
  "vertical_scroll_margin": 5,
  "minimap": { "enabled": false },
  "scrollbar": { "show": "auto" },
  "indent_guides": { "enabled": true },
  "inlay_hints": { "enabled": true },
  "soft_wrap": "editor_width",

  // Terminal integrado
  "terminal": {
    "font_family": "JetBrains Mono",
    "font_size": 13,
    "line_height": 1.4,
    "shell": { "program": "nu" },
    "env": {}
  },

  // Telemetria desactivada
  "telemetry": {
    "diagnostics": false,
    "metrics": false
  },

  // Wayland nativo
  "use_system_path_prompts": true,

  // Rendimiento
  "file_scan_exclusions": [
    "**/.git",
    "**/node_modules",
    "**/target",
    "**/.cache",
    "**/dist",
    "**/__pycache__",
    "**/.venv"
  ],

  // Desactivar IA por defecto (se configura en zed-ai.sh)
  "features": {
    "copilot": false
  },
  "assistant": {
    "enabled": false
  }
}
EOF

# --- Keybindings ---
cat > "$CFG/keymap.json" <<'EOF'
[
  {
    "context": "Editor",
    "bindings": {
      "ctrl-shift-p": "command_palette::Toggle",
      "ctrl-shift-f": "search::ToggleSearchBar",
      "ctrl-`": "terminal_panel::ToggleFocus"
    }
  }
]
EOF

# --- Permisos ---
chown -R "$USERNAME:users" "$CFG"

echo ""
echo "=== Zed editor configurado ==="
echo ""
echo "Optimizaciones:"
echo "  GPU Vulkan (AMD)     → Rendering acelerado"
echo "  JetBrains Mono       → Fuente codigo (fontconfig base)"
echo "  Inter                → Fuente UI"
echo "  Nushell              → Terminal integrado"
echo "  Telemetria off       → Sin tracking"
echo "  IA desactivada       → Configurar con zed-ai.sh"
echo "  OLED dark theme      → One Dark"
echo ""
echo "Ejecutar: zed"
