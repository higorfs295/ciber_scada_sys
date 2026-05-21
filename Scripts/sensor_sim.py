#!/usr/bin/env python3
import time
import os
import random
from pymodbus.client import ModbusTcpClient

# Configuração de Rede (Alvo: VM OpenPLC)
PLC_IP = '192.168.100.20'
PORT = 502

# Cores ANSI para o terminal do Sensor
GREEN  = '\033[92m'
YELLOW = '\033[93m'
RED    = '\033[91m'
CYAN   = '\033[96m'
RESET  = '\033[0m'
BOLD   = '\033[1m'

def simular_sensor():
    # Inicializa o cliente Modbus apontando para o PLC
    client = ModbusTcpClient(host=PLC_IP, port=PORT)
    
    # Valores base para a simulação física estável
    temperatura_base = 60
    pressao_base = 115

    print(f"{YELLOW}{BOLD}=================================================={RESET}")
    print(f"{YELLOW}{BOLD}       SIMULADOR INDUSTRIAL DE TELEMETRIA v2.0    {RESET}")
    print(f"{YELLOW}{BOLD}=================================================={RESET}")
    print(f" Destino: OpenPLC no IP {PLC_IP}:{PORT}")
    print(f" Pressione Ctrl+C para interromper o envio de dados.")
    print(f"{YELLOW}--------------------------------------------------{RESET}\n")

    try:
        while True:
            # Garante que a conexão está aberta antes de enviar
            if not client.is_socket_open():
                client.connect()

            if client.is_socket_open():
                # Gera pequenas flutuações realistas de ruído industrial
                temp_atual = int(temperatura_base + random.uniform(-2.5, 2.5))
                pressao_atual = int(pressao_base + random.uniform(-5.0, 5.0))

                # CORREÇÃO UNIVERSAL: Apenas parâmetros posicionais puros (0 = endereço, lista = valores)
                # Registrador 0: Temperatura | Registrador 1: Pressão
                result = client.write_registers(0, [temp_atual, pressao_atual])

                # Validação de envio para versões antigas e novas do Pymodbus
                if result and not hasattr(result, 'isError') or (hasattr(result, 'isError') and not result.isError()):
                    print(f"[{GREEN}OK{RESET}] Dados transmitidos -> Temp: {BOLD}{temp_atual}°C{RESET} | Pressão: {BOLD}{pressao_atual} PSI{RESET}")
                else:
                    print(f"[{RED}FALHA{RESET}] PLC rejeitou o pacote de registradores Modbus.")
            else:
                print(f"[{RED}ERRO DE REDE{RESET}] Não foi possível alcançar o OpenPLC em {PLC_IP}. Tentando novamente...")

            # Envia uma nova leitura a cada 2 segundos (sincronizado com o SCADA)
            time.sleep(2)

    except KeyboardInterrupt:
        print(f"\n{CYAN}[*] Simulador do sensor finalizado pelo operador.{RESET}")
    finally:
        client.close()

if __name__ == "__main__":
    simular_sensor()