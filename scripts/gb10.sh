#!/usr/bin/env bash
# ComfyUI en GB10/ARM64. No modifica la ruta historica de main.sh.
set -Eeuo pipefail

case "$(uname -m):$(nvidia-smi --query-gpu=name --format=csv,noheader)" in
    aarch64:*GB10*|arm64:*GB10*) ;;
    *) echo "Esta receta requiere ARM64 y una NVIDIA GB10." >&2; exit 1 ;;
esac

WORKFLOW_DIR="${WORKFLOW_DIR:-/scripts}"
COMFY_DIR="${COMFY_DIR:-$WORKFLOW_DIR/comfyui}"
COMFYUI_REF="${COMFYUI_REF:-v0.42.1}"
COMFY_PORT="${COMFY_PORT:-8388}"
SERVICE_MANAGER=screen
if [[ -f /etc/vast_agents/base.md ]] && supervisorctl pid >/dev/null 2>&1; then
    SERVICE_MANAGER=supervisor
fi
case "$SERVICE_MANAGER" in
    supervisor) COMFY_LISTEN="${COMFY_LISTEN:-127.0.0.1}" ;;
    screen) COMFY_LISTEN="${COMFY_LISTEN:-0.0.0.0}" ;;
esac
mkdir -p "$WORKFLOW_DIR"

missing=()
glib_package=libglib2.0-0
if dpkg-query -W -f='${Status}' libglib2.0-0t64 2>/dev/null | grep -q 'install ok installed'; then
    glib_package=libglib2.0-0t64
fi
for package in ca-certificates curl git screen build-essential pkg-config libgl1 "$glib_package"; do
    if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
        missing+=("$package")
    fi
done
if ((${#missing[@]})); then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
fi

export PATH="/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
if ! command -v uv >/dev/null; then
    curl --fail --location --retry 3 https://astral.sh/uv/install.sh -o /tmp/workflow-install-uv.sh
    UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh /tmp/workflow-install-uv.sh
fi

# Instalar solo si no existe: no sobrescribir un ComfyUI ya personalizado.
if [[ ! -f "$COMFY_DIR/main.py" ]]; then
    if [[ -e "$COMFY_DIR" ]]; then
        echo "Ya existe $COMFY_DIR pero no contiene main.py; revisar antes de instalar." >&2
        exit 1
    fi
    git clone --depth 1 --branch "$COMFYUI_REF" https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR"
fi

if [[ -z "${COMFY_VENV:-}" ]]; then
    if [[ -x "$COMFY_DIR/venv/bin/python" ]]; then
        COMFY_VENV="$COMFY_DIR/venv"
    elif [[ -x /venv/main/bin/python ]]; then
        # Imagen oficial vastai/pytorch: reutilizar sus paquetes CUDA/ARM64.
        COMFY_VENV=/venv/main
        ln -s "$COMFY_VENV" "$COMFY_DIR/venv"
    else
        uv python install 3.12
        COMFY_VENV="$COMFY_DIR/venv"
        uv venv --python 3.12 "$COMFY_VENV"
    fi
fi
PYTHON="$COMFY_VENV/bin/python"
test -x "$PYTHON"

if ! "$PYTHON" -c 'import torch, torchvision' >/dev/null 2>&1; then
    uv pip install --python "$PYTHON" \
        'torch==2.14.1' 'torchvision==0.29.1' \
        --index-url https://download.pytorch.org/whl/cu130
fi

# Fallar antes de instalar el resto si el runtime no puede ejecutar en la GPU.
"$PYTHON" - <<'PY'
import json, platform, torch
assert platform.machine() in ('aarch64', 'arm64')
assert torch.cuda.is_available(), 'CUDA no disponible'
assert 'GB10' in torch.cuda.get_device_name(0)
x = torch.ones((64, 64), device='cuda', dtype=torch.bfloat16)
assert (x @ x).float().mean().item() == 64
torch.cuda.synchronize()
print(json.dumps({'torch': torch.__version__, 'cuda': torch.version.cuda,
                  'gpu': torch.cuda.get_device_name(0),
                  'capability': torch.cuda.get_device_capability(0)}))
PY

# Evitar que las dependencias de ComfyUI sustituyan el torch CUDA que funciona.
constraints=$(mktemp)
trap 'rm -f "$constraints"' EXIT
"$PYTHON" - > "$constraints" <<'PY'
from importlib.metadata import version, PackageNotFoundError
for name in ('torch', 'torchvision', 'torchaudio'):
    try:
        print(f'{name}=={version(name)}')
    except PackageNotFoundError:
        pass
PY
uv pip install --python "$PYTHON" -c "$constraints" -r "$COMFY_DIR/requirements.txt"
if [[ -f "$COMFY_DIR/manager_requirements.txt" ]]; then
    uv pip install --python "$PYTHON" -c "$constraints" -r "$COMFY_DIR/manager_requirements.txt"
fi

printf '#!/usr/bin/env bash\nset -e\nexport VIRTUAL_ENV=%q\nexport PATH="$VIRTUAL_ENV/bin:$PATH"\ncd %q\nexec %q main.py --listen %q --port %q --enable-manager "$@"\n' \
    "$COMFY_VENV" "$COMFY_DIR" "$PYTHON" "$COMFY_LISTEN" "$COMFY_PORT" > "$COMFY_DIR/run_comfy_gb10.sh"
chmod +x "$COMFY_DIR/run_comfy_gb10.sh"

if curl --max-time 5 -fsS "http://127.0.0.1:$COMFY_PORT/system_stats" >/dev/null 2>&1; then
    echo "ComfyUI ya responde en el puerto $COMFY_PORT; no se reinicia."
    exit 0
fi
case "$SERVICE_MANAGER" in
    supervisor)
        # Integracion con el portal autenticado de la imagen oficial de Vast.
        printf '#!/usr/bin/env bash\n. /opt/supervisor-scripts/utils/logging.sh\n. /opt/supervisor-scripts/utils/environment.sh\npty %q\n' \
            "$COMFY_DIR/run_comfy_gb10.sh" > /opt/supervisor-scripts/workflow-comfy.sh
        chmod +x /opt/supervisor-scripts/workflow-comfy.sh
        cat > /etc/supervisor/conf.d/workflow-comfy.conf <<'CONF'
[program:workflow-comfy]
environment=PROC_NAME="%(program_name)s"
command=/opt/supervisor-scripts/workflow-comfy.sh
autostart=true
autorestart=unexpected
stdout_logfile=/dev/stdout
redirect_stderr=true
stdout_logfile_maxbytes=0
stopasgroup=true
killasgroup=true
CONF
        supervisorctl reread
        supervisorctl update
        case "$(supervisorctl status workflow-comfy 2>/dev/null || true)" in
            *RUNNING*|*STARTING*) ;;
            *) supervisorctl start workflow-comfy ;;
        esac
        log_file=/var/log/portal/workflow-comfy.log
        ;;
    screen)
        if screen -ls | grep -q '[.]comfyui[[:space:]]'; then
            echo "Ya existe una sesion comfyui sin respuesta HTTP; revisar su log antes de continuar." >&2
            exit 1
        fi
        log_file="$COMFY_DIR/comfyui.log"
        screen -L -Logfile "$log_file" -dmS comfyui "$COMFY_DIR/run_comfy_gb10.sh"
        ;;
esac
for ((attempt=0; attempt<90; attempt++)); do
    if curl --max-time 5 -fsS "http://127.0.0.1:$COMFY_PORT/system_stats" > "$COMFY_DIR/gb10-system-stats.json" 2>/dev/null; then
        echo "ComfyUI listo en el puerto $COMFY_PORT. Log: $log_file"
        exit 0
    fi
    sleep 2
done
tail -n 80 "$log_file" >&2
exit 1
