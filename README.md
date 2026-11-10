# atlantis

O runtime do Terraform da org: [Atlantis](https://www.runatlantis.io/) `v0.49.0` no ECS Fargate, em `https://atlantis.terraform.gomex.me`.

```
GitHub ──webhook──► ALB (HTTPS, ACM) ──► Fargate (1 task) ──► EFS (locks, planos)
                                              │
                                              ├─ task role: só state + sts:AssumeRole
                                              └─► terraform-exec-groundwork / -dev / -prod
```

## Decisões que valem discussão no workshop

| Decisão | Por quê |
|---|---|
| Rede própria, não a do groundwork | O Atlantis aplica o groundwork; não pode depender dele |
| Allowlist só com `groundwork` e `infra-live` | O app está instalado na org toda, mas o Atlantis ignora os outros repos |
| GitHub App, não token pessoal | Token expira em 1h, permissão por repo, não morre quando alguém sai da empresa |
| Task role sem permissão de recurso | Cada stack tem a sua role (`terraform-exec-*`), criada no bootstrap |
| `repos.yaml` server-side | `approved` + `mergeable` + `undiverged` + policy check não podem ser desligados por um repo |
| `allow_custom_workflows: false` | Senão qualquer PR roda `run: curl ... \| sh` com as credenciais do Atlantis |
| EFS + 1 task | Lock fica em disco (BoltDB); perder o disco = perder os locks |
| Segredos fora do state | O Terraform cria o secret vazio; o valor é gravado pela CLI |
| Deploy via Actions + OIDC | O Atlantis não se aplica sozinho; o apply exige aprovação no environment `producao` |
| Policies numa tag | Mudar regra passa por PR nos dois repos |

## Requisitos

1. `bootstrap` aplicado e o NS de `terraform.gomex.me` delegado.
2. Repo `policies` com a tag `v1.0.0`.
3. Environment `producao` neste repo com *required reviewers*.

## Subindo pela primeira vez

### 1. GitHub App

Em *Org settings → Developer settings → GitHub Apps → New GitHub App*:

- **Nome**: `atlantis-terraform-em-producao` (o slug precisa bater com `github_app_slug`)
- **Homepage**: `https://atlantis.terraform.gomex.me`
- **Webhook URL**: `https://atlantis.terraform.gomex.me/events`
- **Webhook secret**: gere com `openssl rand -hex 32` e guarde
- **Permissões de repositório**: Administration (read), Checks (rw), Commit statuses (rw), Contents (rw), Issues (rw), Metadata (read), Pull requests (rw)
- **Permissões de org**: Members (read)
- **Eventos**: Issue comment, Pull request, Pull request review, Push
- **Onde pode ser instalado**: *Only on this account*

Depois: gere a *private key* (baixa um `.pem`), anote o *App ID* e instale o app na org em **All repositories**.

### 2. Infra

O primeiro apply é local (o workflow precisa do environment e das roles, que já existem depois do bootstrap; mas é mais simples ver os erros aqui):

```bash
terraform init
terraform apply
```

### 3. Segredo

```bash
jq -n \
  --arg app_id "<APP_ID>" \
  --rawfile private_key ./atlantis-app.private-key.pem \
  --arg webhook_secret "<WEBHOOK_SECRET>" \
  --arg web_password "$(openssl rand -base64 24)" \
  '$ARGS.named' > /dev/shm/atlantis.json

aws secretsmanager put-secret-value \
  --secret-id atlantis/github-app \
  --secret-string file:///dev/shm/atlantis.json

shred -u /dev/shm/atlantis.json
aws ecs update-service --cluster atlantis --service atlantis --force-new-deployment
```

A senha da UI fica no próprio secret (`web_password`, usuário `admin`).

### 4. Teste

```bash
curl -s https://atlantis.terraform.gomex.me/healthz
```

Em *GitHub App → Advanced → Recent deliveries* o ping deve aparecer com `200`.

## Do segundo deploy em diante

PR neste repo → CI + plan (role `github-atlantis-plan`) → merge → aprovação no environment `producao` → apply (role `github-atlantis-apply`).

## Custo aproximado (us-east-1)

| Item | US$/mês |
|---|---|
| Fargate 1 vCPU / 2 GB | ~36 |
| ALB | ~17 |
| EFS, logs, secret, IPv4 público | ~5 |

Para o workshop: `terraform destroy` depois (o EFS tem `prevent_destroy`; remova antes).
