#!/bin/bash
# Arch Linux — Distrobox entornos de desarrollo
# Post podman.sh
set -e

echo "Selecciona entorno:"
echo "  1) Go"
echo "  2) Python"
echo "  3) Web (Vue/TS/Node)"
echo "  4) Rust"
echo "  5) Todos"
read -rp "Opcion [1/2/3/4/5]: " DEV_CHOICE

IMAGE="docker.io/library/alpine:latest"

# --- Go ---
setup_go() {
  distrobox create -n dev-go -i "$IMAGE" --yes
  distrobox enter dev-go -- sh -c '
    sudo apk add --no-cache curl build-base go
    sudo rm -rf /var/cache/apk/* /tmp/*
    echo "export PATH=\$PATH:\$HOME/go/bin" >> ~/.bashrc
    echo "export GOFLAGS=-trimpath" >> ~/.bashrc
    echo "export CGO_ENABLED=0" >> ~/.bashrc
    echo "Go: $(go version)"
  '
  echo "dev-go listo"
}

# --- Python ---
setup_python() {
  distrobox create -n dev-python -i "$IMAGE" --yes
  distrobox enter dev-python -- sh -c '
    sudo apk add --no-cache curl build-base python3 py3-pip python3-dev
    sudo rm -rf /var/cache/apk/* /tmp/*
    echo "export PATH=\$PATH:\$HOME/.local/bin" >> ~/.bashrc
    echo "export PYTHONDONTWRITEBYTECODE=1" >> ~/.bashrc
    echo "export PIP_NO_CACHE_DIR=1" >> ~/.bashrc
    echo "Python: $(python3 --version)"
  '
  echo "dev-python listo"
}

# --- Web (Vue/TS/Node) ---
setup_web() {
  distrobox create -n dev-web -i "$IMAGE" --yes
  distrobox enter dev-web -- sh -c '
    sudo apk add --no-cache curl build-base nodejs npm
    npm install -g --prefer-offline typescript vue-tsc @vue/cli pnpm
    npm cache clean --force
    sudo rm -rf /var/cache/apk/* /tmp/* /root/.npm
    echo "export NODE_OPTIONS=--max-old-space-size=512" >> ~/.bashrc
    echo "Node: $(node --version)"
  '
  echo "dev-web listo"
}

# --- Rust ---
setup_rust() {
  distrobox create -n dev-rust -i "$IMAGE" --yes
  distrobox enter dev-rust -- sh -c '
    sudo apk add --no-cache curl build-base
    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal --no-modify-path
    echo "source \$HOME/.cargo/env" >> ~/.bashrc
    source "$HOME/.cargo/env"
    echo "export CARGO_INCREMENTAL=0" >> ~/.bashrc
    echo "Rust: $(rustc --version)"
  '
  echo "dev-rust listo"
}

case "$DEV_CHOICE" in
  1) setup_go ;;
  2) setup_python ;;
  3) setup_web ;;
  4) setup_rust ;;
  5) setup_go; setup_python; setup_web; setup_rust ;;
  *) echo "Opcion invalida"; exit 1 ;;
esac

echo ""
echo "=== Entornos de desarrollo ==="
echo ""
echo "Flujo de trabajo:"
echo "  1. Abrir Zed en host"
echo "  2. Terminal: distrobox enter dev-X"
echo "  3. Desarrollar (archivos en ~/Projects del host)"
echo ""
echo "Exportar herramientas al host:"
echo "  distrobox enter dev-go -- distrobox-export --bin /usr/local/go/bin/go --export-path ~/.local/bin"
echo "  distrobox enter dev-web -- distrobox-export --bin \$(which node) --export-path ~/.local/bin"
echo ""
echo "Zed detecta LSPs dentro del distrobox si ejecutas zed desde dentro:"
echo "  distrobox enter dev-go -- zed ~/Projects/mi-proyecto"
