# LABORATÓRIO SCADA / ICS VIRTUALIZADO — CYBER RANGE OT/SCADA
## Catálogo Completo de Vulnerabilidades, Falhas Estruturais e Problemas de Engenharia
### Análise de Risco Aplicada ao Protocolo Modbus TCP e Arquiteturas de Automação Industrial

> Este documento consolida a análise de todas as vulnerabilidades, gargalos de engenharia e falhas sistêmicas identificadas durante o desenvolvimento, comissionamento e testes de intrusão do laboratório. O foco é tanto operacional — identificar pontos de fragilidade, dependências e causas comuns de falha no ambiente — quanto técnico-analítico, dialogando com o framework **MITRE ATT&CK for ICS** e com as normativas da **ISA/IEC 62443**.
>
> Em um laboratório OT/ICS, uma vulnerabilidade pode ser qualquer condição que facilite perda de disponibilidade, reduza a fidelidade do experimento, permita manipulação indevida de sinais, atrapalhe a coleta de evidências, gere comportamento não determinístico ou aumente o risco de quebrar o ambiente durante testes.

---

# PARTE I — VULNERABILIDADES DE REDE E PROTOCOLO (Camadas OSI 3, 4 e 7)

A transição histórica das redes de automação baseadas em enlaces seriais blindados (RS-232, RS-485) para a arquitetura TCP/IP trouxe conectividade corporativa, mas carregou consigo protocolos projetados em uma era onde ameaças cibernéticas não existiam.

---

## 1.1 Ausência absoluta de autenticação no Modbus TCP

### Descrição
A vulnerabilidade mais fundacional do ecossistema é a total falta de mecanismos de autenticação no Modbus TCP. O protocolo utiliza a porta 502 e encapsula a PDU dentro de um cabeçalho MBAP (*Modbus Application Protocol*), que contém apenas identificadores de transação, protocolo, comprimento e Unit ID — sem campos para tokens, hashes criptográficos (HMAC), certificados digitais ou senhas.

Do ponto de vista do CLP (OpenPLC), qualquer interface que consiga concluir o *Three-Way Handshake* TCP (SYN → SYN-ACK → ACK) é imediatamente tratada como um "Operador Master" legítimo.

### Impacto
- leitura passiva não autorizada de registradores;
- escrita direta em registradores sem resistência algorítmica;
- manipulação de processo (injeção de valores falsos);
- replay de comandos gravados anteriormente;
- engenharia social baseada na observação de padrões de tráfego.

### Exploração no laboratório
Qualquer máquina da rede OT (ex: Kali em `192.168.100.10`) pode enviar Function Codes como `06 Write Single Register` ou `16 Write Multiple Registers` diretamente à memória do CLP:

```python
from pymodbus.client import ModbusTcpClient
cliente_ataque = ModbusTcpClient('192.168.100.20')
cliente_ataque.write_registers(0, [2600, 3800])
```

### Mitigação recomendada (ISA 62443)
- implementar *Modbus TCP Security* com envelopamento em túnel TLS 1.2/1.3 e autenticação mútua (mTLS) via certificados X.509;
- instalar *Firewalls DPI (Deep Packet Inspection)* que aceitem pacotes Modbus apenas de endereços MAC estritamente listados;
- usar a exposição de portas somente dentro da rede interna `lab_net`;
- documentar quais portas estão abertas e não publicar serviços OT fora do laboratório.

---

## 1.2 Suscetibilidade a SYN Flood (Negação de Serviço)

### Descrição
A pilha de rede de dispositivos OT é frequentemente rudimentar e subdimensionada — focada no processamento lógico de malhas em hard real-time, não em resiliência de rede. O ataque TCP SYN Flood explora o comportamento padrão do kernel: o atacante dispara pacotes com a flag `SYN` ativada sem enviar o `ACK` final, forçando o kernel do CLP a alocar espaço em memória para cada *Half-Open Connection*, até esgotar a *Backlog Queue*.

### Impacto
- o CLP (`.20`) esgota seus sockets em 5 a 12 segundos sob ataque de `hping3 --flood`;
- a HMI (`.30`) e o Sensor (`.40`) perdem acesso aos registradores Modbus;
- a planta entra em modo de operação "cega": o operador perde visibilidade e controle remoto;
- o firmware OpenPLC mantém intertravamentos (safe state) internamente, mas sem telemetria visível.

### Mitigação recomendada
- aplicar *Rate Limiting* via `iptables`, `nftables` ou UFW;
- habilitar *SYN Cookies* no kernel: `net.ipv4.tcp_syncookies = 1`;
- instalar firewalls perimetrais industriais para absorver a enxurrada antes de atingir o CLP.

---

## 1.3 Exposição de topologia por enumeração ativa (Reconhecimento)

### Descrição
O Modbus foi projetado para ser de fácil diagnóstico. Códigos de função como FC 43 (Read Device Identification) e FC 17 (Report Slave ID) permitem interrogar o dispositivo escravo para obter informações de fabricação e arquitetura sem que sistemas tradicionais de segurança alertem.

### Impacto
- extração de nome do fabricante, versão de firmware, mapas de registradores e Unit IDs ativos;
- base para criação de ataques direcionados (semelhante ao Stuxnet, que confirmava a topografia do hardware antes de agir);
- visibilidade total da superfície de ataque por qualquer host na rede OT.

### Exploração no laboratório
```bash
nmap -sV -p 502 --script modbus-discover 192.168.100.20
```

### Mitigação
- bloquear Function Codes diagnósticos em firewalls DPI;
- documentar a limitação nos relatórios do laboratório.

---

## 1.4 Interceptação de dados em trânsito (Man-in-the-Middle)

### Descrição
Protocolos ICS clássicos trafegam em texto claro (*cleartext*). Toda a telemetria, estados de válvulas e limiares de pressão circulam na rede sem ofuscação. Um atacante com acesso à rede pode realizar envenenamento de tabela ARP (*ARP Spoofing*) para redirecionar o tráfego do CLP para a máquina atacante antes que chegue ao SCADA.

### Impacto
- monitoramento silencioso do funcionamento da planta (aprendizado de setpoints normais);
- modificação ativa de pacotes em trânsito: o atacante reporta temperatura normal ao operador enquanto a planta opera em condição crítica;
- captura passiva de PCAP suficiente para reconstituir toda a lógica do processo.

### Mitigação
- adotar *Modbus Security* (TLS);
- implementar *Dynamic ARP Inspection* (DAI) nos switches;
- segmentar por VLANs e zonas físicas isoladas.

---

## 1.5 Rede OT plana sem segmentação adicional

### Descrição
A `lab_net` foi montada como uma rede interna única. PLC, HMI, Sensor e banco de dados ficam no mesmo domínio de broadcast e podem alcançar uns aos outros sem barreiras intermediárias.

### Impacto
- maior superfície de movimento lateral;
- qualquer host comprometido pode tentar alcançar os demais;
- menor fidelidade em relação a ambientes industriais reais com segmentação por zonas e conduítes (ISA 62443).

### Mitigação
- usar a rede plana apenas como base didática;
- adicionar regras de firewall para simular isolamento adicional;
- documentar essa limitação no relatório do laboratório.

---

## 1.6 Roteamento estocástico por DHCP e sequestro de tráfego do host

### Descrição
Processos daemon como `dhclient` e `systemd-networkd` buscam ativamente renegociar alocações de IP e puxar rotas padrão da rede corporativa ou da placa NAT simulada pelo VirtualBox. Isso pode fazer com que o kernel despache tráfego industrial de telemetria pelo gateway da internet (`10.0.2.2`), criando instabilidade no socket e, pior, espalhando tráfego de ataque (Spoofing) para a rede da instituição.

### Sinais típicos
- `network unreachable` / `invalid gateway`;
- IP OT aparecendo na interface errada;
- `default route` ausente;
- `ping` externo não responde;
- interface correta não recebe DHCP.

### Resolução adotada
Arquitetura *Dual-Homed* com chaves proibitivas no Netplan da interface OT:
- `ipv4.never-default: true`
- `ipv4.ignore-auto-dns: true`

Isso amputa a via da rede OT para a rede IT, retendo o barramento do protocolo em um conduíte cego.

### Mitigação operacional
- nunca modificar a interface de gerenciamento agressivamente;
- aplicar configuração apenas à interface OT;
- validar com `ip a` e `ip route` antes de qualquer instalação;
- evitar scripts que "limpam" todas as conexões de rede.

---

## 1.7 Dependência de NAT temporário no bootstrap

### Descrição
A maioria das VMs OT depende de uma janela temporária de NAT para instalar dependências. Se o NAT falhar, a VM fica sem pacote, sem atualização e sem runtime instalado.

### Impacto
- impossibilidade de instalar OpenPLC, PostgreSQL ou dependências Python;
- scripts terminam com aviso de ausência de internet;
- necessidade de reiniciar a máquina para recuperar rede.

### Mitigação
- validar internet antes de iniciar o script;
- separar claramente fase de bootstrap e fase de isolamento OT;
- usar snapshots após a fase de instalação com internet;
- remover NAT apenas depois que tudo estiver instalado e funcionando.

---

# PARTE II — VULNERABILIDADES DE AUTENTICAÇÃO E CREDENCIAIS

---

## 2.1 Credenciais padrão iguais em várias VMs

### Descrição
O ambiente usa um padrão único de usuário e senha em várias máquinas para simplificar a automação.

### Impacto
- comprometimento de uma VM permite reutilizar credenciais nas demais;
- facilita movimentação lateral;
- reduz o valor da autenticação como barreira real.

### Mitigação
- para estudo, é aceitável manter credenciais uniformes;
- para testes mais realistas, variar senhas por papel (role);
- documentar a limitação;
- nunca expor essas credenciais fora do laboratório.

---

## 2.2 Autenticação SSH por senha

### Descrição
Em várias VMs o SSH foi habilitado com autenticação por senha, simplificando a administração mas ampliando o risco de brute force ou acesso indevido dentro da rede OT.

### Impacto
- login remoto facilitado;
- superfície de ataque maior;
- risco de exploração por credenciais fracas.

### Mitigação
- usar SSH apenas dentro do laboratório e somente quando necessário;
- considerar autenticação por chave SSH em versões mais maduras;
- registrar no relatório que o SSH foi habilitado por motivo operacional.

---

## 2.3 Usuário privilegiado uniforme (`labadmin`)

### Descrição
O usuário `labadmin` com privilégios administrativos aparece em praticamente todas as máquinas.

### Impacto
- comprometimento de uma VM pode expor várias;
- menor separação entre funções;
- aumenta o alcance de erro humano.

### Mitigação
- em ambiente didático, pode permanecer;
- em versões mais maduras, usar usuários distintos por papel;
- registrar o motivo da uniformidade na documentação.

---

# PARTE III — VULNERABILIDADES DE SOFTWARE E COMPILAÇÃO (Camada de Aplicação e IEC 61131-3)

O laboratório também sofre com a fragilidade interna dos softwares controladores e bibliotecas open-source adotadas na automação industrial.

---

## 3.1 Defeitos do compilador Matiec (o "inferno das variáveis")

### Descrição
O OpenPLC utiliza o motor de compilação *Matiec* para traduzir código *Structured Text* (IEC 61131-3) para C/C++. O parser da árvore de sintaxe do Matiec possui um defeito estrutural no processamento do bloco declarativo global `VAR ... END_VAR`.

### Manifestação crítica
Se o programador combinar no mesmo bloco:
- mapeamento direto de memória física (ex: `sensor_temp AT %IW0 : INT;`), com
- instanciação de blocos funcionais com parâmetros (ex: `timer_delay : TON(IN := TRUE, PT := T#3s);`), ou
- inicialização de valores padrão com `:=`,

...o compilador entra em colapso, descartando toda a tabela de símbolos de memória. O terminal do OpenPLC exibe dezenas de erros em cascata (`invalid located variable declaration`, `invalid variable before ':=' in ST assignment statement`), impossibilitando a gravação do firmware.

### Resolução adotada
Abandono do mapeamento purista da norma: todo o endereçamento locacional (`AT %IW / %MW`) foi banido do código fonte e terceirizado para a camada de Interface Web (HAL Binding). Variáveis lógicas passaram a receber inicialização via bloco assíncrono procedural:

```pascal
IF NOT init_done THEN
    (* inicializações aqui *)
    init_done := TRUE;
END_IF;
```

Isso força um *First-Scan Boot* limpo sem quebrar a compilação em C++.

---

## 3.2 Volatilidade da biblioteca Pymodbus (risco de supply chain)

### Descrição
As estações HMI/SCADA e o simulador de sensor dependem do pacote Python `pymodbus`. A transição do Ubuntu 20.04 para o Ubuntu 22.04 forçou a atualização para a v3.x do Pymodbus, que trouxe *Breaking Changes* não documentados adequadamente.

### Manifestação crítica
O argumento nomeado `unit` foi expurgado da API e substituído por `slave`. O formato anteriormente válido:

```python
client.write_registers(address=0, values=[v1, v2], unit=1)
```

...passa a gerar `TypeError: Unexpected Keyword Argument`, abortando o polling do SCADA ou a geração de dados do Sensor no boot.

### Resolução adotada
Refatoração para uso exclusivo de **parâmetros posicionais**:

```python
client.write_registers(0, [v1, v2])
```

Isso remove a dependência de palavras-chave da API e blinda o software de supervisão contra atualizações caprichosas da biblioteca, evidenciando os riscos de supply chain de software livre em redes de missão crítica.

---

## 3.3 Risco de loops infinitos no Scan Cycle e falso Fail-Safe

### Descrição
Equipamentos industriais operam em ciclos contínuos de escaneamento (Scan Cycle). Se o programa ST contiver laços (`WHILE ... DO` ou `REPEAT ... UNTIL`) cujo critério de saída dependa de uma leitura Modbus que foi derrubada por ataque, o *Watchdog Timer* do hardware pode estourar, travando o sistema em estado zumbi (Halted).

### Impacto
- variáveis oriundas de barramentos virtuais congelam;
- se o interlock depender de comunicação cruzada, o CLP pode não acionar a válvula de alívio em emergência.

### Resolução adotada no projeto
A máquina de estados FSM do OpenPLC foi configurada com *default fallback*, permitindo leitura da memória interna do sensor emulada localmente no colapso de rede — sem dependência de handshakes para manter válvulas em posição de alívio emergencial.

---

# PARTE IV — FALHAS DE INFRAESTRUTURA E HIPERVISOR

---

## 4.1 Vetores de fuga do hipervisor (VM Escape)

### Descrição
O uso do VirtualBox expõe o host a riscos mecânicos da virtualização pelas funcionalidades das Guest Additions: *Shared Clipboard*, *Drag and Drop* e, principalmente, os *Shared Folders*.

### Impacto
Uma carga destrutiva APT acionada durante testes de Red Teaming que contenha código voltado para o mapeamento do disco local (`/media/sf_shared`) pode migrar da simulação contida no Linux para infectar o ambiente Windows/Mac que hospeda o laboratório (*Sandbox Breach*).

### Resolução adotada
Abstenção compulsória dessas facilidades. Todo o código foi importado via SSH na rede NAT, ou compilado internamente via repositório Git. O script `scada_lab_master_setup.sh` proíbe dependências mecânicas dos drives do VirtualBox.

---

## 4.2 Configurações permissivas do PostgreSQL e UFW

### Descrição
O PostgreSQL é "Secure by Default": seu listener TCP vem ancorado exclusivamente na interface loopback (`127.0.0.1`), ignorando requisições externas. Paralelamente, o UFW aplica *Default Deny* a tudo. Se não tratados, o SCADA exibe `Connection Refused` permanente ao tentar logar dados.

### Resolução automatizada pelo script IaC
- `sed` substitui `#listen_addresses = 'localhost'` por `listen_addresses = '*'` no arquivo `postgresql.conf`;
- UFW é perfurado seletivamente na porta `5432/TCP`;
- `pg_hba.conf` recebe: `host all all 192.168.100.0/24 scram-sha-256`, liberando apenas o perímetro do laboratório OT para conexões transacionais criptografadas.

---

# PARTE V — VULNERABILIDADES DE SCRIPTS E AUTOMAÇÃO

---

## 5.1 Scripts agressivos com a configuração de rede

### Descrição
Scripts que tentam "resolver tudo" de uma vez — limpar conexões, recriar interfaces, ajustar hostname, modificar rotas, instalar pacotes e configurar serviços simultaneamente — geram efeitos colaterais graves.

### Impacto
- quebra do NAT;
- perda de internet no meio de uma instalação;
- erros de roteamento;
- instabilidade no boot;
- necessidade de intervenção manual para recuperar o ambiente.

### Mitigação
- scripts conservadores que alteram somente o necessário;
- separar instalação de rede de instalação de pacotes;
- não apagar configurações que funcionam;
- tratar apenas a interface OT quando o objetivo for OT.

---

## 5.2 Dependência de ferramentas ausentes

### Descrição
Comandos ou pacotes nem sempre disponíveis no Ubuntu Server (ex: `dhclient`, `modbus-pal`) geram falhas silenciosas durante a execução de scripts.

### Impacto
- script para no meio da execução;
- usuário interpreta como VM quebrada;
- tempo perdido em diagnóstico desnecessário.

### Mitigação
- checar disponibilidade do comando antes de usá-lo (`command -v`);
- usar alternativas mais universais (`ip`, `ss` em vez de `ifconfig`, `netstat`);
- marcar pacotes opcionais como tal na documentação.

---

## 5.3 Erros por formato CRLF em scripts Windows

### Descrição
Scripts editados no Windows e salvos com terminação de linha `CRLF` (em vez de `LF`) quebram a execução no Linux de formas difíceis de diagnosticar.

### Impacto
- erros estranhos como `command not found`;
- Bash interpretando o caractere `\r` como parte do nome do comando;
- perda de confiança no script durante demonstrações.

### Mitigação
```bash
# Converter na VM antes de executar:
sed -i 's/\r$//' script.sh
# ou:
dos2unix script.sh
```

Sempre salvar scripts com terminação `LF` antes de transferir para as VMs.

---

# PARTE VI — VULNERABILIDADES DE MONITORAMENTO E OBSERVABILIDADE

---

## 6.1 Falta de sincronismo de tempo entre VMs

### Descrição
Se as VMs não estiverem com o relógio sincronizado, os logs perdem correlação temporal.

### Impacto
- dificuldade de reconstruir a linha do tempo de um ataque;
- dispersão entre eventos da HMI, do PLC e do DB;
- análise forense mais difícil e menos confiável.

### Mitigação
- usar NTP/chrony em versões futuras;
- padronizar o fuso horário em todas as VMs;
- documentar se não houver sincronização, especialmente ao exportar evidências.

---

## 6.2 Logs distribuídos sem centralização

### Descrição
Os logs estão distribuídos entre máquinas. Se uma VM falhar ou for reiniciada, parte das evidências pode desaparecer.

### Impacto
- dificuldade de auditoria após incidentes;
- perda de rastros de ataque;
- dificuldade de comparar eventos entre diferentes nós.

### Mitigação
- exportar logs para o DB (`historico_sensores`);
- manter capturas PCAP na shared folder ou exportar por SFTP;
- registrar prints e timestamps antes de cada teste;
- usar snapshots como marcos de evidência.

---

## 6.3 Observabilidade limitada quando o processo é estático

### Descrição
Se o PLC não tiver lógica mínima, se a HMI não tiver painéis configurados e se o sensor não gerar variação, o laboratório fica muito estático — ataques parecem não produzir efeito visível.

### Impacto
- testes ficam menos didáticos;
- o valor das capturas PCAP reduz;
- dificuldade de demonstrar o impacto de um ataque.

### Mitigação
- manter ao menos um registrador e uma coil ativa no PLC;
- garantir que o sensor gere variação contínua;
- ter a HMI consumindo e exibindo dados em tempo real;
- gravar e comparar estados antes e depois de cada teste.

---

# PARTE VII — PROBLEMAS OPERACIONAIS RECORRENTES

---

## 7.1 Nomes de interface diferentes entre máquinas

### Descrição
A Kali usa `eth0` / `eth1`, enquanto outras VMs Ubuntu usam `enp0s3` / `enp0s8`.

### Impacto
- confusão em scripts;
- `tcpdump` capturando na interface errada;
- configuração de rede aplicada ao adaptador incorreto.

### Mitigação
- sempre validar com `ip a` antes de configurar ou capturar;
- nunca assumir nomes fixos;
- usar variáveis de ambiente nos scripts para armazenar o nome da interface.

---

## 7.2 Serviços que não sobem automaticamente

### Descrição
Em alguns momentos OpenPLC, Tomcat ou PostgreSQL não inicializaram automaticamente após boot ou após a execução do script.

### Impacto
- porta 502 fechada mesmo com PLC "ligada";
- porta 5432 fechada, bloqueando o SCADA;
- HMI indisponível;
- sensação de falha total quando a causa é apenas um serviço parado.

### Diagnóstico
```bash
systemctl status openplc
ss -tulpn | grep 502
journalctl -u openplc --no-pager -n 50
```

### Mitigação
- separar claramente falha de serviço de falha de rede;
- habilitar serviços no `systemctl enable` durante o setup;
- validar portas antes de declarar o ambiente como operacional.

---

## 7.3 Ambiente sensível ao estado corrente

### Descrição
Pequenas alterações — editar `.bashrc`, trocar nomes de interface, rodar um script fora de ordem — podem mudar significativamente o estado de uma VM e dificultar a reprodução de testes.

### Mitigação
- criar snapshots frequentes com nomes descritivos;
- fazer mudanças por etapas, não tudo de uma vez;
- documentar o estado exato de cada VM antes de iniciar um cenário;
- evitar refatorar múltiplas VMs simultaneamente.

---

# PARTE VIII — MAPA DE CRITICIDADE

## Alta criticidade
| Problema | Efeito imediato |
|---|---|
| NAT quebra durante bootstrap | Instalação para, VM inutilizável |
| Interface OT na placa errada | Tráfego OT vaza para rede externa |
| OpenPLC sem porta 502 | PLC inoperante, todos os cenários falham |
| Perda de gateway | Internet cai, instalações incompletas |
| Scripts em CRLF | Erros silenciosos no Linux |
| Template corrompida | Todos os linked clones comprometidos |

## Média criticidade
| Problema | Efeito |
|---|---|
| Logs sem sincronismo de tempo | Análise forense imprecisa |
| Serviços parados após boot | Ambiente parcialmente inoperante |
| Shared folder com alias errado | Troca de arquivos interrompida |
| Snapshots em excesso | Consumo de disco / confusão de estado |
| Permissões de pasta incorretas | Acesso bloqueado a scripts ou dados |

## Baixa criticidade
| Problema | Efeito |
|---|---|
| Troca de nomes de interface | Confusão pontual resolvida com `ip a` |
| Pacotes opcionais não encontrados | Funcionalidade reduzida, não crítica |
| Mensagens de shell inesperadas | Ruído visual sem impacto funcional |
| Pequenos ajustes de alias | Conveniência operacional apenas |

---

# PARTE IX — CONCLUSÃO E RESUMO DAS FRAGILIDADES CENTRAIS

As vulnerabilidades deste laboratório são, em grande parte, as vulnerabilidades naturais e esperadas de qualquer ambiente didático OT/ICS:

- **Protocolos inseguros por design** — Modbus TCP não tem autenticação, criptografia ou integridade de mensagem;
- **Rede plana** — a `lab_net` sem segmentação expõe todos os nós entre si;
- **Autenticação simples** — credenciais uniformes e SSH por senha facilitam a administração e também a movimentação lateral;
- **Serviços expostos** — portas 502, 5432 e 8080 abertas sem barreiras internas;
- **Bootstrap frágil** — forte dependência de ordenação correta e de janela NAT temporária;
- **Fragilidades de compilador** — bugs do Matiec exigem workarounds no código ST;
- **Supply chain de bibliotecas** — Breaking Changes do Pymodbus geram falhas inesperadas;
- **CRLF em scripts** — erros silenciosos quando editados no Windows;
- **Risco de VM Escape** — shared folders e clipboard podem romper o isolamento do laboratório.

Ao mesmo tempo, o laboratório tem uma boa base de estudo porque:

- está segmentado em rede dual-homed;
- usa linked clones sobre uma template limpa;
- tem snapshots como marcos de estado;
- está documentado e automatizado via IaC;
- permite testes controlados e reproduzíveis;
- tem observabilidade suficiente (HMI com IDS heurístico, DB forense, PCAP) para cenários acadêmicos.

O principal aprendizado é que, em OT virtualizada, **a estabilidade da arquitetura importa tanto quanto a segurança**: o laboratório precisa ser funcional antes de ser "duro", reproduzível antes de ser sofisticado, e bem documentado antes de ser atacado.

---

## Uso recomendado deste documento

Esta análise deve ser usada como base para:

- **documentação** do ambiente e de suas limitações intencionais;
- **relatório técnico** de TCC ou publicação acadêmica;
- **definição de hipóteses** de teste e cenários de ataque controlado;
- **criação de roteiros** de Red Teaming e Blue Teaming;
- **priorização de hardening** em versões futuras do laboratório;
- **comparação** entre o comportamento esperado e o comportamento observado sob ataque.

---

*Este laboratório é excelente para ensino, demonstrações, validação de conceitos OT, coleta de PCAP, estudo de disponibilidade, observação de manipulação de registradores e comparação entre baseline saudável e cenário comprometido.*
