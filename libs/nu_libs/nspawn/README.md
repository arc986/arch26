Estructura creada: libs/nu_libs/nspawn/

mod.nu           ← entrada del módulo, re-exporta todo + nspawn setup-permisos
config.nu        ← capa de datos: constantes + PROFILES (todos los perfiles como records)
core.nu          ← utilidades compartidas + todos los comandos nspawn (list/start/stop/shell/...)
setup/
  venv.nu        ← nspawn create venv [go|python|web|rust|all]
  k3s.nu         ← nspawn create k3s <cluster> [--workers N]
  kvm.nu         ← nspawn create kvm [--no-cockpit]
  box.nu         ← nspawn create box <name> [--distro] [--network] [--podman] [--port]
  ai.nu          ← nspawn create ai
  mod.nu         ← re-exporta todos los create
Cómo usar:


use libs/nu_libs/nspawn/mod.nu *
nspawn setup-permisos --write   # instala /etc/sudoers.d/nspawn
nspawn list
nspawn create venv go
nspawn start venv-go
