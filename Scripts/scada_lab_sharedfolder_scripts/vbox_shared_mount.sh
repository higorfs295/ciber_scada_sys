#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# VBox Shared Folder Mount Helper
# =============================================================================
# Monta manualmente a pasta compartilhada do VirtualBox.
# Útil quando o automount não ocorreu logo após o boot.
# =============================================================================

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

SHARE_NAME="${SHARE_NAME:-shared}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/shared}"

if ! command -v mount >/dev/null 2>&1; then
  echo "[X] comando mount não encontrado"
  exit 1
fi

mkdir -p "$MOUNT_POINT"

if mountpoint -q "$MOUNT_POINT"; then
  echo "[+] Já montado em $MOUNT_POINT"
  exit 0
fi

mount -t vboxsf "$SHARE_NAME" "$MOUNT_POINT"

echo "[+] Montado com sucesso em $MOUNT_POINT"
echo "[+] Use: cd $MOUNT_POINT"
