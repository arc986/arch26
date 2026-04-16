#!/bin/bash
# Arch Linux — Podman + Distrobox (rootless)
# Post archlinux2.md (subuid/subgid ya configurados en base)
set -e

USERNAME=$(getent passwd 1000 | cut -d: -f1)
HOME_DIR="/home/$USERNAME"

# --- Instalar ---
sudo pacman -S --needed podman podman-compose distrobox slirp4netns

# --- Storage rootless: btrfs nativo ---
sudo -u "$USERNAME" mkdir -p "$HOME_DIR/.config/containers"
cat > "$HOME_DIR/.config/containers/storage.conf" <<EOF
[storage]
driver = "btrfs"
graphroot = "$HOME_DIR/.local/share/containers/storage"
EOF

# --- Registries v2 ---
cat > "$HOME_DIR/.config/containers/registries.conf" <<'EOF'
unqualified-search-registries = ["docker.io", "ghcr.io", "quay.io"]
EOF

# --- Permisos ---
chown -R "$USERNAME:users" "$HOME_DIR/.config/containers"

# --- Habilitar socket podman (rootless, como usuario) ---
sudo -u "$USERNAME" bash -c 'systemctl --user enable podman.socket'

echo ""
echo "=== Podman + Distrobox configurado ==="
echo ""
echo "Podman:"
echo "  podman run --rm -it alpine sh          → Contenedor rapido"
echo "  podman ps -a                            → Ver contenedores"
echo "  podman images                           → Ver imagenes"
echo "  podman-compose up -d                    → Levantar compose"
echo ""
echo "Distrobox:"
echo "  distrobox create -n dev -i ubuntu:24.04 → Crear entorno"
echo "  distrobox enter dev                     → Entrar"
echo "  distrobox export --app firefox          → Exportar app al host"
echo "  distrobox list                          → Ver entornos"
echo "  distrobox rm dev                        → Eliminar"
echo ""
echo "Socket se activa en el proximo login."
