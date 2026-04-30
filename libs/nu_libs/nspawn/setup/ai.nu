# Contenedor IA — Alpine + ROCm + Ollama para GPU/NPU AMD
#
# Principio: todo dentro del contenedor, NADA instalado en el host.
# Base: Alpine edge/testing (descargada como tarball, sin herramientas extra).
# Hardware objetivo: Ryzen AI 7 350 — RDNA 3.5 (gfx1151) + XDNA2 NPU.
# Red: zone:ai aislada, solo port 11434 expuesto al host.

use ../config.nu *
use ../core.nu [
    ensure_not_exists, run_in, write_into, append_into,
    create_alpine_base, write_nspawn_config, apply_resources
]

const AI_NAME = "ia-rocm"

def alpine_repos [] -> string {
    [
        $"https://dl-cdn.alpinelinux.org/alpine/v($ALPINE_VER)/main"
        $"https://dl-cdn.alpinelinux.org/alpine/v($ALPINE_VER)/community"
        "@edge https://dl-cdn.alpinelinux.org/alpine/edge/main"
        "@edgecommunity https://dl-cdn.alpinelinux.org/alpine/edge/community"
        "@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing"
    ] | str join "\n"
}

# Crea el contenedor IA con ROCm y Ollama sobre Alpine
export def "nspawn create ai" [] {
    ensure_not_exists $AI_NAME

    # Detectar solo el hardware presente — no enlazar lo que no existe
    let devices       = ["/dev/dri", "/dev/kfd", "/dev/accel"] | where { |it| $it | path exists }
    let device_allows = build_device_allows $devices
    if ($devices | is-empty) {
        error make {msg: "No se detectaron /dev/dri, /dev/kfd ni /dev/accel. ¿Están cargados los drivers AMD?"}
    }
    print $"Hardware detectado: ($devices | str join ', ')"

    # Reglas udev de energía en el host — solo 2-3 archivos pequeños, bajo consumo
    setup_host_udev $devices

    # ── Base Alpine ──────────────────────────────────────────────────────────
    print "Creando base Alpine..."
    create_alpine_base $AI_NAME

    # Repositorios: vía write_into (systemd-nspawn --pipe), sin sudo tee al host
    alpine_repos | write_into $AI_NAME "/etc/apk/repositories"

    # ── ROCm + Ollama ────────────────────────────────────────────────────────
    print "Instalando ROCm y Ollama (puede tardar)..."
    run_in $AI_NAME "apk update"
    run_in $AI_NAME "apk add --no-cache gcompat libstdc++ rocm-opencl@testing rocminfo@testing ollama@testing"

    # ── Entorno optimizado para RDNA 3.5 (gfx1151) + XDNA2 ─────────────────
    [
        "export ROC_ENABLE_PRE_VEGA=0"        # omite código de GPU pre-Vega
        "export HSA_ENABLE_SDMA=0"            # más estable en laptops AMD
        "export HSA_OVERRIDE_GFX_VERSION=11.0.0"  # fuerza reconocimiento gfx1151 en ROCm
        "export OLLAMA_NUM_GPU=999"            # offload máximo a la GPU
        "export OLLAMA_MAX_LOADED_MODELS=1"   # conserva VRAM (laptop)
        "export OLLAMA_KEEP_ALIVE=5m"         # libera VRAM tras 5 min inactiva
        "export OLLAMA_FLASH_ATTENTION=1"     # Flash Attention para RDNA3
        "export OLLAMA_NUM_PARALLEL=1"        # inferencia secuencial (eficiencia energética)
        "export OLLAMA_HOST=0.0.0.0:11434"
    ] | str join "\n" | append_into $AI_NAME "/etc/profile"

    # ── ia-serve ─────────────────────────────────────────────────────────────
    # nice -n 10 + ionice -c 3: Ollama en segundo plano sin degradar batería ni disco
    run_in $AI_NAME "mkdir -p /usr/local/bin"
    "#!/bin/sh\nexec nice -n 10 ionice -c 3 ollama serve\n" | write_into $AI_NAME "/usr/local/bin/ia-serve"
    run_in $AI_NAME "chmod +x /usr/local/bin/ia-serve"

    # ── Configuración nspawn + cgroup ────────────────────────────────────────
    let p = $PROFILES.ai | merge {devices: $devices, device_allows: $device_allows}
    write_nspawn_config $AI_NAME $p
    apply_resources $AI_NAME $PROFILES.ai.resources

    print $"\n=== IA Container listo ==="
    print $"  1. nspawn start ($AI_NAME)"
    print "  2. (dentro del contenedor) ia-serve"
    print "  3. ollama pull qwen2.5-coder:7b   ← recomendado para código"
    print "     ollama pull llama3.1:8b        ← uso general"
    print "  API: http://localhost:11434  (reenviado desde zone:ai)"
}

def build_device_allows [devices: list<string>] {
    mut allows: list<string> = []
    if ($devices | any { |it| $it == "/dev/dri"   }) { $allows = ($allows | append "char-drm rwm") };
    if ($devices | any { |it| $it == "/dev/kfd"   }) { $allows = ($allows | append "/dev/kfd rwm") };
    if ($devices | any { |it| $it == "/dev/accel" }) { $allows = ($allows | append "/dev/accel rwm") };
    $allows
}

# Escribe reglas udev en el HOST para gestión de energía GPU/NPU
# Son 2-3 archivos pequeños en /etc/udev/rules.d y /etc/tmpfiles.d
# Beneficio permanente: la GPU/NPU bajan de potencia cuando están inactivas
def setup_host_udev [devices: list<string>] {
    print "Configurando udev de energía en el host..."

    if ($devices | any { |it| $it == "/dev/dri" }) {
        # DPM auto: la GPU escala su consumo según carga (crítico para batería)
        "ACTION==\"add\", SUBSYSTEM==\"pci\", ATTRS{vendor}==\"0x1002\", ATTR{power/control}=\"auto\"\n"
        | ^sudo tee /etc/udev/rules.d/71-amdgpu-pm.rules | ignore
        # tmpfiles asegura el DPM level tras cada reboot
        "w /sys/class/drm/card0/device/power_dpm_force_performance_level - - - - auto\n"
        | ^sudo tee /etc/tmpfiles.d/amdgpu-pm.conf | ignore
    }

    if ($devices | any { |it| $it == "/dev/accel" }) {
        # XDNA2 NPU power gating: el NPU se apaga cuando no hay tareas de IA
        "ACTION==\"add\", SUBSYSTEM==\"misc\", KERNEL==\"accel*\", ATTR{power/control}=\"auto\"\n"
        | ^sudo tee /etc/udev/rules.d/70-amdxdna.rules | ignore
    }

    ^sudo udevadm control --reload-rules
    ^sudo udevadm trigger
}
