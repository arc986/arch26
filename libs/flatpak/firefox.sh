#!/bin/bash
# Firefox via Flatpak — Alternativa a libs/firefox.sh (pacman)
# Sandbox aislado, verified por Mozilla en Flathub
# Requiere: libs/flatpak.sh ejecutado previamente
#
# Ventajas vs pacman:
#   - Sandbox real (sin acceso al home, filesystem aislado)
#   - Runtime propio (no depende de libs del host)
#   - Rollback facil (flatpak update --commit)
#
# Archivos creados:
#   Overrides de permisos para org.mozilla.firefox
#   ~/.var/app/org.mozilla.firefox/  (datos del sandbox)
set -e

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' C='\033[1;36m' N='\033[0m'
info()  { printf "${C}:: %s${N}\n" "$*"; }
ok()    { printf "${G}✓  %s${N}\n" "$*"; }
warn()  { printf "${Y}⚠  %s${N}\n" "$*"; }
die()   { printf "${R}✗  %s${N}\n" "$*"; exit 1; }

[[ $EUID -eq 0 ]] || die "Ejecuta como root"
command -v flatpak &>/dev/null || die "Flatpak no instalado. Ejecuta primero: bash libs/flatpak.sh"

USERNAME=$(getent passwd 1000 | cut -d: -f1)
[ -z "$USERNAME" ] && die "No se encontro usuario UID 1000"
HOME_DIR="/home/$USERNAME"
APP_ID="org.mozilla.firefox"

# ── Instalar Firefox ──
if flatpak list --app --columns=application | grep -q "$APP_ID"; then
  ok "Firefox Flatpak ya instalado"
else
  info "Instalando Firefox desde Flathub (verified por Mozilla)..."
  flatpak install -y flathub "$APP_ID"
  ok "Firefox instalado"
fi

# ── Permisos: restringir lo que flatpak.sh no cubre ──
info "Aplicando permisos optimizados..."

# Permitir red (navegador la necesita)
flatpak override "$APP_ID" --share=network
# GPU para rendering
flatpak override "$APP_ID" --device=dri
# Wayland nativo (el sandbox no hereda /etc/environment)
flatpak override "$APP_ID" --socket=wayland
flatpak override "$APP_ID" --env=MOZ_ENABLE_WAYLAND=1
# Descargas: solo xdg-download, no home completo
flatpak override "$APP_ID" --filesystem=xdg-download
# Notificaciones
flatpak override "$APP_ID" --talk-name=org.freedesktop.Notifications
# Portales (abrir archivos, imprimir, etc.)
flatpak override "$APP_ID" --talk-name=org.freedesktop.portal.*
# Tema dark del host
flatpak override "$APP_ID" --filesystem=xdg-config/gtk-3.0:ro
flatpak override "$APP_ID" --filesystem=xdg-config/gtk-4.0:ro
flatpak override "$APP_ID" --env=GTK_THEME=Adwaita-dark

ok "Permisos aplicados"

# ── Perfil y hardening ──
# Firefox Flatpak guarda su perfil en ~/.var/app/org.mozilla.firefox/.mozilla/firefox
PROFILES_DIR="$HOME_DIR/.var/app/$APP_ID/.mozilla/firefox"
if [ ! -d "$PROFILES_DIR" ]; then
  info "Creando perfil inicial..."
  sudo -u "$USERNAME" flatpak run "$APP_ID" --headless &
  sleep 4
  kill %1 2>/dev/null || true
  sleep 1
fi

PROFILE=$(find "$PROFILES_DIR" -maxdepth 1 -name "*.default-release" -type d 2>/dev/null | head -1)
[ -z "$PROFILE" ] && PROFILE=$(find "$PROFILES_DIR" -maxdepth 1 -name "*.default*" -type d 2>/dev/null | head -1)
[ -z "$PROFILE" ] && die "No se encontro perfil de Firefox"

if [ -f "$PROFILE/user.js" ]; then
  ok "user.js ya existe — no se modifica"
else
  info "Aplicando hardening (user.js)..."
  cat > "$PROFILE/user.js" <<'USERJS'
// === Telemetria: desactivar todo ===
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);
user_pref("toolkit.telemetry.server", "data:,");
user_pref("toolkit.telemetry.cachedClientID", "");
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);

// === Crash reporter ===
user_pref("breakpad.reportURL", "");
user_pref("browser.tabs.crashReporting.sendReport", false);
user_pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);

// === Estudios y experimentos ===
user_pref("app.normandy.enabled", false);
user_pref("app.normandy.api_url", "");
user_pref("app.shield.optoutstudies.enabled", false);

// === Pocket ===
user_pref("extensions.pocket.enabled", false);

// === Actividad patrocinada ===
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
user_pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);

// === Medicion de anuncios ===
user_pref("dom.private-attribution.submission.enabled", false);

// === Tracking protection ===
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
user_pref("privacy.trackingprotection.cryptomining.enabled", true);
user_pref("privacy.trackingprotection.fingerprinting.enabled", true);

// === Cookies: solo del sitio visitado ===
user_pref("network.cookie.cookieBehavior", 5);

// === HTTPS-Only ===
user_pref("dom.security.https_only_mode", true);

// === DNS over HTTPS (desactivar — usamos systemd-resolved) ===
user_pref("network.trr.mode", 5);
user_pref("doh-rollout.disable-heuristics", true);

// === WebRTC: no filtrar IP local ===
user_pref("media.peerconnection.ice.default_address_only", true);

// === Referer: solo mismo origen ===
user_pref("network.http.referer.XOriginPolicy", 2);
user_pref("network.http.referer.XOriginTrimmingPolicy", 2);

// === Captive portal ===
user_pref("network.captive-portal-service.enabled", false);

// === Connectivity check ===
user_pref("network.connectivity-service.enabled", false);

// === Safe Browsing ===
user_pref("browser.safebrowsing.malware.enabled", false);
user_pref("browser.safebrowsing.phishing.enabled", false);
user_pref("browser.safebrowsing.downloads.enabled", false);

// === Geolocation ===
user_pref("geo.enabled", false);

// === Rendimiento: GPU ===
user_pref("gfx.webrender.all", true);
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("widget.dmabuf.force-enabled", true);

// === OLED: dark mode en contenido web ===
user_pref("layout.css.prefers-color-scheme.content-override", 0);
user_pref("ui.systemUsesDarkTheme", 1);
user_pref("browser.theme.content-theme", 0);
user_pref("browser.theme.toolbar-theme", 0);

// === UI limpia ===
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.startup.page", 3);

// === Pestanas verticales ===
user_pref("sidebar.revamp", true);
user_pref("sidebar.verticalTabs", true);
user_pref("sidebar.visibility", "hide-sidebar");
user_pref("sidebar.main.tools", "history");

// === Densidad compacta ===
user_pref("browser.compactmode.show", true);
user_pref("browser.uidensity", 1);

// === Desactivar funciones innecesarias ===
user_pref("browser.tabs.firefox-view", false);
user_pref("browser.tabs.tabmanager.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("reader.parse-on-load.enabled", false);

// === Reducir huella ===
user_pref("dom.ipc.processCount", 4);
user_pref("browser.sessionhistory.max_entries", 15);
user_pref("browser.cache.disk.capacity", 256000);
user_pref("browser.sessionstore.interval", 30000);

// === Idioma ===
user_pref("intl.accept_languages", "es-MX,es,en-US,en");
user_pref("intl.locale.requested", "es-MX");
USERJS
  chown "$USERNAME:users" "$PROFILE/user.js"
  ok "user.js aplicado"
fi

chown -R "$USERNAME:users" "$HOME_DIR/.var/app/$APP_ID"

echo ""
ok "Firefox Flatpak instalado y optimizado"
echo ""
info "Resumen:"
echo "  Origen:      Flathub verified (Mozilla)"
echo "  Sandbox:     sin acceso a home, solo xdg-download"
echo "  OLED:        dark mode en contenido web"
echo "  UI:          pestanas verticales, densidad compacta"
echo "  Datos:       ~/.var/app/$APP_ID/"
echo ""
echo "  Ejecutar:    flatpak run $APP_ID"
echo "  Actualizar:  flatpak update $APP_ID"
echo "  Permisos:    flatpak info --show-permissions $APP_ID"
echo "  Eliminar:    flatpak uninstall $APP_ID"
