const { Pool } = require('pg');

// Configuração da conexão com PostgreSQL RDS
// As variáveis de ambiente são injetadas pelo ECS Task Definition
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'locpay',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  // SSL/TLS obrigatório para RDS PostgreSQL
  ssl: process.env.NODE_ENV === 'production' ? {
    rejectUnauthorized: false // AWS RDS usa certificados auto-assinados
  } : false,
  // Configurações de pool de conexões
  max: 20, // Máximo de conexões no pool
  idleTimeoutMillis: 30000, // Tempo para fechar conexões inativas
  connectionTimeoutMillis: 2000, // Tempo limite para novas conexões
});

// Testa a conexão e inicializa o banco
pool.connect((err, client, release) => {
  if (err) {
    console.error('Erro ao conectar ao banco de dados PostgreSQL:', err.message);
    console.error('Verifique as variáveis de ambiente: DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD');
  } else {
    console.log('Conectado ao banco de dados PostgreSQL RDS.');
    release();
    initializeDatabase();
  }
});

// Inicializa as tabelas necessárias
async function initializeDatabase() {
  const client = await pool.connect();
  
  try {
    // Tabela de recebedores
    await client.query(`
      CREATE TABLE IF NOT EXISTS receivers (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        balance DECIMAL(10, 2) DEFAULT 0
      )
    `);
    console.log('Tabela receivers criada/verificada com sucesso.');

    // Tabela de operações
    await client.query(`
      CREATE TABLE IF NOT EXISTS operations (
        id SERIAL PRIMARY KEY,
        receiver_id INTEGER NOT NULL,
        gross_value DECIMAL(10, 2) NOT NULL,
        fee DECIMAL(10, 2) NOT NULL,
        net_value DECIMAL(10, 2) NOT NULL,
        status VARCHAR(50) DEFAULT 'pending',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (receiver_id) REFERENCES receivers(id)
      )
    `);
    console.log('Tabela operations criada/verificada com sucesso.');

    // Índices para melhor performance
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_operations_receiver_id 
      ON operations(receiver_id)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_operations_status 
      ON operations(status)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_operations_created_at 
      ON operations(created_at)
    `);
    console.log('Índices criados/verificados com sucesso.');

  } catch (err) {
    console.error('Erro ao inicializar banco de dados:', err.message);
  } finally {
    client.release();
  }
}

// Graceful shutdown - fecha o pool ao encerrar a aplicação
process.on('SIGTERM', () => {
  console.log('SIGTERM recebido, fechando pool de conexões...');
  pool.end(() => {
    console.log('Pool de conexões fechado.');
    process.exit(0);
  });
});

module.exports = pool;
