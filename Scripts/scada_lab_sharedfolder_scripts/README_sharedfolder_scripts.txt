PACOTE DE SCRIPTS PARA PASTA COMPARTILHADA DO VIRTUALBOX
=======================================================

Arquivos:
- vbox_shared_setup.sh
- vbox_shared_mount.sh

O que você faz no VirtualBox manualmente:
- Adiciona a pasta compartilhada
- Nome: shared
- Marca Auto-mount
- Marca Permanent

Depois, dentro da VM Linux:
1. Copie o script para a VM (via shared folder, se já existir, ou outra forma)
2. Execute:
   sudo bash vbox_shared_setup.sh

O script:
- instala dependências
- tenta instalar Guest Additions
- adiciona o usuário ao grupo vboxsf
- cria /mnt/shared
- tenta montar a pasta
- adiciona entrada persistente no /etc/fstab
- cria aliases

Se o automount não acontecer após reboot:
- execute:
  sudo bash vbox_shared_mount.sh

Observação:
- O script assume nome de pasta: shared
- Ajuste SHARE_NAME e MOUNT_POINT se quiser outro nome/caminho
