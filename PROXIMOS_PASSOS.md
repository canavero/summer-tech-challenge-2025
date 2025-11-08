# 🚀 Próximos Passos - Deploy da Aplicação LocPay

Este documento contém **TODOS OS COMANDOS** que você precisa executar para fazer o deploy completo da sua aplicação na AWS.

---

## ✅ Status Atual

- [x] Código da aplicação migrado de SQLite para PostgreSQL
- [x] Dockerfile criado e testado
- [x] Docker Compose testado localmente
- [x] Infraestrutura Terraform configurada (sem Route53/ACM)
- [x] `terraform plan` executado com sucesso (42 recursos)
- [ ] **VOCÊ ESTÁ AQUI** → Aplicar infraestrutura na AWS

---

## 📋 Passo a Passo Completo

### **PASSO 1: Aplicar a Infraestrutura AWS** ⏱️ ~10-15 minutos

```powershell
# 1. Navegue para o diretório infra
cd C:\Users\enzou\case_locpay\summer-tech-challenge-2025\infra

# 2. Execute o terraform apply (vai pedir confirmação)
terraform apply

# Quando perguntar "Do you want to perform these actions?", digite: yes
```

**O que acontece neste passo:**
- Cria VPC com subnets públicas, privadas e de database
- Cria Security Groups (ALB, ECS, RDS)
- Cria RDS PostgreSQL (pode demorar ~5 minutos)
- Cria ECR (Container Registry)
- Cria ECS Cluster, Task Definition e Service
- Cria Application Load Balancer
- Cria Secrets Manager com credenciais do banco
- Cria CloudWatch Log Group
- Cria IAM Roles necessárias

**⚠️ IMPORTANTE**: Anote os outputs que aparecerem no final:
```
alb_dns_name = "locpay-alb-XXXXXXXXX.sa-east-1.elb.amazonaws.com"
app_url = "http://locpay-alb-XXXXXXXXX.sa-east-1.elb.amazonaws.com"
ecr_repository_url = "007323391898.dkr.ecr.sa-east-1.amazonaws.com/locpay"
rds_endpoint = "locpay-db.XXXXXXXXX.sa-east-1.rds.amazonaws.com:5432"
```

---

### **PASSO 2: Build e Push da Imagem Docker** ⏱️ ~5 minutos

```powershell
# 1. Volte para o diretório raiz do projeto
cd C:\Users\enzou\case_locpay\summer-tech-challenge-2025

# 2. Faça login no ECR (copie o comando EXATO do output anterior)
aws ecr get-login-password --region sa-east-1 | docker login --username AWS --password-stdin 007323391898.dkr.ecr.sa-east-1.amazonaws.com

# 3. Build da imagem Docker
docker build -t locpay-api .

# 4. Tag da imagem com o URL do ECR
docker tag locpay-api:latest 007323391898.dkr.ecr.sa-east-1.amazonaws.com/locpay:latest

# 5. Push da imagem para o ECR
docker push 007323391898.dkr.ecr.sa-east-1.amazonaws.com/locpay:latest
```

**O que acontece neste passo:**
- Constrói a imagem Docker da sua aplicação Node.js
- Faz upload da imagem para o ECR na AWS
- ECS será capaz de fazer pull dessa imagem para rodar os containers

---

### **PASSO 3: Forçar Deploy no ECS** ⏱️ ~2 minutos

```powershell
# Force o ECS a atualizar o serviço com a nova imagem
aws ecs update-service `
  --cluster locpay-cluster `
  --service locpay-service `
  --force-new-deployment `
  --region sa-east-1
```

**O que acontece neste passo:**
- ECS para os containers antigos
- Faz pull da nova imagem do ECR
- Inicia 2 novos containers
- Registra os containers no Target Group do ALB
- Health check valida que os containers estão saudáveis

---

### **PASSO 4: Aguardar Deploy e Verificar Status** ⏱️ ~3-5 minutos

```powershell
# Verificar status do serviço ECS
aws ecs describe-services `
  --cluster locpay-cluster `
  --services locpay-service `
  --region sa-east-1 `
  --query 'services[0].deployments'

# Verificar health dos targets no ALB
aws elbv2 describe-target-health `
  --target-group-arn $(aws elbv2 describe-target-groups --names locpay-tg --region sa-east-1 --query 'TargetGroups[0].TargetGroupArn' --output text) `
  --region sa-east-1
```

**Aguarde até que:**
- `runningCount` seja igual a `desiredCount` (2)
- Targets estejam com status `healthy`

---

### **PASSO 5: Testar a Aplicação** ⏱️ ~1 minuto

```powershell
# Obter o DNS do ALB (se você não anotou)
terraform output -raw alb_dns_name

# Testar o endpoint de health
curl http://<ALB-DNS>/health

# Ou no PowerShell:
Invoke-WebRequest -Uri "http://<ALB-DNS>/health" -Method GET

# Testar endpoint de receivers
curl http://<ALB-DNS>/receivers

# Criar um receiver de teste
curl -X POST http://<ALB-DNS>/receivers `
  -H "Content-Type: application/json" `
  -d '{"name":"João Silva","document":"12345678900","email":"joao@example.com"}'
```

**Resposta esperada do /health:**
```json
{
  "status": "ok",
  "database": "connected",
  "timestamp": "2025-11-07T..."
}
```

---

## 🔍 Comandos de Monitoramento

### Ver logs da aplicação em tempo real:
```powershell
aws logs tail /ecs/locpay --follow --region sa-east-1
```

### Ver logs das últimas 10 linhas:
```powershell
aws logs tail /ecs/locpay --since 10m --region sa-east-1
```

### Ver status dos containers ECS:
```powershell
aws ecs list-tasks `
  --cluster locpay-cluster `
  --service-name locpay-service `
  --region sa-east-1

# Para ver detalhes de uma task específica:
aws ecs describe-tasks `
  --cluster locpay-cluster `
  --tasks <TASK-ARN> `
  --region sa-east-1
```

### Ver métricas do RDS:
```powershell
aws cloudwatch get-metric-statistics `
  --namespace AWS/RDS `
  --metric-name DatabaseConnections `
  --dimensions Name=DBInstanceIdentifier,Value=locpay-db `
  --start-time (Get-Date).AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ss") `
  --end-time (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss") `
  --period 300 `
  --statistics Average `
  --region sa-east-1
```

---

## 🐛 Troubleshooting

### Problema: Containers não ficam healthy

**Solução:**
```powershell
# 1. Ver logs do container
aws logs tail /ecs/locpay --since 30m --region sa-east-1

# 2. Verificar se o endpoint /health responde
# Conecte via Session Manager ou veja logs

# 3. Verificar secrets
aws secretsmanager get-secret-value `
  --secret-id locpay-db-connection `
  --region sa-east-1

# 4. Verificar Security Groups
aws ec2 describe-security-groups `
  --filters "Name=group-name,Values=locpay-*" `
  --region sa-east-1
```

### Problema: "Error: authorization token has expired"

**Solução:**
```powershell
# Fazer login novamente no ECR
aws ecr get-login-password --region sa-east-1 | docker login --username AWS --password-stdin 007323391898.dkr.ecr.sa-east-1.amazonaws.com
```

### Problema: Terraform apply falha

**Solução:**
```powershell
# Ver detalhes do erro
terraform plan

# Se for problema de recursos existentes, importar:
terraform import aws_ecr_repository.app locpay

# Se for problema de state, fazer refresh:
terraform refresh
```

### Problema: Não consigo acessar o ALB

**Checklist:**
1. ✅ ALB está "active"? → `aws elbv2 describe-load-balancers --names locpay-alb`
2. ✅ Targets estão "healthy"? → Ver comando no Passo 4
3. ✅ Security Group do ALB permite porta 80? → Ver no Console AWS
4. ✅ Você está usando HTTP (não HTTPS)?

---

## 🔄 Como Atualizar a Aplicação no Futuro

Sempre que você modificar o código da aplicação:

```powershell
# 1. Volte para o diretório raiz
cd C:\Users\enzou\case_locpay\summer-tech-challenge-2025

# 2. Build da nova versão
docker build -t locpay-api .

# 3. Tag com :latest
docker tag locpay-api:latest 007323391898.dkr.ecr.sa-east-1.amazonaws.com/locpay:latest

# 4. Push para ECR
docker push 007323391898.dkr.ecr.sa-east-1.amazonaws.com/locpay:latest

# 5. Force deploy no ECS
aws ecs update-service `
  --cluster locpay-cluster `
  --service locpay-service `
  --force-new-deployment `
  --region sa-east-1

# 6. Aguarde alguns minutos e teste
aws logs tail /ecs/locpay --follow --region sa-east-1
```

---

## 💰 Como Monitorar Custos

```powershell
# Ver custos do mês atual
aws ce get-cost-and-usage `
  --time-period Start=2025-11-01,End=2025-11-30 `
  --granularity MONTHLY `
  --metrics "UnblendedCost" `
  --group-by Type=DIMENSION,Key=SERVICE

# Ver custos por tag (se você tagear recursos)
aws ce get-cost-and-usage `
  --time-period Start=2025-11-01,End=2025-11-30 `
  --granularity MONTHLY `
  --metrics "UnblendedCost" `
  --group-by Type=TAG,Key=Project
```

---

## 🗑️ Como Destruir Tudo (Quando Terminar os Testes)

**⚠️ CUIDADO**: Isso vai apagar TODA a infraestrutura!

```powershell
# 1. Navegar para infra
cd C:\Users\enzou\case_locpay\summer-tech-challenge-2025\infra

# 2. Destruir recursos
terraform destroy

# Quando perguntar, digite: yes
```

**Nota**: O Secrets Manager tem um período de recuperação de 0 dias (configurado), então será deletado imediatamente.

---

## 📊 Checklist Final

Após executar todos os passos, você deve ter:

- [ ] Infraestrutura criada na AWS (42 recursos)
- [ ] Imagem Docker no ECR
- [ ] 2 containers rodando no ECS
- [ ] Targets "healthy" no ALB
- [ ] Aplicação acessível via HTTP no DNS do ALB
- [ ] Endpoint `/health` retornando status OK
- [ ] Endpoints `/receivers` e `/operations` funcionando
- [ ] Logs aparecendo no CloudWatch

---

## 📞 Comandos Rápidos de Referência

```powershell
# Status do ECS Service
aws ecs describe-services --cluster locpay-cluster --services locpay-service --region sa-east-1

# DNS do ALB
terraform output alb_dns_name

# Logs em tempo real
aws logs tail /ecs/locpay --follow --region sa-east-1

# Health dos targets
aws elbv2 describe-target-health --target-group-arn <ARN> --region sa-east-1

# Force redeploy
aws ecs update-service --cluster locpay-cluster --service locpay-service --force-new-deployment --region sa-east-1

# Login no ECR
aws ecr get-login-password --region sa-east-1 | docker login --username AWS --password-stdin 007323391898.dkr.ecr.sa-east-1.amazonaws.com
```

---

## 🎯 Resumo dos Tempos

| Passo | Ação | Tempo Estimado |
|-------|------|----------------|
| 1 | Terraform Apply | 10-15 min |
| 2 | Build + Push Docker | 5 min |
| 3 | Force Deploy ECS | 2 min |
| 4 | Aguardar Deploy | 3-5 min |
| 5 | Testes | 1 min |
| **TOTAL** | - | **~25-30 min** |

---

## 🎉 Próximas Melhorias (Opcional)

Depois que tudo estiver funcionando:

1. **Adicionar HTTPS**:
   - Registrar domínio no Route53
   - Criar certificado SSL no ACM
   - Adicionar listener HTTPS no ALB
   - Redirecionar HTTP → HTTPS

2. **CI/CD**:
   - Configurar GitHub Actions
   - Automatizar build e deploy
   - Testes automatizados

3. **Banco de Dados**:
   - Habilitar Multi-AZ para alta disponibilidade
   - Configurar Read Replicas
   - Implementar backups automáticos para S3

4. **Segurança**:
   - Adicionar WAF no ALB
   - Configurar CloudTrail
   - Implementar GuardDuty
   - Escanear vulnerabilidades com Inspector

5. **Observabilidade**:
   - Configurar alarmes no CloudWatch
   - Criar dashboard personalizado
   - Integrar com ferramentas de APM

---

**Boa sorte com o deploy! 🚀**

**Criado em**: 07/11/2025  
**Versão**: 1.0
