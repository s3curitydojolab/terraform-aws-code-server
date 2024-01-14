#!/bin/bash

set -ue

# Functions
update_hostname() {
  hostnamectl set-hostname ${HOSTNAME}
}

mount_home_drive() {
  mkfs -t ext4 /dev/nvme1n1
  echo '/dev/nvme1n1 /home ext4 defaults,nofail,discard 0 0' \
  | sudo tee -a /etc/fstab
  mount /home
}

add_user() {
  useradd -m -G sudo -s /bin/bash ${USERNAME}
  echo -e "${USERPASS}\n${USERPASS}" | passwd ${USERNAME}
  echo ${USERPASS} > /home/${USERNAME}/sudo.txt
  mkdir /home/${USERNAME}/.ssh && \
  curl https://github.com/${GITHUB_USER}.keys >> /home/${USERNAME}/.ssh/authorized_keys
  chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/
}

update_system() {
  echo "deb [trusted=yes] https://apt.fury.io/caddy/ /" \
  | sudo tee -a /etc/apt/sources.list.d/caddy-fury.list
  apt update
  apt -y dist-upgrade
  apt install -y jq systemd-container caddy
  apt -y autoclean
  apt -y autoremove
}

install_code_server() {
  CODE_SERVER_RELEASE=$(curl -s https://api.github.com/repositories/172953845/releases/latest \
  | jq -r ".assets[] | select(.name | test(\"amd64.deb\")) | .browser_download_url")
  DEB=$(echo "$CODE_SERVER_RELEASE" | awk -F'/' '{print $9}')

  wget "$CODE_SERVER_RELEASE"
  yes | dpkg -i "$DEB"
  rm "$DEB"
}

code_server_config() {
  mkdir -p /home/${USERNAME}/.config/code-server && \
  chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config
  cat <<EOF > "/home/${USERNAME}/.config/code-server/config.yaml"
bind-addr: 127.0.0.1:8080
auth: none
password:
cert: false
EOF
}

enable_code_server() {
  loginctl enable-linger ${USERNAME}
  machinectl shell --uid=${USERNAME} .host /usr/bin/systemctl --user enable --now code-server.service
}

caddy_config() {
  cat <<EOF > "/etc/caddy/Caddyfile"
${DOMAIN}

bind 0.0.0.0
reverse_proxy 127.0.0.1:8080
EOF
  systemctl restart caddy.service
}

main () {
  update_hostname

  mount_home_drive

  add_user

  update_system

  install_code_server

  code_server_config

  enable_code_server

  caddy_config
}

# Exectution
main

exit 0
