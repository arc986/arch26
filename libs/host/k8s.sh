#!/bin/bash
# Arch Linux — K3s Lab en KVM con Alpine Linux
# Post kvm.sh. Cluster: 1 master + 2 workers en <1GB RAM
set -e

ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-3.21.3-x86_64.iso"
ALPINE_ISO="/var/lib/libvirt/images/alpine-virt.iso"
VM_DIR="/var/lib/libvirt/images"
NETWORK="k8s-net"

MASTER_RAM=384
WORKER_RAM=256
MASTER_DISK=4
WORKER_DISK=4
MASTER_CPU=2
WORKER_CPU=1

# --- kubectl en host ---
sudo pacman -S --needed kubectl

# --- Descargar Alpine Virt ISO ---
if [ ! -f "$ALPINE_ISO" ]; then
  echo "Descargando Alpine Virt ISO..."
  sudo curl -fSL -o "$ALPINE_ISO" "$ALPINE_URL"
fi

# --- Red aislada ---
sudo virsh net-define /dev/stdin <<'NETXML'
<network>
  <name>k8s-net</name>
  <forward mode='nat'/>
  <bridge name='k8sbr0' stp='on' delay='0'/>
  <ip address='10.100.0.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.100.0.10' end='10.100.0.50'/>
      <host mac='52:54:00:a8:00:10' ip='10.100.0.10' name='k8s-master'/>
      <host mac='52:54:00:a8:00:11' ip='10.100.0.11' name='k8s-worker1'/>
      <host mac='52:54:00:a8:00:12' ip='10.100.0.12' name='k8s-worker2'/>
    </dhcp>
  </ip>
</network>
NETXML
sudo virsh net-start "$NETWORK" 2>/dev/null || true
sudo virsh net-autostart "$NETWORK"

# --- Crear discos qcow2 sparse ---
sudo qemu-img create -f qcow2 -o preallocation=off "$VM_DIR/k8s-master.qcow2" ${MASTER_DISK}G
sudo qemu-img create -f qcow2 -o preallocation=off "$VM_DIR/k8s-worker1.qcow2" ${WORKER_DISK}G
sudo qemu-img create -f qcow2 -o preallocation=off "$VM_DIR/k8s-worker2.qcow2" ${WORKER_DISK}G

# --- Crear VMs optimizadas ---
create_vm() {
  local NAME=$1 RAM=$2 CPU=$3 MAC=$4
  sudo virt-install \
    --name "$NAME" \
    --ram "$RAM" \
    --vcpus "$CPU" \
    --cpu host-passthrough \
    --disk path="$VM_DIR/${NAME}.qcow2",format=qcow2,bus=virtio,cache=writeback,io=threads,discard=unmap \
    --cdrom "$ALPINE_ISO" \
    --network network="$NETWORK",mac="$MAC",model=virtio \
    --os-variant alpinelinux3.21 \
    --graphics none \
    --console pty,target_type=serial \
    --memballoon model=virtio \
    --noautoconsole
}

echo "=== Creando VMs ==="
create_vm k8s-master  $MASTER_RAM $MASTER_CPU "52:54:00:a8:00:10"
create_vm k8s-worker1 $WORKER_RAM $WORKER_CPU "52:54:00:a8:00:11"
create_vm k8s-worker2 $WORKER_RAM $WORKER_CPU "52:54:00:a8:00:12"

# --- Script Alpine post-install (ejecutar dentro de VM después de setup-alpine + reboot) ---
cat > /tmp/k8s-alpine-post.sh <<'ALPINEPOST'
#!/bin/sh
# Ejecutar dentro de cada VM Alpine después de instalar y rebootear desde disco
set -e

# Paquetes minimos
apk add --no-cache curl iptables ip6tables wireguard-tools

# Deshabilitar servicios innecesarios
rc-update del swap boot 2>/dev/null || true
rc-update del hwdrivers boot 2>/dev/null || true
rc-update del machine-id boot 2>/dev/null || true

# cgroups v2
sed -i 's/^default_kernel_opts=.*/default_kernel_opts="quiet cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"/' /etc/update-extlinux.conf
update-extlinux

# Networking
cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.ipv6.conf.all.disable_ipv6=1
vm.overcommit_memory=1
vm.panic_on_oom=0
EOF
sysctl -p

# Deshabilitar kernel logs excesivos
echo "kernel.printk = 3 3 3 3" >> /etc/sysctl.conf

echo "Alpine optimizado. Reboot necesario para cgroups."
echo "Después del reboot, ejecutar k8s-master-setup.sh o k8s-worker-setup.sh"
ALPINEPOST

# --- K3s master ---
cat > /tmp/k8s-master-setup.sh <<'MASTERSCRIPT'
#!/bin/sh
set -e
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --disable traefik \
  --disable servicelb \
  --disable local-storage \
  --disable metrics-server \
  --write-kubeconfig-mode 644 \
  --node-name k8s-master \
  --flannel-backend wireguard-native \
  --kube-proxy-arg proxy-mode=iptables \
  --kube-apiserver-arg default-not-ready-toleration-seconds=10 \
  --kube-apiserver-arg default-unreachable-toleration-seconds=10 \
  --kube-controller-manager-arg node-monitor-period=5s \
  --kube-controller-manager-arg node-monitor-grace-period=15s \
  --kubelet-arg max-pods=30 \
  --kubelet-arg eviction-hard=memory.available<50Mi \
  --kubelet-arg system-reserved=memory=64Mi" sh -

echo ""
echo "=== K3s Master listo ==="
echo "Token: $(cat /var/lib/rancher/k3s/server/node-token)"
echo "IP: $(hostname -I | awk '{print $1}')"
MASTERSCRIPT

# --- K3s worker ---
cat > /tmp/k8s-worker-setup.sh <<'WORKERSCRIPT'
#!/bin/sh
set -e
read -rp "Master IP [10.100.0.10]: " MASTER_IP
MASTER_IP=${MASTER_IP:-10.100.0.10}
read -rp "Token: " TOKEN

curl -sfL https://get.k3s.io | K3S_URL="https://${MASTER_IP}:6443" \
  K3S_TOKEN="$TOKEN" \
  INSTALL_K3S_EXEC="agent \
  --node-name $(hostname) \
  --kube-proxy-arg proxy-mode=iptables \
  --kubelet-arg max-pods=20 \
  --kubelet-arg eviction-hard=memory.available<30Mi \
  --kubelet-arg system-reserved=memory=32Mi" sh -

echo "Worker unido al cluster"
WORKERSCRIPT

# --- Export/Import ---
cat > /tmp/k8s-export.sh <<'EXPORTSCRIPT'
#!/bin/bash
set -e
DIR="/tmp/k8s-export"
mkdir -p "$DIR"
echo "Apagando VMs..."
for VM in k8s-master k8s-worker1 k8s-worker2; do
  sudo virsh shutdown "$VM" 2>/dev/null || true
done
sleep 10
for VM in k8s-master k8s-worker1 k8s-worker2; do
  sudo cp "/var/lib/libvirt/images/${VM}.qcow2" "$DIR/"
  sudo virsh dumpxml "$VM" > "$DIR/${VM}.xml"
done
sudo virsh net-dumpxml k8s-net > "$DIR/k8s-net.xml"
tar -cf - -C "$DIR" . | zstd -T0 -9 > ~/k8s-lab.tar.zst
rm -rf "$DIR"
echo "Exportado: ~/k8s-lab.tar.zst ($(du -h ~/k8s-lab.tar.zst | cut -f1))"
EXPORTSCRIPT

cat > /tmp/k8s-import.sh <<'IMPORTSCRIPT'
#!/bin/bash
set -e
[ -z "$1" ] && echo "Uso: $0 k8s-lab.tar.zst" && exit 1
DIR="/tmp/k8s-import"
mkdir -p "$DIR"
zstd -d "$1" --stdout | tar -xf - -C "$DIR"
sudo virsh net-define "$DIR/k8s-net.xml"
sudo virsh net-start k8s-net 2>/dev/null || true
sudo virsh net-autostart k8s-net
for VM in k8s-master k8s-worker1 k8s-worker2; do
  sudo cp "$DIR/${VM}.qcow2" /var/lib/libvirt/images/
  sudo virsh define "$DIR/${VM}.xml"
done
rm -rf "$DIR"
echo "Importado. Iniciar: sudo virsh start k8s-master k8s-worker1 k8s-worker2"
IMPORTSCRIPT

chmod +x /tmp/k8s-{export,import,alpine-post,master-setup,worker-setup}.sh

USERNAME=$(getent passwd 1000 | cut -d: -f1)
HOME_DIR="/home/$USERNAME"
mkdir -p "$HOME_DIR/.local/bin"
cp /tmp/k8s-export.sh /tmp/k8s-import.sh "$HOME_DIR/.local/bin/"
chown "$USERNAME:users" "$HOME_DIR/.local/bin"/k8s-{export,import}.sh

echo ""
echo "=== K3s Lab — ~896MB RAM total ==="
echo ""
echo "Paso 1: Instalar Alpine en cada VM"
echo "  sudo virsh console k8s-master   → setup-alpine → reboot"
echo "  sudo virsh console k8s-worker1  → setup-alpine → reboot"
echo "  sudo virsh console k8s-worker2  → setup-alpine → reboot"
echo ""
echo "Paso 2: Post-install (en cada VM)"
echo "  scp /tmp/k8s-alpine-post.sh root@10.100.0.10:/tmp/"
echo "  ssh root@10.100.0.10 sh /tmp/k8s-alpine-post.sh && reboot"
echo ""
echo "Paso 3: K3s (después del reboot)"
echo "  scp /tmp/k8s-master-setup.sh root@10.100.0.10:/tmp/"
echo "  ssh root@10.100.0.10 sh /tmp/k8s-master-setup.sh"
echo "  (copiar token, repetir con worker-setup en .11 y .12)"
echo ""
echo "Paso 4: kubectl desde host"
echo "  mkdir -p ~/.kube"
echo "  scp root@10.100.0.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config"
echo "  sed -i 's/127.0.0.1/10.100.0.10/' ~/.kube/config"
echo "  kubectl get nodes"
