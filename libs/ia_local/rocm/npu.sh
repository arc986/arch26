#!/bin/bash
# ia_local/rocm/npu.sh — XDNA2 NPU: validacion + setup + optimizaciones
# Hardware: Ryzen AI 7 350 (Strix Point) — XDNA2 50 TOPS
# Optimiza: carga automatica, power gating, permisos, sin degradacion
# Requiere: linux-zen 6.9+, ejecutar como root
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
# 1. VALIDAR HARDWARE NPU
# ══════════════════════════════════════════
info "Validando NPU XDNA2..."

KVER=$(uname -r)
ok "Kernel: $KVER"

KVER_MAJOR=$(echo "$KVER" | cut -d. -f1)
KVER_MINOR=$(echo "$KVER" | cut -d. -f2 | cut -d- -f1)
if [[ "$KVER_MAJOR" -lt 6 ]] || [[ "$KVER_MAJOR" -eq 6 && "$KVER_MINOR" -lt 9 ]]; then
    warn "Kernel $KVER < 6.9 — amdxdna requiere 6.9+"
    warn "Instala: pacman -S linux-zen linux-zen-headers"
fi

NPU_OK=false
if modinfo amdxdna &>/dev/null; then
    ok "amdxdna: modulo disponible"
    if modprobe amdxdna 2>/dev/null; then
        ok "amdxdna: cargado"
        NPU_OK=true
    else
        warn "amdxdna: existe pero no cargo — puede requerir reinicio"
    fi
else
    warn "amdxdna: no encontrado en kernel $KVER"
fi

if [ -e /dev/accel/accel0 ]; then
    ok "NPU: /dev/accel/accel0 presente"
    ls -la /dev/accel/accel0
    NPU_OK=true
else
    warn "NPU: /dev/accel/accel0 no encontrado"
    [ "$NPU_OK" = false ] && warn "NPU no accesible — puede requerir reinicio despues del setup"
fi

# Power management actual del NPU
NPU_PCI=$(find /sys/bus/pci/drivers/amdxdna -maxdepth 1 -name "0000:*" 2>/dev/null | head -1 || true)
if [ -n "$NPU_PCI" ]; then
    PM_STATE=$(cat "$NPU_PCI/power/control" 2>/dev/null || echo "desconocido")
    ok "NPU PCI: ${NPU_PCI##*/} — power/control: $PM_STATE"
fi

echo ""
info "Estado NPU: $([ "$NPU_OK" = true ] && echo 'OPERACIONAL' || echo 'NO OPERACIONAL / pendiente de setup')"
echo ""

# ══════════════════════════════════════════
# 2. PREGUNTAR SI CONFIGURAR
# ══════════════════════════════════════════
read -rp "  Configurar entorno NPU ahora? [s/N]: " DO_SETUP
[[ "$DO_SETUP" == "s" ]] || { info "Setup omitido."; exit 0; }

# ══════════════════════════════════════════
# 3. CARGA AUTOMATICA DEL MODULO
# El NPU no se activa si amdxdna no esta cargado al arrancar.
# Sin esto el /dev/accel/accel0 no existe y el NPU esta inactivo.
# ══════════════════════════════════════════
info "Configurando carga automatica de amdxdna..."

echo "amdxdna" > /etc/modules-load.d/amdxdna.conf
ok "amdxdna: se cargara en cada arranque (/etc/modules-load.d/amdxdna.conf)"

# ══════════════════════════════════════════
# 4. UDEV — PERMISOS + POWER GATING NPU
# power/control=auto: NPU hace power gate cuando esta idle
# Sin esto, el NPU consume energia aunque no haya workload activo.
# ══════════════════════════════════════════
info "Configurando udev NPU (permisos + power gating)..."

cat > /etc/udev/rules.d/70-amdxdna.rules <<'UDEV'
# XDNA2 NPU — Ryzen AI 7 350 (Strix Point)

# Permisos: /dev/accel/accel0 accesible por grupo render sin root
SUBSYSTEM=="accel", GROUP="render", MODE="0660"

# Power gating: el NPU se apaga cuando no hay workload activo
# Critico para laptop — sin esto el NPU consume aunque este idle
DRIVER=="amdxdna", ATTR{power/control}="auto"
UDEV

udevadm control --reload-rules
udevadm trigger --subsystem-match=accel 2>/dev/null || true

# Aplicar power gating ahora si el dispositivo ya esta enlazado
if [ -n "$NPU_PCI" ]; then
    echo "auto" > "$NPU_PCI/power/control" 2>/dev/null && \
        ok "NPU power gating → auto (aplicado ahora)" || \
        warn "No se pudo aplicar power gating ahora (se aplicara tras reinicio)"
fi
ok "Reglas udev NPU escritas"

# ══════════════════════════════════════════
# 5. GRUPO render
# ══════════════════════════════════════════
id -nG "$USERNAME" | grep -qw render \
    && ok "Usuario $USERNAME ya esta en grupo render" \
    || { usermod -aG render "$USERNAME"; ok "Usuario $USERNAME → grupo render"; }

# ══════════════════════════════════════════
# 6. VARIABLES DE ENTORNO NPU
# ══════════════════════════════════════════
info "Configurando variables de entorno NPU..."

grep -q "XLNX_ENABLE_DEVICES" /etc/environment 2>/dev/null || cat >> /etc/environment <<'ENVVARS'

# NPU XDNA2 — Ryzen AI 7 350 (Strix Point)
# Habilita todos los dispositivos XDNA disponibles
XLNX_ENABLE_DEVICES=all
# Desactiva DMA engine auxiliar — mejora estabilidad en Linux
XLNX_SKIP_CDMA=1
ENVVARS
ok "Variables NPU escritas en /etc/environment"

# ══════════════════════════════════════════
# 7. XRT — NOTA
# XRT (Xilinx Runtime) no esta en repos oficiales de Arch.
# El NPU XDNA2 es funcional via amdxdna kernel driver sin XRT.
# ══════════════════════════════════════════
warn "XRT no disponible en repos oficiales — NPU usa amdxdna kernel driver directo"

# ══════════════════════════════════════════
# RESUMEN
# ══════════════════════════════════════════
echo ""
info "Setup NPU completado"
echo ""
echo "  Carga automatica: /etc/modules-load.d/amdxdna.conf"
echo "  Power gating:     auto (NPU se apaga cuando no hay workload)"
echo "  Permisos:         /dev/accel/accel0 accesible por grupo render"
echo ""
echo "  Verificar carga:  lsmod | grep amdxdna"
echo "  Verificar device: ls -la /dev/accel/"
echo "  Verificar PM:     cat /sys/bus/pci/drivers/amdxdna/*/power/control"
echo ""
warn "REINICIA para aplicar modulo en arranque, grupo render y variables de entorno"
