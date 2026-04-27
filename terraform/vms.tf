# =============================================================================
# vms.tf — Създаване на 7 VM-а чрез prlctl clone
# =============================================================================
#
# Как работи null_resource:
#   null_resource е Terraform resource без реален облачен обект.
#   "local-exec" provisioner изпълнява shell команди НА MAC-А.
#   "when = destroy" се изпълнява при `terraform destroy`.
#
# Идемпотентност:
#   Проверяваме `prlctl list | grep -q "name" || clone` —
#   ако VM-ът вече съществува → skip. Ако не → clone.
#
# depends_on:
#   Клонирането е последователно за да не претовари disk I/O.
# =============================================================================

# =============================================================================
# LOAD BALANCER
# =============================================================================

resource "null_resource" "lb" {
  triggers = {
    vm_name = "k8s-lb"
    base_vm = var.base_vm_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo ">>> Клониране: ${var.base_vm_name} → k8s-lb"
      prlctl list -a | grep -q "k8s-lb" && echo "k8s-lb вече съществува, пропускам" || \
        prlctl clone "${var.base_vm_name}" --name "k8s-lb"
      prlctl set "k8s-lb" --cpus ${var.lb_cpu} --memsize ${var.lb_ram_mb}
      prlctl start "k8s-lb"
      echo ">>> k8s-lb стартиран"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      prlctl stop "k8s-lb" --kill 2>/dev/null || true
      prlctl delete "k8s-lb" 2>/dev/null || true
    EOT
  }
}

# =============================================================================
# CONTROL PLANE NODES
# =============================================================================

resource "null_resource" "control_plane_01" {
  depends_on = [null_resource.lb]
  triggers   = { vm_name = "k8s-control-01", base_vm = var.base_vm_name }

  provisioner "local-exec" {
    command = <<-EOT
      echo ">>> Клониране → k8s-control-01"
      prlctl list -a | grep -q "k8s-control-01" && echo "вече съществува" || \
        prlctl clone "${var.base_vm_name}" --name "k8s-control-01"
      prlctl set "k8s-control-01" --cpus ${var.control_cpu} --memsize ${var.control_ram_mb}
      prlctl start "k8s-control-01"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      prlctl stop "k8s-control-01" --kill 2>/dev/null || true
      prlctl delete "k8s-control-01" 2>/dev/null || true
    EOT
  }
}

resource "null_resource" "control_plane_02" {
  depends_on = [null_resource.control_plane_01]
  triggers   = { vm_name = "k8s-control-02", base_vm = var.base_vm_name }

  provisioner "local-exec" {
    command = <<-EOT
      echo ">>> Клониране → k8s-control-02"
      prlctl list -a | grep -q "k8s-control-02" && echo "вече съществува" || \
        prlctl clone "${var.base_vm_name}" --name "k8s-control-02"
      prlctl set "k8s-control-02" --cpus ${var.control_cpu} --memsize ${var.control_ram_mb}
      prlctl start "k8s-control-02"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      prlctl stop "k8s-control-02" --kill 2>/dev/null || true
      prlctl delete "k8s-control-02" 2>/dev/null || true
    EOT
  }
}

resource "null_resource" "control_plane_03" {
  depends_on = [null_resource.control_plane_02]
  triggers   = { vm_name = "k8s-control-03", base_vm = var.base_vm_name }

  provisioner "local-exec" {
    command = <<-EOT
      echo ">>> Клониране → k8s-control-03"
      prlctl list -a | grep -q "k8s-control-03" && echo "вече съществува" || \
        prlctl clone "${var.base_vm_name}" --name "k8s-control-03"
      prlctl set "k8s-control-03" --cpus ${var.control_cpu} --memsize ${var.control_ram_mb}
      prlctl start "k8s-control-03"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      prlctl stop "k8s-control-03" --kill 2>/dev/null || true
      prlctl delete "k8s-control-03" 2>/dev/null || true
    EOT
  }
}

# =============================================================================
# WORKER NODES
# =============================================================================

resource "null_resource" "worker_01" {
  depends_on = [null_resource.control_plane_03]
  triggers   = { vm_name = "k8s-worker-01", base_vm = var.base_vm_name }

  provisioner "local-exec" {
    command = <<-EOT
      echo ">>> Клониране → k8s-worker-01"
      prlctl list -a | grep -q "k8s-worker-01" && echo "вече съществува" || \
        prlctl clone "${var.base_vm_name}" --name "k8s-worker-01"
      prlctl set "k8s-worker-01" --cpus ${var.worker_cpu} --memsize ${var.worker_ram_mb}
      prlctl start "k8s-worker-01"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      prlctl stop "k8s-worker-01" --kill 2>/dev/null || true
      prlctl delete "k8s-worker-01" 2>/dev/null || true
    EOT
  }
}

resource "null_resource" "worker_02" {
  depends_on = [null_resource.worker_01]
  triggers   = { vm_name = "k8s-worker-02", base_vm = var.base_vm_name }

  provisioner "local-exec" {
    command = <<-EOT
      echo ">>> Клониране → k8s-worker-02"
      prlctl list -a | grep -q "k8s-worker-02" && echo "вече съществува" || \
        prlctl clone "${var.base_vm_name}" --name "k8s-worker-02"
      prlctl set "k8s-worker-02" --cpus ${var.worker_cpu} --memsize ${var.worker_ram_mb}
      prlctl start "k8s-worker-02"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      prlctl stop "k8s-worker-02" --kill 2>/dev/null || true
      prlctl delete "k8s-worker-02" 2>/dev/null || true
    EOT
  }
}

resource "null_resource" "worker_03" {
  depends_on = [null_resource.worker_02]
  triggers   = { vm_name = "k8s-worker-03", base_vm = var.base_vm_name }

  provisioner "local-exec" {
    command = <<-EOT
      echo ">>> Клониране → k8s-worker-03"
      prlctl list -a | grep -q "k8s-worker-03" && echo "вече съществува" || \
        prlctl clone "${var.base_vm_name}" --name "k8s-worker-03"
      prlctl set "k8s-worker-03" --cpus ${var.worker_cpu} --memsize ${var.worker_ram_mb}
      prlctl start "k8s-worker-03"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      prlctl stop "k8s-worker-03" --kill 2>/dev/null || true
      prlctl delete "k8s-worker-03" 2>/dev/null || true
    EOT
  }
}
