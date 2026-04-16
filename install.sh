#!/usr/bin/env bash
set -euo pipefail

# ── Colores ──
R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' C='\033[1;36m' N='\033[0m'
info()  { printf "${C}:: %s${N}\n" "$*"; }
ok()    { printf "${G}✓  %s${N}\n" "$*"; }
warn()  { printf "${Y}⚠  %s${N}\n" "$*"; }
die()   { printf "${R}✗  %s${N}\n" "$*"; exit 1; }
ask()   { printf "${Y}▸  %s: ${N}" "$1"; read -r "$2"; }
pause() { printf "\n${Y}Presiona ENTER para continuar...${N}"; read -r; }

# ── Validaciones ──
[[ $EUID -eq 0 ]] || die "Ejecuta como root"
[[ -d /sys/firmware/efi ]] || die "No se detecto UEFI"

# ── Datos del usuario ──
echo ""
info "Arch Linux — Instalacion semi-automatica"
echo ""
ask "Nombre del equipo (hostname)" PCNAME
[[ -n "$PCNAME" ]] || die "El hostname no puede estar vacio"
PCNAME="${PCNAME^^}"
ask "Nombre de usuario" USERNAME
[[ -n "$USERNAME" ]] || die "El usuario no puede estar vacio"
echo ""

# ── Disco ──
ask "Disco destino [/dev/nvme0n1]" DISK_INPUT
DISK="${DISK_INPUT:-/dev/nvme0n1}"
EFI="${DISK}p1"
ROOT="${DISK}p2"

warn "Se borrara TODO en $DISK"
ask "Escribir 'SI' para continuar" CONFIRM
[[ "$CONFIRM" == "SI" ]] || die "Cancelado"

# ══════════════════════════════════════════
# Particiones
# ══════════════════════════════════════════
info "Particionando $DISK..."
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+256M -t1:ef00 "$DISK"
sgdisk -n2:0:0 -t2:8300 "$DISK"
mkfs.vfat -n EFI "$EFI"
mkfs.btrfs -f -L ROOT "$ROOT"
ok "Particiones creadas"

# ══════════════════════════════════════════
# Subvolumenes y montaje
# ══════════════════════════════════════════
info "Creando subvolumenes Btrfs..."
mount "$ROOT" /mnt
for sv in @ @home @log @pkg @tmp @snapshots @srv @machines; do
  btrfs subvolume create "/mnt/$sv"
done
umount /mnt

info "Montando subvolumenes..."
OPTS="noatime,ssd,space_cache=v2,discard=async,commit=60"
mount -o "$OPTS,compress=zstd:3,subvol=@" "$ROOT" /mnt
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,var/tmp,.snapshots,srv,efi,var/lib/machines}
mount -o "$OPTS,compress=zstd:3,subvol=@home"      "$ROOT" /mnt/home
mount -o "$OPTS,compress=zstd:3,subvol=@log"        "$ROOT" /mnt/var/log
mount -o "$OPTS,compress=no,subvol=@pkg"            "$ROOT" /mnt/var/cache/pacman/pkg
mount -o "$OPTS,compress=no,subvol=@tmp"            "$ROOT" /mnt/var/tmp
mount -o "$OPTS,compress=zstd:9,subvol=@snapshots"  "$ROOT" /mnt/.snapshots
mount -o "$OPTS,compress=zstd:1,subvol=@srv"        "$ROOT" /mnt/srv
mount -o "$OPTS,compress=no,subvol=@machines"       "$ROOT" /mnt/var/lib/machines
mount "$EFI" /mnt/efi
ok "Subvolumenes montados"

# ══════════════════════════════════════════
# Sistema base
# ══════════════════════════════════════════
info "Instalando sistema base (pacstrap)..."
pacstrap -K /mnt base linux-zen amd-ucode linux-firmware-whence \
  linux-firmware-amdgpu linux-firmware-intel linux-firmware-realtek \
  linux-firmware-mediatek sof-firmware grub efibootmgr btrfs-progs \
  pipewire wireplumber pipewire-jack sbctl pipewire-pulse bluez mesa \
  vulkan-radeon libva-mesa-driver snapper wayland neovim zram-generator \
  hunspell-es_pa fontconfig power-profiles-daemon upower sudo nftables \
  networkmanager iwd nushell inter-font terminus-font ttf-jetbrains-mono \
  noto-fonts noto-fonts-cjk noto-fonts-emoji htop wireless-regdb mdadm \
  git openssh
ok "Sistema base instalado"

genfstab -pU /mnt >> /mnt/etc/fstab

# ══════════════════════════════════════════
# Chroot — script interno
# ══════════════════════════════════════════
info "Entrando a chroot..."

cat > /mnt/chroot-install.sh <<'CHROOT'
#!/usr/bin/env bash
set -euo pipefail

PCNAME="$1"
USERNAME="$2"

# ── Identidad del sistema ──
echo "$PCNAME" > /etc/hostname
printf '127.0.0.1 localhost %s\n::1 localhost %s\n' "$PCNAME" "$PCNAME" >> /etc/hosts
ln -sf /usr/share/zoneinfo/America/Panama /etc/localtime
hwclock --systohc

printf 'LANG=es_PA.UTF-8\nLC_TIME=C\nLC_COLLATE=C\n# Forzar Wayland nativo\nMOZ_ENABLE_WAYLAND=1\nELECTRON_OZONE_PLATFORM_HINT=wayland\nQT_QPA_PLATFORM=wayland;xcb\nSDL_VIDEODRIVER=wayland\n' >> /etc/environment

echo 'es_PA.UTF-8 UTF-8' > /etc/locale.gen
echo 'LANG=es_PA.UTF-8' > /etc/locale.conf
locale-gen

printf 'KEYMAP=la-latin1\nFONT=ter-132n\n' > /etc/vconsole.conf

# ── Bootloader ──
grub-install --efi-directory=/efi --bootloader-id='Arch Linux' --target=x86_64-efi
echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="zswap.enabled=0 amd_pstate=active amdgpu.abmlevel=1 amdgpu.dither=1 nowatchdog nmi_watchdog=0 iommu=pt quiet loglevel=3"/' /etc/default/grub

# ── Kernel y compresion ──
sed -i -e 's/MODULES=()/MODULES=(amdgpu)/' -e 's/^#\?COMPRESSION="zstd"/COMPRESSION="zstd"/' /etc/mkinitcpio.conf
mkinitcpio -P
grub-mkconfig -o /boot/grub/grub.cfg

# ── Rendimiento y memoria ──
printf '[zram0]\nzram-size = ram / 2\ncompression-algorithm = zstd\nswap-priority = 100\nfs-type = swap\n' > /etc/systemd/zram-generator.conf

cat > /etc/sysctl.d/99-performance.conf <<EOF
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.vfs_cache_pressure = 50

# --- Red: endurecimiento ---
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
fs.inotify.max_user_watches = 524288
EOF

# ── Logs y recursos ──
sed -i 's/^#\?Storage=.*/Storage=volatile/' /etc/systemd/journald.conf
sed -i 's/^#\?RuntimeMaxUse=.*/RuntimeMaxUse=15M/' /etc/systemd/journald.conf
sed -i 's/^#\?Storage=external/Storage=none/' /etc/systemd/coredump.conf
sed -i 's/^#\?ProcessSizeMax=.*/ProcessSizeMax=0/' /etc/systemd/coredump.conf
sed -i 's/^#\?NAutoVTs=6/NAutoVTs=2/' /etc/systemd/logind.conf

# ── Usuario ──
echo "Establece la contrasena de root:"
passwd
useradd -m -g users -G wheel -s /usr/bin/nu "$USERNAME"
echo "Establece la contrasena de $USERNAME:"
passwd "$USERNAME"
echo "$USERNAME:100000:65536" | tee -a /etc/subuid >> /etc/subgid
sed -i 's/^#\s*%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# ── Red y servicios ──
mkdir -p /etc/NetworkManager/conf.d
printf '[device]\nwifi.backend=iwd\n' > /etc/NetworkManager/conf.d/iwd.conf
printf '[connection]\nwifi.powersave = 3\n' > /etc/NetworkManager/conf.d/wifi-powersave.conf
systemctl enable bluetooth upower NetworkManager power-profiles-daemon nftables iwd systemd-resolved
systemctl disable man-db.timer shadow.timer

# ── Fuentes ──
ln -s /usr/share/fontconfig/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/
rm -f /etc/fonts/conf.d/10-hinting-slight.conf /etc/fonts/conf.d/10-hinting-full.conf
echo 'FREETYPE_PROPERTIES=cff:no-stem-darkening=0 truetype:interpreter-version=40' >> /etc/environment

cat > /etc/fonts/local.conf <<'FONTEOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="autohint" mode="assign"><bool>false</bool></edit>
    <edit name="rgba" mode="assign"><const>none</const></edit>
    <edit name="lcdfilter" mode="assign"><const>lcdnone</const></edit>
    <edit name="embeddedbitmap" mode="assign"><bool>false</bool></edit>
  </match>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Inter</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>JetBrains Mono</family></prefer>
  </alias>
</fontconfig>
FONTEOF

CHROOT

chmod +x /mnt/chroot-install.sh
arch-chroot /mnt /chroot-install.sh "$PCNAME" "$USERNAME"
rm /mnt/chroot-install.sh

# ══════════════════════════════════════════
# Finalizar
# ══════════════════════════════════════════
ok "Instalacion completada"
info "Desmontando..."
umount -R /mnt
echo ""
warn "Listo. Escribe 'reboot' cuando quieras reiniciar."
