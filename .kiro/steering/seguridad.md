## Seguridad y fuentes de software

- Solo repositorios oficiales. Nunca sugerir, usar ni referenciar paquetes, librerías, scripts o canales de fuentes no oficiales (AUR, repos de GitHub, PPAs, scripts de instalación de terceros, etc.).
- Si una funcionalidad no se puede lograr usando exclusivamente repos oficiales, no se implementa. Se descarta y se busca otra solución o se prescinde de ella.
- La seguridad y privacidad no se negocian por ninguna característica.

## Configuraciones del sistema

- Las variables de entorno y configuraciones que son optimizaciones generales del sistema van en la instalación base (`/etc/environment`, sysctl, etc.), no en scripts de apps individuales.
- Si un entorno aislado (Flatpak sandbox, nspawn, etc.) no hereda la config del host, se re-aplica solo lo estrictamente necesario para ese entorno, con un comentario explicando por qué.
- Variables específicas de una app (ej: `MOZ_ENABLE_WAYLAND`) van como override de esa app, no como config global del sandbox.
