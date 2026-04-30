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

# Gestión ultraligera de contenedores systemd-nspawn
export def nspawn [] {
    help nspawn
}


