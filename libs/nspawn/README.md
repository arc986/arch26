# systemd-nspawn: Gestión de Contenedores Optimizada

Contenedores ultraligeros basados en `systemd-nspawn` sobre **Btrfs**, optimizados para desarrollo, infraestructura y aislamiento con huella cero en idle.

> [!TIP]
> **¿Eres nuevo?** Lee nuestro [Manual para Dummies](file:///c:/Users/david/Desktop/git/arch26/libs/nspawn/MANUAL.md) para aprender a usar todo el sistema paso a paso.

## 🚀 Guía Rápida del CLI

El punto de entrada principal es `nspawn-ctl.sh`. Casi todos los comandos aceptan **filtros** (ej. `start venv` inicia todos los contenedores que empiezan por `venv`).

| Acción | Uso | Descripción |
|---|---|---|
| `list` | `nspawn-ctl list [filtro]` | Tabla con tipo, estado, RAM y disco. |
| `start` | `nspawn-ctl start [filtro]` | Inicia contenedores (soporta batch). |
| `stop` | `nspawn-ctl stop [filtro]` | Detiene contenedores de forma segura. |
| `shell` | `nspawn-ctl shell [nombre]` | Entra al contenedor. |
| `logs` | `nspawn-ctl logs [nombre]` | Ver logs del sistema. |
| `delete` | `nspawn-ctl delete [nombre]` | Elimina contenedor y configuración. |

---

## 🛠️ Tipos de Entornos y Gestión Específica

### 1. Desarrollo (`venv`)
Entornos Alpine ligeros que comparten `~/Projects` con el host.

*   **Crear**: `nspawn-ctl create venv [go|python|web|rust|all]`
*   **Iniciar todos**: `nspawn-ctl start venv`
*   **Entrar a uno**: `nspawn-ctl shell venv-go`
*   **Detener todos**: `nspawn-ctl stop venv`
*   **Borrar**: `nspawn-ctl delete venv-python`

### 2. Clusters Kubernetes (`k3s`)
Clusters locales aislados. kubectl se usa **dentro** del master para no ensuciar el host.

*   **Crear cluster**: `nspawn-ctl create k3s [nombre]`
*   **Iniciar cluster**: `nspawn-ctl start k3s-[nombre]`
*   **Ver nodos (kubectl)**: `sudo machinectl shell k3s-[nombre]-master -- kubectl get nodes`
*   **Añadir worker**: Ejecuta `setup/k3s.sh` y elige la opción 2.
*   **Borrar cluster**: `nspawn-ctl delete k3s-[nombre]-master` (repetir para workers).

### 3. Virtualización (`kvm`)
Servidor de QEMU/KVM aislado. Permite correr ISOs o VMs reales dentro de nspawn.

*   **Crear**: `nspawn-ctl create kvm [cockpit|virt|cli]`
*   **Iniciar**: `nspawn-ctl start kvm-server`
*   **Acceso Web**: `https://<IP>:9090` (Usuario: `root`, Pass: `kvm`).
*   **Ver VMs**: `nspawn-ctl shell kvm-server -- virsh list --all`
*   **Subir ISOs**: `sudo cp mi.iso /var/lib/machines/kvm-server/var/lib/libvirt/images/`
*   **Borrar**: `nspawn-ctl delete kvm-server`

### 4. Contenedores Genéricos (`box`)
Contenedores de diversas distros, opcionalmente con Podman (Docker-in-nspawn).

*   **Crear**: `nspawn-ctl create box [nombre] [alpine|arch|debian]`
*   **Iniciar**: `nspawn-ctl start box-[nombre]`
*   **Entrar**: `nspawn-ctl shell box-[nombre]`
*   **Probar Podman**: `podman run --rm -it alpine sh` (dentro del box).
*   **Borrar**: `nspawn-ctl delete box-[nombre]`

---

## ⚡ Recursos, Límites y Mantenimiento

### Control de Recursos
Los límites son dinámicos y se gestionan vía systemd-slices.
*   **CPUWeight**: Prioridad baja (ej. 50). No consume nada en idle, usa todo si el host está libre.
*   **MemoryHigh**: Throttle suave (frena el consumo sin matar procesos).
*   **Ver consumo real**: `nspawn-ctl resources` (abre `cgtop` filtrado).

### Operaciones de Btrfs
*   **Snapshot**: `nspawn-ctl snapshot [nombre]`. Crea una copia instantánea en `/var/lib/machines`.
*   **Modo Efímero**: `nspawn-ctl ephemeral [nombre]`. Inicia una copia temporal; al salir, todos los cambios se destruyen. Ideal para pruebas rápidas.

---

## 🌐 Networking y Seguridad

*   **Zonas de Red**: Cada tipo de contenedor tiene su propia zona (ej. `Zone=venv`) para que no se vean entre sí a menos que se configure explícitamente.
*   **Exponer Puertos**: 
    1. Edita `/etc/systemd/nspawn/<nombre>.nspawn`.
    2. Añade: `Port=tcp:8080:80` (Host 8080 -> Contenedor 80).
    3. Reinicia: `nspawn-ctl stop <n>` y `nspawn-ctl start <n>`.
*   **Aislamiento**: Se usa `PrivateUsers=pick` para que el `root` del contenedor no sea el `root` del sistema real.

---

## 📂 Estructura del Proyecto

- `nspawn-ctl.sh`: CLI principal.
- `lib/common.sh`: Funciones base y lógica de limpieza.
- `lib/profiles.sh`: Perfiles de hardware y red por cada tipo.
- `setup/`: Scripts de inicialización.
- `cache/`: Descargas temporales persistentes.
