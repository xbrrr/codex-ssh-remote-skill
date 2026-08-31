# Windows B to WSL A setup

## Contents

1. Target topology
2. Prepare networking
3. Prepare the SSH key
4. Configure WSL A
5. Configure Windows B
6. Verify before opening Codex
7. Add the remote project
8. Windows OpenSSH alternative
9. Operational checklist

## Target topology

Use a direct connection from Windows OpenSSH on B to `sshd` in WSL on A over Tailscale or another trusted mesh:

```text
Windows B: Codex Desktop + ssh.exe
  -> computer-a alias
  -> Tailscale/MagicDNS address and dedicated port
  -> WSL A: sshd
  -> WSL user login shell
  -> codex app-server
```

This keeps project paths, shell tools, Codex home, and app-server on one side of the Windows/WSL boundary.

## Prepare networking

1. Install and authenticate the same trusted mesh on both machines.
2. Prefer MagicDNS when it is stable; otherwise record the mesh IPv4 address.
3. Decide where Tailscale terminates:
   - If it runs inside WSL, bind WSL `sshd` directly to the WSL Tailscale address.
   - If it runs only on Windows A, use a deliberate Windows-to-WSL forwarding design and test that forwarding separately. Direct WSL Tailscale is simpler.
4. Choose a dedicated SSH port such as `2223` if port 22 is already used by Windows OpenSSH.
5. Do not expose the Codex app-server port or socket.

Verify from B:

```powershell
tailscale status
Test-NetConnection <TAILSCALE_ADDRESS> -Port 2223
```

If the port test fails, stop. Fix the listener, binding, firewall, or mesh route on A before touching keys or Codex.

## Prepare the SSH key

On B:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.ssh" | Out-Null
ssh-keygen -t ed25519 -a 64 -f "$env:USERPROFILE\.ssh\id_ed25519_codex_a" -C "codex-b-to-a"
Get-Content "$env:USERPROFILE\.ssh\id_ed25519_codex_a.pub"
```

Transfer only the `.pub` line to A through a trusted channel. Never transfer or display the private key.

For unattended Desktop connections, the key must be usable without an interactive prompt. Prefer the Windows OpenSSH agent when the key has a passphrase:

```powershell
# Run in an elevated PowerShell once.
Set-Service ssh-agent -StartupType Automatic
Start-Service ssh-agent

# Run as the normal user.
ssh-add "$env:USERPROFILE\.ssh\id_ed25519_codex_a"
ssh-add -l
```

`Access denied` from `Set-Service` means PowerShell is not elevated. Merely being in `C:\Windows\System32` does not grant elevation.

A dedicated no-passphrase key can avoid agent prompts but increases key-theft risk. Use it only with restrictive ACLs, a dedicated account, and a trusted encrypted device.

## Configure WSL A

Install OpenSSH Server in WSL, not Windows, when WSL is the intended Codex environment:

```bash
sudo apt-get update
sudo apt-get install -y openssh-server
```

Install the public key for the actual WSL user:

```bash
install -d -m 700 ~/.ssh
printf '%s\n' '<PUBLIC_KEY_LINE>' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Review `scripts/setup-wsl-sshd.sh` for an idempotent drop-in configuration. A minimal hardened drop-in is:

```text
Port 2223
ListenAddress <WSL_TAILSCALE_ADDRESS>
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers <WSL_USER>
```

Validate before restarting:

```bash
sudo sshd -t
sudo systemctl enable ssh
sudo systemctl restart ssh
sudo systemctl --no-pager --full status ssh
ss -lntp | grep ':2223'
```

Install and authenticate Codex for that same WSL user. The non-interactive login shell must find it:

```bash
command -v codex
codex --version
```

If `codex` lives in `~/.local/bin`, export that path from a shell startup file that is loaded for the SSH command mode used by the app. Prove it from B rather than assuming interactive and non-interactive shells match.

Also record the effective remote Codex home. This is the canonical task store for a one-source-of-truth setup:

```bash
printf 'CODEX_HOME=%s\n' "${CODEX_HOME:-$HOME/.codex}"
```

Do not run `codex app-server daemon bootstrap` as a generic setup step. It installs durable daemon management. Use it only when the selected Desktop connection mode requires a managed daemon, explain the persistent change, and obtain authorization first.

## Configure Windows B

Back up the existing SSH config:

```powershell
$configPath = "$env:USERPROFILE\.ssh\config"
if (Test-Path $configPath) {
    Copy-Item $configPath "$configPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
}
```

Add a concrete alias. Use forward slashes in `IdentityFile`:

```sshconfig
Host computer-a
    HostName <TAILSCALE_ADDRESS_OR_MAGICDNS>
    Port 2223
    User <WSL_USER>
    IdentityFile C:/Users/<WINDOWS_USER>/.ssh/id_ed25519_codex_a
    IdentitiesOnly yes
    HostKeyAlias computer-a-wsl
    ServerAliveInterval 30
    ServerAliveCountMax 3
    TCPKeepAlive yes
```

Avoid wildcard-only aliases because Codex auto-discovers concrete hosts. Do not add `ProxyJump` unless direct access is impossible.

On first connection, compare the ED25519 fingerprint with A through a separate trusted channel:

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Then connect interactively once and answer `yes` only after the fingerprint matches:

```powershell
ssh computer-a
```

## Verify before opening Codex

Run every check from B:

```powershell
ssh -G computer-a | Select-String '^(hostname|user|port|identityfile|hostkeyalias|proxycommand|proxyjump)'
ssh -o BatchMode=yes -o ConnectTimeout=10 computer-a "echo SSH_READY"
ssh -o BatchMode=yes computer-a "whoami; command -v codex; codex --version"
ssh -o BatchMode=yes computer-a "codex app-server --help >/dev/null && echo APP_SERVER_READY"
```

If this connection uses the managed daemon, also run:

```powershell
ssh -o BatchMode=yes computer-a "codex app-server daemon version"
```

Expected results:

- no password or passphrase prompt;
- the resolved address and port match the WSL listener;
- no unintended `proxyjump` or `proxycommand`;
- `whoami` is the intended WSL account;
- both `SSH_READY` and `APP_SERVER_READY` appear.

For a managed daemon, require a `running` status and compatible CLI/app-server versions. If it was restarted, verify the actual control-socket owner and a harmless request; a restart message alone is not sufficient.

If any check fails, use `references/troubleshooting.md`. Do not open/restart Codex yet.

## Add the remote project

1. Open Codex Desktop on B.
2. Go to **Settings > Connections > SSH**.
3. Enable `computer-a`.
4. Choose a real folder on A, such as `/home/<user>/src/project` or `/mnt/c/Users/<user>/Documents/CodexHub`.
5. Start a test chat in that remote project.
6. Ask it to run `pwd -P`, `hostname`, and a harmless read.
7. Confirm the returned path and hostname belong to A.
8. Record the new task's internal ID/host when possible and confirm it belongs to A, not a local B copy.

The project picker browses A through SSH. It does not require mounting A as a Windows drive on B.

## Windows OpenSSH alternative

Use Windows OpenSSH Server only when the remote Codex installation and projects are meant to run in the Windows account itself.

Install from an elevated PowerShell:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service sshd -StartupType Automatic
Get-Service sshd
```

If installation says elevation is required, stop and reopen PowerShell with `Start-Process powershell -Verb RunAs`. `Start-Service sshd` cannot work until the capability installation succeeds.

Windows account rules differ from WSL:

- Use the actual Windows account accepted by OpenSSH, not a display label or PIN.
- Microsoft-account passwords and local account names are easy to confuse; key auth avoids this ambiguity.
- Administrators may use `%ProgramData%\ssh\administrators_authorized_keys` depending on Windows OpenSSH policy.
- Windows paths and Windows Codex home will differ from WSL paths and WSL Codex home.

## Operational checklist

- Tailscale/mesh is connected on A and B.
- A's VPN remains connected if A needs it for OpenAI.
- B's separate VPN is optional unless B's own Codex UI/auth requires it.
- A does not sleep.
- `sshd` starts automatically.
- The Windows key agent starts automatically or the dedicated key needs no prompt.
- Remote `codex --version` is compatible with the Desktop client.
- The exact SSH alias still passes the four verification commands.
- New chats are created in the remote project when A must remain canonical.
- A's selected remote Codex home is the only active task store; B is only the UI/SSH client.
- Managed daemon status/version and control-socket ownership are read back after any restart.
