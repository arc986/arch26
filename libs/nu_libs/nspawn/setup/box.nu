# Contenedor Alpine genérico con red y opciones configurables
# Opcionalmente incluye Podman para correr contenedores dentro del contenedor

use ../config.nu *
use ../core.nu [
    ensure_not_exists, run_in,
    create_alpine_base, write_nspawn_config, apply_resources
]

# Crea un contenedor Alpine genérico con las opciones indicadas
export def "nspawn create box" [
    name: string                    # nombre del contenedor
    --network: string = "isolated"  # isolated | host
    --podman                        # habilita Podman dentro del contenedor
    --port: string = ""             # reenvío de puerto (ej: tcp:8080:80)
] {
    ensure_not_exists $name

    create_alpine_base $name
    run_in $name "apk add --no-cache bash curl git"

    let net = if $network == "host" { "host" } else { "zone:containers" }
    mut p   = $PROFILES.box | merge {network: $net, port: $port}

    if $podman {
        $p = $p | merge {
            caps:           ["CAP_SETUID", "CAP_SETGID", "CAP_CHOWN", "CAP_FOWNER", "CAP_DAC_OVERRIDE"]
            syscall_filter: "~@obsolete ~@clock ~@keyring bpf"
            devices:        ["/dev/fuse"]
            device_allows:  ["/dev/fuse rwm"]
        }
        run_in $name "apk add --no-cache podman fuse-overlayfs slirp4netns"
        [
            "[storage]"
            "driver = \"overlay\""
            "[storage.options.overlay]"
            "mount_program = \"/usr/bin/fuse-overlayfs\""
        ] | str join "\n" | ^sudo tee $"($MACHINES)/($name)/etc/containers/storage.conf" | ignore
    }

    write_nspawn_config $name $p
    apply_resources $name $PROFILES.box.resources

    print $"\n[+] ($name) listo"
    print $"  nspawn start ($name)  →  nspawn shell ($name)"
}
