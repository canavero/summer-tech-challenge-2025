var express = require('express');
var router = express.Router();

router.get('/', function(req, res, next) {
  res.json({
    message: 'LocPay Tech Challenge API - Summer Job 2025',
    version: '1.0.0',
    endpoints: {
      receivers: {
        'POST /receivers': 'Cria um novo recebedor',
        'GET /receivers': 'Lista todos os recebedores',
        'GET /receivers/:id': 'Retorna dados do recebedor e histórico de operações'
      },
      operations: {
        'POST /operations': 'Cria uma nova operação de antecipação',
        'GET /operations/:id': 'Retorna dados de uma operação',
        'POST /operations/:id/confirm': 'Confirma uma operação e atualiza saldo'
      }
    }
  });
});

// Health check endpoint para Docker e ALB
router.get('/health', function(req, res) {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

module.exports = router;
