# 1. Cria o banco de dados scada_db
sudo -u postgres psql -c "CREATE DATABASE scada_db;"

# 2. Cria a tabela de histórico de sensores
sudo -u postgres psql -d scada_db -c "
CREATE TABLE historico_sensores (
    id SERIAL PRIMARY KEY,
    data_hora TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    sensor VARCHAR(50),
    valor INT
);"

# 3. Insere alguns dados falsos para simular que a planta já roda há algum tempo
sudo -u postgres psql -d scada_db -c "
INSERT INTO historico_sensores (sensor, valor) VALUES 
('Temperatura Forno', 145), 
('Temperatura Forno', 147), 
('Pressão Valvula 1', 210), 
('Pressão Valvula 1', 215);"

# 4. Verifica se os dados estão lá
sudo -u postgres psql -d scada_db -c "SELECT * FROM historico_sensores;"