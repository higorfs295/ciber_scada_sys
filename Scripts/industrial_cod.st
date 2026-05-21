PROGRAM Planta_Petroquimica_V5
VAR
    (* -------------------------------------------------------- *)
    (* VARIÁVEIS DE ENTRADA (Mapeadas para os Sensores)         *)
    (* -------------------------------------------------------- *)
    sensor_temp AT %IW0 : INT;
    sensor_pressao AT %IW1 : INT;
    sensor_nivel AT %IW2 : INT;

    (* -------------------------------------------------------- *)
    (* VARIÁVEIS DE SAÍDA (Mapeadas para os Atuadores)          *)
    (* -------------------------------------------------------- *)
    valvula_vapor AT %QW0 : INT;
    valvula_alivio AT %QW1 : INT;
    bomba_carga AT %QW2 : INT;
    alarme_sirene AT %QX0.0 : BOOL;
    emergencia_led AT %QX0.1 : BOOL;

    (* -------------------------------------------------------- *)
    (* MEMÓRIA MODBUS (Lida/Escrita pelo SCADA)                 *)
    (* NÃO podem conter " := " aqui na declaração!              *)
    (* -------------------------------------------------------- *)
    mb_temp_calc AT %MW0 : INT;
    mb_pressao_calc AT %MW1 : INT;
    mb_nivel_calc AT %MW2 : INT;
    mb_estado_planta AT %MW3 : INT;
    mb_contador_alarmes AT %MW4 : INT;
    mb_setpoint_temp AT %MW5 : INT;

    (* -------------------------------------------------------- *)
    (* VARIÁVEIS INTERNAS DE CÁLCULO E CONTROLE                 *)
    (* -------------------------------------------------------- *)
    temp_real : REAL;
    pressao_real : REAL;
    nivel_real : REAL;
    setpoint_real : REAL;
    erro_temp : REAL;
    comando_valvula : REAL;

    estado_atual : INT;
    flag_alta_temp : BOOL;
    flag_alta_pressao : BOOL;
    interlock_ativo : BOOL;
    init_done : BOOL := FALSE;

    (* -------------------------------------------------------- *)
    (* BLOCOS FUNCIONAIS IEC 61131-3                            *)
    (* -------------------------------------------------------- *)
    timer_alta_temp : TON;
    timer_alta_pressao : TON;
    timer_startup : TON;
END_VAR

(* ================================================================= *)
(* 1. BLOCO DE INICIALIZAÇÃO (Roda apenas 1 vez no Boot)             *)
(* ================================================================= *)
IF NOT init_done THEN
    mb_contador_alarmes := 0;
    mb_setpoint_temp := 75;  (* Setpoint alvo desejado *)
    estado_atual := 0;       (* Estado FSM: 0 = STARTUP *)
    interlock_ativo := FALSE;
    flag_alta_temp := FALSE;
    flag_alta_pressao := FALSE;
    init_done := TRUE;
END_IF;

(* ================================================================= *)
(* 2. AQUISIÇÃO E LINEARIZAÇÃO DE DADOS (Raw INT para Engenharia REAL) *)
(* ================================================================= *)
(* O PLC lê de 0 a 4095. Convertendo para escalas reais:             *)
temp_real := (INT_TO_REAL(sensor_temp) / 4095.0) * 150.0;
pressao_real := (INT_TO_REAL(sensor_pressao) / 4095.0) * 200.0;
nivel_real := (INT_TO_REAL(sensor_nivel) / 4095.0) * 100.0;

(* Espelha os valores computados para os registradores do SCADA *)
mb_temp_calc := REAL_TO_INT(temp_real);
mb_pressao_calc := REAL_TO_INT(pressao_real);
mb_nivel_calc := REAL_TO_INT(nivel_real);

(* ================================================================= *)
(* 3. LÓGICA DE ALARMES COM DEBOUNCE (Filtro de Transientes)         *)
(* ================================================================= *)
(* Alarme de Temperatura após 3 segundos contínuos acima de 90°C *)
timer_alta_temp(IN := temp_real > 90.0, PT := T#3s);
IF timer_alta_temp.Q AND NOT flag_alta_temp THEN
    flag_alta_temp := TRUE;
    mb_contador_alarmes := mb_contador_alarmes + 1;
ELSIF temp_real < 85.0 THEN
    flag_alta_temp := FALSE;
END_IF;

(* Alarme de Pressão após 2 segundos contínuos acima de 150 PSI *)
timer_alta_pressao(IN := pressao_real > 150.0, PT := T#2s);
IF timer_alta_pressao.Q AND NOT flag_alta_pressao THEN
    flag_alta_pressao := TRUE;
    mb_contador_alarmes := mb_contador_alarmes + 1;
ELSIF pressao_real < 130.0 THEN
    flag_alta_pressao := FALSE;
END_IF;

(* Trip de Segurança (Interlock Irreversível por Hardware) *)
IF (temp_real > 110.0) OR (pressao_real > 180.0) THEN
    interlock_ativo := TRUE;
END_IF;

(* ================================================================= *)
(* 4. MÁQUINA DE ESTADOS FINITOS (Controle do Processo)              *)
(* ================================================================= *)
CASE estado_atual OF
    
    (* --- ESTADO 0: STARTUP (Partida a Frio) --- *)
    0:
        alarme_sirene := FALSE;
        emergencia_led := FALSE;
        bomba_carga := 2047;   (* Liga bomba a 50% *)
        valvula_vapor := 1024; (* Pré-aquece a 25% *)
        valvula_alivio := 0;

        (* Aguarda 10 segundos de estabilização antes de ir para RUNNING *)
        timer_startup(IN := TRUE, PT := T#10s);
        IF timer_startup.Q AND NOT interlock_ativo THEN
            estado_atual := 1;
            timer_startup(IN := FALSE, PT := T#10s); (* Reseta o timer *)
        END_IF;

    (* --- ESTADO 1: RUNNING (Regime Permanente & Controle) --- *)
    1:
        alarme_sirene := FALSE;
        emergencia_led := FALSE;

        (* Controle Dinâmico de Nível Otimizado *)
        IF nivel_real < 80.0 THEN
            bomba_carga := 2866; (* ~70% de capacidade *)
        ELSE
            bomba_carga := 0;
        END_IF;

        (* Malha de Controle Proporcional de Temperatura *)
        setpoint_real := INT_TO_REAL(mb_setpoint_temp);
        erro_temp := setpoint_real - temp_real;

        IF erro_temp > 0.0 THEN
            comando_valvula := erro_temp * 40.0; (* Fator de Ganho Proporcional Kp *)
            IF comando_valvula > 4095.0 THEN
                comando_valvula := 4095.0; (* Satura em 100% *)
            END_IF;
            valvula_vapor := REAL_TO_INT(comando_valvula);
        ELSE
            valvula_vapor := 0;
        END_IF;

        (* Proteção Dinâmica de Alívio de Pressão *)
        IF flag_alta_pressao THEN
            valvula_alivio := 4095; (* Abre 100% da purga *)
        ELSE
            valvula_alivio := 0;
        END_IF;

        (* Transição para Falha Crítica *)
        IF interlock_ativo THEN
            estado_atual := 2;
        END_IF;

    (* --- ESTADO 2: SHUTDOWN DE EMERGÊNCIA (ESD) --- *)
    2:
        alarme_sirene := TRUE;
        emergencia_led := TRUE;

        (* Coloca todos os atuadores em estado Fail-Safe (Falha Segura) *)
        bomba_carga := 0;
        valvula_vapor := 0;
        valvula_alivio := 4095; (* Despressurização forçada da planta *)

        (* Nota: A saída deste estado geralmente requer intervenção física/reset *)

END_CASE;

(* Comunica o estado atual para a interface SCADA *)
mb_estado_planta := estado_atual;

END_PROGRAM