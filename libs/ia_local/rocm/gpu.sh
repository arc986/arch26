#!/bin/bash
# ia_local/rocm/gpu.sh — RDNA 3.5 GPU: validacion + ROCm + optimizaciones
# Hardware: Ryzen AI 7 350 (Strix Point) — RDNA 3.5 iGPU gfx1151
# Optimiza: inferencia eficiente, battery saving, thermal, sin degradacion
set -euo pipefail

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' C='\033[1;36m' N='\033[0m'
info()  { printf "${C}:: %s${N}\n" "$*"; }
ok()    { printf "${G}✓  %s${N}\n" "$*"; }
warn()  { printf "${Y}⚠  %s${N}\n" "$*"; }
die()   { printf "${R}✗  %s${N}\n" "$*"; exit 1; }

[[ $EUID -eq 0 ]] || die "Ejecuta como root"

USERNAME=$(getent passwd 1000 | cut -d: -f1)
[ -z "$USERNAME" ] && die "No se encontro usuario UID 1000"

# ══════════════════════════════════════════
# 1. VALIDAR HARDWARE GPU
# ══════════════════════════════════════════
info "Validando GPU RDNA 3.5 (gfx1151)..."

GPU_OK=false

if lsmod | grep -q amdgpu; then
    ok "amdgpu: activo"
    GPU_OK=true
else
    warn "amdgpu: no activo — verifica que KMS este habilitado"
    warn "Agrega 'amdgpu' a MODULES=() en /etc/mkinitcpio.conf y regenera initramfs"
fi

if ls /dev/dri/renderD* &>/dev/null; then
    ok "Render nodes: $(ls /dev/dri/renderD* | tr '\n' ' ')"
else
    warn "Sin render nodes en /dev/dri/"
fi

if command -v lspci &>/dev/null; then
    GPU_INFO=$(lspci | grep -i "VGA\|Display\|3D" | grep -i "AMD\|ATI" || true)
    [ -n "$GPU_INFO" ] && ok "GPU: $GPU_INFO" || warn "No se detecto GPU AMD via lspci"
fi

if command -v rocminfo &>/dev/null; then
    GFX=$(rocminfo 2>/dev/null | grep "Name:" | grep -i "gfx" | awk '{print $2}' | head -1 || true)
    [ -n "$GFX" ] && { ok "ROCm: GPU detectada como $GFX"; GPU_OK=true; } \
                  || warn "ROCm instalado pero no detecta GPU — puede requerir reinicio"
else
    warn "ROCm: no instalado"
fi

if command -v ollama &>/dev/null; then
    OLLAMA_VER=$(ollama --version 2>/dev/null || echo "instalado")
    ok "Ollama: $OLLAMA_VER"
    systemctl is-active ollama &>/dev/null \
        && ok "Ollama: servicio activo" \
        || warn "Ollama: servicio inactivo"
else
    warn "Ollama: no instalado"
fi

# Power level actual
DPM="/sys/class/drm/card0/device/power_dpm_force_performance_level"
[ -f "$DPM" ] && ok "GPU power level: $(cat $DPM)" || warn "No se pudo leer power_dpm_force_performance_level"

echo ""
info "Estado GPU: $([ "$GPU_OK" = true ] && echo 'OPERACIONAL' || echo 'NO OPERACIONAL / pendiente de setup')"
echo ""

# ══════════════════════════════════════════
# 2. PREGUNTAR SI CONFIGURAR
# ══════════════════════════════════════════
read -rp "  Configurar entorno ROCm/GPU ahora? [s/N]: " DO_SETUP
[[ "$DO_SETUP" == "s" ]] || { info "Setup omitido."; exit 0; }

# ══════════════════════════════════════════
# 3. ROCm — PAQUETES
# ══════════════════════════════════════════
info "Instalando ROCm..."

pacman -S --needed --noconfirm \
    rocm-opencl-runtime \
    hip-runtime-amd \
    rocminfo \
    rocm-smi-lib \
    clinfo

ok "ROCm instalado"

# ══════════════════════════════════════════
# 4. GRUPOS render + video
# ══════════════════════════════════════════
id -nG "$USERNAME" | grep -qw render || { usermod -aG render "$USERNAME"; ok "Usuario $USERNAME → grupo render"; }
id -nG "$USERNAME" | grep -qw video  || { usermod -aG video  "$USERNAME"; ok "Usuario $USERNAME → grupo video"; }

# ══════════════════════════════════════════
# 5. VARIABLES DE ENTORNO ROCm
# ══════════════════════════════════════════
info "Configurando variables de entorno ROCm..."

grep -q "ROC_ENABLE_PRE_VEGA" /etc/environment 2>/dev/null || cat >> /etc/environment <<'ENVVARS'

# ROCm — Ryzen AI 7 350 (Strix Point, gfx1151)
ROC_ENABLE_PRE_VEGA=0
HSA_ENABLE_SDMA=0
# Suprime logs de ROCm en consola (evita spam y escrituras innecesarias)
AMD_LOG_LEVEL=0
# Ollama: offload maximo a GPU, 1 modelo a la vez, descarga tras 5min idle
OLLAMA_NUM_GPU=999
OLLAMA_MAX_LOADED_MODELS=1
OLLAMA_KEEP_ALIVE=5m
OLLAMA_FLASH_ATTENTION=1
OLLAMA_NUM_PARALLEL=1
ENVVARS
ok "Variables ROCm escritas en /etc/environment"

# ══════════════════════════════════════════
# 6. GPU POWER MANAGEMENT
# Objetivo: GPU en 'auto' para que el driver gestione dinamicamente
# En reposo: baja frecuencia/voltaje. En inferencia: boost automatico.
# Evita que la iGPU quede pegada en estado de alto consumo.
# ══════════════════════════════════════════
info "Configurando power management GPU..."

# udev: fuerza runtime PM en el dispositivo PCI amdgpu
cat > /etc/udev/rules.d/71-amdgpu-pm.rules <<'UDEV'
# RDNA 3.5 — runtime power management
# Permite al driver subir/bajar clocks segun carga real
DRIVER=="amdgpu", ATTR{power/control}="auto"
SUBSYSTEM=="drm", KERNEL=="card*", DRIVERS=="amdgpu", ATTR{device/power_dpm_force_performance_level}="auto"
UDEV

# tmpfiles: aplica 'auto' en cada arranque (persiste entre reinicios)
cat > /etc/tmpfiles.d/amdgpu-pm.conf <<'TMPFILES'
# GPU power level: 'auto' deja al driver gestionar frecuencias dinamicamente
# Opciones: auto (recomendado) | low (max ahorro) | high (max rendimiento)
w /sys/class/drm/card0/device/power_dpm_force_performance_level - - - - auto
TMPFILES

# Aplicar ahora si el dispositivo existe
if [ -f "$DPM" ]; then
    echo "auto" > "$DPM"
    ok "GPU power level → auto (aplicado ahora)"
fi

udevadm control --reload-rules
ok "Reglas udev GPU escritas"

# ══════════════════════════════════════════
# 7. OLLAMA — INSTALACION
# ══════════════════════════════════════════
info "Instalando Ollama (extra oficial — incluye soporte AMD/ROCm)..."

pacman -S --needed --noconfirm ollama

# ── Systemd drop-in: Ollama optimizado para laptop/iGPU ──
# Nice=10: inferencia no roba CPU a trabajo interactivo
# batch scheduling: el OS prioriza trabajo interactivo sobre Ollama
# MemoryHigh: Ollama puede usar hasta 6G antes de presion de memoria
# MemoryMax: hard limit para no matar el sistema en modelos grandes
OLLAMA_DROPIN_DIR="/etc/systemd/system/ollama.service.d"
mkdir -p "$OLLAMA_DROPIN_DIR"
cat > "$OLLAMA_DROPIN_DIR/optimized.conf" <<'DROPIN'
[Service]
# Offload todas las capas a GPU, 1 modelo en VRAM, descarga tras idle
Environment=OLLAMA_NUM_GPU=999
Environment=OLLAMA_MAX_LOADED_MODELS=1
Environment=OLLAMA_KEEP_ALIVE=5m
Environment=OLLAMA_FLASH_ATTENTION=1
Environment=OLLAMA_NUM_PARALLEL=1
# Suprime logs verbosos de ROCm/HSA
Environment=AMD_LOG_LEVEL=0
Environment=HSA_ENABLE_SDMA=0
# Prioridad baja: no degrada trabajo interactivo durante inferencia
Nice=10
CPUSchedulingPolicy=batch
# Limites de memoria: protege el sistema de OOM en modelos grandes
MemoryHigh=6G
MemoryMax=8G
MemorySwapMax=0
DROPIN

systemctl daemon-reload
systemctl enable --now ollama
ok "Ollama instalado y servicio activo"

# ══════════════════════════════════════════
# 8. MODELO BASE (OPCIONAL)
# ══════════════════════════════════════════
echo ""
echo "  Modelos recomendados (RDNA 3.5, inferencia GPU):"
echo "    1) qwen2.5-coder:7b    Codigo, 4.7GB  (recomendado)"
echo "    2) deepseek-coder-v2   Codigo, 8.9GB"
echo "    3) llama3.1:8b         General, 4.7GB"
echo "    4) ninguno             Descargar luego: ollama pull <modelo>"
echo ""
read -rp "  Modelo [1-4]: " MODEL_CHOICE

case "$MODEL_CHOICE" in
    1) sudo -u "$USERNAME" ollama pull qwen2.5-coder:7b ;;
    2) sudo -u "$USERNAME" ollama pull deepseek-coder-v2 ;;
    3) sudo -u "$USERNAME" ollama pull llama3.1:8b ;;
    4) info "Omitido." ;;
    *) warn "Opcion invalida — omitido" ;;
esac

# ══════════════════════════════════════════
# RESUMEN
# ══════════════════════════════════════════
echo ""
info "Setup GPU/ROCm completado"
echo ""

command -v rocminfo &>/dev/null && {
    GPU_NAME=$(rocminfo 2>/dev/null | grep -m1 "Marketing Name" | cut -d: -f2 | xargs || echo "no detectada")
    ok "GPU ROCm: $GPU_NAME"
}

command -v ollama &>/dev/null && ok "Ollama: $(ollama --version 2>/dev/null || echo 'instalado')"

echo ""
echo "  Power management: auto (GPU sube/baja segun carga)"
echo "  Ollama: offload total GPU | descarga tras 5min idle | prioridad batch"
echo "  Verificar ROCm:  rocminfo | grep 'Marketing Name'"
echo "  Monitor GPU:     rocm-smi"
echo "  Modelos:         ollama list"
echo ""
warn "REINICIA la sesion para aplicar grupos render/video y variables de entorno"
