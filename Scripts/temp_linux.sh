#!/usr/bin/env bash

# =============================================================================
# LINUX TEMPLATE - FINAL BASE SETUP
# =============================================================================
#
# OBJETIVO
# -----------------------------------------------------------------------------
# Script LEVE e ESTÁVEL para transformar a VM linux-template
# em uma golden image limpa e segura para clonagem.
#
# Este script:
# - NÃO mexe agressivamente na rede
# - NÃO reinicia NetworkManager
# - NÃO altera gateway
# - NÃO configura IP fixo
# - NÃO altera DHCP
# - NÃO mexe no NAT
#
# Ele apenas:
# - instala ferramentas básicas;
# - configura SSH;
# - configura hostname;
# - instala ferramentas úteis;
# - cria estrutura inicial do laboratório;
# - configura aliases simples;
# - valida conectividade.
#
# Ideal para:
# - Debian minimal
# - Ubuntu Server minimal
# - Kali minimal
# - VMs headless
#
# =============================================================================
# AUTOR
# -----------------------------------------------------------------------------
# Higor Ferreira Silva
# =============================================================================

set -e

# =============================================================================
# CONFIGURAÇÕES
# =============================================================================

HOSTNAME_FULL="linux-template.semi"
HOSTNAME_SHORT="linux-template"

LAB_USER="${SUDO_USER:-labadmin}"

LAB_ROOT="/opt/scada-lab"

# =============================================================================
# FUNÇÕES
# =============================================================================

log() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

# =============================================================================
# VERIFICAÇÃO ROOT
# =============================================================================

if [[ "$EUID" -ne 0 ]]; then
    echo "[X] Execute com sudo."
    exit 1
fi

# =============================================================================
# INÍCIO
# =============================================================================

log "INICIANDO CONFIGURAÇÃO DA TEMPLATE"

# =============================================================================
# LIMPEZA DE IP ESTÁTICO ACIDENTAL
# =============================================================================

log "REMOVENDO IP OT ACIDENTAL DA INTERFACE NAT"

ip addr del 192.168.100.11/24 dev enp0s3 2>/dev/null || true
ip addr del 192.168.50.10/24 dev enp0s3 2>/dev/null || true

# =============================================================================
# VALIDAÇÃO DE INTERNET
# =============================================================================

log "VALIDANDO INTERNET"

if ping -c 2 1.1.1.1 >/dev/null 2>&1; then
    echo "[+] Internet OK"
else
    echo "[X] Sem internet."
    echo "[X] Corrija NAT/DHCP antes de continuar."
    exit 1
fi

# =============================================================================
# UPDATE
# =============================================================================

log "ATUALIZANDO REPOSITÓRIOS"

apt update

# =============================================================================
# INSTALAÇÃO BASE
# =============================================================================

log "INSTALANDO FERRAMENTAS ESSENCIAIS"

apt install -y \
openssh-server \
curl \
wget \
git \
vim \
nano \
htop \
tmux \
tree \
zip \
unzip \
net-tools \
dnsutils \
tcpdump \
iputils-ping \
traceroute \
python3 \
python3-pip \
python3-venv \
build-essential \
rsync \
ca-certificates

# =============================================================================
# SSH
# =============================================================================

log "CONFIGURANDO SSH"

systemctl enable ssh
systemctl restart ssh

# =============================================================================
# HOSTNAME
# =============================================================================

log "CONFIGURANDO HOSTNAME"

hostnamectl set-hostname "${HOSTNAME_FULL}"

cat > /etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 ${HOSTNAME_FULL} ${HOSTNAME_SHORT}

# IPv6
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# =============================================================================
# ESTRUTURA DO LAB
# =============================================================================

log "CRIANDO ESTRUTURA BASE DO LAB"

mkdir -p ${LAB_ROOT}/{scripts,pcap,exports,logs,tmp,docs}

chmod -R 755 ${LAB_ROOT}

# =============================================================================
# ALIASES
# =============================================================================

log "CONFIGURANDO ALIASES"

BASHRC="/home/${LAB_USER}/.bashrc"

touch "${BASHRC}"

if ! grep -q "SCADA_TEMPLATE_ALIASES" "${BASHRC}"; then

cat >> "${BASHRC}" << 'EOF'

# ============================================================
# SCADA_TEMPLATE_ALIASES
# ============================================================

alias ll='ls -lah'
alias labroot='cd /opt/scada-lab'
alias shared='cd /mnt/shared'

EOF

fi

chown ${LAB_USER}:${LAB_USER} "${BASHRC}"

# =============================================================================
# MOTD
# =============================================================================

log "CONFIGURANDO IDENTIDADE DA TEMPLATE"

cat > /etc/motd <<EOF

============================================================
 SCADA/ICS LAB - LINUX TEMPLATE
============================================================

Hostname:
${HOSTNAME_FULL}

Objetivo:
- Golden Image
- Base de Clonagem
- Ambiente Minimalista
- Laboratório SCADA/ICS

============================================================

EOF

# =============================================================================
# LIMPEZA
# =============================================================================

log "LIMPANDO SISTEMA"

apt autoremove -y
apt clean

# =============================================================================
# TESTES FINAIS
# =============================================================================

log "VALIDANDO RESULTADO FINAL"

echo
echo "[*] Hostname:"
hostname

echo
echo "[*] Interfaces:"
ip a

echo
echo "[*] Rotas:"
ip route

echo
echo "[*] Testando internet:"
ping -c 2 1.1.1.1 || true

echo
echo "[*] Testando DNS:"
ping -c 2 google.com || true

echo
echo "[*] SSH:"
systemctl status ssh --no-pager

# =============================================================================
# FINAL
# =============================================================================

log "TEMPLATE CONFIGURADA COM SUCESSO"

echo
echo "PRÓXIMOS PASSOS:"
echo
echo "1. Validar shared folder"
echo "2. Validar reboot"
echo "3. Desligar VM"
echo "4. Criar snapshot:"
echo
echo "   base-clean"
echo
echo "5. NÃO usar esta VM diretamente"
echo "6. Apenas CLONAR"
echo

# =============================================================================
# REBOOT OPCIONAL
# =============================================================================

echo
read -p "Deseja reiniciar agora? (s/n): " OPCAO

if [[ "$OPCAO" == "s" || "$OPCAO" == "S" ]]; then
    reboot
fi

# =============================================================================
# FIM
# =============================================================================