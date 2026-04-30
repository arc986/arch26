# Cluster Kubernetes ligero con k3s dentro de contenedores Alpine
# Master + N workers, cada uno en su propia zona de red aislada

use ../config.nu *
use ../core.nu [
    ensure_not_exists, run_in, read_from, download_cached,
    create_alpine_base, clone_template,
    write_nspawn_config, apply_resources
]

const K3S_TMPL  = ".k3s-template"
const K3S_FLAGS = "--disable traefik,servicelb,local-storage,metrics-server --flannel-backend=host-gw"

# Template Alpine con dependencias de red para k3s
def k3s_template [] {
    if ($"($MACHINES)/($K3S_TMPL)" | path exists) { return }
    print "Creando template Alpine para k3s..."
    create_alpine_base $K3S_TMPL
    run_in $K3S_TMPL "apk add --no-cache curl iptables ip6tables wireguard-tools ca-certificates"
    print "[+] Template listo"
}

# IP del contenedor según machinectl status
def machine_ip [name: string] {
    ^sudo machinectl status $name
    | lines
    | where { $in | str contains "Address:" }
    | first
    | str replace --regex '.*Address:\s*' ''
    | str trim
    | split row " "
    | first
}

# Espera hasta que k3s genere el token (indica que el servidor está listo)
def wait_for_k3s [master: string] {
    let token_path = $"($MACHINES)/($master)/var/lib/rancher/k3s/server/node-token"
    mut attempts = 0
    print -n "  Esperando k3s master"
    while (not ($token_path | path exists)) and $attempts < 40 {
        print -n "."
        sleep 3sec
        $attempts = $attempts + 1
    }
    print ""
    if $attempts >= 40 {
        error make {msg: "Timeout: el master k3s no arrancó en el tiempo esperado"}
    }
}

# Crea un cluster k3s con un master y N workers
export def "nspawn create k3s" [
    cluster: string       # nombre del cluster (ej: mi-lab)
    --workers: int = 2    # número de nodos worker
] {
    let master  = $"k3s-($cluster)-master"
    let zone    = $"zone:k3s-($cluster)"
    let k3s_sh  = download_cached "https://get.k3s.io" "k3s-install.sh"

    k3s_template

    # ── Master ──────────────────────────────────────────────────────────────
    print $"Creando master: ($master)"
    clone_template $K3S_TMPL $master

    let master_profile = $PROFILES.k3s_master | merge {network: $zone}
    write_nspawn_config $master $master_profile
    apply_resources $master $PROFILES.k3s_master.resources

    ^sudo cp $k3s_sh $"($MACHINES)/($master)/tmp/k3s-install.sh"
    run_in $master $"INSTALL_K3S_SKIP_START=true INSTALL_K3S_EXEC='server ($K3S_FLAGS)' sh /tmp/k3s-install.sh"
    ^sudo machinectl start $master

    wait_for_k3s $master
    let token     = read_from $master "var/lib/rancher/k3s/server/node-token"
    let master_ip = machine_ip $master
    print $"  Master IP: ($master_ip)"

    # ── Workers ─────────────────────────────────────────────────────────────
    for i in 1..($workers) {
        let worker = $"k3s-($cluster)-worker($i)"
        print $"Creando worker: ($worker)"
        clone_template $K3S_TMPL $worker

        let worker_profile = $PROFILES.k3s_worker | merge {network: $zone}
        write_nspawn_config $worker $worker_profile
        apply_resources $worker $PROFILES.k3s_worker.resources

        ^sudo cp $k3s_sh $"($MACHINES)/($worker)/tmp/k3s-install.sh"
        run_in $worker $"INSTALL_K3S_SKIP_START=true INSTALL_K3S_URL=https://($master_ip):6443 INSTALL_K3S_TOKEN=($token) sh /tmp/k3s-install.sh"
        ^sudo machinectl start $worker
    }

    print $"\nCluster '($cluster)' listo  →  ($workers) workers"
    print $"  kubectl: sudo machinectl shell ($master) -- k3s kubectl get nodes"
    print $"  Parar todo: nspawn list k3s-($cluster) | each { |c| nspawn stop ($c.name) }"
}
