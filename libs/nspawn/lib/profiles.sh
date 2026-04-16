#!/bin/bash
# nspawn/lib/profiles.sh — Perfiles .nspawn + recursos por tipo
#
# .nspawn  → [Exec] [Network] [Files] (lo que soporta systemd.nspawn)
# recursos → service override via apply_resources (CPUWeight/MemoryHigh/etc)
#
# Requiere: common.sh ya cargado

profile_venv() {
  local name="$1"
  get_user
  local binds=$(optional_binds)
  write_nspawn_config "$name" "[Exec]
Boot=no
PrivateUsers=pick
NotifyReady=no

[Network]
VirtualEthernet=yes
Zone=venv

[Files]
TemporaryFileSystem=/tmp:mode=1777
Bind=$HOME_DIR/Projects:/root/Projects
${binds}"
  apply_resources "$name" 50 384M 512M 128
}

profile_k3s() {
  local name="$1" cluster="$2" role="$3"
  local weight=25 mhigh=48M mmax=96M tasks=64
  if [ "$role" = "master" ]; then
    weight=50; mhigh=96M; mmax=192M; tasks=128
  fi
  write_nspawn_config "$name" "[Exec]
Boot=no
Capability=CAP_NET_ADMIN CAP_NET_RAW CAP_SYS_ADMIN CAP_SYS_PTRACE CAP_SYS_MODULE
SystemCallFilter=~@obsolete ~@clock

[Network]
VirtualEthernet=yes
Zone=k3s-${cluster}

[Files]
TemporaryFileSystem=/tmp:mode=1777
BindReadOnly=/dev/kmsg"
  apply_resources "$name" "$weight" "$mhigh" "$mmax" "$tasks"
}

profile_kvm() {
  local name="$1"
  write_nspawn_config "$name" "[Exec]
Boot=no
Capability=CAP_NET_ADMIN CAP_NET_RAW CAP_SYS_ADMIN CAP_MKNOD CAP_SYS_RESOURCE
SystemCallFilter=~@obsolete ~@clock

[Network]
VirtualEthernet=yes
Zone=kvm
Port=tcp:9090:9090

[Files]
Bind=/dev/kvm
Bind=/dev/vhost-net
TemporaryFileSystem=/tmp:mode=1777"
  apply_resources "$name" 100 1G 2G 256
  apply_device_allow "$name" "/dev/kvm rw" "/dev/vhost-net rw"
}

profile_podman() {
  local name="$1" mhigh="${2:-512M}" mmax="${3:-1G}"
  get_user
  local binds=$(optional_binds)
  write_nspawn_config "$name" "[Exec]
Boot=no
PrivateUsers=pick
Capability=CAP_NET_ADMIN CAP_NET_RAW CAP_SYS_ADMIN CAP_MKNOD CAP_SETUID CAP_SETGID CAP_CHOWN CAP_FOWNER CAP_DAC_OVERRIDE
SystemCallFilter=~@obsolete ~@clock @keyring bpf

[Network]
VirtualEthernet=yes
Zone=podman

[Files]
TemporaryFileSystem=/tmp:mode=1777
Bind=$HOME_DIR/Projects:/root/Projects
Bind=/dev/fuse
${binds}"
  apply_resources "$name" 75 "$mhigh" "$mmax" 256
  apply_device_allow "$name" "/dev/fuse rwm"
}

profile_container() {
  local name="$1" net="$2" port="$3"
  local net_block="VirtualEthernet=yes
Zone=containers"
  [ "$net" = "host" ] && net_block="VirtualEthernet=no"
  [ -n "$port" ] && net_block="${net_block}
Port=$port"
  write_nspawn_config "$name" "[Exec]
Boot=no
PrivateUsers=pick

[Network]
$net_block

[Files]
TemporaryFileSystem=/tmp:mode=1777"
  apply_resources "$name" 25 128M 256M 64
}
