#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage:' \
    '  setup-wsl-sshd.sh --listen-address <TAILSCALE_IP> --port <PORT> --user <WSL_USER> --public-key-file <FILE>' \
    '' \
    'Installs/configures OpenSSH Server in Debian/Ubuntu WSL using a hardened drop-in.' \
    'The script requires sudo, binds sshd to the supplied address, disables password login,' \
    'validates sshd configuration, and restores the previous drop-in if validation fails.'
}

listen_address=''
ssh_port=''
remote_user=''
public_key_file=''

while (($#)); do
  case "$1" in
    --listen-address)
      listen_address=${2:-}
      shift 2
      ;;
    --port)
      ssh_port=${2:-}
      shift 2
      ;;
    --user)
      remote_user=${2:-}
      shift 2
      ;;
    --public-key-file)
      public_key_file=${2:-}
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$listen_address" || -z "$ssh_port" || -z "$remote_user" || -z "$public_key_file" ]]; then
  usage >&2
  exit 2
fi

if [[ ! "$listen_address" =~ ^[0-9a-fA-F:.]+$ ]]; then
  printf 'Invalid listen address: %s\n' "$listen_address" >&2
  exit 2
fi

if [[ ! "$ssh_port" =~ ^[0-9]+$ ]] || ((ssh_port < 1 || ssh_port > 65535)); then
  printf 'Invalid SSH port: %s\n' "$ssh_port" >&2
  exit 2
fi

if ! id "$remote_user" >/dev/null 2>&1; then
  printf 'WSL user does not exist: %s\n' "$remote_user" >&2
  exit 2
fi

if [[ ! -f "$public_key_file" ]]; then
  printf 'Public key file does not exist: %s\n' "$public_key_file" >&2
  exit 2
fi

public_key=$(tr -d '\r\n' < "$public_key_file")
if [[ ! "$public_key" =~ ^(ssh-ed25519|sk-ssh-ed25519@openssh.com|ecdsa-sha2-nistp256|ssh-rsa)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]]; then
  printf 'The supplied file does not look like a single OpenSSH public key.\n' >&2
  exit 2
fi

remote_home=$(getent passwd "$remote_user" | cut -d: -f6)
if [[ -z "$remote_home" || ! -d "$remote_home" ]]; then
  printf 'Cannot resolve home directory for %s.\n' "$remote_user" >&2
  exit 2
fi

sudo apt-get update
sudo apt-get install -y openssh-server

ssh_dir="$remote_home/.ssh"
authorized_keys="$ssh_dir/authorized_keys"
sudo install -d -m 700 -o "$remote_user" -g "$remote_user" "$ssh_dir"
sudo touch "$authorized_keys"
sudo chown "$remote_user:$remote_user" "$authorized_keys"
sudo chmod 600 "$authorized_keys"

if ! sudo grep -Fqx "$public_key" "$authorized_keys"; then
  printf '%s\n' "$public_key" | sudo tee -a "$authorized_keys" >/dev/null
fi

dropin='/etc/ssh/sshd_config.d/90-codex-remote.conf'
backup_path=''
if sudo test -f "$dropin"; then
  backup_path="${dropin}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  sudo cp -a "$dropin" "$backup_path"
fi

temp_dropin=$(mktemp)
trap 'rm -f "$temp_dropin"' EXIT
printf '%s\n' \
  "Port $ssh_port" \
  "ListenAddress $listen_address" \
  'PubkeyAuthentication yes' \
  'PasswordAuthentication no' \
  'KbdInteractiveAuthentication no' \
  'PermitRootLogin no' \
  "AllowUsers $remote_user" > "$temp_dropin"

sudo install -m 600 -o root -g root "$temp_dropin" "$dropin"

if ! sudo sshd -t; then
  if [[ -n "$backup_path" ]]; then
    sudo cp -a "$backup_path" "$dropin"
  else
    sudo rm -f "$dropin"
  fi
  printf 'sshd validation failed; previous configuration restored.\n' >&2
  exit 1
fi

sudo systemctl enable ssh
sudo systemctl restart ssh
sudo systemctl --no-pager --full status ssh
ss -lnt | grep -E "[.:]${ssh_port}[[:space:]]"

printf 'SSH_READY address=%s port=%s user=%s\n' "$listen_address" "$ssh_port" "$remote_user"
if [[ -n "$backup_path" ]]; then
  printf 'Backup: %s\n' "$backup_path"
fi
