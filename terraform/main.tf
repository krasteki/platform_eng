# =============================================================================
# main.tf — Terraform конфигурация за локален Parallels Desktop Pro
# =============================================================================
#
# ЗАЩО НЕ ПОЛЗВАМЕ ОФИЦИАЛНИЯ PARALLELS PROVIDER (Parallels/parallels-desktop):
#   Официалният provider изисква `prl-devops-service` — отделен Parallels
#   сървис за remote/enterprise управление. Проверено: не е инсталиран локално,
#   API на :8080 не слуша. Дори с Pro edition, provider-ът не работи без него.
#
# ПОДХОДЪТ ТУК — null_resource + prlctl:
#   prlctl е Parallels command-line tool — вече е инсталиран и работи.
#   null_resource изпълнява prlctl команди при `terraform apply/destroy`.
#
#   Предимства:
#   - Работи веднага, без допълнителна настройка
#   - Пълен Terraform lifecycle (plan / apply / destroy)
#   - Terraform state пази кои VM-и са създадени
#   - terraform destroy трие всичко чисто
#   - Идемпотентен — безопасно е да се пусне два пъти
#
# Стратегия за клониране:
#   Имаш "Ubuntu 22.04 ARM64" VM в Parallels → клонираме го 7 пъти.
#   Клонирането е бързо (~30 сек на VM).
#   Ansible след това конфигурира hostname, static IP, kubeadm и т.н.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # null provider — за null_resource
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    # local provider — за генериране на Ansible inventory файл
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}
