# 📘 Guía de Supervivencia: systemd-nspawn para Dummies

¡Bienvenido! Si estás leyendo esto, es porque quieres usar contenedores pero odias que tu sistema se llene de basura o que Docker consuma toda tu RAM. Esta guía te enseñará a usar este sistema de contenedores ultraligeros como un profesional, incluso si nunca has usado nspawn.

---

## 1. ¿Qué es esto y por qué debería importarme?

Imagina que quieres probar una versión nueva de Python o montar un cluster de Kubernetes. Normalmente:
1. Instalas mil paquetes en tu PC (y luego se te olvida borrarlos).
2. Tu sistema se vuelve lento.
3. Te quedas sin batería.

**Con este sistema nspawn:**
*   **Nada se instala en tu PC real**: Todo vive dentro de una "cajita" (contenedor).
*   **Velocidad nativa**: No es una máquina virtual lenta; corre a la velocidad de tu PC.
*   **Cero consumo en pausa**: Si el contenedor no hace nada, consume 0% de tu CPU.
*   **Instantáneo**: Gracias a Btrfs, puedes copiar o borrar contenedores en menos de un segundo.

---

## 2. Los Conceptos Básicos

### La regla de oro: El "Host" se mantiene limpio
Todo lo que necesites instalar (Go, Rust, Node, base de datos) se instala **dentro** del contenedor. Tu PC real (el host) solo tiene los scripts de este repositorio.

### ¿Dónde están mis archivos?
Todos los contenedores de desarrollo (`venv`) comparten una carpeta con tu PC: `~/Projects`.
*   Tú programas en tu PC (con tu editor favorito: VS Code, Cursor, etc.).
*   El contenedor compila y ejecuta el código en `/root/Projects`.
*   ¡Así tu código está seguro en tu PC pero se ejecuta aislado!

---

## 3. El día a día: Comandos que usarás siempre

Para todo usaremos el script `./nspawn-ctl.sh`.

*   **¿Qué tengo instalado?**
    `./nspawn-ctl.sh list`
*   **¡Quiero entrar a mi entorno de Go!**
    `./nspawn-ctl.sh shell venv-go` (Si no está encendido, el sistema te lo dirá).
*   **¿Cómo lo enciendo?**
    `./nspawn-ctl.sh start venv-go`
*   **¿Cómo lo apago para ahorrar batería?**
    `./nspawn-ctl.sh stop venv-go`

---

## 4. Guía por Perfil: ¿Qué quieres hacer hoy?

### A. Soy Desarrollador (Python, Go, Node, Rust)
1. **Crea tu entorno**: `./nspawn-ctl.sh create venv [tu-lenguaje]`
2. **Entra a trabajar**: `./nspawn-ctl.sh shell venv-[tu-lenguaje]`
3. **Tu código**: Pon tus proyectos en la carpeta `Projects/` de tu PC. Dentro del contenedor aparecerán mágicamente.

### B. Quiero aprender Kubernetes (k3s)
1. **Crea el laboratorio**: `./nspawn-ctl.sh create k3s mi-lab`
2. **Espera un poco**: El sistema creará un master y dos workers.
3. **Usa kubectl**: No instales kubectl en tu PC. Entra al master:
   `sudo machinectl shell k3s-mi-lab-master -- kubectl get nodes`
4. **Apaga todo al terminar**: `./nspawn-ctl.sh stop k3s` (Detiene todos los nodos del cluster).

### C. Necesito una Máquina Virtual real (KVM)
A veces un contenedor no es suficiente (necesitas otro Kernel o un sistema completo).
1. **Crea el servidor**: `./nspawn-ctl.sh create kvm cockpit`
2. **Gestiona por Web**: Entra a la IP que te dé el script en el puerto 9090.
3. **Usuario/Pass**: `root` / `kvm`. ¡Ahí tienes un panel visual para crear VMs!

---

## 5. El Superpoder: Snapshots (Botón de "Deshacer")

¿Vas a instalar algo peligroso o que podría romper el contenedor?
1. **Haz una foto**: `./nspawn-ctl.sh snapshot mi-contenedor`
2. El sistema crea una copia exacta en un segundo. Si rompes el original, puedes borrarlo y renombrar el snapshot. ¡Es el botón de "deshacer" definitivo!

---

## 6. Trucos Avanzados

### ¿Cómo sé cuánta RAM consumen?
Ejeucta `./nspawn-ctl.sh resources`. Verás una lista en tiempo real de quién está gastando más.

### Quiero exponer una web que corre en mi contenedor
Si programas una web en el puerto 80 del contenedor:
1. Abre `/etc/systemd/nspawn/mi-contenedor.nspawn`.
2. Añade la línea: `Port=tcp:8080:80`.
3. Reinicia el contenedor. Ahora si vas en tu navegador a `localhost:8080`, verás la web del contenedor.

---

## 7. Solución de Problemas (FAQ)

*   **"El comando sudo pide contraseña muchas veces"**: Es normal por seguridad, el sistema necesita permisos para manejar contenedores y redes.
*   **"No tengo internet dentro del contenedor"**: Asegúrate de que `systemd-networkd` esté corriendo en tu PC real.
*   **"¿Cómo borro todo y empiezo de cero?"**: Usa `./nspawn-ctl.sh delete [nombre]`. Borrará el disco, la config y los límites de RAM.

---

**¡Felicidades!** Ya sabes más que el 90% de la gente sobre contenedores ligeros. Disfruta de tu PC rápido, limpio y con batería de larga duración. 🚀
