#!/bin/bash

# setup_nushell_optimized.sh
# Nushell: OLED + Performance + paleta semántica de plasma.sh
#
# Paleta semántica (de plasma.sh OLEDSafe.colors):
#   Positive  #5a8a4a  → strings, directorios, cmds internos, fechas
#   Active    #4a80b0  → variables, flags, pipes, navegación
#   Hover     #5a90c0  → booleans, operadores lógicos, redirecciones
#   Neutral   #a08840  → números, rangos, filesize, operadores
#   Negative  #a04040  → errores
#   Visited   #9a6a9a  → variables $var, cellpath (único en paleta)
#   Normal    #999999  → texto base
#   Ghost     #333333  → hints, separadores (burn-in safe)

set -e

NU_CONFIG_DIR="$HOME/.config/nushell"
CONFIG_FILE="$NU_CONFIG_DIR/config.nu"
ENV_FILE="$NU_CONFIG_DIR/env.nu"

echo "Aplicando configuración Nushell OLED + Plasma palette..."

mkdir -p "$NU_CONFIG_DIR"

[ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$CONFIG_FILE.bak" && echo "Backup: config.nu.bak"
[ -f "$ENV_FILE" ]    && cp "$ENV_FILE"    "$ENV_FILE.bak"    && echo "Backup: env.nu.bak"

# ─── env.nu ──────────────────────────────────────────────────────────────────
cat << 'ENVEOF' > "$ENV_FILE"
# env.nu — OLED, zero latency (sin starship / oh-my-posh)

$env.PATH = ($env.PATH | split row (char esep) | prepend '/usr/local/bin' | uniq)

# Prompt nativo de Nu — no lanza procesos externos
def create_left_prompt [] {
    let dir = ($env.PWD | str replace $env.HOME "~")

    # Git branch: captura silenciosa con complete, sin fallos si no hay repo
    let branch = (
        do -i { ^git branch --show-current } 
        | complete 
        | get stdout 
        | str trim
    )

    let git_part = if ($branch | is-empty) {
        ""
    } else {
        $" (ansi { fg: '#9a6a9a' })($branch)(ansi reset)"
    }

    $"(ansi { fg: '#4a80b0' attr: 'b' })($dir)(ansi reset)($git_part) "
}

$env.PROMPT_COMMAND             = { || create_left_prompt }
$env.PROMPT_COMMAND_RIGHT       = { || "" }

# Indicadores de modo vi diferenciados (verde insert / azul normal)
$env.PROMPT_INDICATOR           = { || $"(ansi { fg: '#5a8a4a' attr: 'b' })❯(ansi reset) " }
$env.PROMPT_INDICATOR_VI_INSERT = { || $"(ansi { fg: '#5a8a4a' attr: 'b' })❯(ansi reset) " }
$env.PROMPT_INDICATOR_VI_NORMAL = { || $"(ansi { fg: '#4a80b0' attr: 'b' })◆(ansi reset) " }
$env.PROMPT_MULTILINE_INDICATOR = { || $"(ansi { fg: '#333333' })╰─(ansi reset) " }
ENVEOF

# ─── config.nu ───────────────────────────────────────────────────────────────
cat << 'CFGEOF' > "$CONFIG_FILE"
# config.nu — OLED + Plasma palette + Performance

$env.config = {
    show_banner:                      false
    render_right_prompt_on_last_line: false

    # SQLite: más eficiente que plaintext; sync_on_enter false = escribe al salir
    history: {
        file_format:   "sqlite"
        max_size:      10000
        sync_on_enter: false
        isolation:     false
    }

    # compact: menos caracteres de borde = menos píxeles encendidos
    table: {
        mode:                "compact"
        index_mode:          "always"
        header_on_separator: false
        trim: {
            methodology:             "wrapping"
            wrapping_try_keep_words: true
        }
    }

    completions: {
        case_sensitive: false
        quick:          true
        partial:        true
        algorithm:      "prefix"   # Más rápido que fuzzy; sin costo de scoring
        use_ls_colors:  true       # Colorea ítems reutilizando el tema, costo cero
        external: {
            enable:      true
            max_results: 50        # Limitar = menos render de menú
        }
    }

    filesize: {
        unit: metric
    }

    # Cursor distingue modos vi visualmente — crítico en pantalla oscura
    cursor_shape: {
        vi_insert: "line"    # Línea fina → menos píxeles encendidos
        vi_normal: "block"   # Bloque → distinción clara
        emacs:     "line"
    }

    edit_mode:     "vi"
    buffer_editor: "nvim"

    use_ansi_coloring: true
    float_precision:   2
}

# ─────────────────────────────────────────────────────────────────────────────
# OLED COLOR THEME — Paleta semántica plasma.sh
# Cada tipo de dato tiene un rol de color distinto y consistente
# ─────────────────────────────────────────────────────────────────────────────
let oled_theme = {

    # ── Estructura de tabla ───────────────────────────────────────────────────
    separator:                 "#222222"                    # Casi invisible
    leading_trailing_space_bg: { attr: "n" }
    header:                    { fg: "#5a8a4a" attr: "b" } # Positive bold
    empty:                     "#4a80b0"                    # Active blue
    row_index:                 "#444444"                    # Ghost — discreto

    # ── Tipos de dato — Nu colorea por tipo en tablas ─────────────────────────
    bool:     "#5a90c0"    # Hover blue  — true / false
    int:      "#a08840"    # Neutral     — enteros (naranja/dorado, distinto del texto)
    float:    "#a08840"    # Neutral     — decimales
    filesize: "#a08840"    # Neutral     — tamaños de archivo
    duration: "#a08840"    # Neutral     — duraciones de tiempo
    date:     "#5a8a4a"    # Positive    — fechas en verde
    range:    "#a08840"    # Neutral     — rangos a..b
    string:   "#999999"    # Normal      — texto genérico (no saturar verde)
    nothing:  "#444444"    # Ghost       — null / nothing
    binary:   "#a08840"    # Neutral     — datos binarios
    cellpath: "#9a6a9a"    # Visited     — rutas de celda (violeta)
    record:   "#5a90c0"    # Hover blue  — registros {}
    list:     "#4a80b0"    # Active blue — listas []
    block:    "#4a80b0"    # Active blue — bloques {}
    hints:    "#333333"    # Ultra-ghost — sugerencias (OLED burn-in safe)

    # ── Shape colors — sintaxis coloreada al escribir en el prompt ────────────

    # Comandos: interno (bold verde) vs externo (gris) — distinción semántica clave
    shape_internalcall:         { fg: "#5a8a4a" attr: "b" } # Positive bold
    shape_external:             "#999999"                    # Normal gris sin bold
    shape_externalarg:          "#888888"                    # Tenue — args de externos
    shape_custom:               "#5a8a4a"                    # Positive — custom cmds

    # Cadenas y rutas
    shape_string:               "#5a8a4a"                    # Positive green
    shape_string_interpolation: { fg: "#5a8a4a" attr: "u" } # Subrayada — interpolación
    shape_filepath:             "#4a80b0"                    # Active blue
    shape_directory:            { fg: "#4a80b0" attr: "b" } # Active blue bold
    shape_globpattern:          { fg: "#4a80b0" attr: "u" } # Subrayado — glob

    # Números — destacan respecto al texto gris
    shape_int:    "#a08840"    # Neutral naranja
    shape_float:  "#a08840"
    shape_binary: "#a08840"

    # Lógica y flujo de control
    shape_bool:        "#5a90c0"    # Hover blue — true / false
    shape_operator:    "#a08840"    # Neutral — +, -, *, /
    shape_range:       "#a08840"    # Neutral — a..b
    shape_and:         "#5a90c0"    # Hover blue — and
    shape_or:          "#5a90c0"    # Hover blue — or
    shape_pipe:        "#5a90c0"    # Hover blue — |
    shape_redirection: "#5a90c0"    # Hover blue — >, >>

    # Variables y flags — colores distintos entre sí
    shape_variable:    "#9a6a9a"    # Visited purple — $var (único en toda la paleta)
    shape_flag:        "#4a80b0"    # Active blue — --flag

    # Tipos compuestos
    shape_block:   "#4a80b0"
    shape_list:    "#4a80b0"
    shape_record:  "#4a80b0"
    shape_table:   "#4a80b0"
    shape_literal: "#4a80b0"

    # Tiempo y firmas
    shape_datetime:  "#5a8a4a"                    # Positive green
    shape_signature: { fg: "#5a8a4a" attr: "i" } # Italic green — firma de función

    # Especiales
    shape_nothing:           "#5a90c0"     # Hover blue — null literal
    shape_matching_brackets: { attr: "u" } # Sólo subrayado, sin color extra

    # Error — OLED safe: fondo rojo muy oscuro, texto gris (no blanco puro)
    shape_garbage: { fg: "#cccccc" bg: "#5a1a1a" attr: "b" }
}

$env.config.color_config = $oled_theme

# ─────────────────────────────────────────────────────────────────────────────
# ALIASES
# ─────────────────────────────────────────────────────────────────────────────
alias l   = ls
alias la  = ls -a
alias ll  = ls -l
alias lla = ls -la
alias g   = git
alias v   = nvim
alias ..  = cd ..
alias ... = cd ../..
CFGEOF

echo ""
echo "✔ Nushell OLED + Plasma palette configurado."
echo "  Reinicia la shell o ejecuta: exec nu"
