#!/bin/bash

# setup_nushell_optimized.sh
# Standard Linux script to create an optimized Nushell configuration.
# Focused on: Performance, Battery Saving, and OLED Screens.

set -e

# --- Configuration Paths ---
NU_CONFIG_DIR="$HOME/.config/nushell"
CONFIG_FILE="$NU_CONFIG_DIR/config.nu"
ENV_FILE="$NU_CONFIG_DIR/env.nu"

echo "🚀 Starting Nushell optimization for Linux..."

# Create directory if it doesn't exist
mkdir -p "$NU_CONFIG_DIR"

# Backup existing files
if [ -f "$CONFIG_FILE" ]; then
    echo "📦 Backing up existing config.nu to config.nu.bak"
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
fi

if [ -f "$ENV_FILE" ]; then
    echo "📦 Backing up existing env.nu to env.nu.bak"
    cp "$ENV_FILE" "$ENV_FILE.bak"
fi

# --- Create env.nu ---
# env.nu is for environment variables and startup scripts.
cat << 'EOF' > "$ENV_FILE"
# env.nu - Optimized for performance and battery
# Minimal environment setup to reduce startup overhead

# Standard PATH setup (example)
$env.PATH = ($env.PATH | split row (char esep) | prepend '/usr/local/bin')

# Minimal Prompt Definition (Nushell native for zero latency)
# Avoids external binaries like starship/oh-my-posh for battery saving
def create_left_prompt [] {
    let dir = ($env.PWD | str replace $env.HOME "~")
    let path_color = (ansi green_bold)
    let reset = (ansi reset)
    
    $"($path_color)($dir)($reset) "
}

def create_right_prompt [] {
    # Empty or very minimal for performance
    ""
}

$env.PROMPT_COMMAND = { || create_left_prompt }
$env.PROMPT_COMMAND_RIGHT = { || create_right_prompt }
EOF

# --- Create config.nu ---
# config.nu contains the shell behavior and theme.
cat << 'EOF' > "$CONFIG_FILE"
# config.nu - Optimized for OLED, Performance, and Battery

# --- PERFORMANCE & BATTERY SETTINGS ---
$env.config = {
    show_banner: false
    render_right_prompt_on_last_line: false
    
    # History configuration (SQLite + Deduplication)
    history: {
        file_format: "sqlite"     # Faster for large histories
        max_size: 10000           # Keep it lean
        sync_on_enter: false       # Sync across terminals
        ignore_duplicates: true   # PREVENT DUPLICATES (Requested)
    }

    # Use compact tables to save screen space and rendering time
    table: {
        mode: compact # Options: wrapped, thin, rounded, compact
        index_mode: always
        header_on_separator: false
    }

    # Completions optimization
    completions: {
        case_sensitive: false
        quick: true
        partial: true
        algorithm: "prefix" # 'prefix' is faster than 'fuzzy'
        external: {
            enable: true
            max_results: 100
        }
    }

    # Filesystem and performance
    filesize: {
        metric: true
        format: "auto"
    }

    # Disable heavy features if not needed
    edit_mode: nvim # neovim is very light
    buffer_editor: "" # Prevents launching external editors unexpectedly
}

# --- OLED OPTIMIZED COLOR THEME ---
# Inspired by 'OLED Safe' from plasma.sh
# Uses pure black (#000000) backgrounds and soft grays/blues for text
let oled_theme = {
    separator: "#444444"
    leading_trailing_space_bg: { attr: n }
    header: "#5a8a4a" # Positive/Green from plasma.sh
    empty: "#4a80b0"  # Focus Blue
    bool: "#5a90c0"   # Hover Blue
    int: "#999999"    # Foreground Normal
    filesize: "#999999"
    duration: "#999999"
    date: "#5a8a4a"
    range: "#a08840"  # Neutral/Orange
    float: "#999999"
    string: "#999999"
    nothing: "#444444"
    binary: "#a08840"
    cellpath: "#999999"
    row_index: "#5a8a4a"
    record: "#999999"
    list: "#999999"
    block: "#999999"
    hints: "#444444" # Subtle hints to prevent burn-in

    # Shape colors based on plasma.sh palette
    shape_and: "#5a90c0"
    shape_binary: "#a08840"
    shape_block: "#4a80b0"
    shape_bool: "#5a90c0"
    shape_custom: "#5a8a4a"
    shape_datetime: "#5a8a4a"
    shape_directory: "#4a80b0"
    shape_external: "#5a8a4a"
    shape_externalarg: "#5a8a4a"
    shape_filepath: "#4a80b0"
    shape_flag: "#4a80b0"
    shape_float: "#999999"
    shape_garbage: { fg: "#ffffff" bg: "#a04040" attr: b } # Negative Red background
    shape_globpattern: "#4a80b0"
    shape_int: "#999999"
    shape_internalcall: "#5a8a4a"
    shape_list: "#4a80b0"
    shape_literal: "#4a80b0"
    shape_matching_brackets: { attr: u }
    shape_nothing: "#5a90c0"
    shape_operator: "#a08840"
    shape_or: "#5a90c0"
    shape_pipe: "#5a90c0"
    shape_range: "#a08840"
    shape_record: "#4a80b0"
    shape_redirection: "#5a90c0"
    shape_signature: "#5a8a4a"
    shape_string: "#5a8a4a"
    shape_string_interpolation: "#5a8a4a"
    shape_table: "#4a80b0"
    shape_variable: "#5a90c0"
}

# Apply the theme
$env.config.color_config = $oled_theme

# --- OPTIMIZED ALIASES ---
alias l = ls
alias la = ls -a
alias ll = ls -l
alias g = git # If git is installed, simple alias is light

echo "✅ Optimization complete!"
echo "💡 Restart Nushell or run 'source $CONFIG_FILE' to apply."
EOF

chmod +x "$0" 2>/dev/null || true

echo "✨ Configuration files created for Nushell."
