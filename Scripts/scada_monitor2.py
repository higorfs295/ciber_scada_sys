cat << 'EOF' > scada_v3.py
#!/usr/bin/env python3
import time
import os
from datetime import datetime
import psycopg2
from pymodbus.client import ModbusTcpClient

# Configurações de Rede
PLC_IP = '192.168.100.20'
PORT = 502
DB_HOST = '192.168.100.50'

# Paleta de Cores ANSI
GREEN  = '\033[92m'
RED    = '\033[91m'
YELLOW = '\033[93m'
CYAN   = '\033[96m'
MAGENTA= '\033[95m'
RESET  = '\033[0m'
BOLD   = '\033[1m'

# Variáveis Globais de Estatística (Métricas do Processo)
total_leituras = 0
total_alarmes = 0
temperaturas_registradas = []
pressões_registradas = []
ultima_temp = None
alertas_ids = 0

def salvar_no_banco(mensagem, valor):
    """Tenta gravar no Postgres com tratamento de erro robusto"""
    conn = None
    try:
        conn = psycopg2.connect(
            dbname="scada_db", 
            user="postgres", 
            host=DB_HOST, 
            port="5432",
            connect_timeout=2
        )
        cur = conn.cursor()
        cur.execute("INSERT INTO historico_sensores (sensor, valor) VALUES (%s, %s)", (mensagem, int(valor)))
        conn.commit()
        cur.close()
        return True
    except:
        return False
    finally:
        if conn:
            conn.close()

def calcular_metricas(temp, pressao):
    global total_leituras, total_alarmes, ultima_temp, alertas_ids
    total_leituras += 1
    temperaturas_registradas.append(temp)
    pressões_registradas.append(pressao)
    
    # Detecção de Ataque de Injeção Direta (Salto Térmico Irreal)
    suspeito = False
    if ultima_temp is not None:
        if abs(temp - ultima_temp) > 15: # Se a temp pular mais de 15C em 2 segundos
            alertas_ids += 1
            suspeito = True
            
    if temp > 80 or pressao > 150:
        total_alarmes += 1
        
    ultima_temp = temp
    return suspeito

def desenhar_dashboard():
    client = ModbusTcpClient(host=PLC_IP, port=PORT)
    
    try:
        while True:
            os.system('clear')
            agora = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            
            print(f"{CYAN}{BOLD}========================================================================{RESET}")
            print(f"{CYAN}{BOLD}               CENTRO DE SUPERVISÃO E HISTORIAN SCADA - V3.0             {RESET}")
            print(f"{CYAN}{BOLD}========================================================================{RESET}")
            print(f" Timestamp: {agora}  |  PLC: {PLC_IP}:{PORT}  |  DB: {DB_HOST}")
            print(f"{CYAN}------------------------------------------------------------------------{RESET}")

            # Verifica conexão de rede com o PLC
            if not client.is_socket_open():
                client.connect()

            if client.is_socket_open():
                # Leitura estrita com argumentos nomeados (pymodbus 3.x)
                result = client.read_holding_registers(address=0, count=2, slave=1)
                
                if not result.isError():
                    temp = result.registers[0]
                    pressao = result.registers[1]
                    
                    # Processa regras de negócio e segurança
                    ataque_detectado = calcular_metricas(temp, pressao)
                    
                    # Cálculo de Médias
                    media_temp = sum(temperaturas_registradas) / len(temperaturas_registradas)
                    max_temp = max(temperaturas_registradas)
                    
                    # Gravação no Banco de Dados Historian
                    tipo_log = "ALARME_CRITICO" if (temp > 80 or pressao > 150) else "SINAL_NORMAL"
                    db_salvo = salvar_no_banco(tipo_log, temp)
                    status_db = f"{GREEN}GRAVANDO OK{RESET}" if db_salvo else f"{RED}FALHA (OFFLINE?){RESET}"

                    # --- EXIBIÇÃO DE TELEMETRIA EM TEMPO REAL ---
                    print(f"\n {BOLD}ESTADO DA PLANTA INDUSTRIAL:{RESET}")
                    if temp > 80 or pressao > 150:
                        print(f" Status GERAL:  [{RED}{BOLD} ALARME CRÍTICO ÓLEO/PRESSÃO {RESET}]")
                    else:
                        print(f" Status GERAL:  [{GREEN} OPERAÇÃO NORMAL {RESET}]")
                        
                    print(f" Temperatura:   {BOLD}{temp}°C{RESET} (Máx: {max_temp}°C | Média: {media_temp:.1f}°C)")
                    print(f" Pressão:       {BOLD}{pressao} PSI{RESET}")
                    
                    # Alerta do Módulo IDS de Cibersegurança
                    if ataque_detectado:
                        print(f"\n {RED}{BOLD}⚠️ IDS ALERT: Salto térmico abrupto detectado! Possível Injeção Modbus!{RESET}")

                    # --- TABELA DE MÉTRICAS DO SISTEMA ---
                    print(f"\n{CYAN}------------------------------------------------------------------------{RESET}")
                    print(f" {BOLD}MÉTRICAS DO HISTORIAN & AUDITORIA:{RESET}")
                    print(f" Leituras Totais: {total_leituras}   |  Alarmes Disparados: {total_alarmes}")
                    print(f" Status Historian: {status_db}   |  Alertas de Anomalia (IDS): {alertas_ids}")

                else:
                    print(f"\n{RED}[-] ERRO DE PROTOCOLO: Falha na decodificação de pacotes Modbus.{RESET}")
                    salvar_no_banco("ERRO_MODBUS_INTEGRIDADE", 0)
            else:
                print(f"\n{RED}{BOLD}[🚨] SINAL PERDIDO: Impossível conectar ao PLC (Dispositivo Offline ou Sob DoS){RESET}")
                salvar_no_banco("FALHA_CONEXAO_PLC", 0)
                
            print(f"{CYAN}------------------------------------------------------------------------{RESET}")
            print(" Pressione Ctrl+C para encerrar a monitorização do ecossistema OT.")
            time.sleep(2)

    except KeyboardInterrupt:
        print(f"\n{MAGENTA}[*] Sessão SCADA finalizada de forma limpa pelo operador.{RESET}")
    finally:
        client.close()

if __name__ == "__main__":
    desenhar_dashboard()
EOF