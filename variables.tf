variable "regiao" {
  type    = string
  default = "us-east-1"
}

variable "github_org" {
  type    = string
  default = "terraform-em-producao"
}

variable "dominio" {
  description = "Zona criada no bootstrap."
  type        = string
  default     = "terraform.gomex.me"
}

variable "atlantis_image" {
  description = "Imagem pinada por versão. Atualizar = PR neste repo."
  type        = string
  default     = "ghcr.io/runatlantis/atlantis:v0.49.0"
}

variable "terraform_version" {
  description = "Versão padrão do Terraform no Atlantis (cada projeto pode pinar a sua no atlantis.yaml)."
  type        = string
  default     = "1.17.1"
}

variable "policies_ref" {
  description = "Tag do repo policies que o Atlantis usa."
  type        = string
  default     = "v1.0.0"
}

variable "github_app_slug" {
  description = "Slug do GitHub App (https://github.com/apps/<slug>)."
  type        = string
  default     = "atlantis-terraform-em-producao"
}

variable "repos_gerenciados" {
  description = "Únicos repos que o Atlantis atende. bootstrap e atlantis ficam de fora de propósito."
  type        = list(string)
  default     = ["groundwork", "infra-live"]
}

variable "donos_das_policies" {
  description = "Usuários do GitHub que podem rodar `atlantis approve_policies`."
  type        = list(string)
  default     = ["gomex"]
}

variable "cpu" {
  type    = number
  default = 1024
}

variable "memoria" {
  type    = number
  default = 2048
}
