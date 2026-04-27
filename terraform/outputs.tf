# =============================================================================
# outputs.tf — Изходни стойности след terraform apply
# =============================================================================
#
# Как да ги видиш:
#   terraform output                → всички
#   terraform output -json          → JSON (за скриптове)
#
# outputs.tf генерира и ansible/inventory.ini автоматично чрез
# local_file resource — не трябва да го пишеш ръчно.
# =============================================================================

output "lb_ip" {
  description = "IP адрес на Load Balancer"
  value       = "${var.ip_prefix}.10"
}

output "control_plane_ips" {
  description = "IP адреси на Control Plane nodes"
  value = {
    "k8s-control-01" = "${var.ip_prefix}.11"
    "k8s-control-02" = "${var.ip_prefix}.12"
    "k8s-control-03" = "${var.ip_prefix}.13"
  }
}

output "worker_ips" {
  description = "IP адреси на Worker nodes"
  value = {
    "k8s-worker-01" = "${var.ip_prefix}.21"
    "k8s-worker-02" = "${var.ip_prefix}.22"
    "k8s-worker-03" = "${var.ip_prefix}.23"
  }
}

output "ssh_command_lb" {
  description = "SSH команда за Load Balancer"
  value       = "ssh -i ~/.ssh/k8s-local ${var.ssh_user}@${var.ip_prefix}.10"
}

output "ssh_command_control01" {
  description = "SSH команда за control-01"
  value       = "ssh -i ~/.ssh/k8s-local ${var.ssh_user}@${var.ip_prefix}.11"
}

# =============================================================================
# Автоматично генерира ansible/inventory.ini от Terraform outputs
# =============================================================================
#
# local_file записва файл на диска при terraform apply.
# Ansible го чете после — не трябва ръчно да пишеш IP-та.

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content  = templatefile("${path.module}/templates/inventory.tpl", {
    lb_ip         = "${var.ip_prefix}.10"
    control_01_ip = "${var.ip_prefix}.11"
    control_02_ip = "${var.ip_prefix}.12"
    control_03_ip = "${var.ip_prefix}.13"
    worker_01_ip  = "${var.ip_prefix}.21"
    worker_02_ip  = "${var.ip_prefix}.22"
    worker_03_ip  = "${var.ip_prefix}.23"
    ssh_user      = var.ssh_user
    ssh_key_path  = var.ssh_key_path
  })

  depends_on = [null_resource.worker_03]
}
