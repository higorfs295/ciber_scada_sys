#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# PLC / OpenPLC bootstrap - safe version
# =============================================================================
# Objetivo:
# - manter a interface de gerenciamento intacta
# - configurar apenas a interface OT (lab_net)
# - não usar dhclient
# - não derrubar a rede NAT
# - preparar a VM plc-openplc.semi
#
# Uso:
#   sudo bash plc_openplc_bootstrap_safe.sh
#
# Variáveis opcionais:
#   MGMT_IF=enp0s3
#   LAB_IF=enp0s8
#   PLC_IP=192.168.100.20/24
# =============================================================================

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive

HOSTNAME_FULL="plc-openplc.semi"
HOSTNAME_SHORT="plc-openplc"

LAB_USER="${LAB_USER:-labadmin}"
LAB_PASS="${LAB_PASS:-LabSCADA2026!}"

MGMT_IF="${MGMT_IF:-}"
LAB_IF="${LAB_IF:-}"
PLC_IP="${PLC_IP:-192.168.100.20/24}"
LAB_CONN="${LAB_CONN:-scada-lab}"

log(){ echo "[+] $*"; }
warn(){ echo "[!] $*" >&2; }
die(){ echo "[X] $*" >&2; exit 1; }

have_cmd(){ command -v "$1" >/dev/null 2>&1; }

internet_ok() {
  ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1
}

detect_default_iface() {
  ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

detect_lab_iface() {
  local default_if="$1"
  local ifc
  for ifc in $(ip -o link show | awk -F': ' '$2 != "lo" {print $2}'); do
    [[ "$ifc" == "$default_if" ]] && continue
    echo "$ifc"
    return 0
  done
  return 1
}

set_identity() {
  hostnamectl set-hostname "$HOSTNAME_FULL"
  cat >/etc/hosts <<EOF
127.0.0.1       localhost
127.0.1.1       ${HOSTNAME_FULL} ${HOSTNAME_SHORT}

# IPv6
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF
}

ensure_user() {
  if ! id "$LAB_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$LAB_USER"
  fi
  echo "${LAB_USER}:${LAB_PASS}" | chpasswd
  usermod -aG sudo "$LAB_USER" >/dev/null 2>&1 || true
}

install_base_pkgs() {
  if ! internet_ok; then
    warn "Sem internet no momento; pulando instalação de pacotes."
    return 0
  fi

  apt-get update
  apt-get install -y \
    network-manager \
    openssh-server \
    curl wget git vim nano tmux htop \
    net-tools dnsutils tcpdump \
    python3 python3-pip python3-venv python3-dev \
    build-essential iproute2 procps lsof psmisc \
    whois traceroute mtr iputils-ping \
    netcat-openbsd socat rsync ca-certificates \
    libmodbus-dev default-jre-headless
}

configure_lab_iface() {
  local iface="$1"
  local ip_cidr="$2"

  [[ -n "$iface" ]] || die "LAB_IF não definido."
  [[ "$iface" != "$MGMT_IF" ]] || die "LAB_IF não pode ser a mesma interface de gerenciamento."

  ip link set "$iface" up >/dev/null 2>&1 || true

  if have_cmd nmcli; then
    systemctl enable --now NetworkManager >/dev/null 2>&1 || true
    nmcli networking on >/dev/null 2>&1 || true

    nmcli con show "$LAB_CONN" >/dev/null 2>&1 && nmcli con delete "$LAB_CONN" >/dev/null 2>&1 || true

    nmcli con add type ethernet ifname "$iface" con-name "$LAB_CONN" \
      ipv4.method manual \
      ipv4.addresses "$ip_cidr" \
      ipv4.never-default yes \
      ipv4.ignore-auto-dns yes \
      ipv6.method ignore \
      connection.autoconnect yes >/dev/null

    nmcli con up "$LAB_CONN" >/dev/null 2>&1 || true
  else
    # Fallback sem NM: apenas configura o IP na interface OT.
    ip addr add "$ip_cidr" dev "$iface" 2>/dev/null || true
  fi
}

prepare_openplc() {
  if ! internet_ok; then
    warn "Sem internet; OpenPLC ficará para instalação manual posterior."
    install -d -m 755 /opt/openplc
    echo "OpenPLC runtime deve ser colocado em /opt/openplc" >/opt/openplc/README.txt
    return 0
  fi

  if [[ ! -d /opt/openplc_src ]]; then
    git clone https://github.com/thiagoralves/OpenPLC_v3.git /opt/openplc_src >/dev/null 2>&1 || {
      warn "Falha ao clonar OpenPLC_v3; seguindo sem instalar runtime."
      install -d -m 755 /opt/openplc
      echo "OpenPLC runtime deve ser colocado em /opt/openplc" >/opt/openplc/README.txt
      return 0
    }
  fi

  if [[ -d /opt/openplc_src ]]; then
    (cd /opt/openplc_src && ./install.sh linux) || warn "OpenPLC install falhou; revise manualmente depois."
  fi
}

create_swap() {
  local size="${1:-2G}"
  local path="/swapfile"

  if [[ ! -f "$path" ]]; then
    fallocate -l "$size" "$path"
    chmod 600 "$path"
    mkswap "$path" >/dev/null
  fi

  grep -q "^${path} " /etc/fstab || echo "${path} none swap sw 0 0" >> /etc/fstab
  swapon "$path" || true
}

main() {
  log "Detectando interfaces"
  MGMT_IF="${MGMT_IF:-$(detect_default_iface || true)}"
  [[ -n "$MGMT_IF" ]] || die "Não foi possível detectar a interface de gerenciamento."

  LAB_IF="${LAB_IF:-$(detect_lab_iface "$MGMT_IF" || true)}"
  [[ -n "$LAB_IF" ]] || die "Não foi possível detectar a interface lab_net."

  log "MGMT_IF=$MGMT_IF"
  log "LAB_IF=$LAB_IF"

  log "Configurando hostname"
  set_identity

  log "Configurando apenas a interface OT"
  configure_lab_iface "$LAB_IF" "$PLC_IP"

  log "Instalando pacotes base"
  install_base_pkgs

  log "Criando usuário"
  ensure_user

  log "Criando swap"
  create_swap "2G"

  log "Preparando OpenPLC"
  prepare_openplc

  log "Ajustando motd"
  cat >/etc/motd <<EOF

===============================================================
 PLC / OpenPLC - SCADA/ICS LAB
 Hostname: ${HOSTNAME_FULL}
 Interface de gestão: ${MGMT_IF}
 Interface OT: ${LAB_IF} -> ${PLC_IP}
===============================================================

EOF

  log "Ativando SSH"
  systemctl enable --now ssh >/dev/null 2>&1 || true

  log "Limpeza final"
  apt-get autoremove -y >/dev/null 2>&1 || true
  apt-get clean >/dev/null 2>&1 || true

  echo
  echo "[OK] PLC bootstrap concluído."
  echo "Agora valide:"
  echo "  ip a"
  echo "  ip route"
  echo "  systemctl status ssh --no-pager"
  echo
  echo "Se necessário, remova o NAT no VirtualBox apenas depois de validar tudo."
}

main "$@"