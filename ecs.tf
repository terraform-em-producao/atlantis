resource "aws_ecs_cluster" "atlantis" {
  name = "atlantis"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "atlantis" {
  name              = "/ecs/atlantis"
  retention_in_days = 30
}

locals {
  segredo = aws_secretsmanager_secret.atlantis.arn

  # Clona as policies numa tag fixa e só então sobe o Atlantis.
  # Se a tag não existir, o container nem sobe — falha cedo e visível.
  comando = join(" && ", [
    "git clone --quiet --depth 1 --branch ${var.policies_ref} https://github.com/${var.github_org}/policies.git /home/atlantis/policies",
    "exec atlantis server",
  ])

  ambiente = {
    ATLANTIS_ATLANTIS_URL             = local.url
    ATLANTIS_PORT                     = "4141"
    ATLANTIS_DATA_DIR                 = "/atlantis-data"
    ATLANTIS_REPO_ALLOWLIST           = join(",", [for r in var.repos_gerenciados : "github.com/${var.github_org}/${r}"])
    ATLANTIS_SILENCE_ALLOWLIST_ERRORS = "true" # app instalado na org toda: ignora repos fora da lista sem comentar
    ATLANTIS_REPO_CONFIG_JSON         = jsonencode(local.repos_config)
    ATLANTIS_GH_APP_SLUG              = var.github_app_slug
    ATLANTIS_WRITE_GIT_CREDS          = "true"
    ATLANTIS_DEFAULT_TF_VERSION       = var.terraform_version
    ATLANTIS_ENABLE_POLICY_CHECKS     = "true"
    ATLANTIS_CHECKOUT_STRATEGY        = "merge"
    ATLANTIS_HIDE_PREV_PLAN_COMMENTS  = "true"
    ATLANTIS_EMOJI_REACTION           = "eyes"
    ATLANTIS_WEB_BASIC_AUTH           = "true"
    ATLANTIS_WEB_USERNAME             = "admin"
    AWS_REGION                        = var.regiao
  }

  segredos = {
    ATLANTIS_GH_APP_ID         = "${local.segredo}:app_id::"
    ATLANTIS_GH_APP_KEY        = "${local.segredo}:private_key::"
    ATLANTIS_GH_WEBHOOK_SECRET = "${local.segredo}:webhook_secret::"
    ATLANTIS_WEB_PASSWORD      = "${local.segredo}:web_password::"
  }
}

resource "aws_ecs_task_definition" "atlantis" {
  family                   = "atlantis"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memoria
  execution_role_arn       = aws_iam_role.execucao.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  volume {
    name = "dados"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.atlantis.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.atlantis.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([{
    name      = "atlantis"
    image     = var.atlantis_image
    essential = true
    command   = ["sh", "-c", local.comando]

    portMappings = [{ containerPort = 4141, protocol = "tcp" }]

    environment = [for k, v in local.ambiente : { name = k, value = v }]
    secrets     = [for k, v in local.segredos : { name = k, valueFrom = v }]

    mountPoints = [{ sourceVolume = "dados", containerPath = "/atlantis-data" }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.atlantis.name
        awslogs-region        = var.regiao
        awslogs-stream-prefix = "atlantis"
      }
    }
  }])
}

resource "aws_ecs_service" "atlantis" {
  name            = "atlantis"
  cluster         = aws_ecs_cluster.atlantis.id
  task_definition = aws_ecs_task_definition.atlantis.arn
  launch_type     = "FARGATE"

  # Exatamente UMA task: o Atlantis guarda lock em disco local (BoltDB).
  # Duas tasks = dois bancos de lock = dois applies no mesmo state.
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  health_check_grace_period_seconds = 60
  enable_execute_command            = false

  network_configuration {
    subnets          = aws_subnet.publica[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.atlantis.arn
    container_name   = "atlantis"
    container_port   = 4141
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.https, aws_efs_mount_target.atlantis]
}
