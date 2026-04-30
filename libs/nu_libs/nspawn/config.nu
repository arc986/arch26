# Rutas, versiones y perfiles de contenedor — toda la "data layer" en un lugar

export const MACHINES    = "/var/lib/machines"
export const NSPAWN_CFG  = "/etc/systemd/nspawn"
export const SYSTEMD_SVC = "/etc/systemd/system"
export const ALPINE_VER  = "3.21"

export def cache_dir [] -> string {
    $"($env.HOME)/.nspawn/cache"
}

# Usuario con UID 1000 (para bind mounts de ~/Projects)
export def host_user [] -> record<name: string, home: string> {
    open /etc/passwd
    | lines
    | parse "{name}:{_p}:{uid}:{_g}:{_i}:{home}:{_s}"
    | where uid == "1000"
    | first
    | select name home
}

# Perfiles de contenedor: configuración nspawn + límites cgroup
# Todos los campos presentes en todos los perfiles → sin accesos opcionales
export const PROFILES = {
    venv: {
        boot: false, private_users: "pick", network: "zone:venv",
        caps: [], syscall_filter: "~@obsolete ~@clock",
        bind_projects: true, bind_dotfiles: true, bind_kmsg: false,
        port: "", devices: [], device_allows: [],
        resources: {cpu_weight: 50, mem_high: "384M", mem_max: "512M", tasks_max: 128}
    }
    k3s_master: {
        boot: true, private_users: "no", network: "zone:k3s",
        caps: ["CAP_NET_ADMIN", "CAP_NET_RAW", "CAP_SYS_ADMIN", "CAP_SYS_PTRACE", "CAP_SYS_MODULE"],
        syscall_filter: "~@obsolete ~@clock",
        bind_projects: false, bind_dotfiles: false, bind_kmsg: true,
        port: "", devices: [], device_allows: [],
        resources: {cpu_weight: 50, mem_high: "96M", mem_max: "192M", tasks_max: 256}
    }
    k3s_worker: {
        boot: true, private_users: "no", network: "zone:k3s",
        caps: ["CAP_NET_ADMIN", "CAP_NET_RAW", "CAP_SYS_ADMIN", "CAP_SYS_PTRACE"],
        syscall_filter: "~@obsolete ~@clock",
        bind_projects: false, bind_dotfiles: false, bind_kmsg: true,
        port: "", devices: [], device_allows: [],
        resources: {cpu_weight: 25, mem_high: "48M", mem_max: "96M", tasks_max: 64}
    }
    kvm: {
        boot: true, private_users: "no", network: "zone:kvm",
        caps: ["CAP_NET_ADMIN", "CAP_NET_RAW", "CAP_SYS_ADMIN", "CAP_MKNOD", "CAP_SYS_RESOURCE"],
        syscall_filter: "~@obsolete",
        bind_projects: false, bind_dotfiles: false, bind_kmsg: false,
        port: "tcp:9090:9090", devices: ["/dev/kvm", "/dev/vhost-net"],
        device_allows: ["/dev/kvm rwm", "/dev/vhost-net rwm"],
        resources: {cpu_weight: 100, mem_high: "1G", mem_max: "2G", tasks_max: 256}
    }
    box: {
        boot: false, private_users: "pick", network: "zone:containers",
        caps: [], syscall_filter: "~@obsolete",
        bind_projects: false, bind_dotfiles: false, bind_kmsg: false,
        port: "", devices: [], device_allows: [],
        resources: {cpu_weight: 25, mem_high: "128M", mem_max: "256M", tasks_max: 128}
    }
    ai: {
        boot: false, private_users: "no", network: "zone:ai",
        caps: ["CAP_SYS_ADMIN"], syscall_filter: "",
        bind_projects: false, bind_dotfiles: false, bind_kmsg: false,
        port: "tcp:11434:11434", devices: ["/dev/dri", "/dev/kfd", "/dev/accel"],
        device_allows: ["char-drm rwm", "/dev/kfd rwm", "/dev/accel rwm"],
        resources: {cpu_weight: 75, mem_high: "3G", mem_max: "6G", tasks_max: 256}
    }
}
