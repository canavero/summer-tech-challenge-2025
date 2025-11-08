const express = require('express');
const router = express.Router();
const db = require('../database');

/**
 * POST /receivers
 * Cria um novo recebedor
 */
router.post('/', async (req, res) => {
  const { name } = req.body;

  if (!name) {
    return res.status(400).json({ error: 'name é obrigatório' });
  }

  try {
    const result = await db.query(
      'INSERT INTO receivers (name, balance) VALUES ($1, 0) RETURNING *',
      [name]
    );

    res.status(201).json({
      id: result.rows[0].id,
      name: result.rows[0].name,
      balance: parseFloat(result.rows[0].balance)
    });
  } catch (err) {
    console.error('Erro ao criar recebedor:', err);
    return res.status(500).json({ error: 'Erro ao criar recebedor' });
  }
});

/**
 * GET /receivers/:id
 * Retorna o nome e saldo do recebedor, além do histórico de operações
 */
router.get('/:id', async (req, res) => {
  const { id } = req.params;

  try {
    // Busca o recebedor
    const receiverResult = await db.query(
      'SELECT * FROM receivers WHERE id = $1',
      [id]
    );

    if (receiverResult.rows.length === 0) {
      return res.status(404).json({ error: 'Recebedor não encontrado' });
    }

    const receiver = receiverResult.rows[0];

    // Busca o histórico de operações do recebedor
    const operationsResult = await db.query(
      'SELECT * FROM operations WHERE receiver_id = $1 ORDER BY created_at DESC',
      [id]
    );

    res.json({
      id: receiver.id,
      name: receiver.name,
      balance: parseFloat(receiver.balance),
      operations: operationsResult.rows.map(op => ({
        id: op.id,
        gross_value: parseFloat(op.gross_value),
        fee: parseFloat(op.fee),
        net_value: parseFloat(op.net_value),
        status: op.status,
        created_at: op.created_at
      }))
    });
  } catch (err) {
    console.error('Erro ao buscar recebedor:', err);
    return res.status(500).json({ error: 'Erro ao buscar recebedor' });
  }
});

/**
 * GET /receivers
 * Lista todos os recebedores
 */
router.get('/', async (req, res) => {
  try {
    const result = await db.query('SELECT * FROM receivers');
    
    res.json(result.rows.map(receiver => ({
      id: receiver.id,
      name: receiver.name,
      balance: parseFloat(receiver.balance)
    })));
  } catch (err) {
    console.error('Erro ao buscar recebedores:', err);
    return res.status(500).json({ error: 'Erro ao buscar recebedores' });
  }
});

module.exports = router;
