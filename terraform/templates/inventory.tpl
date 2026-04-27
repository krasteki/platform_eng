[lb]
${lb_ip} ansible_user=${ssh_user} ansible_ssh_private_key_file=${ssh_key_path}

[control_plane]
${control_01_ip} ansible_user=${ssh_user} ansible_ssh_private_key_file=${ssh_key_path}
${control_02_ip} ansible_user=${ssh_user} ansible_ssh_private_key_file=${ssh_key_path}
${control_03_ip} ansible_user=${ssh_user} ansible_ssh_private_key_file=${ssh_key_path}

[workers]
${worker_01_ip} ansible_user=${ssh_user} ansible_ssh_private_key_file=${ssh_key_path}
${worker_02_ip} ansible_user=${ssh_user} ansible_ssh_private_key_file=${ssh_key_path}
${worker_03_ip} ansible_user=${ssh_user} ansible_ssh_private_key_file=${ssh_key_path}

[k8s_nodes:children]
control_plane
workers

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
