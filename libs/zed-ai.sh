#!/bin/bash
# Zed — Configuracion de IA (interactivo)
# Guia paso a paso para configurar proveedores de IA en Zed
# Auto-detecta Ollama local si esta corriendo
# Requiere: libs/zed.sh ejecutado previamente
set -e

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' C='\033[1;36m' N='\033[0m'
info()  { printf "${C}:: %s${N}\n" "$*"; }
ok()    { printf "${G}✓  %s${N}\n" "$*"; }
warn()  { printf "${Y}⚠  %s${N}\n" "$*"; }
die()   { printf "${R}✗  %s${N}\n" "$*"; exit 1; }

USERNAME=$(getent passwd 1000 | cut -d: -f1)
[ -z "$USERNAME" ] && die "No se encontro usuario UID 1000"
HOME_DIR="/home/$USERNAME"
CFG="$HOME_DIR/.config/zed"
SETTINGS="$CFG/settings.json"

[ -f "$SETTINGS" ] || die "$SETTINGS no existe. Ejecuta primero: bash libs/zed.sh"

# ── Auto-deteccion ──
OLLAMA_RUNNING=false
OLLAMA_MODELS=""
if command -v ollama &>/dev/null && curl -sf http://localhost:11434/api/tags &>/dev/null; then
  OLLAMA_RUNNING=true
  OLLAMA_MODELS=$(curl -sf http://localhost:11434/api/tags | python3 -c "
import json,sys
data=json.load(sys.stdin)
for m in data.get('models',[]):
    print(m['name'])
" 2>/dev/null || true)
fi

# ── Menu principal ──
echo ""
info "Zed — Configuracion de IA"
echo ""
echo "  ── Proveedores en la nube (requieren API key) ──"
echo "    1) Anthropic        Claude Sonnet/Opus/Haiku"
echo "    2) OpenAI           GPT-4o / GPT-4o-mini"
echo "    3) Google AI        Gemini Flash / Pro"
echo "    4) DeepSeek         DeepSeek Chat / Reasoner"
echo "    5) GitHub Copilot   Requiere suscripcion GitHub"
echo "    6) OpenRouter       Acceso a multiples modelos con una API key"
echo ""
echo "  ── Proveedores locales (sin API key, sin telemetria) ──"
if $OLLAMA_RUNNING; then
  echo "    7) Ollama           ✓ Detectado corriendo"
  [ -n "$OLLAMA_MODELS" ] && echo "                        Modelos: $(echo "$OLLAMA_MODELS" | tr '\n' ', ' | sed 's/,$//')"
else
  echo "    7) Ollama           (no detectado — requiere: pacman -S ollama)"
fi
echo "    8) LM Studio        Servidor local compatible OpenAI"
echo ""
echo "  ── Otros ──"
echo "    9) Proveedor compatible OpenAI (custom URL)"
echo "    0) Desactivar IA"
echo ""
read -rp "  Opcion [0-9]: " AI_CHOICE

# ── Funcion: editar settings.json ──
apply_config() {
  python3 -c "
import json, re, sys

with open('$SETTINGS', 'r') as f:
    content = f.read()

# Eliminar comentarios // para parsear JSON
clean = re.sub(r'//.*', '', content)
data = json.loads(clean)

config = json.loads(sys.stdin.read())

# Aplicar config
for k, v in config.items():
    data[k] = v

with open('$SETTINGS', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" <<< "$1"
}

# ── Funcion: elegir modelo de una lista ──
pick_model() {
  local provider="$1"
  shift
  local models=("$@")
  echo ""
  echo "  Modelos disponibles:"
  local i=1
  for m in "${models[@]}"; do
    echo "    $i) $m"
    i=$((i+1))
  done
  echo ""
  read -rp "  Modelo [1-${#models[@]}]: " MODEL_CHOICE
  MODEL_CHOICE=$((MODEL_CHOICE - 1))
  if [ "$MODEL_CHOICE" -ge 0 ] && [ "$MODEL_CHOICE" -lt "${#models[@]}" ]; then
    SELECTED_MODEL="${models[$MODEL_CHOICE]}"
  else
    SELECTED_MODEL="${models[0]}"
  fi
}

# ── Configurar segun eleccion ──
case "$AI_CHOICE" in

  1) # Anthropic
    pick_model "anthropic" \
      "claude-sonnet-4-5" \
      "claude-sonnet-4-20250514" \
      "claude-3-5-haiku-20241022"
    apply_config "{
      \"features\": {\"copilot\": false},
      \"assistant\": {\"enabled\": true},
      \"agent\": {
        \"default_model\": {\"provider\": \"anthropic\", \"model\": \"$SELECTED_MODEL\"},
        \"enable_feedback\": false
      }
    }"
    ok "Anthropic configurado: $SELECTED_MODEL"
    echo ""
    warn "Siguiente paso:"
    echo "  1. Abre Zed"
    echo "  2. Ctrl+Shift+A → Agent Panel → icono de engranaje"
    echo "  3. Seccion Anthropic → pega tu API key"
    echo "  4. Obtener key: https://console.anthropic.com/settings/keys"
    ;;

  2) # OpenAI
    pick_model "openai" \
      "gpt-4o" \
      "gpt-4o-mini" \
      "o3-mini"
    apply_config "{
      \"features\": {\"copilot\": false},
      \"assistant\": {\"enabled\": true},
      \"agent\": {
        \"default_model\": {\"provider\": \"openai\", \"model\": \"$SELECTED_MODEL\"},
        \"enable_feedback\": false
      }
    }"
    ok "OpenAI configurado: $SELECTED_MODEL"
    echo ""
    warn "Siguiente paso:"
    echo "  1. Abre Zed → Agent Panel → Settings → OpenAI"
    echo "  2. Pega tu API key de https://platform.openai.com/api-keys"
    echo "  3. Tu cuenta OpenAI necesita creditos cargados"
    ;;

  3) # Google AI
    pick_model "google" \
      "gemini-2.0-flash" \
      "gemini-2.5-pro-preview-05-06" \
      "gemini-2.0-flash-lite"
    apply_config "{
      \"features\": {\"copilot\": false},
      \"assistant\": {\"enabled\": true},
      \"agent\": {
        \"default_model\": {\"provider\": \"google\", \"model\": \"$SELECTED_MODEL\"},
        \"enable_feedback\": false
      }
    }"
    ok "Google AI configurado: $SELECTED_MODEL"
    echo ""
    warn "Siguiente paso:"
    echo "  1. Abre Zed → Agent Panel → Settings → Google AI"
    echo "  2. Pega tu API key de https://aistudio.google.com/apikey"
    echo "  3. Gemini Flash tiene tier gratuito generoso"
    ;;

  4) # DeepSeek
    pick_model "deepseek" \
      "deepseek-chat" \
      "deepseek-reasoner"
    apply_config "{
      \"features\": {\"copilot\": false},
      \"assistant\": {\"enabled\": true},
      \"agent\": {
        \"default_model\": {\"provider\": \"deepseek\", \"model\": \"$SELECTED_MODEL\"},
        \"enable_feedback\": false
      }
    }"
    ok "DeepSeek configurado: $SELECTED_MODEL"
    echo ""
    warn "Siguiente paso:"
    echo "  1. Abre Zed → Agent Panel → Settings → DeepSeek"
    echo "  2. Pega tu API key de https://platform.deepseek.com/api_keys"
    echo "  3. Precios muy bajos comparado con otros proveedores"
    ;;

  5) # GitHub Copilot
    apply_config "{
      \"features\": {\"copilot\": true},
      \"assistant\": {\"enabled\": true},
      \"agent\": {
        \"default_model\": {\"provider\": \"copilot_chat\", \"model\": \"gpt-4o\"},
        \"enable_feedback\": false
      }
    }"
    ok "GitHub Copilot configurado"
    echo ""
    warn "Siguiente paso:"
    echo "  1. Abre Zed → Agent Panel → Settings → GitHub Copilot Chat"
    echo "  2. Click 'Sign in' y sigue la autenticacion de GitHub"
    echo "  3. Requiere suscripcion a GitHub Copilot"
    ;;

  6) # OpenRouter
    pick_model "open_router" \
      "openrouter/auto" \
      "anthropic/claude-sonnet-4" \
      "google/gemini-2.0-flash-001" \
      "deepseek/deepseek-chat"
    apply_config "{
      \"features\": {\"copilot\": false},
      \"assistant\": {\"enabled\": true},
      \"agent\": {
        \"default_model\": {\"provider\": \"open_router\", \"model\": \"$SELECTED_MODEL\"},
        \"enable_feedback\": false
      }
    }"
    ok "OpenRouter configurado: $SELECTED_MODEL"
    echo ""
    warn "Siguiente paso:"
    echo "  1. Abre Zed → Agent Panel → Settings → OpenRouter"
    echo "  2. Pega tu API key de https://openrouter.ai/keys"
    echo "  3. Una sola key da acceso a todos los modelos"
    ;;

  7) # Ollama
    if ! $OLLAMA_RUNNING; then
      warn "Ollama no esta corriendo"
      echo ""
      echo "  Para instalar y configurar:"
      echo "    sudo pacman -S ollama"
      echo "    systemctl --user enable --now ollama"
      echo "    ollama pull qwen2.5-coder"
      echo ""
      read -rp "  Continuar de todas formas? [s/N]: " CONT
      [[ "$CONT" == "s" ]] || exit 0
    fi

    # Si hay modelos, dejar elegir; si no, sugerir
    if [ -n "$OLLAMA_MODELS" ]; then
      mapfile -t OMODELS <<< "$OLLAMA_MODELS"
      pick_model "ollama" "${OMODELS[@]}"
    else
      pick_model "ollama" \
        "qwen2.5-coder" \
        "codellama" \
        "deepseek-coder-v2" \
        "llama3.1"
      warn "Recuerda descargar el modelo: ollama pull $SELECTED_MODEL"
    fi

    apply_config "{
      \"features\": {\"copilot\": false},
      \"assistant\": {\"enabled\": true},
      \"agent\": {
        \"default_model\": {\"provider\": \"ollama\", \"model\": \"$SELECTED_MODEL\"},
        \"enable_feedback\": false
      },
      \"language_models\": {
        \"ollama\": {
          \"api_url\": \"http://localhost:11434\"
        }
      }
    }"
    ok "Ollama configurado: $SELECTED_MODEL"
    echo ""
    echo "  100% local, sin API key, sin telemetria"
    echo "  Asegurate de que ollama este corriendo: ollama serve"
    ;;

  8) # LM Studio
    read -rp "  Puerto de LM Studio [1234]: " LMS_PORT
    LMS_PORT="${LMS_PORT:-1234}"
    read -rp "  Nombre del modelo cargado: " LMS_MODEL
    [ -z "$LMS_MODEL" ] && LMS_MODEL="loaded-model"

    apply_config "{
      \"features\": {\"copilot\": false},
      \"assistant\": {\"enabled\": true},
      \"agent\": {
        \"default_model\": {\"provider\": \"lm_studio\", \"model\": \"$LMS_MODEL\"},
        \"enable_feedback\": false
      }
    }"
    ok "LM Studio configurado: $LMS_MODEL en puerto $LMS_PORT"
    echo ""
    echo "  Asegurate de que LM Studio este corriendo con el modelo cargado"
    ;;

  9) # OpenAI Compatible (custom)
    read -rp "  Nombre del proveedor (ej: Together AI): " CUSTOM_NAME
    [ -z "$CUSTOM_NAME" ] && die "Nombre requerido"
    read -rp "  URL de la API (ej: https://api.together.xyz/v1): " CUSTOM_URL
    [ -z "$CUSTOM_URL" ] && die "URL requerida"
    read -rp "  Nombre del modelo: " CUSTOM_MODEL
    [ -z "$CUSTOM_MODEL" ] && die "Modelo requerido"
    read -rp "  Max tokens [32768]: " CUSTOM_TOKENS
    CUSTOM_TOKENS="${CUSTOM_TOKENS:-32768}"

    # Variable de entorno para la API key
    ENVVAR_NAME=$(echo "$CUSTOM_NAME" | tr '[:lower:] ' '[:upper:]_')_API_KEY
    apply_config "{
      \"features\": {\"copilot\": false},
      \"assistant\": {\"enabled\": true},
      \"agent\": {
        \"default_model\": {\"provider\": \"openai_compatible\", \"model\": \"$CUSTOM_MODEL\"},
        \"enable_feedback\": false
      },
      \"language_models\": {
        \"openai_compatible\": {
          \"$CUSTOM_NAME\": {
            \"api_url\": \"$CUSTOM_URL\",
            \"available_models\": [{
              \"name\": \"$CUSTOM_MODEL\",
              \"display_name\": \"$CUSTOM_MODEL\",
              \"max_tokens\": $CUSTOM_TOKENS
            }]
          }
        }
      }
    }"
    ok "Proveedor custom configurado: $CUSTOM_NAME / $CUSTOM_MODEL"
    echo ""
    warn "Configura la API key como variable de entorno:"
    echo "  export $ENVVAR_NAME=tu-api-key"
    echo "  (agregar a ~/.bashrc o ~/.config/nushell/env.nu)"
    ;;

  0) # Desactivar
    apply_config "{
      \"features\": {\"copilot\": false},
      \"assistant\": {\"enabled\": false}
    }"
    # Limpiar agent config si existe
    python3 -c "
import json, re
with open('$SETTINGS', 'r') as f:
    clean = re.sub(r'//.*', '', f.read())
data = json.loads(clean)
data.pop('agent', None)
data.pop('language_models', None)
with open('$SETTINGS', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
    ok "IA desactivada"
    ;;

  *)
    die "Opcion invalida"
    ;;
esac

chown -R "$USERNAME:users" "$CFG"

echo ""
info "Las API keys se guardan en el keychain del OS, no en settings.json"
echo "  Ejecuta este script de nuevo para cambiar de proveedor"
