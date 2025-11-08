# Dockerfile para LocPay Tech Challenge
# Node.js 18 LTS com Alpine Linux (imagem leve)

FROM node:18-alpine

# Metadados
LABEL maintainer="LocPay Team"
LABEL description="API de antecipação de recebíveis - LocPay Summer Job 2025"

# Instalar dependências do sistema (para compilação de módulos nativos)
RUN apk add --no-cache \
    python3 \
    make \
    g++

# Diretório de trabalho dentro do container
WORKDIR /app

# Copiar arquivos de dependências
COPY package*.json ./

# Instalar dependências de produção
RUN npm ci --only=production

# Copiar código da aplicação
COPY . .

# Expor porta da aplicação
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Usuário não-root para segurança
USER node

# Comando para iniciar a aplicação
CMD ["node", "./bin/www"]
