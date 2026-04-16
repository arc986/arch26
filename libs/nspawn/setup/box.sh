#!/bin/bash
# nspawn — Contenedor generico (con o sin Podman)
# Uso: box.sh [nombre] [alpine|arch|debian]
# No instala nada en el host automaticamente
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/profiles.sh"

SUFFIX="${1:-}"
[ -z "$SUFFIX" ] && read -rp "Nombre (prefijo box-): box-" SUFFIX
CNAME="box-${SUFFIX}"; validate_name "$CNAME"; ensure_not_exists "$CNAME"

DISTRO="${2:-}"
if [ -z "$DISTRO" ]; then
  cat <<MSG
Distro:
  1) Alpine   2) Arch   3) Debian
MSG
  read -rp "Opcion [1/2/3]: " DISTRO
fi

# Normalizar
case "$DISTRO" in alpine) DISTRO=1 ;; arch) DISTRO=2 ;; debian) DISTRO=3 ;; esac

cat <<MSG
Red:
  1) Aislada (seguro)   2) Host (simple)
MSG
read -rp "Opcion [1/2]: " NET_CHOICE
NET=$([ "$NET_CHOICE" = "2" ] && echo "host" || echo "isolated")

PORT=""; [ "$NET" = "isolated" ] && read -rp "Puerto (vacio=ninguno): " PORT

cat <<MSG
Podman (docker-compose, imagenes OCI):
  1) No   2) Si
MSG
read -rp "Opcion [1/2]: " PODMAN

# Crear — Arch/Debian requieren herramientas en el host, se valida sin instalar
case "$DISTRO" in
  1) create_alpine_base "$CNAME" ;;
  2) command -v pacstrap >/dev/null || { echo "Error: requiere arch-install-scripts. Instalar manualmente: sudo pacman -S arch-install-scripts"; exit 1; }
     sudo btrfs subvolume create "$MACHINES/$CNAME"; sudo pacstrap -c "$MACHINES/$CNAME" base ;;
  3) command -v debootstrap >/dev/null || { echo "Error: requiere debootstrap. Instalar manualmente: sudo pacman -S debootstrap debian-archive-keyring"; exit 1; }
     sudo btrfs subvolume create "$MACHINES/$CNAME"; sudo debootstrap --include=dbus,libpam-systemd --variant=minbase stable "$MACHINES/$CNAME" https://deb.debian.org/debian ;;
  *) echo "Invalido"; exit 1 ;;
esac

if [ "$PODMAN" = "2" ]; then
  profile_podman "$CNAME"
  case "$DISTRO" in
    1) run_in "$CNAME" 'apk add --no-cache podman podman-compose fuse-overlayfs slirp4netns buildah skopeo ca-certificates curl; mkdir -p /etc/containers; printf "[storage]\ndriver=\"overlay\"\n[storage.options.overlay]\nmount_program=\"/usr/bin/fuse-overlayfs\"\n" > /etc/containers/storage.conf; printf "unqualified-search-registries=[\"docker.io\",\"ghcr.io\",\"quay.io\"]\n" > /etc/containers/registries.conf; rm -rf /var/cache/apk/*' ;;
    2) run_in "$CNAME" 'pacman -Sy --noconfirm podman buildah skopeo fuse-overlayfs slirp4netns' ;;
    3) run_in "$CNAME" 'apt-get update && apt-get install -y podman buildah skopeo fuse-overlayfs slirp4netns && apt-get clean' ;;
  esac
else
  profile_container "$CNAME" "$NET" "$PORT"
fi

get_user; sudo -u "$USERNAME" mkdir -p "$HOME_DIR/Projects"

cat <<MSG

=== $CNAME creado ===
Shell: sudo machinectl shell $CNAME
$([ "$PODMAN" = "2" ] && echo "Podman: podman run --rm -it alpine sh")
MSG
