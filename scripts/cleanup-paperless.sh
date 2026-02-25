#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="container-user"
PREFIX="paperless-ngx-"

confirm() {
  echo "This will remove all Paperless containers, networks, and volumes for ${TARGET_USER}."
  echo "It will also stop related systemd units and delete leftover tmpfiles directories under /mnt/storage/containers." 
  read -r -p "Type 'yes' to continue: " ans
  [[ "$ans" == "yes" ]]
}

remove_systemd_units() {
  local units
  units=$(systemctl list-units --all --no-legend 'podman-paperless-ngx-*' | awk '{print $1}' || true)
  if [[ -n "$units" ]]; then
    echo "Stopping systemd units..."
    while read -r unit; do
      [[ -z "$unit" ]] && continue
      sudo systemctl stop "$unit" || true
      sudo systemctl disable "$unit" || true
    done <<< "$units"
  fi

  local gpg_units
  gpg_units=$(systemctl list-units --all --no-legend 'paperless-ngx-*-gpg-setup.service' | awk '{print $1}' || true)
  if [[ -n "$gpg_units" ]]; then
    while read -r unit; do
      [[ -z "$unit" ]] && continue
      sudo systemctl stop "$unit" || true
      sudo systemctl disable "$unit" || true
    done <<< "$gpg_units"
  fi

  sudo systemctl daemon-reload
  sudo systemctl reset-failed
}

remove_podman_resources() {
  echo "Removing containers..."
  sudo -u "$TARGET_USER" podman ps -a --format '{{.Names}}' | grep "^${PREFIX}" | xargs -r sudo -u "$TARGET_USER" podman rm -f

  echo "Removing networks..."
  sudo -u "$TARGET_USER" podman network ls --format '{{.Name}}' | grep "^${PREFIX}" | xargs -r sudo -u "$TARGET_USER" podman network rm

  echo "Removing volumes..."
  sudo -u "$TARGET_USER" podman volume ls --format '{{.Name}}' | grep "${PREFIX}" | xargs -r sudo -u "$TARGET_USER" podman volume rm
}

remove_directories() {
  echo "Removing data directories..."
  sudo rm -rf /mnt/storage/containers/paperless-ngx-* || true
}

main() {
  confirm
  remove_systemd_units
  remove_podman_resources
  remove_directories
  echo "Done. Paperless resources removed."
}

main "$@"
