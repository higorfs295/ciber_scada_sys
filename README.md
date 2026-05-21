================================================================================
LABORATÓRIO SCADA / ICS VIRTUALIZADO — ROTEIRO COMPLETO REVISADO
Ambiente headless com Kali Admin no NVMe + HMI/PLC no NVMe + DB/Sensor no HDD
Domínio interno: .semi
Rede OT: lab_net
================================================================================

AUTOR
Higor Ferreira Silva

OBJETIVO GERAL
Construir um ambiente virtualizado, isolado e reproduzível para estudo de
sistemas supervisórios SCADA, controladores industriais, comunicação OT,
monitoramento de rede, threat intelligence, gestão de vulnerabilidades e testes
básicos de cibersegurança industrial.

OBJETIVOS PRÁTICOS
- Simular uma pequena infraestrutura industrial.
- Representar os componentes clássicos de um cenário SCADA/ICS.
- Permitir observação de tráfego industrial e comportamento de serviços.
- Validar comunicação entre supervisório, PLC, sensores e banco de dados.
- Executar testes controlados de enumeração, captura e bloqueio.
- Organizar o laboratório para fins acadêmicos, demonstrativos e experimentais.
- Manter o host físico fora da rede OT simulada.
- Garantir que o ambiente possa ser reconstruído com facilidade.
- Evitar conflito de rede entre o canal de gerenciamento e a rede OT.

================================================================================
1) VISÃO GERAL DA ARQUITETURA
================================================================================

HOST FÍSICO
- Windows
- Oracle VirtualBox
- NVMe interno disponível
- HD externo SATA 1 TB conectado via USB 3.0

AMBIENTE DE TESTE
- Todas as VMs são headless
- Sem interface gráfica em nenhuma VM
- Administração via SSH, scripts, terminal e dashboards web
- O host Windows não participa da rede OT

REDE BASE
- eth0 da Kali = gerenciamento / internet / atualizações
- eth1 da Kali = rede OT isolada lab_net
- lab_net = 192.168.100.0/24
- domínio lógico interno = .semi

MODELO DE ARMAZENAMENTO
- NVMe interno: Kali Admin, SCADA HMI e PLC OpenPLC
- HD externo: linux-template, Database, Sensor, snapshots, ISOs, exports, PCAPs

POR QUE ESSE DESENHO?
- A Kali é a máquina mais usada e mais sensível a desempenho
- O HMI e o PLC respondem melhor no NVMe
- O banco e o sensor podem ficar no externo sem comprometer a simulação
- O template fica no externo por ser apenas imagem-base
- O laboratório fica mais estável em um host com memória moderada

================================================================================
2) DOMÍNIO LÓGICO INTERNO .SEMI
================================================================================

O domínio interno .semi não é um domínio público nem precisa sair da rede.
Ele existe apenas para dar identidade ao laboratório e padronizar os hosts.

.semi significa, neste contexto:
Smart Environment for Monitoring and Industry

É um nome funcional porque:
- organiza os hosts;
- ajuda na documentação;
- melhora a apresentação do projeto;
- dá coerência visual e conceitual ao laboratório.

Exemplos de nomes:
- kali-admin.semi
- linux-template.semi
- plc-openplc.semi
- scada-hmi.semi
- sensor-node.semi
- db-server.semi

================================================================================
3) ESTRUTURA DE PASTAS
================================================================================

A estrutura a seguir deve ser mantida exatamente assim:

E:\SCADA-LAB\
E:\SCADA-LAB\Base\
E:\SCADA-LAB\PLC\
E:\SCADA-LAB\HMI\
E:\SCADA-LAB\Sensor\
E:\SCADA-LAB\Database\
E:\SCADA-LAB\Snapshots\
E:\SCADA-LAB\ISOs\
E:\SCADA-LAB\PCAP\
E:\SCADA-LAB\Docs\
E:\SCADA-LAB\Scripts\
E:\SCADA-LAB\Exports\

FINALIDADE
- Base: golden image e arquivos da VM modelo
- PLC: VDI, logs e arquivos do controlador
- HMI: arquivos do supervisório
- Sensor: scripts e dados do sensor simulado
- Database: banco, dump e persistência
- Snapshots: pontos de retorno
- ISOs: instaladores de SO
- PCAP: capturas de rede
- Docs: documentação e evidências
- Scripts: automações
- Exports: OVA, backups e exportações

Essa organização evita a mistura de artefatos e facilita bastante a manutenção.

================================================================================
4) TABELA FINAL DE RECURSOS
================================================================================

| VM | Função | vCPU | RAM | Swap | Disco | Local | Observações |
|---|---:|---:|---:|---:|---:|---|---|
| Kali Admin | Administração, análise, captura e testes | 2 | 3 GB | 6 GB | 24 GB | NVMe interno | VM principal, headless |
| SCADA HMI | Supervisão, alarmes e dashboards web | 2 | 3 GB | 6 GB | 15 GB | NVMe interno | Headless, web-based |
| PLC OpenPLC | Controle industrial e Modbus TCP | 1 | 1,5 GB | 4 GB | 15 GB | NVMe interno | Leve e estável |
| Database | Histórico, eventos e logs | 1 | 1,5 GB | 4 GB | 15 GB | HD externo | PostgreSQL headless |
| Sensor Node | Simulação de sensores | 1 | 718 MB | 1 GB | 15 GB | HD externo | Scripts Python |
| linux-template | Base de clonagem | 1 | 1,5 GB | 1 GB | 15 GB | HD externo | Só molde |

RESUMO
- RAM total provisionada: 7,5 GB
- Swap total provisionado: 14 GB
- Disco provisionado total: 72 GB

================================================================================
5) ESPECIFICAÇÕES DAS MÁQUINAS VIRTUAIS
================================================================================

--------------------------------------------------------------------------------
5.1) KALI ADMIN — ARMAZENAMENTO INTERNO NVMe
--------------------------------------------------------------------------------

NOME DA VM
kali-admin

HOSTNAME COMPLETO
kali-admin.semi

FUNÇÃO
- estação de administração
- estação atacante controlada
- captura de tráfego
- enumeração
- testes
- consulta aos demais nós
- máquina principal do laboratório

LOCAL
- NVMe interno

ESPECIFICAÇÃO RECOMENDADA
- vCPU: 2
- RAM: 2048 MB
- Swap: 4 GB
- Disco: 16 GB dinâmico

REDE
- eth0 = gerenciamento / internet
- eth1 = lab_net

IP ESPERADO
- eth0 = DHCP via NAT ou rede de gerenciamento funcional
- eth1 = 192.168.100.10/24

OBSERVAÇÃO
- a eth0 não deve receber IP fixo da OT
- a eth1 não deve ter gateway
- a eth1 é exclusiva para a rede OT
- a Kali deve continuar headless, sem GUI

USUÁRIO
labadmin

SENHA
LabSCADA2026!

POR QUE ESSA CONFIGURAÇÃO?
- 2 GB de RAM combinados com swap ajudam a manter a Kali fluida
- 16 GB de disco cabem confortavelmente no limite interno
- o NVMe melhora a resposta de ferramentas e scripts

--------------------------------------------------------------------------------
5.2) LINUX TEMPLATE — HD EXTERNO
--------------------------------------------------------------------------------

NOME DA VM
linux-template

HOSTNAME COMPLETO
linux-template.semi

FUNÇÃO
- base limpa
- golden image
- fonte para clonagem

LOCAL
- HD externo SATA USB 3.0

ESPECIFICAÇÃO RECOMENDADA
- vCPU: 1
- RAM: 1024 MB
- Swap: 1 GB
- Disco: 12 GB dinâmico

REDE
- lab_net

IP
- não precisa de gateway
- a rede é interna
- a VM pode ficar apenas na lab_net

USUÁRIO
labadmin

SENHA
LabSCADA2026!

POR QUE ESSA CONFIGURAÇÃO?
- é só a base do laboratório
- 1 GB de RAM e 1 GB de swap são suficientes
- 12 GB dão margem para atualização, limpeza e snapshot base

--------------------------------------------------------------------------------
5.3) PLC OPENPLC — NVMe INTERNO
--------------------------------------------------------------------------------

NOME DA VM
plc-openplc

HOSTNAME COMPLETO
plc-openplc.semi

FUNÇÃO
- controlador industrial
- resposta Modbus TCP
- leitura e escrita de registradores
- lógica de processo

LOCAL
- NVMe interno

ESPECIFICAÇÃO RECOMENDADA
- vCPU: 1
- RAM: 1024 MB
- Swap: 2 GB
- Disco: 10 GB dinâmico

REDE
- lab_net

IP
- 192.168.100.20/24

SERVIÇO PRINCIPAL
- OpenPLC Runtime

PORTA PRINCIPAL
- 502/TCP

USUÁRIO
labadmin

SENHA
LabSCADA2026!

POR QUE ESSA CONFIGURAÇÃO?
- o PLC é leve
- responde melhor com baixa latência
- 1 GB de RAM e 2 GB de swap são suficientes para um cenário educacional

--------------------------------------------------------------------------------
5.4) SCADA HMI — NVMe INTERNO
--------------------------------------------------------------------------------

NOME DA VM
scada-hmi

HOSTNAME COMPLETO
scada-hmi.semi

FUNÇÃO
- supervisão
- alarmes
- tendências
- painéis
- leitura do PLC
- visualização do processo

LOCAL
- NVMe interno

ESPECIFICAÇÃO RECOMENDADA
- vCPU: 2
- RAM: 2048 MB
- Swap: 4 GB
- Disco: 14 GB dinâmico

REDE
- lab_net

IP
- 192.168.100.30/24

SERVIÇOS
- Java
- Tomcat
- aplicação HMI/SCADA web

PORTAS COMUNS
- 8080
- 8443

USUÁRIO
labadmin

SENHA
LabSCADA2026!

POR QUE ESSA CONFIGURAÇÃO?
- a HMI é a VM mais sensível a lentidão após a Kali
- 2 GB de RAM + swap ajudam muito em serviço headless web
- 14 GB permitem aplicação, logs e crescimento leve

--------------------------------------------------------------------------------
5.5) SENSOR NODE — HD EXTERNO
--------------------------------------------------------------------------------

NOME DA VM
sensor-node

HOSTNAME COMPLETO
sensor-node.semi

FUNÇÃO
- gerar sinais
- simular leituras
- alimentar o PLC
- representar entradas do processo

LOCAL
- HD externo SATA USB 3.0

ESPECIFICAÇÃO RECOMENDADA
- vCPU: 1
- RAM: 512 MB
- Swap: 1 GB
- Disco: 6 GB dinâmico

REDE
- lab_net

IP
- 192.168.100.40/24

USUÁRIO
labadmin

SENHA
LabSCADA2026!

POR QUE ESSA CONFIGURAÇÃO?
- nó muito leve
- scripts Python simples
- pouco uso de disco e memória

--------------------------------------------------------------------------------
5.6) DATABASE SERVER — HD EXTERNO
--------------------------------------------------------------------------------

NOME DA VM
db-server

HOSTNAME COMPLETO
db-server.semi

FUNÇÃO
- persistência
- histórico
- logs
- eventos
- auditoria local

LOCAL
- HD externo SATA USB 3.0

ESPECIFICAÇÃO RECOMENDADA
- vCPU: 1
- RAM: 1024 MB
- Swap: 2 GB
- Disco: 14 GB dinâmico

REDE
- lab_net

IP
- 192.168.100.50/24

BANCO RECOMENDADO
- PostgreSQL

USUÁRIO DO BANCO
postgres

SENHA DO BANCO
Postgres2026!

USUÁRIO DA VM
labadmin

SENHA DA VM
LabSCADA2026!

POR QUE ESSA CONFIGURAÇÃO?
- banco headless
- carga moderada
- histórico e logs sem exagero
- fica aceitável no HDD externo

================================================================================
6) RESUMO DE RECURSOS
================================================================================

ARMAZENAMENTO INTERNO
- Kali Admin: 16 GB
- SCADA HMI: 14 GB
- PLC OpenPLC: 10 GB
- total interno provisionado: 40 GB

ARMAZENAMENTO EXTERNO
- linux-template: 12 GB
- Sensor Node: 6 GB
- Database: 14 GB
- snapshots, ISOs, PCAPs e exports: restante

ESPAÇO EXTERNO REMANESCENTE
- suficiente para crescimento, snapshots e arquivos de evidência

SWAP TOTAL
- Kali: 4 GB
- HMI: 4 GB
- PLC: 2 GB
- Database: 2 GB
- Sensor: 1 GB
- Template: 1 GB

================================================================================
7) TOPOLOGIA DE REDE DEFINITIVA
================================================================================

AQUI ESTÁ A PARTE MAIS IMPORTANTE PARA NÃO RECRIAR O PROBLEMA DE REDE.

REDE DE GERENCIAMENTO
- interface da Kali: eth0
- função: internet / atualizações / downloads / administração
- IP: DHCP automático
- gateway: da rede de gerenciamento
- não deve ser usado para os ativos OT

REDE OT
- interface da Kali: eth1
- função: lab_net
- sub-rede: 192.168.100.0/24
- IP da Kali: 192.168.100.10/24
- sem gateway
- sem internet
- comunicação apenas entre as VMs do laboratório

TOPOLOGIA LÓGICA

                    INTERNET / GERENCIAMENTO
                               |
                             eth0
                        [ kali-admin ]
                        DHCP / NAT / mgmt
                               |
                               |
                     --------------------------------
                     |                              |
                     |                              |
                  eth1 -> lab_net             VMs OT internas
             192.168.100.10/24                    |
                     |                              |
                     |     -------------------------------
                     |     |       |        |            |
                     |   plc     hmi     sensor        db
                     |  .20     .30       .40         .50
                     --------------------------------

IMPORTANTE
- eth0 nunca deve receber o IP da OT
- eth1 nunca deve receber gateway
- o gateway default da Kali deve apontar para a rede de gerenciamento
- a lab_net deve ser exclusivamente interna

================================================================================
8) REQUISITOS DO HOST WINDOWS
================================================================================

RECOMENDADO
- VirtualBox instalado
- Extension Pack compatível
- VT-x / AMD-V habilitado
- 16 GB de RAM ou mais no host, idealmente 24 GB
- SSD/NVMe para o sistema host
- USB 3.0 estável para o HD externo
- evitar suspensão durante uso do laboratório

BOAS PRÁTICAS
- desligar as VMs antes de retirar o HD externo
- não usar bridge para a rede OT
- não misturar arquivo de VM no host e no externo sem organização
- não clonar VMs ligadas
- não fazer snapshots excessivos sem necessidade

================================================================================
9) PASSO A PASSO DE DESENVOLVIMENTO DO AMBIENTE
================================================================================

A seguir está o fluxo mais simples e mais seguro para montar tudo.

--------------------------------------------------------------------------------
9.1) PREPARAR O HOST
--------------------------------------------------------------------------------

1. Conferir se a virtualização está ativa na BIOS/UEFI.
2. Instalar o Oracle VirtualBox.
3. Instalar o Extension Pack correspondente.
4. Criar as pastas do laboratório no HD externo.
5. Garantir que o HD externo esteja estável e com espaço disponível.
6. Separar o NVMe interno para a Kali, HMI e PLC.
7. Não conectar ainda o laboratório à internet física do host por bridge.

--------------------------------------------------------------------------------
9.2) BAIXAR AS ISOS
--------------------------------------------------------------------------------

Baixar:
- Kali Linux Installer ISO
- Ubuntu Server LTS ou Debian netinst

Guardar em:
- E:\SCADA-LAB\ISOs\

Se o espaço interno for limitado:
- deixar a ISO no externo ou mover depois
- manter o host limpo

--------------------------------------------------------------------------------
9.3) CRIAR A KALI ADMIN
--------------------------------------------------------------------------------

1. Criar a VM kali-admin no NVMe interno.
2. Definir:
   - 2 vCPU
   - 2048 MB RAM
   - 16 GB disco dinâmico
3. Criar duas interfaces:
   - eth0 = gerenciamento / internet
   - eth1 = lab_net
4. Instalar a Kali minimal/headless.
5. Criar usuário labadmin.
6. Definir senha LabSCADA2026!.

--------------------------------------------------------------------------------
9.4) CONFIGURAR A REDE DA KALI
--------------------------------------------------------------------------------

Objetivo:
- eth0 deve continuar com internet
- eth1 deve ser a rede OT

Estrutura correta:
- eth0: DHCP/NAT
- eth1: IP fixo 192.168.100.10/24

O que não fazer:
- não colocar IP da OT na eth0
- não colocar gateway na eth1
- não sobrescrever resolv.conf de forma manual permanente
- não configurar default route na OT
- não usar /etc/network/interfaces para brigar com o NetworkManager

RECOMENDAÇÃO
- usar NetworkManager para as duas interfaces
- eth0 = perfil DHCP
- eth1 = perfil estático sem gateway

--------------------------------------------------------------------------------
9.5) INSTALAR PACOTES ESSENCIAIS NA KALI
--------------------------------------------------------------------------------

Instalar:
- openssh-server
- curl
- wget
- git
- vim
- nano
- tmux
- htop
- net-tools
- dnsutils
- tcpdump
- tshark
- nmap
- arp-scan
- iperf3
- tree
- jq
- unzip
- zip
- python3
- python3-pip
- python3-venv
- python3-dev
- build-essential
- iproute2
- procps
- lsof
- psmisc
- whois
- traceroute
- mtr
- iputils-ping
- netcat-openbsd
- socat
- rsync
- ca-certificates

Opcionalmente, se disponíveis no repositório:
- btop
- iftop
- iotop
- masscan
- netdiscover
- mbpoll

BIBLIOTECAS PYTHON
- pymodbus
- pyModbusTCP
- scapy
- opcua
- pandas
- matplotlib
- flask
- requests

OBSERVAÇÃO
- `modbus-pal` não será usado porque não está disponível nos repositórios padrões
- `tshark` é suficiente para a análise em ambiente headless

--------------------------------------------------------------------------------
9.6) AJUSTAR SSH NA KALI
--------------------------------------------------------------------------------

Ativar:
- ssh service

Endurecimento básico:
- desabilitar login root via SSH
- permitir autenticação por senha apenas se for necessário no lab

--------------------------------------------------------------------------------
9.7) CONFIGURAR A ESTRUTURA DE DIRETÓRIOS NA KALI
--------------------------------------------------------------------------------

Criar:

~/lab/
~/lab/pcap/
~/lab/scripts/
~/lab/logs/
~/lab/reports/
~/lab/modbus/
~/lab/tests/
~/lab/tools/
~/lab/exports/

--------------------------------------------------------------------------------
9.8) CRIAR A BASE linux-template
--------------------------------------------------------------------------------

1. Criar linux-template no HD externo.
2. Configurar:
   - 1 vCPU
   - 1024 MB RAM
   - 1 GB swap
   - 12 GB disco
3. Instalar um servidor minimal sem GUI.
4. Definir hostname linux-template.semi.
5. Atualizar e limpar o sistema.
6. Instalar SSH e ferramentas básicas.
7. Criar snapshot base-clean.

--------------------------------------------------------------------------------
9.9) CLONAR A BASE
--------------------------------------------------------------------------------

A partir da linux-template, criar clones conforme a necessidade:

- plc-openplc
- scada-hmi
- sensor-node
- db-server

Depois de clonar:
- alterar hostname
- configurar IP estático
- instalar o serviço específico
- validar conectividade
- validar logs

--------------------------------------------------------------------------------
9.10) INSTALAR O PLC
--------------------------------------------------------------------------------

No plc-openplc:
- instalar OpenPLC Runtime
- validar porta 502/TCP
- testar leitura e escrita de registradores
- criar tags simples

--------------------------------------------------------------------------------
9.11) INSTALAR O HMI
--------------------------------------------------------------------------------

No scada-hmi:
- instalar Java
- instalar Tomcat ou stack equivalente
- instalar a aplicação HMI/SCADA web
- criar painéis
- criar alarmes
- conectar ao PLC

OBSERVAÇÃO
- o HMI é headless
- acesso visual será feito a partir da Kali, por navegador ou cliente web

--------------------------------------------------------------------------------
9.12) INSTALAR O SENSOR
--------------------------------------------------------------------------------

No sensor-node:
- instalar Python
- instalar pymodbus
- criar scripts que gerem leituras e variações
- simular sinais de processo

--------------------------------------------------------------------------------
9.13) INSTALAR O BANCO
--------------------------------------------------------------------------------

No db-server:
- instalar PostgreSQL
- criar banco scadalab
- criar usuário postgres com senha definida
- preparar tabelas de logs, eventos e histórico

================================================================================
10) SWAP PADRÃO E POLÍTICA DE MEMÓRIA
================================================================================

OBJETIVO
- manter as VMs estáveis mesmo com RAM reduzida
- usar swap como segurança, não como substituto de RAM

RECOMENDAÇÃO DE SWAPPINESS
- Kali: 15
- HMI: 20
- PLC: 5
- Database: 10
- Sensor: 10
- Template: 10

CRIAÇÃO DE SWAP (MODELO GERAL)
- criar arquivo swap com o tamanho da VM
- aplicar permissão 600
- ativar com mkswap / swapon
- registrar em /etc/fstab
- ajustar vm.swappiness em /etc/sysctl.d/

EXEMPLO DE IDEIA
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo 'vm.swappiness=15' | sudo tee /etc/sysctl.d/99-swappiness.conf
    sudo sysctl --system

================================================================================
11) REDE E ENDEREÇAMENTO IP
================================================================================

REDE DE GERENCIAMENTO
- DHCP/NAT na eth0
- endereço variável conforme a rede de virtualização
- usado somente para updates e administração

REDE OT
- 192.168.100.0/24
- eth1 da Kali: 192.168.100.10/24
- PLC: 192.168.100.20/24
- HMI: 192.168.100.30/24
- Sensor: 192.168.100.40/24
- DB: 192.168.100.50/24

SEM GATEWAY NA OT
- a rede OT é isolada
- sem saída para internet
- sem default route na eth1

================================================================================
12) PROBLEMAS QUE NÃO DEVEM SER REPETIDOS
================================================================================

1. Não colocar IP da OT na eth0.
2. Não adicionar gateway na eth1.
3. Não sobrescrever resolv.conf manualmente.
4. Não usar bridge para a OT.
5. Não misturar configuração estática de OT com a rede de gerenciamento.
6. Não instalar pacotes inexistentes como modbus-pal.
7. Não usar /etc/network/interfaces para gerar conflito com NetworkManager.
8. Não clonar VM ligada.
9. Não usar snapshots demais.
10. Não reconfigurar a rede toda hora.

================================================================================
13) COMO A KALI DEVE FICAR AO FINAL
================================================================================

A Kali deve ficar assim:

- eth0 = internet / gerenciamento / updates
- eth1 = lab_net / OT
- hostname = kali-admin.semi
- usuário = labadmin
- senha = LabSCADA2026!
- diretório ~/lab criado
- scripts prontos
- SSH ativo
- ferramentas de rede instaladas
- Python OT instalado
- IP da OT fixado em 192.168.100.10/24
- snapshot kali-ready criado

================================================================================
14) SCRIPTS DA KALI
================================================================================

Os scripts devem existir na Kali antes das demais VMs, pois ela será a estação
central de teste e enumeração.

--------------------------------------------------------------------------------
14.1) discover_lab.sh
--------------------------------------------------------------------------------

Objetivo:
- descobrir hosts na OT
- fazer ping sweep
- fazer ARP scan

Conteúdo:

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

--------------------------------------------------------------------------------
14.2) capture_modbus.sh
--------------------------------------------------------------------------------

Objetivo:
- capturar tráfego Modbus TCP na interface OT

Conteúdo:

    #!/usr/bin/env bash
    set -euo pipefail

    INTERFACE="${INTERFACE:-eth1}"
    TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

    mkdir -p ~/lab/pcap

    sudo tcpdump -i "${INTERFACE}" tcp port 502 -w ~/lab/pcap/modbus_${TIMESTAMP}.pcap

--------------------------------------------------------------------------------
14.3) check_ports.sh
--------------------------------------------------------------------------------

Objetivo:
- validar serviços principais das VMs OT

Conteúdo:

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

--------------------------------------------------------------------------------
14.4) check_modbus.sh
--------------------------------------------------------------------------------

Objetivo:
- verificar porta 502 no PLC

Conteúdo:

    #!/usr/bin/env bash
    set -euo pipefail

    TARGET="192.168.100.20"
    PORT="502"

    nc -vz "${TARGET}" "${PORT}"

--------------------------------------------------------------------------------
14.5) test_modbus.py
--------------------------------------------------------------------------------

Objetivo:
- leitura de registradores do PLC

Conteúdo:

    #!/usr/bin/env python3
    from pymodbus.client import ModbusTcpClient

    PLC_IP = "192.168.100.20"
    PLC_PORT = 502

    client = ModbusTcpClient(PLC_IP, port=PLC_PORT)

    print(f"[*] Connecting to {PLC_IP}:{PLC_PORT}")

    if client.connect():
        print("[+] Connected")
        result = client.read_holding_registers(0, 10, slave=1)
        print("[*] Read result:")
        print(result)
        client.close()
    else:
        print("[-] Failed to connect")

--------------------------------------------------------------------------------
14.6) write_modbus.py
--------------------------------------------------------------------------------

Objetivo:
- escrita controlada de registrador autorizado

Conteúdo:

    #!/usr/bin/env python3
    from pymodbus.client import ModbusTcpClient

    PLC_IP = "192.168.100.20"
    PLC_PORT = 502
    REGISTER = 0
    VALUE = 123

    client = ModbusTcpClient(PLC_IP, port=PLC_PORT)

    print(f"[*] Connecting to {PLC_IP}:{PLC_PORT}")

    if client.connect():
        print("[+] Connected")
        print(f"[*] Writing {VALUE} to register {REGISTER}")
        rr = client.write_register(REGISTER, VALUE, slave=1)
        print(rr)
        client.close()
    else:
        print("[-] Failed to connect")

--------------------------------------------------------------------------------
14.7) lab_status.sh
--------------------------------------------------------------------------------

Objetivo:
- verificar IPs, rotas e conectividade

Conteúdo:

    #!/usr/bin/env bash
    set -euo pipefail

    echo "=== IP ADDRESS ==="
    ip a

    echo
    echo "=== ROUTES ==="
    ip route

    echo
    echo "=== NETWORKMANAGER ==="
    nmcli dev status || true

    echo
    echo "=== PING MGMT ==="
    ping -c 1 -W 2 1.1.1.1 || true

    echo
    echo "=== PING DNS ==="
    ping -c 1 -W 2 google.com || true

================================================================================
15) SCRIPT ÚNICO DE CONFIGURAÇÃO DA KALI
================================================================================

A seguir está um script único e consolidado para configurar a Kali corretamente,
sem misturar a rede OT na interface errada.

Este script:
- mantém eth0 em DHCP / gerenciamento
- define eth1 como rede OT estática
- limpa perfis antigos
- evita gateway na OT
- instala pacotes
- cria scripts
- evita uso de modbus-pal
- prepara a máquina para snapshot

Conteúdo do script:

    #!/usr/bin/env bash
    set -euo pipefail

    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        exec sudo -E bash "$0" "$@"
    fi

    export DEBIAN_FRONTEND=noninteractive

    MGMT_IF="eth0"
    LAB_IF="eth1"
    LAB_CONN="scada-lab"
    MGMT_CONN="scada-mgmt"

    HOSTNAME_FULL="kali-admin.semi"
    HOSTNAME_SHORT="kali-admin"
    LAB_USER="labadmin"
    LAB_PASS="LabSCADA2026!"
    LAB_ROOT="/opt/scada-lab"

    LAB_IP_CIDR="192.168.100.10/24"
    PLC_IP="192.168.100.20"
    HMI_IP="192.168.100.30"
    SENSOR_IP="192.168.100.40"
    DB_IP="192.168.100.50"

    log(){ echo "[+] $*"; }
    warn(){ echo "[!] $*" >&2; }
    die(){ echo "[X] $*" >&2; exit 1; }

    log "Verificando interfaces"
    ip link show "$MGMT_IF" >/dev/null 2>&1 || die "Interface $MGMT_IF não encontrada"
    ip link show "$LAB_IF" >/dev/null 2>&1 || die "Interface $LAB_IF não encontrada"

    log "Configurando hostname"
    hostnamectl set-hostname "$HOSTNAME_FULL"

    log "Ajustando /etc/hosts"
    cat > /etc/hosts <<EOF
    127.0.0.1       localhost
    127.0.1.1       ${HOSTNAME_FULL} ${HOSTNAME_SHORT}
    192.168.100.20  plc-openplc.semi plc-openplc
    192.168.100.30  scada-hmi.semi scada-hmi
    192.168.100.40  sensor-node.semi sensor-node
    192.168.100.50  db-server.semi db-server
    ::1             localhost ip6-localhost ip6-loopback
    ff02::1         ip6-allnodes
    ff02::2         ip6-allrouters
    EOF

    log "Removendo conflitos de rede antigos"
    systemctl disable --now systemd-networkd >/dev/null 2>&1 || true
    systemctl disable --now networking >/dev/null 2>&1 || true

    cat > /etc/network/interfaces <<EOF
    source /etc/network/interfaces.d/*

    auto lo
    iface lo inet loopback
    EOF

    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/10-scada-lab.conf <<EOF
    [main]
    plugins=ifupdown,keyfile

    [ifupdown]
    managed=true
    EOF

    systemctl enable --now NetworkManager >/dev/null 2>&1 || true
    systemctl restart NetworkManager >/dev/null 2>&1 || true
    nmcli networking on >/dev/null 2>&1 || true

    log "Limpando perfis Ethernet antigos do NetworkManager"
    while IFS= read -r conn; do
        [[ -n "$conn" ]] && nmcli con delete "$conn" >/dev/null 2>&1 || true
    done < <(nmcli -t -f NAME,TYPE con show | awk -F: '$2=="802-3-ethernet"{print $1}')

    log "Limpando IPs antigos"
    ip addr flush dev "$MGMT_IF" >/dev/null 2>&1 || true
    ip addr flush dev "$LAB_IF" >/dev/null 2>&1 || true

    log "Criando conexão de gerenciamento DHCP na eth0"
    nmcli con add type ethernet \
        ifname "$MGMT_IF" \
        con-name "$MGMT_CONN" \
        ipv4.method auto \
        ipv4.route-metric 10 \
        ipv6.method ignore \
        connection.autoconnect yes \
        >/dev/null

    log "Criando conexão OT estática na eth1"
    nmcli con add type ethernet \
        ifname "$LAB_IF" \
        con-name "$LAB_CONN" \
        ipv4.method manual \
        ipv4.addresses "$LAB_IP_CIDR" \
        ipv4.never-default yes \
        ipv4.ignore-auto-dns yes \
        ipv6.method ignore \
        connection.autoconnect yes \
        >/dev/null

    log "Subindo conexões"
    nmcli con up "$MGMT_CONN" >/dev/null
    nmcli con up "$LAB_CONN" >/dev/null
    sleep 3

    log "Validando rede"
    ip -4 addr show "$MGMT_IF"
    ip -4 addr show "$LAB_IF"
    ip route

    if ! ip route | grep -q "^default .* dev ${MGMT_IF}"; then
        die "Rota default não está na interface de gerenciamento (${MGMT_IF})"
    fi

    if ! ip -4 addr show "$LAB_IF" | grep -q "192.168.100.10"; then
        die "eth1 não recebeu 192.168.100.10"
    fi

    log "Testando conectividade"
    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || die "Sem internet na interface de gerenciamento"
    ping -c 1 -W 2 google.com >/dev/null 2>&1 || warn "DNS externo falhou; revisar apenas se necessário"

    log "Atualizando sistema"
    apt-get update
    apt-get upgrade -y
    apt-get autoremove -y
    apt-get clean

    log "Instalando pacotes"
    apt-get install -y \
        openssh-server curl wget git vim nano tmux htop net-tools dnsutils \
        tcpdump tshark nmap arp-scan iperf3 tree jq unzip zip \
        python3 python3-pip python3-venv python3-dev build-essential dkms \
        iproute2 procps lsof psmisc whois traceroute mtr iputils-ping \
        netcat-openbsd socat rsync ca-certificates

    apt-get install -y mbpoll >/dev/null 2>&1 || warn "mbpoll não encontrado nos repositórios"
    apt-get install -y btop iftop iotop masscan netdiscover >/dev/null 2>&1 || true

    log "Instalando bibliotecas Python"
    pip3 install --break-system-packages pymodbus pyModbusTCP scapy opcua pandas matplotlib flask requests

    log "Ativando SSH"
    systemctl enable ssh
    systemctl start ssh

    if grep -q '^#\?PermitRootLogin' /etc/ssh/sshd_config; then
        sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    else
        echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
    fi

    if grep -q '^#\?PasswordAuthentication' /etc/ssh/sshd_config; then
        sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    else
        echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
    fi

    systemctl restart ssh

    log "Garantindo usuário do laboratório"
    if ! id "$LAB_USER" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$LAB_USER"
    fi
    echo "${LAB_USER}:${LAB_PASS}" | chpasswd
    usermod -aG sudo "$LAB_USER" >/dev/null 2>&1 || true
    getent group wireshark >/dev/null 2>&1 && usermod -aG wireshark "$LAB_USER" >/dev/null 2>&1 || true
    getent group vboxsf >/dev/null 2>&1 && usermod -aG vboxsf "$LAB_USER" >/dev/null 2>&1 || true

    log "Aplicando sysctl básico"
    cat > /etc/sysctl.d/99-scada-lab.conf <<EOF
    net.ipv4.icmp_echo_ignore_broadcasts = 1
    net.ipv4.conf.all.accept_redirects = 0
    net.ipv4.conf.default.accept_redirects = 0
    net.ipv4.conf.all.send_redirects = 0
    net.ipv4.conf.default.send_redirects = 0
    net.ipv4.conf.all.accept_source_route = 0
    net.ipv4.conf.default.accept_source_route = 0
    EOF
    sysctl --system >/dev/null

    log "Criando diretórios do laboratório"
    install -d -m 755 \
        "$LAB_ROOT"/pcap "$LAB_ROOT"/scripts "$LAB_ROOT"/exports "$LAB_ROOT"/logs \
        "$LAB_ROOT"/docs "$LAB_ROOT"/reports "$LAB_ROOT"/modbus "$LAB_ROOT"/attacks \
        "$LAB_ROOT"/defense "$LAB_ROOT"/tmp "$LAB_ROOT"/tests "$LAB_ROOT"/tools
    chown -R "$LAB_USER:$LAB_USER" "$LAB_ROOT"

    log "Criando scripts"
    cat > "$LAB_ROOT/scripts/discover_lab.sh" <<EOF
    #!/usr/bin/env bash
    set -euo pipefail
    echo "===================================="
    echo "DISCOVERING LAB"
    echo "===================================="
    nmap -sn 192.168.100.0/24
    sudo arp-scan 192.168.100.0/24
    EOF
    chmod +x "$LAB_ROOT/scripts/discover_lab.sh"

    cat > "$LAB_ROOT/scripts/capture_modbus.sh" <<EOF
    #!/usr/bin/env bash
    set -euo pipefail
    INTERFACE="\${INTERFACE:-${LAB_IF}}"
    TIMESTAMP="\$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${LAB_ROOT}/pcap"
    sudo tcpdump -i "\${INTERFACE}" tcp port 502 -w "${LAB_ROOT}/pcap/modbus_\${TIMESTAMP}.pcap"
    EOF
    chmod +x "$LAB_ROOT/scripts/capture_modbus.sh"

    cat > "$LAB_ROOT/scripts/check_ports.sh" <<EOF
    #!/usr/bin/env bash
    set -euo pipefail
    nmap -sV ${PLC_IP}
    nmap -sV ${HMI_IP}
    nmap -sV ${DB_IP}
    EOF
    chmod +x "$LAB_ROOT/scripts/check_ports.sh"

    cat > "$LAB_ROOT/scripts/check_modbus.sh" <<EOF
    #!/usr/bin/env bash
    set -euo pipefail
    nc -vz ${PLC_IP} 502
    EOF
    chmod +x "$LAB_ROOT/scripts/check_modbus.sh"

    cat > "$LAB_ROOT/scripts/test_modbus.py" <<EOF
    #!/usr/bin/env python3
    from pymodbus.client import ModbusTcpClient
    PLC_IP = "${PLC_IP}"
    client = ModbusTcpClient(PLC_IP, port=502)
    print(f"[*] Connecting to {PLC_IP}:502")
    if client.connect():
        print("[+] Connected")
        result = client.read_holding_registers(0, 10, slave=1)
        print(result)
        client.close()
    else:
        print("[-] Failed to connect")
    EOF
    chmod +x "$LAB_ROOT/scripts/test_modbus.py"

    cat > "$LAB_ROOT/scripts/write_modbus.py" <<EOF
    #!/usr/bin/env python3
    from pymodbus.client import ModbusTcpClient
    PLC_IP = "${PLC_IP}"
    client = ModbusTcpClient(PLC_IP, port=502)
    print(f"[*] Connecting to {PLC_IP}:502")
    if client.connect():
        print("[+] Connected")
        rr = client.write_register(0, 123, slave=1)
        print(rr)
        client.close()
    else:
        print("[-] Failed to connect")
    EOF
    chmod +x "$LAB_ROOT/scripts/write_modbus.py"

    cat > "$LAB_ROOT/scripts/lab_status.sh" <<EOF
    #!/usr/bin/env bash
    set -euo pipefail
    ip a
    ip route
    nmcli dev status || true
    ping -c 1 -W 2 1.1.1.1 || true
    ping -c 1 -W 2 google.com || true
    EOF
    chmod +x "$LAB_ROOT/scripts/lab_status.sh"

    log "Criando atalhos globais"
    ln -sf "$LAB_ROOT/scripts/discover_lab.sh" /usr/local/bin/scanlab
    ln -sf "$LAB_ROOT/scripts/test_modbus.py" /usr/local/bin/modtest
    ln -sf "$LAB_ROOT/scripts/write_modbus.py" /usr/local/bin/modwrite
    ln -sf "$LAB_ROOT/scripts/capture_modbus.sh" /usr/local/bin/capmod
    ln -sf "$LAB_ROOT/scripts/check_ports.sh" /usr/local/bin/checkplc
    ln -sf "$LAB_ROOT/scripts/check_modbus.sh" /usr/local/bin/checkmodbus
    ln -sf "$LAB_ROOT/scripts/lab_status.sh" /usr/local/bin/labstatus
    chmod +x /usr/local/bin/scanlab /usr/local/bin/modtest /usr/local/bin/modwrite /usr/local/bin/capmod /usr/local/bin/checkplc /usr/local/bin/checkmodbus /usr/local/bin/labstatus

    log "Configurando .bashrc"
    BASHRC="/home/${LAB_USER}/.bashrc"
    touch "$BASHRC"
    chown "$LAB_USER:$LAB_USER" "$BASHRC"
    if ! grep -q "SCADA LAB ALIASES" "$BASHRC"; then
    cat >> "$BASHRC" <<'EOF'

    # =============================================================
    # SCADA LAB ALIASES
    # =============================================================
    alias ll='ls -lah'
    alias scanlab='scanlab'
    alias modtest='modtest'
    alias modwrite='modwrite'
    alias capmod='capmod'
    alias checkplc='checkplc'
    alias checkmodbus='checkmodbus'
    alias labstatus='labstatus'
    alias labroot='cd /opt/scada-lab'
    EOF
    fi
    chown "$LAB_USER:$LAB_USER" "$BASHRC"

    log "Configurando MOTD"
    cat > /etc/motd <<EOF

    ===============================================================
     KALI ADMIN - SCADA/ICS SECURITY LAB
     Domínio: ${HOSTNAME_FULL}
     Rede de gestão: ${MGMT_IF}
     Rede OT: ${LAB_IF} -> ${LAB_IP_CIDR}
    ===============================================================

    Ambiente acadêmico para estudos de:
    - SCADA
    - ICS
    - Modbus TCP
    - Threat Intelligence
    - Monitoramento OT
    - Cibersegurança Industrial

    ===============================================================

    EOF

    log "Limpando"
    apt-get autoremove -y
    apt-get clean

    log "Resumo final"
    echo "Hostname.............: ${HOSTNAME_FULL}"
    echo "Usuário..............: ${LAB_USER}"
    echo "Interface gerência...: ${MGMT_IF}"
    echo "Interface OT.........: ${LAB_IF}"
    echo "IP OT................: ${LAB_IP_CIDR}"
    echo "Lab root.............: ${LAB_ROOT}"
    echo
    echo "Agora:"
    echo "1. Reinicie a VM"
    echo "2. Valide: ping 1.1.1.1"
    echo "3. Valide: ping google.com"
    echo "4. Valide: ip a"
    echo "5. Crie snapshot: kali-ready"

================================================================================
16) COMO USAR O SCRIPT ÚNICO
================================================================================

1. Salve o conteúdo acima como:
   install_kali_scada_lab_setup_rede_corrigida.sh

2. Dê permissão:
   chmod +x install_kali_scada_lab_setup_rede_corrigida.sh

3. Execute:
   sudo ./install_kali_scada_lab_setup_rede_corrigida.sh

4. Após terminar:
- reinicie a VM
- valide a internet
- valide a OT
- valide os scripts
- crie o snapshot kali-ready

================================================================================
17) O QUE VALIDAR DEPOIS DA EXECUÇÃO
================================================================================

VERIFICAÇÕES OBRIGATÓRIAS
- ip a
- ip route
- nmcli dev status
- ping 1.1.1.1
- ping google.com
- ping 192.168.100.10
- hostnamectl
- systemctl status ssh

RESULTADO ESPERADO
- eth0 com conexão de gerenciamento e internet
- eth1 com 192.168.100.10/24
- sem gateway na eth1
- ferramentas instaladas
- scripts criados
- SSH ativo
- domínio .semi configurado
- ambiente pronto para criar a base Linux e as demais VMs

================================================================================
18) OBSERVAÇÃO FINAL SOBRE A REDE
================================================================================

O ajuste mais importante para não voltar ao problema antigo é este:

- NÃO usar 192.168.50.1 como gateway da OT
- NÃO colocar a rede OT na eth0
- NÃO fazer resolv.conf manual persistente
- NÃO tentar bridge para a OT
- NÃO usar modbus-pal, porque o pacote não existe nos repositórios padrões
- NÃO misturar DHCP da internet com o IP estático da OT

A regra definitiva é:
- eth0 = gerenciamento / internet
- eth1 = OT / lab_net / 192.168.100.10/24

================================================================================
19) RESULTADO FINAL ESPERADO
================================================================================

Ao terminar, a Kali deve estar:
- estável
- organizada
- com internet pela interface certa
- com rede OT pela interface certa
- com hostname correto
- com ferramentas OT/SCADA instaladas
- com scripts de descoberta, captura e teste
- pronta para snapshot
- pronta para servir como estação principal do laboratório

================================================================================
FIM
================================================================================
