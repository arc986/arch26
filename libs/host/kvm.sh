#!/bin/bash
# Arch Linux — KVM/QEMU optimizado para AMD + btrfs
# Post archlinux2.md base install (iommu=pt ya en GRUB)
set -e

USERNAME=$(getent passwd 1000 | cut -d: -f1)

# --- Selector GUI ---
echo "Selecciona interfaz grafica:"
echo "  1) virt-manager  (KDE / Tiling / completo)"
echo "  2) gnome-boxes   (GNOME / simple)"
read -rp "Opcion [1/2]: " GUI_CHOICE

# --- Paquetes base KVM ---
sudo pacman -S --needed \
  qemu-desktop \
  libvirt \
  iptables-nft \
  dnsmasq \
  bridge-utils \
  edk2-ovmf \
  swtpm \
  virtiofsd

# --- GUI ---
case "$GUI_CHOICE" in
  1) sudo pacman -S --needed virt-manager ;;
  2) sudo pacman -S --needed gnome-boxes ;;
  *) echo "Opcion invalida"; exit 1 ;;
esac

# --- Agregar usuario al grupo libvirt + kvm ---
sudo usermod -aG libvirt,kvm "$USERNAME"

# --- Libvirt: socket como usuario ---
sudo sed -i 's/^#\?unix_sock_group = .*/unix_sock_group = "libvirt"/' /etc/libvirt/libvirtd.conf
sudo sed -i 's/^#\?unix_sock_rw_perms = .*/unix_sock_rw_perms = "0770"/' /etc/libvirt/libvirtd.conf

# --- QEMU: ejecutar como usuario + optimizaciones AMD ---
sudo sed -i "s/^#\?user = .*/user = \"$USERNAME\"/" /etc/libvirt/qemu.conf
sudo sed -i "s/^#\?group = .*/group = \"libvirt\"/" /etc/libvirt/qemu.conf

# --- Modulos KVM AMD ---
sudo mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/kvm-amd.conf <<'EOF'
# Nested virtualization (VMs dentro de VMs)
options kvm_amd nested=1
# AVIC: AMD Virtual Interrupt Controller (reduce latencia interrupciones)
options kvm_amd avic=1
# SEV: Secure Encrypted Virtualization (si hardware soporta)
options kvm ignore_msrs=1
EOF

# --- Storage pool en subvolumen @libvirt (btrfs nativo) ---
# Verificar si @libvirt esta montado
LIBVIRT_PATH=""
if mountpoint -q /var/lib/libvirt 2>/dev/null; then
  LIBVIRT_PATH="/var/lib/libvirt/images"
elif [ -d /var/lib/libvirt/images ]; then
  LIBVIRT_PATH="/var/lib/libvirt/images"
fi

# --- Habilitar servicios ---
sudo systemctl enable --now libvirtd.service
sudo systemctl enable --now virtlogd.service

# --- Red default (NAT) ---
sudo virsh net-autostart default 2>/dev/null || true
sudo virsh net-start default 2>/dev/null || true

# --- Configurar storage pool btrfs si @libvirt montado ---
if [ -n "$LIBVIRT_PATH" ]; then
  sudo virsh pool-define-as default dir --target "$LIBVIRT_PATH" 2>/dev/null || true
  sudo virsh pool-autostart default 2>/dev/null || true
  sudo virsh pool-start default 2>/dev/null || true
fi

# --- Sysctl: permitir bridge para VMs ---
cat > /etc/sysctl.d/99-bridge.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-arptables = 0
EOF

echo ""
echo "=== KVM optimizado para AMD + btrfs ==="
echo ""
echo "Optimizaciones activas:"
echo "  iommu=pt          → Passthrough listo (GRUB base)"
echo "  kvm_amd nested=1  → VMs dentro de VMs"
echo "  kvm_amd avic=1    → Interrupciones AMD optimizadas"
echo "  btrfs storage     → Snapshots nativos de discos VM"
echo "  swtpm             → TPM virtual (Windows 11)"
echo "  virtiofsd         → Carpetas compartidas host<->VM"
echo "  OVMF              → UEFI boot en VMs"
echo ""
echo "Comandos:"
echo "  virt-manager / gnome-boxes  → GUI"
echo "  virsh list --all            → Ver VMs"
echo ""
echo "Cerrar sesion para que grupos apliquen."
