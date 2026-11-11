# ---------------------------------------------------------------------------
# Configuração server-side: as regras que NENHUM repo consegue afrouxar.
# O atlantis.yaml de cada repo só escolhe projetos/diretórios; quem decide
# o que é exigido antes do apply é este arquivo, que passa por PR e deploy.
# ---------------------------------------------------------------------------
locals {
  repos_config = {
    repos = [{
      id     = "/.*/"
      branch = "/^main$/"

      # mergeable:  o PR não tem conflito com a main
      # undiverged: a branch está em dia com a main (o plan reflete a main atual)
      plan_requirements   = ["undiverged"]
      apply_requirements  = ["mergeable", "undiverged"]
      import_requirements = ["mergeable", "undiverged"]

      workflow               = "padrao"
      allow_custom_workflows = false
      allowed_overrides      = ["delete_source_branch_on_merge"]

      policy_check                  = true
      delete_source_branch_on_merge = true
    }]

    workflows = {
      padrao = {
        plan = {
          steps = [
            "init",
            { plan = { extra_args = ["-lock-timeout=5m"] } },
          ]
        }
        policy_check = {
          steps = ["show", "policy_check"]
        }
        apply = {
          steps = [{ apply = { extra_args = ["-lock-timeout=5m"] } }]
        }
      }
    }

    policies = {
      owners = {
        users = var.donos_das_policies
      }
      policy_sets = [{
        name   = "padroes-da-org"
        path   = "/home/atlantis/policies/policy"
        source = "local"
      }]
    }
  }
}
