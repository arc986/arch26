#!/bin/bash
# Arch Linux — Configuracion inicial de Snapper
# Ejecutar después del primer reboot post archlinux2.md
# Solo snapshots manuales. Sin timers. Sin automatizacion.
set -e

echo "=== Configurando Snapper ==="

# Desmontar .snapshots si existe (snapper necesita crearlo)
sudo umount /.snapshots 2>/dev/null || true
sudo rm -rf /.snapshots

# Crear configuracion root
sudo snapper -c root create-config /

# Reemplazar subvolumen de snapper por @snapshots original
sudo btrfs subvolume delete /.snapshots 2>/dev/null || true
sudo mkdir -p /.snapshots
sudo mount -a

# Permisos
sudo chmod 750 /.snapshots

# Desactivar todo lo automatico
sudo sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="no"/' /etc/snapper/configs/root
sudo sed -i 's/^TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="no"/' /etc/snapper/configs/root
sudo sed -i 's/^NUMBER_CLEANUP=.*/NUMBER_CLEANUP="no"/' /etc/snapper/configs/root

# Crear snapshot base (importante — nunca borrar)
sudo snapper -c root create --description "base" --userdata "important=yes"

echo ""
echo "=== Snapper configurado (solo manual) ==="
echo ""
echo "Comandos:"
echo "  snapper -c root create --description x   → Crear snapshot"
echo "  snapper -c root list                      → Ver snapshots"
echo "  snapper -c root undochange N..0            → Revertir a snapshot N"
echo "  snapper -c root delete N                  → Eliminar snapshot N"
echo ""
echo "IMPORTANTE: Snapshot #1 (base) no debe borrarse nunca."
