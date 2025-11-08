variable "aws_region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "sa-east-1"
}

variable "project_name" {
  description = "Nome do projeto (usado como prefixo em recursos)"
  type        = string
  default     = "locpay"
}

variable "vpc_cidr" {
  description = "CIDR block para a VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_name" {
  description = "Nome do banco de dados PostgreSQL"
  type        = string
  default     = "locpay"
}

variable "db_username" {
  description = "Usuário master do banco de dados"
  type        = string
  default     = "locpayuser"
}

variable "db_password" {
  description = "Senha do usuário master do banco de dados"
  type        = string
  sensitive   = true
}

variable "desired_count" {
  description = "Número desejado de tasks ECS rodando"
  type        = number
  default     = 2
}
