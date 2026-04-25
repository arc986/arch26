#!/bin/bash
# nspawn/setup/ia_rocm.sh — Contenedor IA local: ROCm + Ollama aislado
# Arch base — ROCm/Ollama NO se instalan en el host
# Hardware: Ryzen AI 7 350 — RDNA 3.5 (gfx1151) + XDNA2 NPU
# Optimiza: power gating GPU/NPU en host, inferencia eficiente en contenedor
# Uso: bash ia_rocm.sh [nombre]  (default: ia-rocm)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/profiles.sh"

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' C='\033[1;36m' N='\033[0m'
info()  { printf "${C}:: %s${N}\n" "$*"; }
ok()    { printf "${G}✓  %s${N}\n" "$*"; }
warn()  { printf "${Y}⚠  %s${N}\n" "$*"; }

CNAME="${1:-ia-rocm}"
validate_name "$CNAME"
ensure_not_exists "$CNAME"

# ══════════════════════════════════════════
# 1. REQUISITOS EN EL HOST
# ══════════════════════════════════════════
info "Verificando requisitos en el host..."

command -v pacstrap >/dev/null || {
    warn "Requiere arch-install-scripts (solo para crear el contenedor):"
    echo "  sudo pacman -S arch-install-scripts"
    exit 1
}

# Kernel comparte modulos con el contenedor — deben existir en el host
[ -d /dev/dri ]   && ok "GPU: /dev/dri presente"  || warn "GPU: /dev/dri no encontrado (amdgpu inactivo?)"
[ -e /dev/kfd ]   && ok "ROCm: /dev/kfd presente" || warn "ROCm: /dev/kfd no encontrado (carga amdgpu o instala firmware)"
[ -d /dev/accel ] && ok "NPU: /dev/accel presente" || warn "NPU: /dev/accel no encontrado (amdxdna no cargado o kernel < 6.9)"
echo ""

# ══════════════════════════════════════════
# 2. POWER MANAGEMENT EN EL HOST
# Los drivers corren en el host — las optimizaciones de power también.
# El contenedor hereda el kernel pero no puede escribir en /sys del host.
# ══════════════════════════════════════════
info "Aplicando power management GPU/NPU en el host..."

# GPU: 'auto' permite al driver ajustar clocks segun carga real
# Sin esto la iGPU puede quedar en estado de alto consumo aunque Ollama este idle
cat > /etc/udev/rules.d/71-amdgpu-pm.rules <<'UDEV'
# RDNA 3.5 — runtime power management
DRIVER=="amdgpu", ATTR{power/control}="auto"
SUBSYSTEM=="drm", KERNEL=="card*", DRIVERS=="amdgpu", ATTR{device/power_dpm_force_performance_level}="auto"
UDEV

# Persiste el power level tras cada arranque
cat > /etc/tmpfiles.d/amdgpu-pm.conf <<'TMPFILES'
w /sys/class/drm/card0/device/power_dpm_force_performance_level - - - - auto
TMPFILES

# Aplicar ahora si el dispositivo existe
DPM="/sys/class/drm/card0/device/power_dpm_force_performance_level"
[ -f "$DPM" ] && echo "auto" > "$DPM" && ok "GPU power level → auto"

# NPU: power gating — se apaga cuando no hay workload activo
# Critico para laptop: sin esto el NPU consume aunque este idle
cat > /etc/udev/rules.d/70-amdxdna.rules <<'UDEV'
# XDNA2 NPU — Ryzen AI 7 350
SUBSYSTEM=="accel", GROUP="render", MODE="0660"
DRIVER=="amdxdna", ATTR{power/control}="auto"
UDEV

# Aplicar power gating ahora si el NPU ya esta enlazado
NPU_PCI=$(find /sys/bus/pci/drivers/amdxdna -maxdepth 1 -name "0000:*" 2>/dev/null | head -1 || true)
[ -n "$NPU_PCI" ] && echo "auto" > "$NPU_PCI/power/control" 2>/dev/null && ok "NPU power gating → auto"

udevadm control --reload-rules
udevadm trigger --subsystem-match=drm   2>/dev/null || true
udevadm trigger --subsystem-match=accel 2>/dev/null || true
ok "Reglas udev host escritas (GPU + NPU)"

# ══════════════════════════════════════════
# 3. CREAR BASE ARCH
# ══════════════════════════════════════════
info "Creando subvolumen Arch ($CNAME)..."
sudo btrfs subvolume create "$MACHINES/$CNAME"

info "Instalando base Arch con pacstrap (puede tardar)..."
sudo pacstrap -c "$MACHINES/$CNAME" base

sudo sh -c "
    echo '$CNAME' > '$MACHINES/$CNAME/etc/hostname'
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > '$MACHINES/$CNAME/etc/resolv.conf'
"
ok "Base Arch creada"

# ══════════════════════════════════════════
# 4. ROCm + OLLAMA + OPTIMIZACIONES DENTRO DEL CONTENEDOR
# ══════════════════════════════════════════
info "Instalando ROCm + Ollama dentro del contenedor..."

run_in "$CNAME" '
    pacman -Sy --noconfirm
    pacman -S --needed --noconfirm \
        rocm-opencl-runtime \
        hip-runtime-amd \
        rocminfo \
        rocm-smi-lib \
        clinfo \
        ollama \
        python \
        python-numpy \
        curl

    # Variables ROCm + Ollama optimizadas para inferencia en iGPU/laptop
    cat >> /etc/environment << "ENVVARS"

# ROCm — RDNA 3.5 (gfx1151)
ROC_ENABLE_PRE_VEGA=0
HSA_ENABLE_SDMA=0
# Suprime logs verbosos de ROCm (evita escrituras y spam en consola)
AMD_LOG_LEVEL=0

# NPU XDNA2
XLNX_ENABLE_DEVICES=all
XLNX_SKIP_CDMA=1

# Ollama: offload total a GPU, 1 modelo en VRAM, descarga tras 5min idle
# Evita que el modelo quede ocupando VRAM cuando no se usa (bateria)
OLLAMA_NUM_GPU=999
OLLAMA_MAX_LOADED_MODELS=1
OLLAMA_KEEP_ALIVE=5m
OLLAMA_FLASH_ATTENTION=1
OLLAMA_NUM_PARALLEL=1
ENVVARS

    # Grupos para acceso a /dev/dri, /dev/kfd, /dev/accel
    groupadd -f render
    groupadd -f video
    usermod -aG render,video root 2>/dev/null || true

    # ia-serve: inicia Ollama con todas las optimizaciones aplicadas
    # nice -n 10: inferencia no roba CPU a trabajo interactivo
    # ionice -c 3: I/O idle class, carga de modelo no degrada disco del host
    cat > /usr/local/bin/ia-serve << '"'"'SERVE'"'"'
#!/bin/bash
set -a; source /etc/environment; set +a
exec nice -n 10 ionice -c 3 ollama serve
SERVE
    chmod +x /usr/local/bin/ia-serve

    # Limpiar cache pacman — el contenedor no necesita cache
    pacman -Scc --noconfirm 2>/dev/null
    rm -rf /var/cache/pacman/pkg/*
'
ok "ROCm + Ollama instalados y optimizados"

# ══════════════════════════════════════════
# 5. PERFIL NSPAWN + LIMITES DE RECURSOS
# passthrough GPU/NPU + prioridad batch para el contenedor completo
# ══════════════════════════════════════════
info "Aplicando perfil nspawn..."
profile_ia_rocm "$CNAME"

# Nice del proceso nspawn en si mismo (afecta todo lo que corre dentro)
DROPIN_DIR="/etc/systemd/system/systemd-nspawn@${CNAME}.service.d"
mkdir -p "$DROPIN_DIR"
cat >> "$DROPIN_DIR/resources.conf" <<'NICE'
Nice=10
CPUSchedulingPolicy=batch
NICE
systemctl daemon-reload
ok "Perfil + limites de recursos aplicados"

# ══════════════════════════════════════════
# 6. MODELO BASE (OPCIONAL)
# ══════════════════════════════════════════
echo ""
echo "  Modelos recomendados (se descargan dentro del contenedor):"
echo "    1) qwen2.5-coder:7b    Codigo, 4.7GB  (recomendado)"
echo "    2) deepseek-coder-v2   Codigo, 8.9GB"
echo "    3) llama3.1:8b         General, 4.7GB"
echo "    4) ninguno             Descargar luego"
echo ""
read -rp "  Modelo [1-4]: " MODEL_CHOICE

if [[ "$MODEL_CHOICE" =~ ^[123]$ ]]; then
    info "Iniciando contenedor para descargar modelo..."
    sudo machinectl start "$CNAME" 2>/dev/null || true
    sleep 2
fi

case "$MODEL_CHOICE" in
    1) sudo machinectl shell "$CNAME" -- ollama pull qwen2.5-coder:7b ;;
    2) sudo machinectl shell "$CNAME" -- ollama pull deepseek-coder-v2 ;;
    3) sudo machinectl shell "$CNAME" -- ollama pull llama3.1:8b ;;
    4) info "Omitido." ;;
    *) warn "Opcion invalida — omitido" ;;
esac

# ══════════════════════════════════════════
# RESUMEN
# ══════════════════════════════════════════
echo ""
info "Contenedor $CNAME listo"
echo ""
echo "  Host:       power gating GPU/NPU activo (udev + tmpfiles)"
echo "  Contenedor: ROCm aislado, Ollama optimizado para iGPU/laptop"
echo ""
echo "  Iniciar Ollama:"
echo "    sudo machinectl start $CNAME"
echo "    sudo machinectl shell $CNAME -- ia-serve &"
echo ""
echo "  Acceder al contenedor:"
echo "    sudo machinectl shell $CNAME"
echo ""
echo "  Dentro del contenedor:"
echo "    rocminfo    # verificar GPU"
echo "    rocm-smi    # monitor GPU"
echo "    ollama list # modelos"
echo ""
echo "  Desde el host:"
echo "    curl http://localhost:11434/api/tags"
echo ""
warn "Red: VirtualEthernet=no — Ollama escucha en localhost:11434 del host"
