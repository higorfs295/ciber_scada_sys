#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# OpenPLC Runtime v3 - SAFE INSTALLER
# =============================================================================
# Versão ajustada:
# - sem hostnamectl
# - sem comando hostname
# - sem dhclient
# - sem alteração agressiva de rede
# - não toca na NAT
# - apenas instala OpenPLC e dependências
#
# Compatível com:
# - Debian
# - Ubuntu
# - Kali
# - Debian minimal/headless
# =============================================================================

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive

LAB_USER="${LAB_USER:-labadmin}"
LAB_PASS="${LAB_PASS:-LabSCADA2026!}"

OPENPLC_REPO="https://github.com/thiagoralves/OpenPLC_v3.git"
OPENPLC_DIR="/opt/OpenPLC_v3"

log() {
  echo "[+] $*"
}

warn() {
  echo "[!] $*" >&2
}

die() {
  echo "[X] $*" >&2
  exit 1
}

internet_ok() {
  ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1
}

# =============================================================================
# HOSTNAME
# =============================================================================

set_identity() {

  log "Configurando hostname"

  echo "plc-openplc" >/etc/hostname

  cat >/etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 plc-openplc

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

}

# =============================================================================
# USER
# =============================================================================

ensure_user() {

  log "Garantindo usuário"

  if ! id "$LAB_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$LAB_USER"
  fi

  echo "${LAB_USER}:${LAB_PASS}" | chpasswd

  usermod -aG sudo "$LAB_USER" >/dev/null 2>&1 || true
}

# =============================================================================
# PACKAGES
# =============================================================================

install_prereqs() {

  log "Instalando dependências"

  if ! internet_ok; then
    die "Sem internet. Verifique a interface NAT."
  fi

  apt-get update

  apt-get install -y \
    git \
    curl \
    wget \
    ca-certificates \
    build-essential \
    cmake \
    make \
    gcc \
    g++ \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    libmodbus-dev \
    default-jre-headless \
    openssh-server \
    net-tools \
    iproute2 \
    iputils-ping \
    tcpdump \
    htop \
    vim \
    nano \
    tmux \
    rsync \
    procps \
    lsof \
    psmisc \
    netcat-openbsd
}

# =============================================================================
# DIRECTORIES
# =============================================================================

prepare_dirs() {

  log "Criando diretórios"

  install -d -m 755 /opt/openplc
  install -d -m 755 /opt/openplc_src
}

# =============================================================================
# CLONE REPO
# =============================================================================

clone_repo() {

  log "Obtendo OpenPLC_v3"

  if [[ ! -d "${OPENPLC_DIR}/.git" ]]; then

    rm -rf "$OPENPLC_DIR"

    git clone "$OPENPLC_REPO" "$OPENPLC_DIR"

  else

    log "Repositório já existe"

    (
      cd "$OPENPLC_DIR"
      git pull --ff-only || true
    )

  fi
}

# =============================================================================
# INSTALL
# =============================================================================

run_installer() {

  log "Executando instalador OpenPLC"

  cd "$OPENPLC_DIR"

  chmod +x install.sh

  ./install.sh linux
}

# =============================================================================
# SYSTEMD SERVICE
# =============================================================================

configure_service() {

  log "Configurando serviço OpenPLC"

  local starter=""

  if [[ -x "${OPENPLC_DIR}/start_openplc.sh" ]]; then
    starter="${OPENPLC_DIR}/start_openplc.sh"

  elif [[ -x "${OPENPLC_DIR}/start.sh" ]]; then
    starter="${OPENPLC_DIR}/start.sh"

  else

    starter="$(find "$OPENPLC_DIR" -type f \
      \( -name 'start_openplc.sh' -o -name 'start.sh' \) \
      2>/dev/null | head -n1 || true)"

  fi

  if [[ -z "${starter:-}" ]]; then
    warn "Script de start não encontrado."
    return 0
  fi

  chmod +x "$starter" || true

  cat >/etc/systemd/system/openplc.service <<EOF
[Unit]
Description=OpenPLC Runtime v3
After=network.target

[Service]
Type=simple
WorkingDirectory=${OPENPLC_DIR}
ExecStart=${starter}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload

  systemctl enable openplc >/dev/null 2>&1 || true

  systemctl restart openplc >/dev/null 2>&1 || true
}

# =============================================================================
# VALIDATION
# =============================================================================

validate_runtime() {

  log "Validando portas"

  echo
  echo "======================================="
  echo "PORTAS OPENPLC"
  echo "======================================="

  ss -tulpn | grep -E '(:502|:8080|:8443)' || true

  echo
  echo "======================================="
  echo "STATUS OPENPLC"
  echo "======================================="

  systemctl status openplc --no-pager || true
}

# =============================================================================
# FINAL
# =============================================================================

finish_message() {

cat <<EOF

============================================================
OPENPLC FINALIZADO
============================================================

Valide agora:

1)
ip a

2)
ip route

3)
ss -tulpn | grep 502

4)
systemctl status openplc --no-pager

5)
Na Kali:
nc -vz 192.168.100.20 502

============================================================

EOF

}

# =============================================================================
# MAIN
# =============================================================================

main() {

  set_identity

  ensure_user

  install_prereqs

  prepare_dirs

  clone_repo

  run_installer

  configure_service

  chown -R "$LAB_USER:$LAB_USER" "$OPENPLC_DIR" >/dev/null 2>&1 || true

  apt-get autoremove -y >/dev/null 2>&1 || true

  apt-get clean >/dev/null 2>&1 || true

  validate_runtime

  finish_message
}

main "$@"