# workflow-comfy

## Construir runpod:

Imagen:
```dockerimage
docker.io/library/debian:12
```
Start Command:
```bash
bash -c 'apt update && apt install -y openssh-server sudo curl wget neofetch git vim htop screen && time . <(curl -fsSL https://raw.githubusercontent.com/zsh4k0/comfy/refs/heads/main/runpod) && mkdir -p /run/sshd && echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && echo "root:pass" | chpasswd && /usr/sbin/sshd -D'
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