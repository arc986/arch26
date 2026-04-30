# nspawn - Nushell Container Management

Una librería ultraligera y nativa en Nushell para gestionar contenedores `systemd-nspawn` usando instantáneas Btrfs. Diseñada para crear entornos de desarrollo, laboratorios, y servidores virtualizados de manera rápida, segura y aislada en tu host.

Compatible y optimizada para los estándares modernos de **Nushell (0.90+)**.

## Estructura del Proyecto

```text
libs/nu_libs/nspawn/
├── mod.nu           # Entrada principal del módulo. Re-exporta todo.
├── config.nu        # Capa de configuración: constantes, directorios y PROFILES.
├── core.nu          # Utilidades compartidas y comandos de gestión (start/stop/list/shell).
└── setup/           # Plantillas de creación de contenedores específicos.
    ├── mod.nu       # Exporta todas las plantillas de creación.
    ├── venv.nu      # `nspawn create venv`: Entornos de desarrollo (Go, Python, Web, Rust).
    ├── k3s.nu       # `nspawn create k3s`: Clústeres de Kubernetes con master y workers.
    ├── kvm.nu       # `nspawn create kvm`: Servidor de virtualización KVM + libvirt + Cockpit.
    ├── box.nu       # `nspawn create box`: Contenedores Alpine genéricos y configurables.
    └── ai.nu        # `nspawn create ai`: Contenedor para IA (ROCm + Ollama + GPU/NPU AMD).
```

## Requisitos Previos

- **Nushell** (versión reciente recomendada, testeado en > 0.90+)
- **systemd-nspawn** y **machinectl** (`systemd-container`)
- Sistema de archivos **Btrfs** para uso de instantáneas rápidas y eficientes en almacenamiento (`/var/lib/machines`)
- Permisos configurados mediante `sudoers` (ver sección de uso).

## Instalación y Uso Básico

Para cargar la librería en tu sesión actual de Nushell:

```nushell
use libs/nu_libs/nspawn/mod.nu *
```

### 1. Comandos Principales

```nushell
nspawn list             # Muestra todos los contenedores y su consumo de RAM
nspawn status <nombre>  # Muestra el estatus de un contenedor
nspawn start <nombre>   # Arranca un contenedor
nspawn stop <nombre>    # Detiene un contenedor
nspawn shell <nombre>   # Abre una terminal (shell) interactiva en el contenedor
nspawn logs <nombre>    # Muestra los logs del contenedor (journalctl)
nspawn delete <nombre>  # Elimina un contenedor y su subvolumen btrfs
```

## Creación de Entornos (`nspawn create`)

La suite de comandos `create` facilita el despliegue instantáneo de entornos preconfigurados:

### Entornos de Desarrollo Aislados (`venv`)
Descarga una plantilla de Alpine y configura entornos sin ensuciar tu sistema host. Tu directorio `~/Projects` se montará automáticamente.
```nushell
nspawn create venv go      # Entorno Go
nspawn create venv python  # Entorno Python
nspawn create venv web     # Entorno Node.js/TypeScript
nspawn create venv rust    # Entorno Rust
nspawn create venv all     # Crea los cuatro simultáneamente
```

### Kubernetes (`k3s`)
Despliega un clúster k3s ligero (master y múltiples workers) con redes aisladas.
```nushell
nspawn create k3s mi-lab --workers 2
```

### Virtualización (`kvm`)
Monta un servidor de virtualización anidado con libvirt, qemu y Cockpit Web.
```nushell
nspawn create kvm
nspawn create kvm --no-cockpit  # Solo SSH y virsh
```

### Contenedor de IA Avanzado (`ai`)
Contenedor altamente optimizado para Inteligencia Artificial (ROCm + Ollama) que delega correctamente el uso de la GPU (DRI) y aceleradores NPU (XDNA) de hardware AMD, aislándolo del host.
```nushell
nspawn create ai
```

### Cajas Genéricas (`box`)
Un sistema base configurado a tu medida.
```nushell
nspawn create box mi-caja
nspawn create box mi-caja --network host
nspawn create box mi-caja --podman  # Habilita anidación con Podman interno
```
