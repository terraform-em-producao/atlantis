# O Terraform cria só o "cofre". O valor é gravado fora do Terraform
# (aws secretsmanager put-secret-value), então a chave do GitHub App
# nunca aparece no state nem no plan. Veja o README.
resource "aws_secretsmanager_secret" "atlantis" {
  name        = "atlantis/github-app"
  description = "app_id, private_key, webhook_secret e web_password do Atlantis"

  recovery_window_in_days = 7
}
