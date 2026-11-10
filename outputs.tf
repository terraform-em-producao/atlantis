output "url" {
  value = local.url
}

output "webhook_url" {
  value = "${local.url}/events"
}

output "segredo_arn" {
  value = aws_secretsmanager_secret.atlantis.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}
