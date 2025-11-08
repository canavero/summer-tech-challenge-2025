terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr
  azs              = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets   = ["10.0.11.0/24", "10.0.12.0/24"]
  database_subnets = ["10.0.21.0/24", "10.0.22.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true
  create_database_subnet_group = true
  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-ecs-sg"
  description = "Security group for ECS"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}-ecs-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"
  identifier               = "${var.project_name}-db"
  engine                   = "postgres"
  engine_version           = "15"
  family                   = "postgres15"
  major_engine_version     = "15"
  instance_class           = "db.t3.micro"
  allocated_storage        = 20
  max_allocated_storage    = 100
  storage_encrypted        = true
  db_name                  = var.db_name
  username                 = var.db_username
  password                 = var.db_password
  port                     = 5432
  multi_az                 = false
  db_subnet_group_name     = module.vpc.database_subnet_group_name
  vpc_security_group_ids   = [aws_security_group.rds.id]
  backup_retention_period  = 7
  skip_final_snapshot      = true
  deletion_protection      = false
  publicly_accessible      = false
  tags = {
    Name = "${var.project_name}-db"
  }
}

resource "aws_secretsmanager_secret" "db_connection" {
  name                    = "${var.project_name}-db-connection"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_connection" {
  secret_id = aws_secretsmanager_secret.db_connection.id
  secret_string = jsonencode({
    DB_HOST     = module.rds.db_instance_address
    DB_PORT     = "5432"
    DB_NAME     = var.db_name
    DB_USER     = var.db_username
    DB_PASSWORD = var.db_password
  })
}

resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecs-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_secrets" {
  name = "${var.project_name}-secrets"
  role = aws_iam_role.ecs_task_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = aws_secretsmanager_secret.db_connection.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.project_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([{
    name      = var.project_name
    image     = "${aws_ecr_repository.app.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]
    environment = [{
      name  = "NODE_ENV"
      value = "production"
    }, {
      name  = "PORT"
      value = "3000"
    }]
    secrets = [{
      name      = "DB_HOST"
      valueFrom = "${aws_secretsmanager_secret.db_connection.arn}:DB_HOST::"
    }, {
      name      = "DB_PORT"
      valueFrom = "${aws_secretsmanager_secret.db_connection.arn}:DB_PORT::"
    }, {
      name      = "DB_NAME"
      valueFrom = "${aws_secretsmanager_secret.db_connection.arn}:DB_NAME::"
    }, {
      name      = "DB_USER"
      valueFrom = "${aws_secretsmanager_secret.db_connection.arn}:DB_USER::"
    }, {
      name      = "DB_PASSWORD"
      valueFrom = "${aws_secretsmanager_secret.db_connection.arn}:DB_PASSWORD::"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  network_configuration {
    security_groups  = [aws_security_group.ecs.id]
    subnets          = module.vpc.private_subnets
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.project_name
    container_port   = 3000
  }
  depends_on = [aws_lb_listener.http]
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "app_url" {
  value = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "rds_endpoint" {
  value = module.rds.db_instance_endpoint
}
