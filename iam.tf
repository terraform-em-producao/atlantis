data "aws_caller_identity" "atual" {}

data "aws_kms_alias" "state" {
  name = "alias/terraform-state"
}

locals {
  conta        = data.aws_caller_identity.atual.account_id
  bucket_state = "terraform-em-producao-tfstate-${local.conta}"
}

data "aws_iam_policy_document" "confia_ecs" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ecs:${var.regiao}:${local.conta}:*"]
    }
  }
}

# ---------------------------------------------------------------------------
# Execution role: usada pelo ECS para baixar imagem, escrever log e
# injetar o segredo. O processo do Atlantis não tem acesso a ela.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "execucao" {
  name               = "atlantis-execucao"
  assume_role_policy = data.aws_iam_policy_document.confia_ecs.json
}

resource "aws_iam_role_policy_attachment" "execucao" {
  role       = aws_iam_role.execucao.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execucao_segredo" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.atlantis.arn]
  }
}

resource "aws_iam_role_policy" "execucao_segredo" {
  name   = "le-segredo-atlantis"
  role   = aws_iam_role.execucao.id
  policy = data.aws_iam_policy_document.execucao_segredo.json
}

# ---------------------------------------------------------------------------
# Task role: a identidade do Atlantis. Quase nada direto — só state e
# sts:AssumeRole nas roles terraform-exec-* criadas no bootstrap.
# O nome é fixo porque o bootstrap confia nele por aws:PrincipalArn.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  name               = "atlantis-task"
  assume_role_policy = data.aws_iam_policy_document.confia_ecs.json
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "AssumeRolesDeExecucao"
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = ["arn:aws:iam::${local.conta}:role/terraform-exec-*"]
  }

  statement {
    sid       = "ListaState"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.bucket_state}"]
  }

  # O state do bootstrap e do próprio atlantis ficam de fora.
  statement {
    sid     = "LeEscreveState"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "arn:aws:s3:::${local.bucket_state}/groundwork/*",
      "arn:aws:s3:::${local.bucket_state}/infra-live/*",
    ]
  }

  statement {
    sid       = "KmsDoState"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [data.aws_kms_alias.state.target_key_arn]
  }

  statement {
    sid       = "MontaEfs"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    resources = [aws_efs_file_system.atlantis.arn]

    condition {
      test     = "StringEquals"
      variable = "elasticfilesystem:AccessPointArn"
      values   = [aws_efs_access_point.atlantis.arn]
    }
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "atlantis"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}
