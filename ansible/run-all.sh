#!/usr/bin/env bash
# run-all.sh — Стартира всички Ansible playbooks в правилния ред
# Изпълнява се от ansible/ директорията
# Usage: bash run-all.sh

set -euo pipefail

INVENTORY="inventory.ini"
ANSIBLE_ARGS="-i ${INVENTORY} ${@}"

echo "=== Phase 2: Kubernetes cluster bootstrap ==="
echo ""

echo "[1/5] Static IPs..."
ansible-playbook ${ANSIBLE_ARGS} 05-static-ips.yml
echo "Waiting 15s for network to settle..."
sleep 15

echo "[2/5] Prerequisites (containerd + kubeadm)..."
ansible-playbook ${ANSIBLE_ARGS} 01-prereqs.yml

echo "[3/5] HAProxy on LB..."
ansible-playbook ${ANSIBLE_ARGS} 02-haproxy.yml

echo "[4/5] Initialize control plane..."
ansible-playbook ${ANSIBLE_ARGS} 03-control-init.yml

echo "[5/5] Join remaining nodes..."
ansible-playbook ${ANSIBLE_ARGS} 04-join-nodes.yml

echo ""
echo "=== Cluster bootstrap complete! ==="
echo "Copy kubeconfig to your Mac:"
echo "  scp -i ~/.ssh/k8s-local parallels@10.211.55.11:/home/parallels/.kube/config ~/.kube/k8s-local-config"
echo "  export KUBECONFIG=~/.kube/k8s-local-config"
echo "  kubectl get nodes"
