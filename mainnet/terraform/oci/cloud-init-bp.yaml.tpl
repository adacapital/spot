#cloud-config
users:
  - name: cardano
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh-authorized-keys:
      - ${bp_node_ssh_public_key}
      - ${relay1_ssh_public_key}
      - ${relay2_ssh_public_key}

runcmd:
  - echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
  - systemctl restart sshd

write_files:
  - path: /home/cardano/.ssh/adact-preprod-relay1
    content: |
      ${relay1_ssh_private_key}
    owner: cardano:cardano
    permissions: '0600'
    defer: true
  - path: /home/cardano/.ssh/adact-preprod-relay2
    content: |
      ${relay2_ssh_private_key}
    owner: cardano:cardano
    permissions: '0600'
    defer: true
  - path: /home/cardano/.bashrc
    content: |
      ${bashrc_file}
    owner: cardano:cardano
    permissions: '0644'
    defer: true