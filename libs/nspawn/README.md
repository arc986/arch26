# nspawn — Contenedores systemd-nspawn optimizados

Host limpio. Cero paquetes extra (systemd ya incluye nspawn).
Contenedores en btrfs (`@machines`) con snapshots nativos.

## Principios

- **Huella cero en idle**: CPUWeight (peso relativo, no reserva) + MemoryHigh (throttle suave)
- **Bajo demanda**: si necesita mas recursos, los toma. Si no hace nada, consume nada
- **Host limpio**: nada se instala automaticamente en el host
- **Aislamiento real**: PrivateUsers, capabilities minimas, SystemCallFilter, Zones de red

## Estructura

```
nspawn/
├── nspawn-ctl.sh       CLI principal
├── lib/
│   ├── common.sh       Funciones compartidas + recursos via service override
│   └── profiles.sh     Perfiles .nspawn + limites por tipo
└── setup/
    ├── venv.sh         Desarrollo (Go/Python/Web/Rust)
    ├── k3s.sh          Clusters K3s
    ├── kvm.sh          KVM/QEMU aislado
    └── box.sh          Generico (con/sin Podman)
```

## Recursos: como funciona

El archivo `.nspawn` solo soporta `[Exec]`, `[Files]` y `[Network]`.
Los limites de recursos van en el service unit de systemd:

```
/etc/systemd/system/systemd-nspawn@<nombre>.service.d/resources.conf
```

| Directiva | Efecto |
|---|---|
| `CPUWeight=50` | Peso relativo. Idle = 0% CPU real. Bajo demanda si necesita |
| `MemoryHigh=384M` | Throttle suave: frena sin matar |
| `MemoryMax=512M` | OOM kill como ultimo recurso |
| `MemorySwapMax=0` | Sin swap — todo en RAM o nada |
| `TasksMax=128` | Anti fork bomb |

## CLI

```
nspawn-ctl <accion> [filtro]
```

### Crear rapido (sin menus)

```bash
nspawn-ctl create venv go
nspawn-ctl create venv all
nspawn-ctl create k3s lab
nspawn-ctl create kvm cockpit
nspawn-ctl create box test alpine
```

### Crear interactivo

```bash
nspawn-ctl create
```

### Acciones

| Accion | Descripcion |
|---|---|
| `list [filtro]` | Tabla: tipo, nombre, estado, RAM real, disco |
| `status` | Estado + config .nspawn + recursos |
| `start [filtro]` | Iniciar (1 = directo, N = batch) |
| `stop [filtro]` | Detener (1 = directo, N = batch) |
| `shell [filtro]` | Entrar a un contenedor |
| `logs` | Ver logs (journalctl -M) |
| `resources` | RAM/CPU en vivo (systemd-cgtop) |
| `snapshot` | Crear snapshot btrfs |
| `ephemeral` | Copia desechable (cambios se pierden) |
| `delete` | Eliminar contenedor + config + overrides |
| `config` | Ver archivo .nspawn |
| `commands` | Cheatsheet |

## Filtros por prefijo

| Prefijo | Tipo |
|---|---|
| `venv` | Entornos desarrollo |
| `k3s` | Clusters K3s |
| `kvm` | KVM aislado |
| `box` | Contenedores generales |

## Requisitos

- archlinux base instalado (btrfs, subvolumen @machines)
- Nada mas. systemd-nspawn ya viene con systemd.
