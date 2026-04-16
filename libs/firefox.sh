#!/bin/bash
# Firefox — Instalacion + hardening (telemetria, privacidad, rendimiento)
# Ejecutar despues de instalar cualquier UI (tiling/plasma/gnome)
set -e

USERNAME=$(getent passwd 1000 | cut -d: -f1)
HOME_DIR="/home/$USERNAME"

# --- Instalar Firefox + idioma ---
sudo pacman -S --needed firefox firefox-i18n-es-mx

# --- Esperar a que exista un perfil ---
PROFILES_DIR="$HOME_DIR/.mozilla/firefox"
if [ ! -d "$PROFILES_DIR" ]; then
  echo "Creando perfil inicial de Firefox..."
  sudo -u "$USERNAME" firefox --headless &
  sleep 3
  kill %1 2>/dev/null || true
  sleep 1
fi

# --- Detectar perfil ---
PROFILE=$(find "$PROFILES_DIR" -maxdepth 1 -name "*.default-release" -type d | head -1)
if [ -z "$PROFILE" ]; then
  PROFILE=$(find "$PROFILES_DIR" -maxdepth 1 -name "*.default*" -type d | head -1)
fi
[ -z "$PROFILE" ] && echo "Error: no se encontro perfil de Firefox" && exit 1

echo "Perfil: $PROFILE"

# --- user.js: hardening + privacidad + rendimiento ---
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

// === UI limpia ===
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.startup.page", 3);

// === Idioma ===
user_pref("intl.accept_languages", "es-MX,es,en-US,en");
user_pref("intl.locale.requested", "es-MX");
USERJS

# --- Enterprise policies: desactivar updates automaticos + crashreporter ---
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
    "OverridePostUpdatePage": ""
  }
}
POLICIES

# --- Eliminar crashreporter y pingsender del sistema ---
# Se regeneran con updates, pero pacman NoExtract los mantiene fuera
for f in crashreporter minidump-analyzer pingsender; do
  sudo rm -f "/usr/lib/firefox/$f"
done

# Persistir eliminacion via pacman NoExtract
if ! grep -q "NoExtract.*crashreporter" /etc/pacman.conf 2>/dev/null; then
  sudo sed -i '/^\[options\]/a NoExtract = usr/lib/firefox/crashreporter usr/lib/firefox/minidump-analyzer usr/lib/firefox/pingsender' /etc/pacman.conf
fi

chown -R "$USERNAME:users" "$PROFILES_DIR"

echo ""
echo "=== Firefox instalado y optimizado ==="
echo "Telemetria desactivada, tracking protection activo, HTTPS-Only, Wayland nativo."
echo "Updates de Firefox desactivados (se actualiza via pacman)."
