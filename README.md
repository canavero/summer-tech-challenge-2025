#  LocPay API - Sistema de Antecipação de Recebíveis

> **API RESTful** para gerenciamento de operações de antecipação de recebíveis, desenvolvida como solução para o **LocPay Tech Challenge - Summer Job 2025**.

[![Node.js](https://img.shields.io/badge/Node.js-18.x-green)](https://nodejs.org/)
[![Express](https://img.shields.io/badge/Express-4.x-blue)](https://expressjs.com/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-blue)](https://www.postgresql.org/)
[![Docker](https://img.shields.io/badge/Docker-Ready-blue)](https://www.docker.com/)
[![AWS](https://img.shields.io/badge/AWS-Deployed-orange)](https://aws.amazon.com/)

---

##  Status da Infraestrutura

**A infraestrutura AWS está DESLIGADA** para redução de custos.

**Para testar a API em produção:**
-  Entre em contato (no final do documento) para ativar a infraestrutura
-  Tempo de ativação: ~5 minutos
-  Infraestrutura: AWS São Paulo (sa-east-1)

**Para testes locais:**
- Use Docker Compose
- Comando: docker-compose up -d

---

##  Sobre o Projeto

API para simular **antecipação de recebíveis** para proprietários de imóveis. Permite que recebedores antecipem valores futuros com taxa de 3%.

### Regras de Negócio

- **Taxa**: 3% sobre o valor bruto
- **Cálculo**: valor_liquido = valor_bruto - (valor_bruto * 0.03)
- **Status**: pending (aguardando) ou confirmed (confirmado)

---

##  Arquitetura

### AWS (Produção)

`
Internet  ALB (Port 80)  ECS Fargate (2 tasks)  RDS PostgreSQL
`

**Serviços AWS:**
- VPC: 10.0.0.0/16 (6 subnets, 2 AZs)
- ECS Fargate: 2 containers (512 CPU, 1024 MB)
- RDS: PostgreSQL 15, db.t3.micro, 20GB
- ALB: Application Load Balancer
- ECR: Docker Registry
- Secrets Manager: Credenciais
- CloudWatch: Logs

### Local (Docker Compose)

`
API Node.js (Port 3000)  PostgreSQL (Port 5432)
`

---

##  Tecnologias

- **Node.js 18** + **Express 4** + **PostgreSQL 15**
- **Docker** + **Terraform** + **AWS**
- Bibliotecas: pg, dotenv, morgan

---

##  Como Executar Localmente

`Bash
# 1. Clonar repositório
git clone <URL>
cd summer-tech-challenge-2025

# 2. Iniciar com Docker Compose
docker-compose up -d

# 3. Testar
curl http://localhost:3000/health
`

---

##  API Endpoints

### Health Check
`Bash
GET /health
# Resposta: { "status": "ok", "database": "connected" }
`

### Recebedores

**Listar todos:**
`Bash
GET /receivers
`

**Buscar por ID:**
`Bash
GET /receivers/:id
`

**Criar recebedor:**
`Bash
POST /receivers
Body: { "name": "João Silva" }
# Resposta: { "message": "Recebedor criado com sucesso!", "receiver": {...} }
`

### Operações

**Criar operação:**
`Bash
POST /operations
Body: { "receiver_id": 1, "gross_amount": 1000.00 }
# Resposta: { "message": "Operação criada com sucesso! Aguardando confirmação.", ... }
# Calcula automaticamente: fee = 30.00, net_amount = 970.00
`

**Confirmar operação:**
`Bash
POST /operations/:id/confirm
# Resposta: { "message": "Operação confirmada com sucesso! O saldo foi atualizado.", ... }
# Credita R$ 970,00 no saldo do recebedor
`

**Buscar operação:**
`Bash
GET /operations/:id
`

### Exemplo Completo (PowerShell)

`powershell
# Criar recebedor
 = @{ name = "João Silva" } | ConvertTo-Json
 = Invoke-RestMethod http://localhost:3000/receivers -Method Post -Body  -ContentType "application/json"

# Criar operação
 = @{ receiver_id = .receiver.id; gross_amount = 1000.00 } | ConvertTo-Json
 = Invoke-RestMethod http://localhost:3000/operations -Method Post -Body  -ContentType "application/json"

# Confirmar
Invoke-RestMethod "http://localhost:3000/operations//confirm" -Method Post

# Ver saldo (deve mostrar R$ 970,00)
Invoke-RestMethod "http://localhost:3000/receivers/"
`

---

##  Deploy na AWS

### Pré-requisitos
- AWS CLI configurado
- Terraform instalado
- Docker instalado

---

##  Estrutura

`
summer-tech-challenge-2025/
 app.js                  # Express app
 database.js             # PostgreSQL connection
 routes/
    receivers.js       # Endpoints recebedores
    operations.js      # Endpoints operações
 infra/                 # Terraform (42 recursos AWS)
 docker-compose.yml     # Ambiente local
 Dockerfile             # Imagem Docker
 package.json           # Dependências
`

---

##  Contato

**Desenvolvido por:** [Enzo Urioste Canavero]

-  [ecanavero2@gmail.com]
-  [+55(11)99496-0323]

---

<div align="center">

** Feito com dedicação para o LocPay Summer Job 2025**

</div>