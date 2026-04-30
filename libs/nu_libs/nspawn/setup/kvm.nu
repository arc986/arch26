# Servidor de virtualización KVM dentro de un contenedor Alpine
# Cockpit web (puerto 9090) para gestionar VMs desde el navegador

use ../config.nu *
use ../core.nu [
    ensure_not_exists, run_in,
    create_alpine_base, write_nspawn_config, apply_resources
]

const KVM_NAME = "kvm-server"

# Crea el servidor KVM con libvirt y QEMU
# Después de crearlo: abre http://<IP-contenedor>:9090 (user: root / pass: kvm)
export def "nspawn create kvm" [
    --no-cockpit  # omite la instalación de Cockpit (solo virsh/SSH)
] {
    ensure_not_exists $KVM_NAME

    if not ("/dev/kvm" | path exists) {
        error make {msg: "/dev/kvm no encontrado. Verifica que KVM esté habilitado en tu CPU/BIOS."}
    }

    print "Creando base Alpine para KVM..."
    create_alpine_base $KVM_NAME

    # Paquetes de virtualización disponibles en Alpine Community
    run_in $KVM_NAME "apk add --no-cache qemu-system-x86_64 qemu-img libvirt libvirt-daemon dnsmasq bridge-utils ovmf swtpm openssh"
    run_in $KVM_NAME "rc-update add libvirtd"
    run_in $KVM_NAME "rc-update add sshd"

    # Contraseña de acceso SSH
    run_in $KVM_NAME "echo 'root:kvm' | chpasswd"
    run_in $KVM_NAME "sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config"

    if not $no_cockpit {
        run_in $KVM_NAME "apk add --no-cache cockpit cockpit-machines"
        run_in $KVM_NAME "rc-update add cockpit"
    }

    write_nspawn_config $KVM_NAME $PROFILES.kvm
    apply_resources $KVM_NAME $PROFILES.kvm.resources

    ^sudo machinectl start $KVM_NAME
    sleep 2sec

    let ip = try {
        ^sudo machinectl status $KVM_NAME
        | lines
        | where { $in | str contains "Address:" }
        | first
        | str replace --regex '.*Address:\s*' ''
        | str trim | split row " " | first
    } catch { "<IP-contenedor>" }

    print $"\n=== KVM Server listo ==="
    if not $no_cockpit {
        print $"  Web:   http://($ip):9090  (root / kvm)"
    }
    print $"  SSH:   ssh root@($ip)  (pass: kvm)"
    print $"  ISOs:  ($MACHINES)/($KVM_NAME)/var/lib/libvirt/images/"
}
