#!/bin/bash
# Firefox — Instalación + hardening (telemetria, privacidad, rendimiento)
# Ejecutar después de instalar cualquier UI (tiling/plasma/gnome)
set -e

# Detectar usuario real (el que no es root)
USERNAME=$(getent passwd 1000 | cut -d: -f1)
HOME_DIR="/home/$USERNAME"

echo "Configurando Firefox para el usuario: $USERNAME"

# --- Instalar Firefox + idioma ---
sudo pacman -S --needed --noconfirm firefox firefox-i18n-es-mx

# --- Forzar creación de estructura de directorios ---
PROFILES_DIR="$HOME_DIR/.mozilla/firefox"
sudo -u "$USERNAME" mkdir -p "$PROFILES_DIR"

# --- Generar perfil si no existe ---
# Buscamos si existe algún directorio que termine en .default o .default-release
if ! find "$PROFILES_DIR" -maxdepth 1 -name "*.default*" -type d | grep -q .; then
  echo "Creando perfil inicial de Firefox (headless)..."
  sudo -u "$USERNAME" firefox --headless > /dev/null 2>&1 &
  FPID=$!
  
  # Esperar hasta 15 segundos a que Firefox cree los archivos
  TIMEOUT=15
  while [ $TIMEOUT -gt 0 ]; do
    PROFILE_PATH=$(find "$PROFILES_DIR" -maxdepth 1 -name "*.default*" -type d | head -1)
    if [ -n "$PROFILE_PATH" ]; then
      echo "Perfil encontrado en: $PROFILE_PATH"
      break
    fi
    sleep 1
    ((TIMEOUT--))
  done

  kill $FPID 2>/dev/null || true
  sleep 2
fi

# --- Detectar perfil final ---
PROFILE=$(find "$PROFILES_DIR" -maxdepth 1 -name "*.default-release" -type d | head -1)
if [ -z "$PROFILE" ]; then
  PROFILE=$(find "$PROFILES_DIR" -maxdepth 1 -name "*.default*" -type d | head -1)
fi

if [ -z "$PROFILE" ]; then
  echo "Error: No se pudo crear o encontrar el perfil de Firefox."
  exit 1
fi

echo "Configurando perfil: $PROFILE"

# --- user.js: hardening + privacidad + rendimiento ---
sudo -u "$USERNAME" cat > "$PROFILE/user.js" <<'USERJS'
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

// === Estudios y experimentos (Normandy/Shield) ===
user_pref("app.normandy.enabled", false);
user_pref("app.normandy.api_url", "");
user_pref("app.shield.optoutstudies.enabled", false);

// === Pocket ===
user_pref("extensions.pocket.enabled", false);

// === Actividad patrocinada y sugerencias ===
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
user_pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);

// === Medicion de anuncios (Privacy-Preserving Attribution) ===
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

// === Captive portal (no conectar a servidores de deteccion) ===
user_pref("network.captive-portal-service.enabled", false);

// === Connectivity check ===
user_pref("network.connectivity-service.enabled", false);

// === Safe Browsing (envia URLs a Google) ===
user_pref("browser.safebrowsing.malware.enabled", false);
user_pref("browser.safebrowsing.phishing.enabled", false);
user_pref("browser.safebrowsing.downloads.enabled", false);

// === Geolocation ===
user_pref("geo.enabled", false);

// === Rendimiento: Wayland nativo + GPU ===
user_pref("gfx.webrender.all", true);
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("widget.dmabuf.force-enabled", true);

// === OLED: forzar dark mode en contenido web ===
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

// === Pestanas verticales (nativo desde Firefox 136) ===
user_pref("sidebar.revamp", true);
user_pref("sidebar.verticalTabs", true);
user_pref("sidebar.visibility", "hide-sidebar");
user_pref("sidebar.main.tools", "history");

// === Densidad compacta (menos espacio en barras) ===
user_pref("browser.compactmode.show", true);
user_pref("browser.uidensity", 1);

// === Desactivar funciones innecesarias ===
user_pref("browser.tabs.firefox-view", false);
user_pref("browser.tabs.tabmanager.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("reader.parse-on-load.enabled", false);

// === Reducir huella: procesos y memoria ===
user_pref("dom.ipc.processCount", 4);
user_pref("browser.sessionhistory.max_entries", 15);
user_pref("browser.cache.disk.capacity", 256000);
user_pref("browser.sessionstore.interval", 30000);

// === Idioma ===
user_pref("intl.accept_languages", "es-MX,es,en-US,en");
user_pref("intl.locale.requested", "es-MX");
USERJS

# --- Enterprise policies ---
sudo mkdir -p /usr/lib/firefox/distribution
sudo tee /usr/lib/firefox/distribution/policies.json > /dev/null <<'POLICIES'
{
  "policies": {
    "DisableAppUpdate": true,
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "DisableFirefoxAccounts": false,
    "DisableFormHistory": false,
    "DontCheckDefaultBrowser": true,
    "HardwareAcceleration": true,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      },
      "skipredirect@sblask": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/skip-redirect/latest.xpi"
      }
    }
  }
}
POLICIES

# --- Limpieza de binarios de telemetría ---
for f in crashreporter minidump-analyzer pingsender; do
  sudo rm -f "/usr/lib/firefox/$f"
done

# Persistir eliminación vía pacman NoExtract
if ! grep -q "NoExtract.*crashreporter" /etc/pacman.conf 2>/dev/null; then
  sudo sed -i '/^\[options\]/a NoExtract = usr/lib/firefox/crashreporter usr/lib/firefox/minidump-analyzer usr/lib/firefox/pingsender' /etc/pacman.conf
fi

# Ajuste final de permisos
sudo chown -R "$USERNAME:users" "$HOME_DIR/.mozilla"

echo ""
echo "=== Firefox instalado y optimizado con éxito ==="
echo "Perfil configurado en: $PROFILE"
