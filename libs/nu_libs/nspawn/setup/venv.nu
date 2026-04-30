# Entornos de desarrollo ligeros basados en Alpine
# Cada lenguaje es un clone instantáneo del template → setup aislado del host

use ../config.nu *
use ../core.nu [
    ensure_not_exists, run_in, download_cached, copy_into,
    create_alpine_base, clone_template,
    write_nspawn_config, apply_resources, sudo_exists
]

const VENV_TMPL = ".venv-template"

# Crea el template Alpine base con herramientas de compilación (solo una vez)
def venv_template [] {
    if (sudo_exists $"($MACHINES)/($VENV_TMPL)") { return }
    print "Creando template Alpine para venv..."
    create_alpine_base $VENV_TMPL
    run_in $VENV_TMPL "apk add --no-cache curl build-base ca-certificates git"
    print "[+] Template listo"
}

def setup_go [name: string] {
    clone_template $VENV_TMPL $name
    run_in $name "apk add --no-cache go"
    run_in $name "echo 'export CGO_ENABLED=0' >> /etc/profile"
    write_nspawn_config $name $PROFILES.venv
    apply_resources $name $PROFILES.venv.resources
    print $"[+] ($name)  (Go)"
}

def setup_python [name: string] {
    clone_template $VENV_TMPL $name
    run_in $name "apk add --no-cache python3 py3-pip py3-virtualenv"
    run_in $name "echo 'export PYTHONDONTWRITEBYTECODE=1' >> /etc/profile"
    write_nspawn_config $name $PROFILES.venv
    apply_resources $name $PROFILES.venv.resources
    print $"[+] ($name)  (Python)"
}

def setup_web [name: string] {
    clone_template $VENV_TMPL $name
    run_in $name "apk add --no-cache nodejs npm"
    run_in $name "npm install -g typescript pnpm"
    write_nspawn_config $name $PROFILES.venv
    apply_resources $name $PROFILES.venv.resources
    print $"[+] ($name)  (Web/Node)"
}

def setup_rust [name: string] {
    let rustup = download_cached "https://sh.rustup.rs" "rustup-init.sh"
    clone_template $VENV_TMPL $name
    copy_into $name $rustup "/tmp/rustup-init.sh"
    run_in $name "sh /tmp/rustup-init.sh -y --profile minimal --default-toolchain stable"
    run_in $name "echo 'source /root/.cargo/env' >> /etc/profile"
    write_nspawn_config $name $PROFILES.venv
    apply_resources $name $PROFILES.venv.resources
    print $"[+] ($name)  (Rust)"
}

# Crea un entorno de desarrollo aislado para el lenguaje indicado
export def "nspawn create venv" [
    lang?: string  # go | python | web | rust | all
] {
    let lang = if ($lang | is-empty) {
        print "Lenguaje disponible: go  python  web  rust  all"
        input "→ "
    } else { $lang }

    venv_template

    match $lang {
        "go"     => { setup_go     "venv-go" }
        "python" => { setup_python "venv-python" }
        "web"    => { setup_web    "venv-web" }
        "rust"   => { setup_rust   "venv-rust" }
        "all"    => {
            setup_go     "venv-go"
            setup_python "venv-python"
            setup_web    "venv-web"
            setup_rust   "venv-rust"
        }
        _ => { error make {msg: $"Lenguaje desconocido: ($lang)  →  go | python | web | rust | all"} }
    }

    let names = if $lang == "all" { ["venv-go", "venv-python", "venv-web", "venv-rust"] } else { [$"venv-($lang)"] }
    print $"\nCreados: ($names | str join ', ')"
    print "  Uso: nspawn start <nombre>  →  nspawn shell <nombre>"
    print "  ~/Projects del host aparece en /root/Projects dentro del contenedor."
}
