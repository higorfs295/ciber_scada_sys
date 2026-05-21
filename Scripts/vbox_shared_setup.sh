#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# VBox Shared Folder Guest Setup
# =============================================================================
# Objetivo:
# - preparar a VM Linux para usar a pasta compartilhada do VirtualBox
# - instalar Guest Additions (quando possível)
# - adicionar o usuário ao grupo vboxsf
# - criar ponto de montagem
# - montar a pasta compartilhada
# - configurar montagem persistente
#
# IMPORTANTE:
# - A pasta compartilhada deve ser criada no VirtualBox manualmente:
#   Nome: shared
#   Caminho: E:\SCADA-LAB\Shared (ou a pasta que você escolher)
#   Marcar: Auto-mount / Permanent
# - Este script roda dentro da VM
# =============================================================================

set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

SHARE_NAME="${SHARE_NAME:-shared}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/shared}"
LAB_USER="${LAB_USER:-labadmin}"
PREFER_MEDIA_PATH="${PREFER_MEDIA_PATH:-yes}"

log(){ echo "[+] $*"; }
warn(){ echo "[!] $*" >&2; }
die(){ echo "[X] $*" >&2; exit 1; }

have_cmd(){ command -v "$1" >/dev/null 2>&1; }

detect_pkg_manager() {
  if have_cmd apt-get; then
    echo apt
  else
    die "Este script foi preparado para sistemas Debian/Ubuntu/Kali."
  fi
}

install_deps() {
  log "Instalando dependências"
  apt-get update || true
  apt-get install -y \
    build-essential dkms gcc make perl tar bzip2 curl wget \
    linux-headers-$(uname -r) \
    virtualbox-guest-utils \
    virtualbox-guest-dkms \
    virtualbox-guest-x11 \
    >/dev/null 2>&1 || true
}

enable_services() {
  log "Habilitando serviços do VirtualBox"
  systemctl enable vboxservice >/dev/null 2>&1 || true
  systemctl start vboxservice >/dev/null 2>&1 || true
}

ensure_user() {
  log "Validando usuário"
  if ! id "$LAB_USER" >/dev/null 2>&1; then
    warn "Usuário $LAB_USER não encontrado. Criando usuário básico."
    useradd -m -s /bin/bash "$LAB_USER"
    passwd "$LAB_USER"
  fi
  usermod -aG vboxsf "$LAB_USER" >/dev/null 2>&1 || true
}

ensure_mount_point() {
  log "Criando ponto de montagem"
  mkdir -p "$MOUNT_POINT"
  chmod 775 "$MOUNT_POINT"
}

try_mount_now() {
  log "Tentando montar a pasta compartilhada"
  if mountpoint -q "$MOUNT_POINT"; then
    warn "$MOUNT_POINT já está montado."
    return 0
  fi

  if mount -t vboxsf "$SHARE_NAME" "$MOUNT_POINT"; then
    log "Pasta compartilhada montada com sucesso"
  else
    warn "Montagem imediata falhou."
    warn "Causas comuns:"
    warn "- a pasta ainda não foi criada no VirtualBox"
    warn "- Guest Additions ainda não carregaram"
    warn "- a VM precisa reiniciar"
    warn "- o nome 'shared' está incorreto"
  fi
}

configure_fstab() {
  log "Configurando montagem persistente em /etc/fstab"

  local uid gid
  uid="$(id -u "$LAB_USER")"
  gid="$(id -g "$LAB_USER")"

  if ! grep -q "vboxsf" /etc/fstab; then
    echo "${SHARE_NAME} ${MOUNT_POINT} vboxsf defaults,uid=${uid},gid=${gid},rw 0 0" >> /etc/fstab
  else
    warn "Já existe uma entrada vboxsf no /etc/fstab"
  fi
}

create_aliases() {
  log "Criando aliases úteis"
  local bashrc="/home/${LAB_USER}/.bashrc"
  touch "$bashrc"
  chown "$LAB_USER:$LAB_USER" "$bashrc"

  if ! grep -q "SCADA_SHARED_ALIASES" "$bashrc"; then
    cat >> "$bashrc" <<'EOF'

# ============================================================
# SCADA_SHARED_ALIASES
# ============================================================
alias shared='cd /mnt/shared'
alias labshared='cd /mnt/shared'
alias ll='ls -lah'
EOF
  fi
}

finalize() {
  chown -R "$LAB_USER:$LAB_USER" "$MOUNT_POINT" >/dev/null 2>&1 || true

  cat <<EOF

============================================================
CONFIGURAÇÃO FINALIZADA
============================================================

Usuário:        ${LAB_USER}
Share name:     ${SHARE_NAME}
Mount point:    ${MOUNT_POINT}

Teste agora:
  1) Reinicie a VM
  2) Execute: shared
  3) Verifique o conteúdo
  4) Execute: mount | grep vboxsf

============================================================

EOF
}

main() {
  log "Iniciando setup da pasta compartilhada"
  install_deps
  enable_services
  ensure_user
  ensure_mount_point
  try_mount_now
  configure_fstab
  create_aliases
  finalize
}

main "$@"
