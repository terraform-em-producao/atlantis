# ---------------------------------------------------------------------------
# Rede própria do Atlantis. De propósito NÃO usa a VPC do groundwork:
# o Atlantis aplica o groundwork, então não pode depender dele
# (senão um apply errado no groundwork derruba quem conserta o groundwork).
#
# Só subnets públicas e sem NAT Gateway para economizar (~US$ 32/mês por NAT).
# A task recebe IP público para sair para a internet, mas o security group
# só aceita entrada vinda do ALB.
# ---------------------------------------------------------------------------
data "aws_availability_zones" "disponiveis" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.disponiveis.names, 0, 2)
}

resource "aws_vpc" "atlantis" {
  cidr_block           = "10.250.0.0/24"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "atlantis" }
}

resource "aws_internet_gateway" "atlantis" {
  vpc_id = aws_vpc.atlantis.id

  tags = { Name = "atlantis" }
}

resource "aws_subnet" "publica" {
  count = length(local.azs)

  vpc_id            = aws_vpc.atlantis.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(aws_vpc.atlantis.cidr_block, 2, count.index)

  tags = { Name = "atlantis-publica-${local.azs[count.index]}" }
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.atlantis.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.atlantis.id
  }

  tags = { Name = "atlantis-publica" }
}

resource "aws_route_table_association" "publica" {
  count = length(aws_subnet.publica)

  subnet_id      = aws_subnet.publica[count.index].id
  route_table_id = aws_route_table.publica.id
}

# Default SG sem regra nenhuma: ninguém usa por acidente.
resource "aws_default_security_group" "atlantis" {
  vpc_id = aws_vpc.atlantis.id
}

resource "aws_security_group" "alb" {
  name        = "atlantis-alb"
  description = "Entrada HTTPS do Atlantis"
  vpc_id      = aws_vpc.atlantis.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "Webhooks do GitHub e UI"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Apenas redireciona para HTTPS"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_para_task" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.task.id
  from_port                    = 4141
  to_port                      = 4141
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "task" {
  name        = "atlantis-task"
  description = "Container do Atlantis"
  vpc_id      = aws_vpc.atlantis.id
}

resource "aws_vpc_security_group_ingress_rule" "task_do_alb" {
  security_group_id            = aws_security_group.task.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 4141
  to_port                      = 4141
  ip_protocol                  = "tcp"
}

# O Atlantis precisa sair para GitHub, registry do Terraform e APIs da AWS.
# Esses destinos não têm faixa de IP fixa, então a saída é aberta.
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "task_saida" {
  security_group_id = aws_security_group.task.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "efs" {
  name        = "atlantis-efs"
  description = "NFS do Atlantis"
  vpc_id      = aws_vpc.atlantis.id
}

resource "aws_vpc_security_group_ingress_rule" "efs_da_task" {
  security_group_id            = aws_security_group.efs.id
  referenced_security_group_id = aws_security_group.task.id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
}
