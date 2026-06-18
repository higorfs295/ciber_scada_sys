#!/usr/bin/env python3
# =============================================================================
# SCADA HMI / HISTORIAN DASHBOARD
# Versão consolidada e melhorada
#
# Objetivo:
# - atuar como painel supervisório textual do laboratório SCADA/ICS
# - gerar telemetria simulada
# - gravar histórico no PostgreSQL
# - mostrar status do Historian
# - exibir alertas, métricas e uptime
# - ser resiliente a falhas do banco sem encerrar o painel
#
# Requisitos:
# - python3
# - psycopg2 / psycopg2-binary
#
# Banco esperado:
# - DB: scada
# - user: hmi_user
# - tabela: historian.process_history
# =============================================================================

import os
import time
import random
import signal
from dataclasses import dataclass
from datetime import datetime
from collections import deque

import psycopg2
from psycopg2 import OperationalError, Error as PsycopgError


# =============================================================================
# CONFIGURAÇÃO
# =============================================================================

DB_HOST = os.getenv("SCADA_DB_HOST", "192.168.100.50")
DB_PORT = int(os.getenv("SCADA_DB_PORT", "5432"))
DB_NAME = os.getenv("SCADA_DB_NAME", "scada")
DB_USER = os.getenv("SCADA_DB_USER", "hmi_user")
DB_PASSWORD = os.getenv("SCADA_DB_PASSWORD", "HMI2026!")

REFRESH_SECONDS = float(os.getenv("SCADA_REFRESH_SECONDS", "2"))
CONNECT_TIMEOUT = int(os.getenv("SCADA_CONNECT_TIMEOUT", "3"))

# =============================================================================
# CORES ANSI
# =============================================================================

GREEN   = "\033[92m"
RED     = "\033[91m"
YELLOW  = "\033[93m"
CYAN    = "\033[96m"
BLUE    = "\033[94m"
MAGENTA = "\033[95m"
WHITE   = "\033[97m"

LABEL   = RED        # rótulos em vermelho
VALUE   = WHITE      # valores em branco
SECTION = YELLOW     # títulos de seção em amarelo

BOLD    = "\033[1m"
DIM     = ""         # remove texto apagado/cinza
RESET   = "\033[0m"

# =============================================================================
# UTILITÁRIOS
# =============================================================================

def clear_screen() -> None:
    os.system("cls" if os.name == "nt" else "clear")


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def fmt_num(value: float, decimals: int = 1) -> str:
    return f"{value:.{decimals}f}"


def bar(value: float, minimum: float, maximum: float, width: int = 24) -> str:
    if maximum <= minimum:
        return "[" + (" " * width) + "]"
    ratio = (value - minimum) / (maximum - minimum)
    ratio = max(0.0, min(1.0, ratio))
    filled = int(ratio * width)
    return "[" + ("█" * filled) + (" " * (width - filled)) + "]"


def color_state(ok: bool) -> str:
    return f"{GREEN}ONLINE{RESET}" if ok else f"{RED}OFFLINE{RESET}"


def box_line(title: str, width: int = 76) -> str:
    return f"{CYAN}{BOLD}╔{'═' * (width - 2)}╗{RESET}"


def box_title(title: str, width: int = 76) -> str:
    content = f" {title} "
    pad = max(0, width - 2 - len(content))
    left = pad // 2
    right = pad - left
    return f"{CYAN}{BOLD}║{' ' * left}{content}{' ' * right}║{RESET}"


def box_footer(width: int = 76) -> str:
    return f"{CYAN}{BOLD}╚{'═' * (width - 2)}╝{RESET}"


def kv(label: str, value: str, label_width: int = 22) -> str:
    return f"{LABEL}{BOLD}{label:<{label_width}}{RESET}: {VALUE}{value}{RESET}"


# =============================================================================
# SIMULADOR DE PROCESSO
# =============================================================================

@dataclass
class ProcessSnapshot:
    temperature: float
    pressure: float
    flow: float
    level: float
    mode: str
    alarm: bool
    ids_alert: bool
    valve_open: bool
    pump_on: bool


class ProcessSimulator:
    def __init__(self) -> None:
        self.temperature = 68.0
        self.pressure = 122.0
        self.flow = 48.0
        self.level = 54.0
        self.prev_temperature = None
        self.recent_temperatures = deque(maxlen=30)

    def step(self) -> ProcessSnapshot:
        anomaly = random.random() < 0.05

        if anomaly:
            # pico simulado / injeção anômala
            self.temperature = random.uniform(85, 98)
            self.pressure = random.uniform(155, 180)
            self.flow = random.uniform(18, 35)
            self.level = clamp(self.level - random.uniform(2, 8), 0, 100)
            mode = "ANOMALIA"
        else:
            # flutuação operacional normal
            self.temperature = clamp(self.temperature + random.uniform(-1.4, 1.4), 62, 72)
            self.pressure = clamp(self.pressure + random.uniform(-2.5, 2.5), 115, 130)
            self.flow = clamp(self.flow + random.uniform(-2.0, 2.0), 38, 55)
            self.level = clamp(self.level + random.uniform(-0.8, 0.8), 45, 65)
            mode = "NORMAL"

        alarm = (self.temperature > 80) or (self.pressure > 150)

        ids_alert = False
        if self.prev_temperature is not None:
            ids_alert = abs(self.temperature - self.prev_temperature) > 15

        self.prev_temperature = self.temperature
        self.recent_temperatures.append(self.temperature)

        valve_open = self.flow > 42 and not alarm
        pump_on = self.level < 60 and not alarm

        return ProcessSnapshot(
            temperature=self.temperature,
            pressure=self.pressure,
            flow=self.flow,
            level=self.level,
            mode=mode,
            alarm=alarm,
            ids_alert=ids_alert,
            valve_open=valve_open,
            pump_on=pump_on,
        )

    def average_temperature(self) -> float:
        if not self.recent_temperatures:
            return 0.0
        return sum(self.recent_temperatures) / len(self.recent_temperatures)


# =============================================================================
# HISTORIAN / POSTGRESQL
# =============================================================================

class HistorianClient:
    def __init__(self) -> None:
        self.conn = None
        self.last_error = "Nenhum"
        self.last_ok_ts = None
        self.last_latency_ms = None

    def connect(self):
        self.conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            connect_timeout=CONNECT_TIMEOUT,
        )
        return self.conn

    def ensure_connection(self):
        if self.conn is None or self.conn.closed != 0:
            self.connect()
        return self.conn

    def ping(self) -> bool:
        start = time.time()
        try:
            conn = self.ensure_connection()
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
                cur.fetchone()
            self.last_latency_ms = round((time.time() - start) * 1000, 1)
            self.last_ok_ts = datetime.now()
            self.last_error = "Nenhum"
            return True
        except (OperationalError, PsycopgError, Exception) as exc:
            self.last_error = str(exc)
            self.close()
            return False

    def write_snapshot(self, snapshot: ProcessSnapshot) -> bool:
        start = time.time()
        try:
            conn = self.ensure_connection()
            with conn:
                with conn.cursor() as cur:
                    payload = [
                        ("temperature", float(snapshot.temperature)),
                        ("pressure", float(snapshot.pressure)),
                        ("flow", float(snapshot.flow)),
                        ("level", float(snapshot.level)),
                        ("alarm_flag", 1.0 if snapshot.alarm else 0.0),
                        ("ids_flag", 1.0 if snapshot.ids_alert else 0.0),
                    ]
                    cur.executemany(
                        """
                        INSERT INTO historian.process_history
                            (tag_name, tag_value)
                        VALUES
                            (%s, %s)
                        """,
                        payload,
                    )
            self.last_latency_ms = round((time.time() - start) * 1000, 1)
            self.last_ok_ts = datetime.now()
            self.last_error = "Nenhum"
            return True
        except (OperationalError, PsycopgError, Exception) as exc:
            self.last_error = str(exc)
            self.close()
            return False

    def close(self) -> None:
        try:
            if self.conn is not None:
                self.conn.close()
        finally:
            self.conn = None


# =============================================================================
# DASHBOARD
# =============================================================================

class Dashboard:
    def __init__(self) -> None:
        self.sim = ProcessSimulator()
        self.db = HistorianClient()
        self.leituras = 0
        self.alarmes = 0
        self.ids_alerts = 0
        self.gravacoes_ok = 0
        self.gravacoes_falha = 0
        self.start_ts = time.time()
        self.running = True
        self.last_snapshot = None

    def handle_sigint(self, *_):
        self.running = False

    def uptime_str(self) -> str:
        elapsed = int(time.time() - self.start_ts)
        h = elapsed // 3600
        m = (elapsed % 3600) // 60
        s = elapsed % 60
        return f"{h:02}:{m:02}:{s:02}"

    def format_center(self, text: str, width: int = 76) -> str:
        if len(text) >= width - 2:
            return f"║ {text[:width-4]} ║"
        pad = width - 2 - len(text)
        left = pad // 2
        right = pad - left
        return f"║{' ' * left}{text}{' ' * right}║"

    def render_header(self) -> None:
        width = 84
        print(f"{CYAN}{BOLD}╔{'═' * (width - 2)}╗{RESET}")
        print(self.format_center("SCADA HMI / HISTORIAN / IDS DASHBOARD", width))
        print(self.format_center("Laboratório Virtual SCADA / ICS", width))
        print(f"{CYAN}{BOLD}╠{'═' * (width - 2)}╣{RESET}")

    def render_footer(self) -> None:
        width = 84
        print(f"{CYAN}{BOLD}╚{'═' * (width - 2)}╝{RESET}")

    def render(self, snap: ProcessSnapshot, db_online: bool) -> None:
        clear_screen()
        self.render_header()

        now = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
        print(self.format_center(f"Timestamp: {now}", 84))
        print(self.format_center(f"Host DB: {DB_HOST}:{DB_PORT} | Banco: {DB_NAME} | User: {DB_USER}", 84))
        print(f"{CYAN}{BOLD}╠{'═' * (84 - 2)}╣{RESET}")

        # Bloco de estado
        print(f"{SECTION}{BOLD}│ ESTADO DO PROCESSO{' ' * 63}│{RESET}")
        status = f"{GREEN}{BOLD}NORMAL{RESET}" if not snap.alarm else f"{RED}{BOLD}ALARME CRÍTICO{RESET}"
        print(f"│ {kv('Estado', status, 20):<80}│")
        print(f"│ {kv('Modo simulado', snap.mode, 20):<80}│")
        print(f"│ {kv('Temperatura', f'{snap.temperature:.2f} °C  {bar(snap.temperature, 50, 100, 18)}', 20):<80}│")
        print(f"│ {kv('Pressão', f'{snap.pressure:.2f} PSI  {bar(snap.pressure, 100, 180, 18)}', 20):<80}│")
        print(f"│ {kv('Fluxo', f'{snap.flow:.2f} L/min  {bar(snap.flow, 0, 70, 18)}', 20):<80}│")
        print(f"│ {kv('Nível', f'{snap.level:.2f} %  {bar(snap.level, 0, 100, 18)}', 20):<80}│")
        print(f"│ {kv('Válvula', 'ABERTA' if snap.valve_open else 'FECHADA', 20):<80}│")
        print(f"│ {kv('Bomba', 'LIGADA' if snap.pump_on else 'DESLIGADA', 20):<80}│")

        print(f"{CYAN}{BOLD}╠{'═' * (84 - 2)}╣{RESET}")

        # Bloco de Historian / DB
        db_status = f"{GREEN}{BOLD}ONLINE{RESET}" if db_online else f"{RED}{BOLD}OFFLINE{RESET}"
        print(f"{SECTION}{BOLD}│ HISTORIAN / BANCO{' ' * 63}│{RESET}")
        print(f"│ {kv('Status DB', db_status, 20):<80}│")
        print(f"│ {kv('Última latência', f'{self.db.last_latency_ms} ms' if self.db.last_latency_ms is not None else 'N/D', 20):<80}│")
        print(f"│ {kv('Última gravação', self.db.last_ok_ts.strftime('%H:%M:%S') if self.db.last_ok_ts else 'N/D', 20):<80}│")
        print(f"│ {kv('Último erro', self.db.last_error[:52], 20):<80}│")

        print(f"{CYAN}{BOLD}╠{'═' * (84 - 2)}╣{RESET}")

        # Métricas
        avg_temp = self.sim.average_temperature()
        print(f"{SECTION}{BOLD}│ MÉTRICAS OPERACIONAIS{' ' * 58}│{RESET}")
        print(f"│ {kv('Leituras', str(self.leituras), 20):<80}│")
        print(f"│ {kv('Alarmes', str(self.alarmes), 20):<80}│")
        print(f"│ {kv('IDS Alerts', str(self.ids_alerts), 20):<80}│")
        print(f"│ {kv('Gravações OK', str(self.gravacoes_ok), 20):<80}│")
        print(f"│ {kv('Falhas DB', str(self.gravacoes_falha), 20):<80}│")
        print(f"│ {kv('Média Temperatura', f'{avg_temp:.2f} °C', 20):<80}│")
        print(f"│ {kv('Uptime', self.uptime_str(), 20):<80}│")

        print(f"{CYAN}{BOLD}╠{'═' * (84 - 2)}╣{RESET}")

        # Rodapé
        print(f"{SECTION}{BOLD}│ TOPOLOGIA LÓGICA{' ' * 61}│{RESET}")
        print(f"│ {kv('OT Net', '192.168.100.0/24', 20):<80}│")
        print(f"│ {kv('HMI Host', 'scada-hmi.semi', 20):<80}│")
        print(f"│ {kv('PLC Host', 'plc-openplc.semi', 20):<80}│")
        print(f"│ {kv('Sensor Host', 'sensor-node.semi', 20):<80}│")
        print(f"│ {kv('DB Host', 'db-server.semi', 20):<80}│")

        self.render_footer()
        print(f"{YELLOW}CTRL+C para sair | Atualização a cada {REFRESH_SECONDS:.1f}s{RESET}")

    def run(self) -> None:
        signal.signal(signal.SIGINT, self.handle_sigint)
        signal.signal(signal.SIGTERM, self.handle_sigint)

        # tentativas de inicialização do banco
        startup_db_ok = self.db.ping()

        while self.running:
            snap = self.sim.step()
            self.leituras += 1
            if snap.alarm:
                self.alarmes += 1
            if snap.ids_alert:
                self.ids_alerts += 1

            # grava no banco somente se conseguir conectar; se falhar, continua em modo degradado
            db_online = self.db.write_snapshot(snap)
            if db_online:
                # duas leituras úteis por ciclo: uma para telemetria e outra de write
                self.gravacoes_ok += 6
            else:
                self.gravacoes_falha += 1

            self.render(snap, db_online)

            time.sleep(REFRESH_SECONDS)

        self.db.close()
        clear_screen()
        print("Monitor encerrado com segurança.")


# =============================================================================
# MAIN
# =============================================================================

def main() -> None:
    dash = Dashboard()
    dash.run()


if __name__ == "__main__":
    main()