#!/bin/bash

check() { for p in "$@"; do dpkg -l "$p" 2>/dev/null | grep -q '^ii' && echo "$p Ya instalado" || apt install -y "$p"; done; }
clors(){ echo -e "\e[1;${1};${2}m${3}\e[0m"; }

apt update
apt upgrade -y
check neofetch htop curl nano

# Dependencias python
check install build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev liblzma-dev tk-dev libxml2-dev libxmlsec1-dev git

# python
clors 90 107 "Instalando python"
. <(curl -fsSL https://monsterbunx.github.io/python/main.sh)
# uv
clors 90 107 "Instalando uv"
. <(curl -fsSL https://monsterbunx.github.io/uv/main.sh)
# comfy
clors 90 107 "Instalando comfyui"
. <(curl -fsSL https://monsterbunx.github.io/comfyui/main.sh)
# dotnet
clors 90 107 "Instalando dotnet"
. <(curl -fsSL https://monsterbunx.github.io/dotnet/main.sh)
# swarmui
clors 90 107 "Instalando swarmui"
. <(curl -fsSL https://monsterbunx.github.io/swarmui/main.sh)

tail -f /dev/null