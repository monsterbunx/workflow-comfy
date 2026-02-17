#!/bin/bash

check() { for p in "$@"; do dpkg -l "$p" 2>/dev/null | grep -q '^ii' && echo "$p Ya instalado" || apt install -y "$p"; done; }

apt update
apt upgrade -y
check neofetch htop curl nano

# Dependencias python
check install build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev liblzma-dev tk-dev libxml2-dev libxmlsec1-dev git

# python
. <(curl -fsSL https://monsterbunx.github.io/python/main.sh)
# uv
. <(curl -fsSL https://monsterbunx.github.io/uv/main.sh)
# comfy
. <(curl -fsSL https://monsterbunx.github.io/comfy/main.sh)
# dotnet
. <(curl -fsSL https://monsterbunx.github.io/dotnet/main.sh)
# swarmui
. <(curl -fsSL https://monsterbunx.github.io/swarmui/main.sh)

tail -f /dev/null