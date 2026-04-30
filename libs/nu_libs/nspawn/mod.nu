# nspawn — gestión de contenedores systemd-nspawn ultraligeros
#
# Uso básico:
#   use libs/nu_libs/nspawn/mod.nu *
#   nspawn list
#   nspawn create venv go
#   nspawn start venv-go
#   nspawn shell venv-go
#
# Permisos necesarios: nspawn setup-permisos --write

export use ./config.nu *
export use ./core.nu *
export use ./setup/mod.nu *

# Muestra (y opcionalmente instala) las reglas sudo necesarias para operar sin contraseña
export def "nspawn setup-permisos" [
    --write (-w)  # escribe /etc/sudoers.d/nspawn  (requiere sudo activo)
] {
    let u = $env.USER
    let rules = [
        "# nspawn — permisos para systemd-nspawn container management"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/btrfs subvolume *"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/btrfs property *"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/systemd-nspawn *"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/machinectl *"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/systemctl daemon-reload"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/systemctl start systemd-nspawn@*"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop systemd-nspawn@*"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/journalctl *"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/tee ($NSPAWN_CFG)/*"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/tee ($SYSTEMD_SVC)/systemd-nspawn@*.service.d/*"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/mkdir -p ($SYSTEMD_SVC)/systemd-nspawn@*.service.d"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/mkdir -p ($MACHINES)/*"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/tar -xzf * -C ($MACHINES)/*"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/cp * ($MACHINES)/*"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/rm -f ($NSPAWN_CFG)/*"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/rm -rf ($SYSTEMD_SVC)/systemd-nspawn@*.service.d"
        "# Contenedores IA (udev + tmpfiles):"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/udev/rules.d/*"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/tmpfiles.d/*"
        $"($u) ALL=(ALL) NOPASSWD: /usr/bin/udevadm *"
    ] | str join "\n"

    print $rules

    if $write {
        $rules | ^sudo tee /etc/sudoers.d/nspawn | ignore
        ^sudo chmod 440 /etc/sudoers.d/nspawn
        ^sudo visudo -c -f /etc/sudoers.d/nspawn
        print "\n[+] Instalado en /etc/sudoers.d/nspawn"
    } else {
        print "\nPara aplicar:  nspawn setup-permisos --write"
    }
}
