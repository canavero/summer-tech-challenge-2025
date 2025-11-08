const express = require('express');
const router = express.Router();
const db = require('../database');

// Constante para taxa de antecipação (3%)
const FEE_PERCENTAGE = 0.03;

/**
 * POST /operations
 * Cria uma nova operação de antecipação
 */
router.post('/', async (req, res) => {
  const { receiver_id, gross_value } = req.body;

  // Validação dos dados de entrada
  if (!receiver_id || !gross_value) {
    return res.status(400).json({
      error: 'receiver_id e gross_value são obrigatórios'
    });
  }

  if (typeof gross_value !== 'number' || gross_value <= 0) {
    return res.status(400).json({
      error: 'gross_value deve ser um número positivo'
    });
  }

  try {
    // Verifica se o receiver existe
    const receiverCheck = await db.query(
      'SELECT id FROM receivers WHERE id = $1',
      [receiver_id]
    );

    if (receiverCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Recebedor não encontrado' });
    }

    // Calcula fee e net_value
    const fee = gross_value * FEE_PERCENTAGE;
    const net_value = gross_value - fee;

    // Insere a operação no banco de dados
    const result = await db.query(
      `INSERT INTO operations (receiver_id, gross_value, fee, net_value, status)
       VALUES ($1, $2, $3, $4, 'pending')
       RETURNING *`,
      [receiver_id, gross_value, fee, net_value]
    );

    const operation = result.rows[0];

    res.status(201).json({
      id: operation.id,
      receiver_id: operation.receiver_id,
      gross_value: parseFloat(operation.gross_value),
      fee: parseFloat(operation.fee),
      net_value: parseFloat(operation.net_value),
      status: operation.status,
      created_at: operation.created_at
    });
  } catch (err) {
    console.error('Erro ao criar operação:', err);
    return res.status(500).json({ error: 'Erro ao criar operação' });
  }
});

/**
 * GET /operations/:id
 * Retorna os dados completos de uma operação
 */
router.get('/:id', async (req, res) => {
  const { id } = req.params;

  try {
    const result = await db.query(
      'SELECT * FROM operations WHERE id = $1',
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Operação não encontrada' });
    }

    const operation = result.rows[0];

    res.json({
      id: operation.id,
      receiver_id: operation.receiver_id,
      gross_value: parseFloat(operation.gross_value),
      fee: parseFloat(operation.fee),
      net_value: parseFloat(operation.net_value),
      status: operation.status,
      created_at: operation.created_at
    });
  } catch (err) {
    console.error('Erro ao buscar operação:', err);
    return res.status(500).json({ error: 'Erro ao buscar operação' });
  }
});

/**
 * POST /operations/:id/confirm
 * Confirma uma operação e atualiza o saldo do recebedor
 */
router.post('/:id/confirm', async (req, res) => {
  const { id } = req.params;

  // Usa um client para executar uma transação
  const client = await db.connect();

  try {
    // Inicia a transação
    await client.query('BEGIN');

    // Busca a operação
    const operationResult = await client.query(
      'SELECT * FROM operations WHERE id = $1',
      [id]
    );

    if (operationResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Operação não encontrada' });
    }

    const operation = operationResult.rows[0];

    if (operation.status === 'confirmed') {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Operação já foi confirmada' });
    }

    // Atualiza o status da operação para 'confirmed'
    await client.query(
      'UPDATE operations SET status = $1 WHERE id = $2',
      ['confirmed', id]
    );

    // Atualiza o saldo do recebedor
    await client.query(
      'UPDATE receivers SET balance = balance + $1 WHERE id = $2',
      [operation.net_value, operation.receiver_id]
    );

    // Confirma a transação
    await client.query('COMMIT');

    // Busca a operação confirmada
    const confirmedResult = await client.query(
      'SELECT * FROM operations WHERE id = $1',
      [id]
    );

    const confirmedOperation = confirmedResult.rows[0];

    res.json({
      id: confirmedOperation.id,
      receiver_id: confirmedOperation.receiver_id,
      gross_value: parseFloat(confirmedOperation.gross_value),
      fee: parseFloat(confirmedOperation.fee),
      net_value: parseFloat(confirmedOperation.net_value),
      status: confirmedOperation.status,
      created_at: confirmedOperation.created_at,
      message: 'Operação confirmada com sucesso'
    });

  } catch (err) {
    // Em caso de erro, faz rollback
    await client.query('ROLLBACK');
    console.error('Erro ao confirmar operação:', err);
    return res.status(500).json({ error: 'Erro ao confirmar operação' });
  } finally {
    // Libera o client de volta ao pool
    client.release();
  }
});

module.exports = router;
