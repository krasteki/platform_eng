# =============================================================================
# variables.tf — Входни параметри
# =============================================================================
#
# null_resource + prlctl не изискват Parallels credentials.
# prlctl работи директно като текущия Mac потребител.
# =============================================================================

# --- Base VM за клониране ---

variable "base_vm_name" {
  description = "Името на съществуващия Parallels VM за клониране"
  type        = string
  default     = "Ubuntu 22.04 ARM64"
  # prlctl clone "Ubuntu 22.04 ARM64" --name "k8s-lb"
}

# --- Network ---

variable "ip_prefix" {
  description = "Мрежов префикс (Parallels Shared Network)"
  type        = string
  default     = "192.168.64"
}

variable "gateway" {
  description = "Default gateway"
  type        = string
  default     = "192.168.64.1"
}

variable "dns_server" {
  description = "DNS сървър"
  type        = string
  default     = "8.8.8.8"
}

# --- SSH ---

variable "ssh_user" {
  description = "SSH потребител в клонираните VM-и"
  type        = string
  default     = "parallels"
  # Паралелс клонира VM-а с оригиналния user — за Ubuntu Desktop VM е "parallels"
}

variable "ssh_key_path" {
  description = "Път до private SSH ключа"
  type        = string
  default     = "~/.ssh/k8s-local"
}

# --- Load Balancer specs ---

variable "lb_cpu" {
  type    = number
  default = 1
}

variable "lb_ram_mb" {
  description = "RAM в MB"
  type        = number
  default     = 1024
}

# --- Control Plane specs ---

variable "control_cpu" {
  type    = number
  default = 2
}

variable "control_ram_mb" {
  type    = number
  default = 4096
}

# --- Worker specs ---

variable "worker_cpu" {
  type    = number
  default = 2
}

variable "worker_ram_mb" {
  type    = number
  default = 2048
}
