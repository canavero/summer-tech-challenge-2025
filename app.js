var express = require('express');
var cookieParser = require('cookie-parser');
var logger = require('morgan');

var indexRouter = require('./routes/index');
var operationsRouter = require('./routes/operations');
var receiversRouter = require('./routes/receivers');

var app = express();

app.use(logger('dev'));
app.use(express.json());
app.use(express.urlencoded({ extended: false }));
app.use(cookieParser());

app.use('/', indexRouter);
app.use('/operations', operationsRouter);
app.use('/receivers', receiversRouter);

// Tratamento de erros 404
app.use((req, res, next) => {
  res.status(404).json({ error: 'Rota não encontrada' });
});

// Tratamento de erros gerais
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Erro interno do servidor' });
});

module.exports = app;
