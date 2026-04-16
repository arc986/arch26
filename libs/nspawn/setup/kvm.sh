#!/bin/bash
# nspawn — KVM/QEMU aislado en nspawn Alpine
# Uso: kvm.sh [cockpit|virt|cli]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/profiles.sh"

CNAME="kvm-server"
ensure_not_exists "$CNAME"

GUI="${1:-}"
if [ -z "$GUI" ]; then
  cat <<MSG
Interfaz:
  1) Cockpit (web)  2) virt-manager (SSH)  3) CLI (virsh)
MSG
  read -rp "Opcion [1/2/3]: " GUI
fi

# Normalizar
case "$GUI" in cockpit) GUI=1 ;; virt) GUI=2 ;; cli) GUI=3 ;; esac

create_alpine_base "$CNAME"
profile_kvm "$CNAME"

run_in "$CNAME" '
apk add --no-cache qemu-system-x86_64 qemu-img libvirt libvirt-daemon libvirt-qemu dnsmasq bridge-utils iptables ip6tables openssh ovmf swtpm ca-certificates
rc-update add libvirtd default; rc-update add sshd default
sed -i "s/^#\?unix_sock_group = .*/unix_sock_group = \"libvirt\"/" /etc/libvirt/libvirtd.conf
sed -i "s/^#\?unix_sock_rw_perms = .*/unix_sock_rw_perms = \"0770\"/" /etc/libvirt/libvirtd.conf
echo "root:kvm" | chpasswd; mkdir -p /var/lib/libvirt/images; rm -rf /var/cache/apk/*
'
[ "$GUI" = "1" ] && run_in "$CNAME" 'apk add --no-cache cockpit cockpit-machines; rc-update add cockpit default'

sudo systemd-nspawn -bD "$MACHINES/$CNAME" --machine="$CNAME" \
  --bind=/dev/kvm --bind=/dev/vhost-net \
  --capability=CAP_NET_ADMIN,CAP_NET_RAW,CAP_SYS_ADMIN,CAP_MKNOD,CAP_SYS_RESOURCE \
  --network-veth -q &
sleep 5

KVM_IP=$(sudo machinectl show "$CNAME" -p Addresses --value 2>/dev/null | cut -d' ' -f1)

cat <<MSG

=== KVM en nspawn listo ===
IP: $KVM_IP
$([ "$GUI" = "1" ] && echo "Cockpit: https://$KVM_IP:9090 (root/kvm)")
$([ "$GUI" = "2" ] && echo "virt-manager -c qemu+ssh://root@$KVM_IP/system")
$([ "$GUI" = "3" ] && echo "sudo machinectl shell $CNAME -- virsh list --all")
ISOs: sudo cp archivo.iso $MACHINES/$CNAME/var/lib/libvirt/images/
MSG
