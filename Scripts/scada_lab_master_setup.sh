#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# SCADA/ICS LAB MASTER SETUP - SAFE VERSION
# =============================================================================
#
# Fix principal:
# - NÃO toca na interface de gerenciamento (NAT/internet)
# - Configura apenas a interface OT (lab_net)
# - Não usa dhclient
# - Menus interativos preservados
# - Funciona por papel: kali, template, plc, hmi, sensor, db
#
# Uso:
#   sudo bash scada_lab_master_setup.sh
#   sudo bash scada_lab_master_setup.sh --kali
#   sudo bash scada_lab_master_setup.sh --template
#   sudo bash scada_lab_master_setup.sh --plc
#   sudo bash scada_lab_master_setup.sh --hmi
#   sudo bash scada_lab_master_setup.sh --sensor
#   sudo bash scada_lab_master_setup.sh --db
#   sudo bash scada_lab_master_setup.sh --all
#
# Observação:
# - Para clones OT, mantenha temporariamente NAT + lab_net durante bootstrap.
# - Depois do setup, remova NAT no VirtualBox se quiser isolamento final.
# =============================================================================

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive

ROLE="${1:-}"
OFFLINE_OK=0
if [[ "${ROLE:-}" == "--offline" ]]; then
  OFFLINE_OK=1
  ROLE="${2:-}"
fi

LAB_USER="${LAB_USER:-labadmin}"
LAB_PASS="${LAB_PASS:-LabSCADA2026!}"
LAB_ROOT="${LAB_ROOT:-/opt/scada-lab}"

KALI_IP="${KALI_IP:-192.168.100.10/24}"
TEMPLATE_IP="${TEMPLATE_IP:-192.168.100.11/24}"
PLC_IP="${PLC_IP:-192.168.100.20/24}"
HMI_IP="${HMI_IP:-192.168.100.30/24}"
SENSOR_IP="${SENSOR_IP:-192.168.100.40/24}"
DB_IP="${DB_IP:-192.168.100.50/24}"

MGMT_CONN="${MGMT_CONN:-scada-mgmt}"
LAB_CONN="${LAB_CONN:-scada-lab}"

log(){ echo "[+] $*"; }
warn(){ echo "[!] $*" >&2; }
die(){ echo "[X] $*" >&2; exit 1; }

have_cmd(){ command -v "$1" >/dev/null 2>&1; }

internet_ok(){
  ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1
}

detect_default_iface(){
  ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

detect_non_lo_ifaces(){
  ip -o link show | awk -F': ' '$2 != "lo" {print $2}'
}

detect_lab_iface(){
  local default_if="${1:-$(detect_default_iface || true)}"
  local ifc
  for ifc in $(detect_non_lo_ifaces); do
    [[ -n "${default_if:-}" && "$ifc" == "$default_if" ]] && continue
    echo "$ifc"
    return 0
  done
  return 1
}

ensure_nm(){
  if have_cmd nmcli; then
    systemctl enable --now NetworkManager >/dev/null 2>&1 || true
    nmcli networking on >/dev/null 2>&1 || true
    return 0
  fi

  if ! internet_ok; then
    warn "nmcli ausente e sem internet; continuando sem NetworkManager."
    return 1
  fi

  apt-get update
  apt-get install -y network-manager
  systemctl enable --now NetworkManager >/dev/null 2>&1 || true
  nmcli networking on >/dev/null 2>&1 || true
}

set_hostname_hosts(){
  local fqdn="$1"
  local short="$2"
  shift 2

  hostnamectl set-hostname "$fqdn"
  {
    echo "127.0.0.1 localhost"
    echo "127.0.1.1 ${fqdn} ${short}"
    for line in "$@"; do echo "$line"; done
    echo "::1 localhost ip6-localhost ip6-loopback"
    echo "ff02::1 ip6-allnodes"
    echo "ff02::2 ip6-allrouters"
  } >/etc/hosts
}

create_user(){
  if ! id "$LAB_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$LAB_USER"
  fi

  echo "${LAB_USER}:${LAB_PASS}" | chpasswd
  usermod -aG sudo "$LAB_USER" >/dev/null 2>&1 || true
  getent group wireshark >/dev/null 2>&1 && usermod -aG wireshark "$LAB_USER" >/dev/null 2>&1 || true
  getent group vboxsf >/dev/null 2>&1 && usermod -aG vboxsf "$LAB_USER" >/dev/null 2>&1 || true
  touch "/home/${LAB_USER}/.bashrc"
  chown "${LAB_USER}:${LAB_USER}" "/home/${LAB_USER}/.bashrc"
}

create_swap(){
  local size="$1"
  local path="${2:-/swapfile}"

  if [[ ! -f "$path" ]]; then
    fallocate -l "$size" "$path"
    chmod 600 "$path"
    mkswap "$path" >/dev/null
  fi

  grep -q "^${path} " /etc/fstab || echo "${path} none swap sw 0 0" >> /etc/fstab
  swapon "$path" || true
}

install_common_pkgs(){
  if ! internet_ok; then
    warn "Sem internet neste momento; pulando apt/pip."
    return 0
  fi

  apt-get update
  apt-get install -y \
    curl wget git vim nano tmux htop net-tools dnsutils \
    tcpdump tshark nmap arp-scan iperf3 tree jq unzip zip \
    python3 python3-pip python3-venv python3-dev build-essential \
    iproute2 procps lsof psmisc whois traceroute mtr iputils-ping \
    netcat-openbsd socat rsync ca-certificates openssh-server

  apt-get install -y btop iftop iotop masscan netdiscover >/dev/null 2>&1 || true
  pip3 install --break-system-packages \
    pymodbus pyModbusTCP scapy opcua pandas matplotlib flask requests >/dev/null 2>&1 || true
}

configure_lab_iface(){
  local iface="$1"
  local ip_cidr="$2"
  local conn="${3:-scada-lab}"
  local default_if
  default_if="$(detect_default_iface || true)"

  [[ -n "$iface" ]] || die "LAB_IF não definido."
  [[ "$iface" != "$default_if" ]] || die "LAB_IF não pode ser a interface de gerenciamento."

  ip link set "$iface" up >/dev/null 2>&1 || true

  if ensure_nm >/dev/null 2>&1; then
    if ! nmcli con show "$conn" >/dev/null 2>&1; then
      nmcli con add type ethernet ifname "$iface" con-name "$conn" \
        ipv4.method manual \
        ipv4.addresses "$ip_cidr" \
        ipv4.never-default yes \
        ipv4.ignore-auto-dns yes \
        ipv6.method ignore \
        connection.autoconnect yes >/dev/null
    else
      nmcli con mod "$conn" ipv4.method manual ipv4.addresses "$ip_cidr" ipv4.never-default yes ipv4.ignore-auto-dns yes ipv6.method ignore
    fi
    nmcli con up "$conn" >/dev/null 2>&1 || true
  else
    ip addr add "$ip_cidr" dev "$iface" 2>/dev/null || true
  fi
}

write_base_dirs(){
  install -d -m 755 \
    "$LAB_ROOT"/pcap \
    "$LAB_ROOT"/scripts \
    "$LAB_ROOT"/exports \
    "$LAB_ROOT"/logs \
    "$LAB_ROOT"/docs \
    "$LAB_ROOT"/reports \
    "$LAB_ROOT"/modbus \
    "$LAB_ROOT"/attacks \
    "$LAB_ROOT"/defense \
    "$LAB_ROOT"/tmp \
    "$LAB_ROOT"/tests \
    "$LAB_ROOT"/tools
  chown -R "$LAB_USER:$LAB_USER" "$LAB_ROOT"
}

write_lab_scripts(){
  cat >"$LAB_ROOT/scripts/discover_lab.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "===================================="
echo "DISCOVERING LAB"
echo "===================================="
echo
echo "[*] Ping sweep em 192.168.100.0/24"
nmap -sn 192.168.100.0/24
echo
echo "[*] ARP scan em 192.168.100.0/24"
sudo arp-scan 192.168.100.0/24
echo
echo "[*] Done"
EOF
  chmod +x "$LAB_ROOT/scripts/discover_lab.sh"

  cat >"$LAB_ROOT/scripts/capture_modbus.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
INTERFACE="${INTERFACE:-eth1}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
mkdir -p ~/lab/pcap
sudo tcpdump -i "${INTERFACE}" tcp port 502 -w ~/lab/pcap/modbus_${TIMESTAMP}.pcap
EOF
  chmod +x "$LAB_ROOT/scripts/capture_modbus.sh"

  cat >"$LAB_ROOT/scripts/check_ports.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo
echo "[*] PLC (192.168.100.20)"
nmap -sV 192.168.100.20
echo
echo "[*] HMI (192.168.100.30)"
nmap -sV 192.168.100.30
echo
echo "[*] Database (192.168.100.50)"
nmap -sV 192.168.100.50
EOF
  chmod +x "$LAB_ROOT/scripts/check_ports.sh"

  cat >"$LAB_ROOT/scripts/check_modbus.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
nc -vz 192.168.100.20 502
EOF
  chmod +x "$LAB_ROOT/scripts/check_modbus.sh"

  cat >"$LAB_ROOT/scripts/test_modbus.py" <<'EOF'
#!/usr/bin/env python3
from pymodbus.client import ModbusTcpClient
PLC_IP = "192.168.100.20"
c = ModbusTcpClient(PLC_IP, port=502)
print(f"[*] Connecting to {PLC_IP}:502")
if c.connect():
    print("[+] Connected")
    print(c.read_holding_registers(0, 10, slave=1))
    c.close()
else:
    print("[-] Failed to connect")
EOF
  chmod +x "$LAB_ROOT/scripts/test_modbus.py"

  cat >"$LAB_ROOT/scripts/write_modbus.py" <<'EOF'
#!/usr/bin/env python3
from pymodbus.client import ModbusTcpClient
PLC_IP = "192.168.100.20"
c = ModbusTcpClient(PLC_IP, port=502)
print(f"[*] Connecting to {PLC_IP}:502")
if c.connect():
    print("[+] Connected")
    print(c.write_register(0, 123, slave=1))
    c.close()
else:
    print("[-] Failed to connect")
EOF
  chmod +x "$LAB_ROOT/scripts/write_modbus.py"

  cat >"$LAB_ROOT/scripts/lab_status.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ip a
ip route
nmcli dev status 2>/dev/null || true
ping -c 1 -W 2 1.1.1.1 || true
ping -c 1 -W 2 google.com || true
EOF
  chmod +x "$LAB_ROOT/scripts/lab_status.sh"

  ln -sf "$LAB_ROOT/scripts/discover_lab.sh" /usr/local/bin/scanlab
  ln -sf "$LAB_ROOT/scripts/test_modbus.py" /usr/local/bin/modtest
  ln -sf "$LAB_ROOT/scripts/write_modbus.py" /usr/local/bin/modwrite
  ln -sf "$LAB_ROOT/scripts/capture_modbus.sh" /usr/local/bin/capmod
  ln -sf "$LAB_ROOT/scripts/check_ports.sh" /usr/local/bin/checkplc
  ln -sf "$LAB_ROOT/scripts/check_modbus.sh" /usr/local/bin/checkmodbus
  ln -sf "$LAB_ROOT/scripts/lab_status.sh" /usr/local/bin/labstatus
  chmod +x /usr/local/bin/scanlab /usr/local/bin/modtest /usr/local/bin/modwrite /usr/local/bin/capmod /usr/local/bin/checkplc /usr/local/bin/checkmodbus /usr/local/bin/labstatus

  if ! grep -q "SCADA LAB ALIASES" "/home/${LAB_USER}/.bashrc"; then
    cat >>"/home/${LAB_USER}/.bashrc" <<'EOF'

# =============================================================
# SCADA LAB ALIASES
# =============================================================
alias ll='ls -lah'
alias shared='cd /media/sf_shared_dir'
alias labroot='cd /opt/scada-lab'
alias scanlab='scanlab'
alias modtest='modtest'
alias modwrite='modwrite'
alias capmod='capmod'
alias checkplc='checkplc'
alias checkmodbus='checkmodbus'
alias labstatus='labstatus'
EOF
  fi
  chown "${LAB_USER}:${LAB_USER}" "/home/${LAB_USER}/.bashrc"
}

set_motd(){
  cat >/etc/motd <<EOF

===============================================================
 SCADA/ICS SECURITY LAB
 Domínio: ${HOSTNAME_FULL}
===============================================================

- Kali: administração e análise
- HMI: supervisão web/headless
- PLC: controle Modbus TCP
- Sensor: leituras e eventos
- DB: histórico e logs

===============================================================

EOF
}

base_finalize(){
  apt-get autoremove -y >/dev/null 2>&1 || true
  apt-get clean >/dev/null 2>&1 || true
  systemctl enable --now ssh >/dev/null 2>&1 || true
}

summary(){
  cat <<EOF
FINAL LAYOUT
- Kali Admin: 2 vCPU / 2 GB RAM / 4 GB swap / 16 GB disk / NVMe
- HMI: 2 vCPU / 2 GB RAM / 4 GB swap / 14 GB disk / NVMe
- PLC: 1 vCPU / 1 GB RAM / 2 GB swap / 10 GB disk / NVMe
- Template: 1 vCPU / 1 GB RAM / 1 GB swap / 12 GB disk / HDD
- Sensor: 1 vCPU / 512 MB RAM / 1 GB swap / 6 GB disk / HDD
- Database: 1 vCPU / 1 GB RAM / 2 GB swap / 14 GB disk / HDD

NETWORK
- mgmt stays untouched (VirtualBox NAT / current default route)
- OT interface gets static 192.168.100.0/24
- no gateway on lab_net

RULES
- No dhclient
- No gateway on OT
- No bridge for OT
- No modbus-pal
- Do not run apt installs without network
EOF
}

setup_kali(){
  local lab_if="${LAB_IF:-}"
  [[ -n "$lab_if" ]] || lab_if="$(detect_lab_iface || true)"
  [[ -n "$lab_if" ]] || die "Não consegui detectar a interface lab_net."

  set_hostname_hosts "kali-admin.semi" "kali-admin" \
    "192.168.100.20  plc-openplc.semi plc-openplc" \
    "192.168.100.30  scada-hmi.semi scada-hmi" \
    "192.168.100.40  sensor-node.semi sensor-node" \
    "192.168.100.50  db-server.semi db-server"

  configure_lab_iface "$lab_if" "$KALI_IP" "$LAB_CONN"
  install_common_pkgs
  create_user
  create_swap 4G
  write_base_dirs
  write_lab_scripts
  set_motd
  base_finalize
  echo "[OK] Kali pronta."
}

setup_template(){
  # Template: mantemos simples e conservador.
  set_hostname_hosts "linux-template.semi" "linux-template"
  install_common_pkgs
  create_user
  create_swap 1G
  write_base_dirs
  set_motd
  base_finalize
  echo "[OK] Template pronta."
}

setup_plc(){
  local lab_if="${LAB_IF:-}"
  [[ -n "$lab_if" ]] || lab_if="$(detect_lab_iface || true)"
  [[ -n "$lab_if" ]] || die "PLC bootstrap: interface lab_net não encontrada."

  set_hostname_hosts "plc-openplc.semi" "plc-openplc"
  configure_lab_iface "$lab_if" "$PLC_IP" "$LAB_CONN"

  install_common_pkgs
  apt-get install -y libmodbus-dev default-jre-headless >/dev/null 2>&1 || true
  create_user
  create_swap 2G
  write_base_dirs

  install -d -m 755 /opt/openplc
  if internet_ok; then
    if [[ ! -d /opt/openplc_src ]]; then
      git clone https://github.com/thiagoralves/OpenPLC_v3.git /opt/openplc_src >/dev/null 2>&1 || true
    fi
    if [[ -d /opt/openplc_src ]]; then
      (cd /opt/openplc_src && ./install.sh linux) || warn "OpenPLC install falhou; continue manualmente se necessário."
    fi
  fi
  echo "OpenPLC runtime pode ser colocado em /opt/openplc" >/opt/openplc/README.txt

  set_motd
  base_finalize
  echo "[OK] PLC pronta."
}

setup_hmi(){
  local lab_if="${LAB_IF:-}"
  [[ -n "$lab_if" ]] || lab_if="$(detect_lab_iface || true)"
  [[ -n "$lab_if" ]] || die "HMI bootstrap: interface lab_net não encontrada."

  set_hostname_hosts "scada-hmi.semi" "scada-hmi"
  configure_lab_iface "$lab_if" "$HMI_IP" "$LAB_CONN"

  install_common_pkgs
  apt-get install -y default-jre-headless >/dev/null 2>&1 || true
  apt-get install -y tomcat10 >/dev/null 2>&1 || apt-get install -y tomcat9 >/dev/null 2>&1 || true
  create_user
  create_swap 4G
  write_base_dirs

  install -d -m 755 /opt/scada-hmi
  echo "HMI/web pode ser colocada em /opt/scada-hmi" >/opt/scada-hmi/README.txt

  set_motd
  base_finalize
  echo "[OK] HMI pronta."
}

setup_sensor(){
  local lab_if="${LAB_IF:-}"
  [[ -n "$lab_if" ]] || lab_if="$(detect_lab_iface || true)"
  [[ -n "$lab_if" ]] || die "Sensor bootstrap: interface lab_net não encontrada."

  set_hostname_hosts "sensor-node.semi" "sensor-node"
  configure_lab_iface "$lab_if" "$SENSOR_IP" "$LAB_CONN"

  install_common_pkgs
  create_user
  create_swap 1G
  write_base_dirs

  install -d -m 755 /opt/sensor
  cat >/opt/sensor/sensor_sim.py <<'EOF'
#!/usr/bin/env python3
import time, random
from pathlib import Path
from datetime import datetime

log = Path("/opt/sensor/sensor.log")
log.parent.mkdir(parents=True, exist_ok=True)

while True:
    line = f"{datetime.now().isoformat()} temp={20+random.random()*10:.2f} vib={random.random()*2:.2f}\n"
    log.write_text((log.read_text() if log.exists() else "") + line)
    print(line, end="")
    time.sleep(5)
EOF
  chmod +x /opt/sensor/sensor_sim.py

  set_motd
  base_finalize
  echo "[OK] Sensor pronta."
}

setup_db(){
  local lab_if="${LAB_IF:-}"
  [[ -n "$lab_if" ]] || lab_if="$(detect_lab_iface || true)"
  [[ -n "$lab_if" ]] || die "DB bootstrap: interface lab_net não encontrada."

  set_hostname_hosts "db-server.semi" "db-server"
  configure_lab_iface "$lab_if" "$DB_IP" "$LAB_CONN"

  install_common_pkgs
  apt-get install -y postgresql postgresql-contrib >/dev/null 2>&1 || true
  create_user
  create_swap 2G
  write_base_dirs

  if systemctl is-active postgresql >/dev/null 2>&1; then
    systemctl enable --now postgresql
    pgver="$(ls /etc/postgresql | sort -V | tail -n1 || true)"
    if [[ -n "${pgver:-}" && -f "/etc/postgresql/${pgver}/main/postgresql.conf" ]]; then
      sed -i "s/^#\?listen_addresses.*/listen_addresses = '*'/" "/etc/postgresql/${pgver}/main/postgresql.conf" || true
      grep -q "192.168.100.0/24" "/etc/postgresql/${pgver}/main/pg_hba.conf" || \
        echo "host    all     all     192.168.100.0/24    scram-sha-256" >>"/etc/postgresql/${pgver}/main/pg_hba.conf"
      systemctl restart postgresql

      sudo -u postgres psql <<'EOF'
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'scada_lab') THEN
    CREATE ROLE scada_lab LOGIN PASSWORD 'Postgres2026!';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'scadalab') THEN
    CREATE DATABASE scadalab OWNER scada_lab;
  END IF;
END $$;
EOF
    fi
  fi

  set_motd
  base_finalize
  echo "[OK] DB pronta."
}

menu(){
  while true; do
    cat <<EOF

==================== SCADA LAB MASTER SETUP ====================
1) Kali Admin
2) Linux Template
3) PLC OpenPLC
4) SCADA HMI
5) Sensor Node
6) Database Server
7) Show final layout summary
0) Exit
================================================================
EOF
    read -r -p "Choose: " choice
    case "$choice" in
      1) setup_kali ;;
      2) setup_template ;;
      3) setup_plc ;;
      4) setup_hmi ;;
      5) setup_sensor ;;
      6) setup_db ;;
      7) summary ;;
      0) exit 0 ;;
      *) echo "[!] Opção inválida" ;;
    esac
    echo
    read -r -p "Pressione ENTER para voltar ao menu..." _
  done
}

case "${ROLE:-}" in
  --kali|kali) setup_kali ;;
  --template|template) setup_template ;;
  --plc|plc) setup_plc ;;
  --hmi|hmi) setup_hmi ;;
  --sensor|sensor) setup_sensor ;;
  --db|db) setup_db ;;
  --all) summary ;;
  "") menu ;;
  *) die "Uso: --kali|--template|--plc|--hmi|--sensor|--db|--all" ;;
esac