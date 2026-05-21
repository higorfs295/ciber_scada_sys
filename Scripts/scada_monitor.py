#!/usr/bin/env python3
import time
import os
import psycopg2
from pymodbus.client import ModbusTcpClient

PLC_IP = '192.168.100.20'
PORT = 502
DB_HOST = '192.168.100.50'

# Cores para o terminal
GREEN, RED, YELLOW, CYAN, RESET = '\033[92m', '\033[91m', '\033[93m', '\033[96m', '\033[0m'

def salvar_no_banco(mensagem, valor):
    try:
        conn = psycopg2.connect(dbname="scada_db", user="postgres", host=DB_HOST, port="5432")
        cur = conn.cursor()
        cur.execute("INSERT INTO historico_sensores (sensor, valor) VALUES (%s, %s)", (mensagem, valor))
        conn.commit()
        cur.close()
        conn.close()
        return True
    except:
        return False

def run_hmi():
    client = ModbusTcpClient(PLC_IP, port=PORT)
    try:
        while True:
            os.system('clear')
            print(f"{CYAN}=== PAINEL HMI SUPERVISÓRIO OT ==={RESET}")
            print(f"Alvo PLC: {PLC_IP}:{PORT} | Database: {DB_HOST}\n")

            if not client.is_socket_open():
                print(f"{YELLOW}[!] Tentando conectar ao PLC...{RESET}")
                client.connect()

            if client.is_socket_open():
                # AQUI ESTÁ A CORREÇÃO: Argumentos nomeados para o pymodbus 3.x
                result = client.read_holding_registers(address=0, count=2, slave=1)
                
                if not result.isError():
                    temp = result.registers[0]
                    pressao = result.registers[1]
                    status_msg = f"Temp: {temp}C | Pressao: {pressao}PSI"
                    
                    if temp > 80 or pressao > 150:
                        print(f"{RED}[!] ALARME CRÍTICO: {status_msg}{RESET}")
                        salvo = salvar_no_banco("ALARME_TEMP", temp)
                    else:
                        print(f"{GREEN}[+] Status NORMAL: {status_msg}{RESET}")
                        salvo = salvar_no_banco("LEITURA_NORMAL", temp)
                        
                    print(f"\nStatus DB: {'Conectado e Gravando' if salvo else 'Falha na Gravação'}")
                else:
                    print(f"{RED}[-] Erro Modbus (Corrupção de Pacote/Erro de Leitura){RESET}")
            else:
                print(f"{RED}[-] SINAL PERDIDO com PLC{RESET}")
                
            time.sleep(2)
    except KeyboardInterrupt:
        print("\nHMI encerrado.")
    finally:
        client.close()

if __name__ == "__main__":
    run_hmi()