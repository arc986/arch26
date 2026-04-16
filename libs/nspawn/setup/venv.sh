#!/bin/bash
# nspawn — Entornos desarrollo Alpine
# Uso: venv.sh [go|python|web|rust|all]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/profiles.sh"

TEMPLATE=".venv-template"

CHOICE="${1:-}"
if [ -z "$CHOICE" ]; then
  cat <<MSG
Entorno de desarrollo:
  1) Go        2) Python
  3) Web       4) Rust
  5) Todos
MSG
  read -rp "Opcion [1/2/3/4/5]: " CHOICE
fi

# Normalizar: nombre → numero
case "$CHOICE" in
  go) CHOICE=1 ;; python) CHOICE=2 ;; web) CHOICE=3 ;; rust) CHOICE=4 ;; all) CHOICE=5 ;;
esac

if ! container_exists "$TEMPLATE"; then
  create_alpine_base "$TEMPLATE"
  run_in "$TEMPLATE" 'apk add --no-cache curl build-base ca-certificates; rm -rf /var/cache/apk/*'
fi

# Pre-cachear rustup si se va a necesitar
if [ "$CHOICE" = "4" ] || [ "$CHOICE" = "5" ]; then
  init_cache
  cache_download "https://sh.rustup.rs" "rustup-init.sh"
fi

setup_go()     { clone_template "$TEMPLATE" venv-go;     profile_venv venv-go;     run_in venv-go     'apk add --no-cache go; echo "export PATH=\$PATH:\$HOME/go/bin" >> /root/.profile; echo "export CGO_ENABLED=0" >> /root/.profile; rm -rf /var/cache/apk/*'; }
setup_python() { clone_template "$TEMPLATE" venv-python;  profile_venv venv-python;  run_in venv-python  'apk add --no-cache python3 py3-pip python3-dev; echo "export PYTHONDONTWRITEBYTECODE=1" >> /root/.profile; rm -rf /var/cache/apk/*'; }
setup_web()    { clone_template "$TEMPLATE" venv-web;     profile_venv venv-web;     run_in venv-web     'apk add --no-cache nodejs npm; npm install -g typescript vue-tsc @vue/cli pnpm; npm cache clean --force; echo "export NODE_OPTIONS=--max-old-space-size=512" >> /root/.profile; rm -rf /var/cache/apk/* /tmp/* /root/.npm'; }
setup_rust()   {
  clone_template "$TEMPLATE" venv-rust; profile_venv venv-rust
  sudo cp "$CACHE_DIR/rustup-init.sh" "$MACHINES/venv-rust/tmp/rustup-init.sh"
  run_in venv-rust 'sh /tmp/rustup-init.sh -y --default-toolchain stable --profile minimal --no-modify-path; echo "source /root/.cargo/env" >> /root/.profile; rm -rf /tmp/*'
}

get_user; sudo -u "$USERNAME" mkdir -p "$HOME_DIR/Projects"

case "$CHOICE" in
  1) setup_go ;; 2) setup_python ;; 3) setup_web ;; 4) setup_rust ;;
  5) setup_go; setup_python; setup_web; setup_rust ;;
  *) echo "Invalido"; exit 1 ;;
esac

cat <<MSG

=== Entornos creados ===
Entrar:    sudo machinectl shell venv-{go,python,web,rust}
Projects:  ~/Projects (compartido)
MSG
