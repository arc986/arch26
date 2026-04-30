# Utilidades compartidas + comandos principales de gestión de contenedores

use ./config.nu *

# ── Guardas ────────────────────────────────────────────────────────────────────

export def ensure_exists [name: string] {
    if not ($"($MACHINES)/($name)" | path exists) {
        error make {msg: $"Contenedor no encontrado: ($name)"}
    }
}

export def ensure_not_exists [name: string] {
    if ($"($MACHINES)/($name)" | path exists) {
        error make {msg: $"Ya existe un contenedor con ese nombre: ($name)"}
    }
}

# ── Ejecución dentro de contenedores ──────────────────────────────────────────

# Ejecuta un comando en un contenedor detenido (setup, instalación de paquetes)
export def run_in [name: string, cmd: string] {
    ^sudo systemd-nspawn -q -D $"($MACHINES)/($name)" --pipe -- sh -c $cmd
}

# Escribe contenido (desde pipe) en un archivo dentro del contenedor
# Uso: "contenido" | write_into "nombre" "/etc/archivo"
export def write_into [name: string, path: string] {
    $in | ^sudo systemd-nspawn -q -D $"($MACHINES)/($name)" --pipe -- sh -c $"cat > ($path)"
}

# Añade contenido (desde pipe) al final de un archivo dentro del contenedor
export def append_into [name: string, path: string] {
    $in | ^sudo systemd-nspawn -q -D $"($MACHINES)/($name)" --pipe -- sh -c $"cat >> ($path)"
}

# Copia un archivo del host al interior del contenedor (vía stdin de nspawn, sin sudo cp)
export def copy_into [name: string, src: string, dest: string] {
    open --raw $src | ^sudo systemd-nspawn -q -D $"($MACHINES)/($name)" --pipe -- sh -c $"cat > ($dest)"
}

# Lee el contenido de un archivo del rootfs del contenedor (funciona aunque esté en ejecución)
export def read_from [name: string, rel_path: string] -> string {
    open $"($MACHINES)/($name)/($rel_path)" | str trim
}

# ── Descargas con caché ────────────────────────────────────────────────────────

export def download_cached [url: string, filename: string] -> string {
    let dir = cache_dir
    if not ($dir | path exists) { mkdir $dir }
    let dest = $"($dir)/($filename)"
    if not ($dest | path exists) {
        print $"  Descargando ($filename)..."
        ^curl -fL --progress-bar -o $dest $url
    }
    $dest
}

# ── Generación de configuración .nspawn ────────────────────────────────────────

# Convierte un perfil (record) al formato INI de systemd-nspawn
export def gen_nspawn_config [name: string, p: record] -> string {
    let u = host_user
    mut lines: list<string> = []

    $lines = $lines | append "[Exec]"
    $lines = $lines | append (if $p.boot { "Boot=yes" } else { "Boot=no" })
    $lines = $lines | append $"PrivateUsers=($p.private_users)"

    $lines = $lines | append ""
    $lines = $lines | append "[Network]"
    if $p.network == "host" {
        $lines = $lines | append "VirtualEthernet=no"
    } else {
        let zone = $p.network | str replace "zone:" ""
        $lines = $lines | append "VirtualEthernet=yes"
        $lines = $lines | append $"Zone=($zone)"
    }
    if not ($p.port | is-empty) {
        $lines = $lines | append $"Port=($p.port)"
    }

    $lines = $lines | append ""
    $lines = $lines | append "[Files]"
    if $p.bind_projects {
        $lines = $lines | append $"Bind=($u.home)/Projects:/root/Projects"
    }
    if $p.bind_dotfiles {
        if ($"($u.home)/.ssh" | path exists) {
            $lines = $lines | append $"BindReadOnly=($u.home)/.ssh:/root/.ssh"
        }
        if ($"($u.home)/.gitconfig" | path exists) {
            $lines = $lines | append $"BindReadOnly=($u.home)/.gitconfig:/root/.gitconfig"
        }
    }
    for dev in $p.devices {
        $lines = $lines | append $"Bind=($dev)"
    }
    if $p.bind_kmsg {
        $lines = $lines | append "Bind=/dev/kmsg"
    }

    let has_caps    = not ($p.caps | is-empty)
    let has_filter  = not ($p.syscall_filter | is-empty)
    let has_devices = not ($p.device_allows | is-empty)
    if $has_caps or $has_filter or $has_devices {
        $lines = $lines | append ""
        $lines = $lines | append "[System]"
        if $has_caps {
            $lines = $lines | append $"Capability=($p.caps | str join ',')"
        }
        if $has_filter {
            $lines = $lines | append $"SystemCallFilter=($p.syscall_filter)"
        }
        for allow in $p.device_allows {
            $lines = $lines | append $"DeviceAllow=($allow)"
        }
    }

    $lines | str join "\n"
}

export def write_nspawn_config [name: string, p: record] {
    gen_nspawn_config $name $p | ^sudo tee $"($NSPAWN_CFG)/($name).nspawn" | ignore
}

# ── Recursos cgroup ────────────────────────────────────────────────────────────

export def apply_resources [name: string, r: record] {
    let dir = $"($SYSTEMD_SVC)/systemd-nspawn@($name).service.d"
    ^sudo mkdir -p $dir
    [
        "[Service]"
        $"CPUWeight=($r.cpu_weight)"
        $"MemoryHigh=($r.mem_high)"
        $"MemoryMax=($r.mem_max)"
        "MemorySwapMax=0"
        $"TasksMax=($r.tasks_max)"
    ] | str join "\n" | ^sudo tee $"($dir)/resources.conf" | ignore
    ^sudo systemctl daemon-reload
}

# ── Ciclo de vida base ─────────────────────────────────────────────────────────

# Crea una base Alpine mínima.
# Todo el setup del rootfs va por systemd-nspawn --pipe (mismo canal que run_in),
# sin escribir directamente al filesystem del host con sudo tee.
export def create_alpine_base [name: string] {
    ensure_not_exists $name
    let tarball = $"alpine-minirootfs-($ALPINE_VER).0-x86_64.tar.gz"
    let url = $"https://dl-cdn.alpinelinux.org/alpine/v($ALPINE_VER)/releases/x86_64/($tarball)"
    let cached = download_cached $url $tarball

    ^sudo btrfs subvolume create $"($MACHINES)/($name)"
    ^sudo tar -xzf $cached -C $"($MACHINES)/($name)"

    # Configuración via write_into: sin sudo tee en paths del host
    $name | write_into $name "/etc/hostname"
    "nameserver 1.1.1.1\nnameserver 8.8.8.8" | write_into $name "/etc/resolv.conf"
    [
        $"https://dl-cdn.alpinelinux.org/alpine/v($ALPINE_VER)/main"
        $"https://dl-cdn.alpinelinux.org/alpine/v($ALPINE_VER)/community"
    ] | str join "\n" | write_into $name "/etc/apk/repositories"
}

# Clona un template como snapshot Btrfs (operación instantánea)
export def clone_template [template: string, name: string] {
    ensure_exists $template
    ensure_not_exists $name
    ^sudo btrfs subvolume snapshot $"($MACHINES)/($template)" $"($MACHINES)/($name)"
}

# Elimina un contenedor y toda su configuración asociada
export def cleanup_container [name: string] {
    ensure_exists $name
    try { ^sudo machinectl terminate $name } catch { }
    ^sudo btrfs subvolume delete $"($MACHINES)/($name)"
    ^sudo rm -f $"($NSPAWN_CFG)/($name).nspawn"
    ^sudo rm -rf $"($SYSTEMD_SVC)/systemd-nspawn@($name).service.d"
    ^sudo systemctl daemon-reload
}

# ── Comandos exportados ────────────────────────────────────────────────────────

# Lista todos los contenedores con su estado y RAM usada
export def "nspawn list" [filter?: string] {
    let running = try {
        ^sudo machinectl list --no-legend
        | lines
        | where { ($in | is-not-empty) and not ($in | str starts-with "0 machines") }
        | each { |l| $l | str trim | split row " " | first }
    } catch { [] }

    ls $MACHINES
    | where type == "dir"
    | get name
    | each { |f| $f | path basename }
    | where { |name| if ($filter | is-empty) { true } else { $name | str starts-with $filter } }
    | each { |name|
        let state = if ($running | any { $in == $name }) { "running" } else { "stopped" }
        let ram = if $state == "running" {
            let cg = $"/sys/fs/cgroup/machine.slice/systemd-nspawn@($name).service/memory.current"
            if ($cg | path exists) {
                let bytes = open $cg | str trim | into int
                let mb = $bytes / 1048576 | math round
                $"($mb)M"
            } else { "-" }
        } else { "-" }
        {name: $name, state: $state, ram: $ram}
    }
}

export def "nspawn start" [name: string] {
    ensure_exists $name
    ^sudo machinectl start $name
    print $"[+] Iniciado: ($name)"
}

export def "nspawn stop" [name: string] {
    ^sudo machinectl stop $name
    print $"[-] Detenido: ($name)"
}

export def "nspawn shell" [name: string] {
    ensure_exists $name
    ^sudo machinectl shell $name
}

export def "nspawn logs" [
    name: string
    --lines (-n): int = 50
] {
    ^sudo journalctl -M $name -n $lines --no-pager
}

export def "nspawn status" [name?: string] {
    if ($name | is-empty) {
        ^sudo machinectl list
    } else {
        ^sudo machinectl status $name
    }
}

export def "nspawn resources" [] {
    ^sudo systemd-cgtop -M
}

export def "nspawn snapshot" [name: string] {
    ensure_exists $name
    let ts = date now | format date "%Y%m%d-%H%M%S"
    let snap = $"($name)-snap-($ts)"
    ^sudo btrfs subvolume snapshot $"($MACHINES)/($name)" $"($MACHINES)/($snap)"
    print $"Snapshot: ($snap)"
}

# Lanza una instancia efímera (los cambios se descartan al cerrar)
export def "nspawn ephemeral" [name: string] {
    ensure_exists $name
    ^sudo systemd-nspawn -x -D $"($MACHINES)/($name)"
}

export def "nspawn delete" [name: string] {
    print $"Eliminando: ($name)"
    cleanup_container $name
    print "Listo."
}
