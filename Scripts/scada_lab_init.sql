-- ============================================================================
-- SCADA / ICS LAB DATABASE INITIALIZATION
-- PostgreSQL
-- Autor: Higor Ferreira Silva
-- ============================================================================

-- ============================================================================
-- USUÁRIOS
-- ============================================================================

CREATE ROLE plc_user LOGIN PASSWORD 'PLC2026!';
CREATE ROLE hmi_user LOGIN PASSWORD 'HMI2026!';
CREATE ROLE sensor_user LOGIN PASSWORD 'SENSOR2026!';
CREATE ROLE analyst_user LOGIN PASSWORD 'ANALYST2026!';

-- ============================================================================
-- BANCO
-- ============================================================================

CREATE DATABASE scada;

\c scada

-- ============================================================================
-- SCHEMAS
-- ============================================================================

CREATE SCHEMA plc;
CREATE SCHEMA telemetry;
CREATE SCHEMA alarms;
CREATE SCHEMA historian;
CREATE SCHEMA security;
CREATE SCHEMA threat_intelligence;

-- ============================================================================
-- TABELAS PLC
-- ============================================================================

CREATE TABLE plc.registers (
    id SERIAL PRIMARY KEY,
    register_number INTEGER NOT NULL,
    register_value INTEGER NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TABELAS TELEMETRIA
-- ============================================================================

CREATE TABLE telemetry.sensor_data (
    id SERIAL PRIMARY KEY,
    sensor_name VARCHAR(100),
    sensor_value NUMERIC(10,2),
    unit VARCHAR(20),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TABELAS ALARMES
-- ============================================================================

CREATE TABLE alarms.events (
    id SERIAL PRIMARY KEY,
    alarm_name VARCHAR(100),
    severity VARCHAR(20),
    description TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TABELAS HISTÓRICO
-- ============================================================================

CREATE TABLE historian.process_history (
    id SERIAL PRIMARY KEY,
    tag_name VARCHAR(100),
    tag_value NUMERIC(10,2),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TABELAS SEGURANÇA
-- ============================================================================

CREATE TABLE security.security_events (
    id SERIAL PRIMARY KEY,
    source_ip VARCHAR(50),
    event_type VARCHAR(100),
    description TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TABELAS THREAT INTELLIGENCE
-- ============================================================================

CREATE TABLE threat_intelligence.indicators (
    id SERIAL PRIMARY KEY,
    indicator_type VARCHAR(50),
    indicator_value TEXT,
    source VARCHAR(100),
    confidence INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- PERMISSÕES
-- ============================================================================

GRANT CONNECT ON DATABASE scada TO plc_user;
GRANT CONNECT ON DATABASE scada TO hmi_user;
GRANT CONNECT ON DATABASE scada TO sensor_user;
GRANT CONNECT ON DATABASE scada TO analyst_user;

GRANT USAGE ON SCHEMA plc TO plc_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA plc TO plc_user;

GRANT USAGE ON SCHEMA telemetry TO sensor_user;
GRANT INSERT, SELECT ON ALL TABLES IN SCHEMA telemetry TO sensor_user;

GRANT USAGE ON SCHEMA telemetry TO hmi_user;
GRANT USAGE ON SCHEMA alarms TO hmi_user;
GRANT USAGE ON SCHEMA historian TO hmi_user;

GRANT SELECT ON ALL TABLES IN SCHEMA telemetry TO hmi_user;
GRANT SELECT ON ALL TABLES IN SCHEMA historian TO hmi_user;
GRANT INSERT ON ALL TABLES IN SCHEMA alarms TO hmi_user;

GRANT ALL PRIVILEGES ON DATABASE scada TO analyst_user;

-- ============================================================================
-- DADOS DE TESTE
-- ============================================================================

INSERT INTO telemetry.sensor_data
(sensor_name,sensor_value,unit)
VALUES
('Temperature',25.4,'C'),
('Pressure',3.2,'bar'),
('Flow',120.5,'L/min');

INSERT INTO plc.registers
(register_number,register_value)
VALUES
(0,100),
(1,200),
(2,300);

INSERT INTO alarms.events
(alarm_name,severity,description)
VALUES
('High Temperature','WARNING','Temperature above threshold');

INSERT INTO security.security_events
(source_ip,event_type,description)
VALUES
('192.168.100.10','NMAP_SCAN','Initial laboratory scan');

INSERT INTO threat_intelligence.indicators
(indicator_type,indicator_value,source,confidence)
VALUES
('IP','192.168.100.200','Lab Test',80);

-- ============================================================================
-- FINALIZAÇÃO
-- ============================================================================

SELECT 'SCADA DATABASE INITIALIZED SUCCESSFULLY';