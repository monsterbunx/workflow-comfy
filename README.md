# workflow-comfy

## Construir runpod:

Imagen:
```dockerimage
docker.io/library/debian:12
```
Start Command:
```bash
bash -c 'apt update && apt install -y openssh-server sudo curl wget neofetch git vim htop screen && source <(curl -fsSL https://monsterbunx.github.io/workflow-comfy/run) && mkdir -p /run/sshd && echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && echo "root:pass" | chpasswd && /usr/sbin/sshd -D' 
```

Volume mounth path:
```
/scripts
```
Expose HTTP ports:
```
80,81,8388,8488,8588,8688,443
```

Expose TCP ports:
```
22
```
## Construir local:

En una carpeta vacia copiar el comando:
```
source <(curl -fsSL https://monsterbunx.github.io/workflow-comfy/local)
```

## GB10 / ARM64 en Vast.ai

`scripts/main.sh` detecta `aarch64`/`arm64` junto con una GPU `GB10` mediante
`case` y ejecuta `scripts/gb10.sh`. El resto del instalador anterior se conserva
sin cambios. Esta receta especial instala **ComfyUI**; SwarmUI y .NET siguen en
el flujo anterior y no se han validado en GB10.

Configuración comprobada el **26 de octubre de 2026**, en una GB10 de Francia:

- Imagen: `vastai/pytorch:cuda-13.0.3-auto`.
- Digest ARM64 probado: `sha256:1075a6fb4107f569cf33b515e3accebc2f3d300b2b0c7a7c9c59f5399807150c`.
- Python **3.12.15**, PyTorch **2.14.1+cu130**, torchvision **0.29.1+cu130**,
  controlador **580.173.02**, capacidad CUDA **12.1**.
- ComfyUI **v0.42.1**, Manager **4.2.2**, puerto interno **8388**.

En Vast, crear la instancia con esa imagen, modo SSH y el comando de inicio
`entrypoint.sh`. Esto inicializa Supervisor, el portal y la autenticación de la
imagen; el modo SSH por sí solo no ejecuta su entrypoint.

Puertos TCP: **22**, **1111**, **18388**. Variables del contenedor:

```bash
PORTAL_CONFIG='localhost:1111:11111:/:Instance Portal|localhost:18388:8388:/:ComfyUI'
OPEN_BUTTON_PORT=18388
```

Después de conectar por SSH:

```bash
git clone https://github.com/monsterbunx/workflow-comfy.git /opt/workflow-comfy
mkdir -p /scripts
cp -a /opt/workflow-comfy/scripts/. /scripts/
bash /scripts/gb10.sh
```

La receta reutiliza `/venv/main` cuando está disponible, comprueba un cálculo
BF16 en GPU y fija las versiones instaladas de torch al resolver las dependencias
con `uv`. No actualiza un checkout de ComfyUI ya existente ni sobrescribe su
`run_comfy.sh`: genera `run_comfy_gb10.sh`. ComfyUI usa Supervisor en la imagen de
Vast y escucha en `127.0.0.1`; el puerto **18388** pasa por el proxy autenticado.
En entornos sin ese Supervisor utiliza `screen`. La variante probada es la imagen
Vast indicada arriba; la instalación desde Debian vacío y el fallback de `screen`
no forman parte de esta validación.

Se pueden configurar `WORKFLOW_DIR` (por defecto `/scripts`), `COMFY_DIR`,
`COMFY_VENV` (entorno ya existente), `COMFYUI_REF`, `COMFY_PORT` y `COMFY_LISTEN`.
Si cambia el puerto interno, hay que ajustar también `PORTAL_CONFIG`/`portal.yaml`.

```bash
supervisorctl status workflow-comfy
supervisorctl restart workflow-comfy
tail -f /var/log/portal/workflow-comfy.log
curl -fsS http://127.0.0.1:8388/system_stats
```

El acceso público requiere el token de apertura de la instancia. Usar el botón
**Open** de Vast o un túnel SSH privado; no desactivar la autenticación del proxy.

### Pruebas realizadas

- Operaciones FP16, BF16 y FP32; atención BF16 con backward; asignación y escritura
  de 4 GiB en GPU: correctas. [Resultados](evidencia/gb10-francia/gb10-probe-result.json).
- Compilación nativa de un programa CUDA para `sm_121` y ejecución en GPU:
  correcta. [Código](examples/gb10-cuda.cu).
- Dos generaciones SD 1.5 FP16, **512×512**, **20 pasos**, `dpmpp_2m/karras`, CFG 7:
  **4.253 s** iniciales y **1.632 s** con checkpoint y texto ya cargados, medidos
  entre `execution_start` y `execution_success`. El segundo trabajo usa otra
  semilla, por lo que vuelve a ejecutar el sampler y el VAE.
- Acceso HTTPS a `/system_stats`: **401** sin autenticación y **200** con ella.

Estos tiempos corresponden a esta prueba pequeña; no son una estimación para
Z-Image, Qwen, entrenamiento de LoRAs o nodos personalizados.

[Workflow en formato API](examples/gb10-smoke-api.json) ·
[Resultado PNG](evidencia/gb10-francia/gb10-smoke_00002_.png) ·
[Historial de ejecución](evidencia/gb10-francia/gb10-generation-results.json) ·
[Modelo, revisión y SHA-256](evidencia/gb10-francia/modelo.json).

Para repetir las comprobaciones de cómputo:

```bash
/scripts/comfyui/venv/bin/python /opt/workflow-comfy/examples/gb10-probe.py
nvcc -arch=sm_121 /opt/workflow-comfy/examples/gb10-cuda.cu -o /tmp/gb10-cuda
/tmp/gb10-cuda
```

El workflow utiliza `v1-5-pruned-emaonly-fp16.safetensors` del repositorio
`Comfy-Org/stable-diffusion-1.5`, colocado en `models/checkpoints/`. El JSON es
formato API: enviar `{"prompt": <contenido del archivo>}` a `POST /prompt`.
