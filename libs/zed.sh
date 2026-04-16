#!/bin/bash
# Zed editor — Instalacion y configuracion optimizada
# OLED, GPU Vulkan AMD, telemetria off, huella minima
# IA desactivada por defecto — configurar con: bash libs/zed-ai.sh
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
  "buffer_font_family": "JetBrains Mono",
  "buffer_font_size": 14,
  "buffer_line_height": 1.6,
  "ui_font_family": "Inter",
  "ui_font_size": 14,

  "theme": {
    "mode": "dark",
    "dark": "One Dark",
    "light": "One Dark"
  },

  "gpu": true,

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

  "terminal": {
    "font_family": "JetBrains Mono",
    "font_size": 13,
    "line_height": 1.4,
    "shell": { "program": "nu" },
    "env": {}
  },

  "telemetry": {
    "diagnostics": false,
    "metrics": false
  },

  "use_system_path_prompts": true,

  "file_scan_exclusions": [
    "**/.git",
    "**/node_modules",
    "**/target",
    "**/.cache",
    "**/dist",
    "**/__pycache__",
    "**/.venv",
    "**/build",
    "**/.flatpak-builder"
  ],

  "features": {
    "copilot": false
  },
  "assistant": {
    "enabled": false
  },

  "auto_update": false,
  "show_whats_new": false,
  "collaboration_panel": { "button": false },
  "notification_panel": { "button": false },
  "chat_panel": { "button": false }
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
echo "  GPU Vulkan AMD    Rendering acelerado"
echo "  JetBrains Mono    Fuente codigo"
echo "  Inter             Fuente UI"
echo "  Nushell           Terminal integrado"
echo "  Telemetria off    Sin tracking"
echo "  Auto-update off   Se actualiza via pacman"
echo "  OLED dark         One Dark"
echo "  IA desactivada    Configurar con: bash libs/zed-ai.sh"
echo ""
echo "Ejecutar: zed"
