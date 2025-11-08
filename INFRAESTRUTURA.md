# 📋 Documentação da Infraestrutura LocPay

## 🎯 Visão Geral

Este documento descreve toda a infraestrutura AWS configurada via Terraform para a API LocPay, incluindo o backend (aplicação Node.js + PostgreSQL) e todos os serviços de suporte.

---

## 🏗️ Arquitetura Completa

### Diagrama Lógico
```
Internet
    ↓
Application Load Balancer (HTTP:80)
    ↓
ECS Fargate Cluster
    ↓
Container Node.js (porta 3000)
    ↓
RDS PostgreSQL (porta 5432)
```

---

## 📦 Componentes da Infraestrutura

### 1. **Rede (VPC)**
- **Recurso**: VPC customizada com CIDR `10.0.0.0/16`
- **Availability Zones**: 2 AZs (sa-east-1a, sa-east-1b)
- **Subnets**:
  - **Públicas** (2): `10.0.11.0/24`, `10.0.12.0/24` - Para ALB
  - **Privadas** (2): `10.0.1.0/24`, `10.0.2.0/24` - Para ECS Tasks
  - **Database** (2): `10.0.21.0/24`, `10.0.22.0/24` - Para RDS
- **Internet Gateway**: Permite acesso à internet para subnets públicas
- **NAT Gateway**: Permite que containers privados acessem a internet (1 único para economia)
- **Route Tables**: Rotas configuradas para públicas e privadas

### 2. **Security Groups**

#### ALB Security Group (`locpay-alb-sg`)
- **Inbound**: 
  - HTTP (porta 80) de qualquer origem (0.0.0.0/0)
- **Outbound**: Todo tráfego permitido

#### ECS Security Group (`locpay-ecs-sg`)
- **Inbound**: 
  - Porta 3000 (HTTP) apenas do ALB Security Group
- **Outbound**: Todo tráfego permitido

#### RDS Security Group (`locpay-rds-sg`)
- **Inbound**: 
  - PostgreSQL (porta 5432) apenas do ECS Security Group
- **Outbound**: Todo tráfego permitido

### 3. **Banco de Dados (RDS PostgreSQL)**
- **Engine**: PostgreSQL 15.4
- **Classe da Instância**: `db.t3.micro` (Free Tier eligible)
- **Storage**: 
  - Inicial: 20 GB
  - Máximo: 100 GB (auto-scaling)
  - Tipo: Encrypted (Storage Encrypted = true)
- **Multi-AZ**: Desabilitado (economia)
- **Backup**:
  - Retenção: 7 dias
  - Janela de backup: 03:00-06:00 UTC
  - Janela de manutenção: Segunda 00:00-03:00 UTC
- **Database Name**: `locpay`
- **Username**: `postgres`
- **Password**: Definido em `terraform.tfvars`
- **Acesso Público**: Desabilitado (segurança)
- **Logs**: PostgreSQL e upgrade logs exportados para CloudWatch

### 4. **Secrets Manager**
- **Secret Name**: `locpay-db-connection`
- **Conteúdo** (JSON):
  ```json
  {
    "DB_HOST": "<RDS_ENDPOINT>",
    "DB_PORT": "5432",
    "DB_NAME": "locpay",
    "DB_USER": "postgres",
    "DB_PASSWORD": "<SENHA>"
  }
  ```
- **Uso**: ECS Tasks leem essas credenciais de forma segura

### 5. **Container Registry (ECR)**
- **Repository Name**: `locpay`
- **Image Tag Mutability**: MUTABLE (permite sobrescrever tags)
- **Scan on Push**: Habilitado (verifica vulnerabilidades)
- **Lifecycle Policy**:
  - Mantém últimas 10 imagens com tag
  - Remove imagens sem tag após 1 dia

### 6. **IAM Roles**

#### ECS Task Execution Role (`locpay-ecs-execution`)
- **Propósito**: Usado pelo ECS Agent para iniciar containers
- **Permissões**:
  - Ler segredos do Secrets Manager
  - Pull de imagens do ECR
  - Escrever logs no CloudWatch
- **Policies**:
  - `AmazonECSTaskExecutionRolePolicy` (AWS Managed)
  - Policy customizada para acesso ao secret específico

#### ECS Task Role (se necessário no futuro)
- **Propósito**: Permissões que a aplicação em execução precisa
- **Nota**: Atualmente não usado, mas preparado para expansão

### 7. **CloudWatch Logs**
- **Log Group**: `/ecs/locpay`
- **Retenção**: 7 dias
- **Uso**: Todos os logs da aplicação Node.js são enviados aqui

### 8. **ECS (Elastic Container Service)**

#### Cluster
- **Nome**: `locpay-cluster`
- **Tipo**: Fargate (serverless)
- **Container Insights**: Habilitado (métricas detalhadas)

#### Task Definition
- **Family**: `locpay`
- **Launch Type**: FARGATE
- **CPU**: 512 (0.5 vCPU)
- **Memory**: 1024 MB (1 GB)
- **Network Mode**: `awsvpc` (cada task tem ENI própria)
- **Container**:
  - Nome: `locpay`
  - Imagem: `<ECR_URL>:latest`
  - Porta: 3000
  - **Variáveis de Ambiente**:
    - `NODE_ENV=production`
    - `PORT=3000`
  - **Secrets** (do Secrets Manager):
    - `DB_HOST`
    - `DB_PORT`
    - `DB_NAME`
    - `DB_USER`
    - `DB_PASSWORD`
  - **Health Check**:
    - Command: `curl -f http://localhost:3000/health || exit 1`
    - Intervalo: 30s
    - Timeout: 5s
    - Retries: 3
    - Start Period: 60s
  - **Logs**: Enviados para CloudWatch Log Group

#### Service
- **Nome**: `locpay-service`
- **Desired Count**: 2 containers
- **Load Balancer**: Integrado com ALB Target Group
- **Network**:
  - Subnets: Privadas
  - Security Group: ECS SG
  - Public IP: Desabilitado
- **Deployment**:
  - Max Healthy: 200%
  - Min Healthy: 100%

### 9. **Application Load Balancer (ALB)**

#### Load Balancer
- **Nome**: `locpay-alb`
- **Tipo**: Application Load Balancer
- **Scheme**: Internet-facing
- **Subnets**: Públicas (2 AZs)
- **Security Group**: ALB SG
- **HTTP/2**: Habilitado

#### Target Group
- **Nome**: `locpay-tg`
- **Porta**: 3000
- **Protocolo**: HTTP
- **Target Type**: IP (para Fargate)
- **VPC**: locpay-vpc
- **Health Check**:
  - Path: `/health`
  - Healthy Threshold: 2 checks
  - Unhealthy Threshold: 3 checks
  - Timeout: 5s
  - Intervalo: 30s
  - Matcher: HTTP 200

#### Listener
- **Porta**: 80
- **Protocolo**: HTTP
- **Ação**: Forward para Target Group
- **Nota**: SEM HTTPS/SSL (não há certificado ou domínio configurado)

---

## 🔧 Backend (Aplicação)

### Tecnologia
- **Runtime**: Node.js 18 (Alpine Linux)
- **Framework**: Express.js
- **Database Client**: `pg` (node-postgres)
- **Port**: 3000

### Arquitetura do Código
```
app.js                  # Entry point da aplicação
├── database.js         # Pool de conexão PostgreSQL
└── routes/
    ├── index.js        # Health check endpoint
    ├── receivers.js    # CRUD de recebedores
    └── operations.js   # CRUD de operações
```

### Endpoints da API

#### Health Check
- `GET /health` - Retorna status da API e conexão com DB

#### Receivers (Recebedores)
- `GET /receivers` - Lista todos os recebedores
- `GET /receivers/:id` - Busca recebedor por ID
- `POST /receivers` - Cria novo recebedor
- `PUT /receivers/:id` - Atualiza recebedor
- `DELETE /receivers/:id` - Remove recebedor

#### Operations (Operações)
- `GET /operations` - Lista todas as operações
- `GET /operations/:id` - Busca operação por ID
- `POST /operations` - Cria nova operação
- `PUT /operations/:id` - Atualiza operação
- `DELETE /operations/:id` - Remove operação

### Configuração via Variáveis de Ambiente
```bash
NODE_ENV=production
PORT=3000
DB_HOST=<obtido do Secrets Manager>
DB_PORT=5432
DB_NAME=locpay
DB_USER=postgres
DB_PASSWORD=<obtido do Secrets Manager>
```

### Dockerfile
```dockerfile
FROM node:18-alpine
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
CMD ["node", "bin/www"]
```

---

## 📊 Recursos Totais Criados

Quando você executar `terraform apply`, serão criados **42 recursos**:

- 1 VPC
- 6 Subnets (2 públicas, 2 privadas, 2 database)
- 3 Security Groups
- 1 Internet Gateway
- 1 NAT Gateway
- 1 Elastic IP (para NAT)
- 6 Route Tables e Associations
- 1 RDS PostgreSQL Instance
- 1 DB Parameter Group
- 1 DB Subnet Group
- 1 Secrets Manager Secret + Version
- 1 ECR Repository + Lifecycle Policy
- 1 CloudWatch Log Group
- 1 ECS Cluster
- 1 ECS Task Definition
- 1 ECS Service
- 2 IAM Roles (Execution + Task)
- 2 IAM Policies
- 1 Application Load Balancer
- 1 Target Group
- 1 Listener HTTP

---

## 💰 Estimativa de Custos (sa-east-1)

### Custos Mensais Estimados:
- **ECS Fargate** (2 tasks, 0.5 vCPU, 1GB): ~$30-35/mês
- **RDS db.t3.micro**: ~$15-20/mês
- **ALB**: ~$20-25/mês (inclui LCU)
- **NAT Gateway**: ~$35-40/mês (mais tráfego)
- **Secrets Manager**: ~$0.40/mês
- **ECR Storage**: ~$1/mês (depende do tamanho)
- **CloudWatch Logs**: ~$1-2/mês (depende do volume)
- **Data Transfer**: Variável

**Total Estimado**: ~$105-125/mês

### Free Tier (12 meses):
- RDS: 750 horas/mês de db.t3.micro
- NAT Gateway: Não tem free tier ⚠️

---

## 🔒 Segurança

### Princípios Aplicados:
1. **Isolamento de Rede**: ECS e RDS em subnets privadas
2. **Least Privilege**: Security Groups com regras mínimas necessárias
3. **Secrets Management**: Credenciais no Secrets Manager, não em código
4. **Encryption at Rest**: RDS com storage encrypted
5. **Encryption in Transit**: Comunicação ECS ↔ RDS usa SSL
6. **No Public Access**: RDS não acessível da internet
7. **Container Scanning**: ECR escaneia imagens automaticamente

### Melhorias Futuras:
- [ ] Implementar WAF no ALB
- [ ] Adicionar HTTPS com ACM Certificate
- [ ] Configurar IAM Database Authentication
- [ ] Implementar VPC Flow Logs
- [ ] Adicionar GuardDuty

---

## 📈 Observabilidade

### Logs
- **CloudWatch Logs**: Todos os logs da aplicação
- **RDS Logs**: PostgreSQL logs e upgrade logs

### Métricas (CloudWatch)
- ECS Container Insights (CPU, Memory, Network)
- RDS Metrics (Connections, CPU, Storage)
- ALB Metrics (Request Count, Latency, Target Health)

### Comandos Úteis:
```bash
# Ver logs do ECS em tempo real
aws logs tail /ecs/locpay --follow --region sa-east-1

# Ver métricas de CPU do ECS
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=locpay-cluster \
  --start-time 2025-11-07T00:00:00Z \
  --end-time 2025-11-07T23:59:59Z \
  --period 3600 \
  --statistics Average
```

---

## 🔄 Fluxo de Deploy

### Primeira Implantação:
1. `terraform init` - Inicializa providers e módulos
2. `terraform plan` - Visualiza mudanças
3. `terraform apply` - Cria infraestrutura (~10-15 min)
4. `docker build` - Constrói imagem da aplicação
5. `docker tag` - Adiciona tag do ECR
6. `docker push` - Envia para ECR
7. ECS automaticamente faz pull e inicia containers

### Atualizações da Aplicação:
1. Modificar código
2. `docker build` - Nova imagem
3. `docker tag` - Tag `:latest` ou versão específica
4. `docker push` - Push para ECR
5. `aws ecs update-service --force-new-deployment` - Force redeploy
6. ECS faz rolling update (zero downtime)

---

## 🌐 Acesso à Aplicação

Após o deploy, a aplicação estará disponível em:
```
http://<ALB-DNS-NAME>
```

O DNS do ALB será exibido nos outputs do Terraform:
```bash
terraform output alb_dns_name
# Exemplo: locpay-alb-1234567890.sa-east-1.elb.amazonaws.com
```

**⚠️ IMPORTANTE**: Como não há domínio configurado, você usará o DNS fornecido pela AWS (formato longo). Se quiser um domínio personalizado, seria necessário:
1. Registrar domínio no Route53
2. Criar certificado SSL no ACM
3. Adicionar listener HTTPS no ALB
4. Criar record no Route53 apontando para o ALB

---

## 📝 Arquivos Terraform

### `main.tf`
Arquivo principal contendo todos os recursos da infraestrutura.

### `variables.tf`
Variáveis configuráveis:
- `aws_region` (default: sa-east-1)
- `project_name` (default: locpay)
- `vpc_cidr` (default: 10.0.0.0/16)
- `db_name` (default: locpay)
- `db_username` (default: postgres)
- `db_password` (OBRIGATÓRIO - definir em terraform.tfvars)
- `desired_count` (default: 2 tasks)

### `terraform.tfvars`
Valores das variáveis (criado localmente, não commitado):
```hcl
db_password = "SuaSenhaSegura123!"
```

---

## 🎓 Conceitos-Chave

### ECS Fargate vs EC2
- **Fargate**: Serverless, AWS gerencia infraestrutura, paga por uso
- **EC2**: Você gerencia instâncias, mais controle, pode ser mais barato em escala

### Task vs Service
- **Task**: Uma instância rodando do container
- **Service**: Gerencia múltiplas tasks, mantém desired count, integra com ALB

### Target Group vs Listener
- **Target Group**: Grupo de destinos (IPs, instâncias) que recebem tráfego
- **Listener**: Porta/protocolo que o ALB escuta, direciona para Target Groups

---

## 🚨 Troubleshooting

### Container não inicia
1. Verificar logs no CloudWatch
2. Verificar se imagem existe no ECR
3. Verificar IAM Role do Task Execution
4. Verificar se secrets existem no Secrets Manager

### Health Check falhando
1. Verificar se endpoint `/health` responde HTTP 200
2. Verificar Security Groups
3. Verificar se container está escutando na porta 3000
4. Ver logs do container no CloudWatch

### Não consigo acessar a aplicação
1. Verificar se ALB está "active"
2. Verificar se targets estão "healthy" no Target Group
3. Verificar Security Group do ALB (porta 80 aberta)
4. Verificar DNS do ALB nos outputs

---

**Documentação criada em**: 07/11/2025  
**Versão**: 1.0  
**Autor**: GitHub Copilot
