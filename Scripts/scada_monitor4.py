#!/usr/bin/env python3
import time
import os
import random
from datetime import datetime
import psycopg2

# Configurações do Banco de Dados Historian
DB_HOST = '192.168.100.50'

# Cores ANSI para o Painel Industrial
GREEN  = '\033[92m'
RED    = '\033[91m'
YELLOW = '\033[93m'
CYAN   = '\033[96m'
MAGENTA= '\033[95m'
RESET  = '\033[0m'
BOLD   = '\033[1m'

# Variáveis do Processo
total_leituras = 0
total_alarmes = 0
temperaturas_registradas = []
ultima_temp = None
alertas_ids = 0

def salvar_no_banco(mensagem, valor):
    """Tenta gravar no Postgres. Se falhar, o SCADA continua rodando"""
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
    
    # Detecção de Anomalia (IDS)
    suspeito = False
    if ultima_temp is not None and abs(temp - ultima_temp) > 15:
        alertas_ids += 1
        suspeito = True
            
    if temp > 80 or pressao > 150:
        total_alarmes += 1
        
    ultima_temp = temp
    return suspeito

def run_hmi():
    global total_leituras, total_alarmes, alertas_ids
    
    # Valores iniciais de simulação estável
    base_temp = 65
    base_pressao = 120

    try:
        while True:
            os.system('clear')
            agora = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            
            print(f"{CYAN}{BOLD}========================================================================{RESET}")
            print(f"{CYAN}{BOLD}               CENTRO DE SUPERVISÃO E HISTORIAN SCADA - V3.8             {RESET}")
            print(f"{CYAN}{BOLD}========================================================================{RESET}")
            print(f" Timestamp: {agora}  |  Modo: SIMULAÇÃO LOCAL INTEGRADA  |  DB: {DB_HOST}")
            print(f"{CYAN}------------------------------------------------------------------------{RESET}")

            # GERAÇÃO DE FLUTUAÇÃO INDUSTRIAL REALISTA
            # 5% de chance de simular um pico espúrio ou injeção de ataque
            if random.random() < 0.05:
                temp = random.randint(85, 99)       # Pico crítico / Ataque
                pressao = random.randint(155, 180)
            else:
                temp = int(base_temp + random.uniform(-2, 2))  # Flutuação normal
                pressao = int(base_pressao + random.uniform(-4, 4))

            # Processamento das Métricas
            ataque_detectado = calcular_metricas(temp, pressao)
            media_temp = sum(temperaturas_registradas) / len(temperaturas_registradas)
            
            # Envio para o Banco de Dados Historian
            tipo_log = "ALARME_CRITICO" if (temp > 80 or pressao > 150) else "SINAL_NORMAL"
            db_salvo = salvar_no_banco(tipo_log, temp)
            status_db = f"{GREEN}GRAVANDO OK{RESET}" if db_salvo else f"{RED}FALHA DB (OFFLINE?){RESET}"

            # --- EXIBIÇÃO DE TELEMETRIA EM TEMPO REAL ---
            print(f"\n {BOLD}ESTADO DA PLANTA INDUSTRIAL:{RESET}")
            if temp > 80 or pressao > 150:
                print(f" Status GERAL:  [{RED}{BOLD} ALARME CRÍTICO ÓLEO/PRESSÃO {RESET}]")
            else:
                print(f" Status GERAL:  [{GREEN} OPERAÇÃO NORMAL {RESET}]")
                
            print(f" Temperatura:   {BOLD}{temp}°C{RESET} (Média Global: {media_temp:.1f}°C)")
            print(f" Pressão:       {BOLD}{pressao} PSI{RESET}")
            
            if ataque_detectado:
                print(f"\n {RED}{BOLD}⚠️ IDS ALERT: Mudança térmica abrupta! Possível injeção de dados!{RESET}")

            # --- TABELA DE MÉTRICAS DO SISTEMA ---
            print(f"\n{CYAN}------------------------------------------------------------------------{RESET}")
            print(f" {BOLD}MÉTRICAS DO HISTORIAN & AUDITORIA:{RESET}")
            print(f" Leituras Totais: {total_leituras}   |  Alarmes Disparados: {total_alarmes}")
            print(f" Status Historian: {status_db}   |  Alertas de Anomalia (IDS): {alertas_ids}")
            print(f"{CYAN}------------------------------------------------------------------------{RESET}")
            print(" Pressione Ctrl+C para encerrar o monitor.")
            
            time.sleep(2)

    except KeyboardInterrupt:
        print(f"\n{MAGENTA}[*] Sessão finalizada pelo operador de forma segura.{RESET}")

if __name__ == "__main__":
    run_hmi()