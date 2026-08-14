# Troubleshooting Codex over SSH

## Contents

1. Diagnostic order
2. Error map
3. Connection flapping
4. SSH config integrity
5. Codex-specific checks
6. Evidence bundle

## Diagnostic order

Diagnose in this order and stop at the first failing layer:

1. Mesh/VPN reachability
2. TCP listener
3. Effective SSH config
4. Host-key verification
5. Public-key authentication
6. Remote login shell and PATH
7. Remote Codex version/config
8. Codex Desktop connection and project
9. Chat index and Codex home
10. OpenAI outbound network/auth

Changing a later layer cannot repair an earlier one.

## Error map

| Symptom | Likely meaning | Prove it | Targeted fix |
|---|---|---|---|
| `requested operation requires elevation` while installing OpenSSH Server | PowerShell is not elevated | Check the window title or run `net session` | Reopen with `Start-Process powershell -Verb RunAs`, approve UAC, then install |
| `Cannot find service sshd` | OpenSSH Server installation did not complete | `Get-WindowsCapability -Online | ? Name -like 'OpenSSH.Server*'` | Complete capability installation before starting the service |
| First connection shows an unknown host, then `Host key verification failed` | The host fingerprint was not accepted | Compare server fingerprint out of band | Connect interactively once, verify, then type `yes` |
| Password is rejected although Windows login works | PIN, Microsoft password, local account, and SSH user are being confused | Check `whoami` on A and SSH server logs | Use the actual server account and prefer public-key auth |
| Desktop asks for a key passphrase or silently fails | The private key is not loaded non-interactively | `ssh-add -l`; `ssh -o BatchMode=yes alias true` | Enable/start Windows `ssh-agent` as admin, then `ssh-add` as the user |
| `Set-Service ssh-agent ... Access denied` | Service configuration needs elevation | Run `Get-Service ssh-agent` | Use an elevated PowerShell for `Set-Service` and `Start-Service` |
| `Bad configuration option: `r`n` or `unsupported option "yes..."` | A PowerShell replacement wrote literal escape text or joined fields | `Get-Content ~/.ssh/config`; `ssh -G alias` | Restore the backup and rewrite explicit lines; validate before Codex |
| `kex_exchange_identification: read: Connection reset` | TCP connected but the SSH listener/proxy closed before key exchange | `ssh -vvv`; listener and server logs | Fix the listener, forwarding target, firewall, or service; do not change passwords |
| `Connection reset ... port 2222/2223` after changing ports | The chosen port has no stable SSH listener | `Test-NetConnection`; `ss -lntp`; `Get-NetTCPConnection` | Configure one listener and keep the port fixed |
| `Connection closed by UNKNOWN port 65535` | A ProxyJump/stdio-forward channel closed; the displayed 65535 is not the real server port | `ssh -G alias` and verbose logs showing `ProxyJump`/`-W` | Test hop 1 and target separately or remove the unnecessary jump |
| `hostname 127.0.0.1` plus `proxyjump computer-a-windows` | The alias targets WSL through a Windows hop | `ssh -G alias` | Prefer direct WSL Tailscale SSH; otherwise prove the loopback forward exists on hop 1 |
| Host-key mismatch after changing topology | The alias now reaches a different SSH server | Compare both fingerprints | Verify the new endpoint, then use `ssh-keygen -R <host-or-alias>` and reconnect |
| `unknown variant priority, expected fast or flex` | An older remote Codex CLI is reading a newer config value | Compare client and remote `codex --version`; inspect only the indicated config key | Upgrade remote Codex or isolate a compatible remote config; do not alter sessions |
| `codex: command not found` only through SSH | Non-interactive login PATH differs from interactive PATH | `ssh alias 'printf "%s\n" "$PATH"; command -v codex'` | Export the install directory from the correct shell startup path or use a stable executable path |
| Codex says the SSH CLI version must be updated | Remote app-server version is behind the Desktop expectation | `ssh alias 'codex --version'` | Update Codex on A, then rerun CLI gates before restarting Desktop |
| `No chats` while files are visible | SSH works, but the remote Codex home/index has no matching tasks | Inspect remote `CODEX_HOME`, `~/.codex/sessions`, and task working directories | Create new remote chats or intentionally reconcile stores; adding folders alone does not migrate chats |
| Chat appears, disappears, or resolves to the wrong host after manual copy | The same internal task ID exists on multiple hosts | List host IDs and inspect both session stores | Fork the imported A task to a new ID, verify it, archive both old-ID copies |
| `Only project-scoped Git repository chats can be handed off` | Official Hand off cannot move a projectless task | Check the saved project and `projectId` | Use a matching saved Git project for future tasks or follow the last-resort migration protocol |
| `stream disconnected ... backend-api/codex/responses` | The app-server host lost outbound OpenAI access or auth | Test from A; inspect VPN and auth logs | Restore A's VPN/network/auth; B's separate VPN is not a substitute for A's outbound path |
| Remote chat works in terminal but not Desktop | `codex resume` proved CLI access, not Desktop app-server compatibility | Run app-server acceptance gate and enable Connections > SSH | Configure Desktop SSH after app-server checks pass |
| Remote task runs in `/` or wrong path after import | Imported session contains a stale source cwd | Read task metadata and run `pwd -P` | Prefer a compatibility path/symlink or new fork; avoid bulk rewriting history |

## Connection flapping

When a connection alternates between working and failing, gather a timeline rather than repeatedly editing config:

```powershell
1..10 | ForEach-Object {
    $stamp = Get-Date -Format o
    $result = ssh -o BatchMode=yes -o ConnectTimeout=10 computer-a "echo OK" 2>&1
    [pscustomobject]@{ Time = $stamp; ExitCode = $LASTEXITCODE; Output = ($result -join ' ') }
    Start-Sleep -Seconds 5
}
```

Correlate failures with:

- A sleep/wake and Windows session state;
- Tailscale route changes or VPN reconnects;
- `sshd` restarts and listener disappearance;
- Windows-to-WSL port-proxy teardown;
- key-agent restarts;
- remote Codex updates;
- outbound VPN drops on A.

Use keepalives only after the base connection is stable. Keepalives detect dead links; they do not repair a missing listener.

## SSH config integrity

Always inspect the effective configuration:

```powershell
ssh -G computer-a | Select-String '^(hostname|user|port|identityfile|hostkeyalias|proxycommand|proxyjump)'
```

Important findings:

- `proxyjump` may be inherited from another `Host` block.
- OpenSSH applies the first obtained value for many settings, so block order matters.
- `Host *` defaults can silently affect the alias.
- `HostKeyAlias` changes the `known_hosts` lookup key.
- A valid-looking visible block can still resolve to `127.0.0.1` through inherited options.

Back up before editing. Prefer a structured line array or a reviewed script over regex replacement. After every edit, run `ssh -G` before `ssh` and before Codex Desktop.

If `ProxyJump` must remain, test the target from the jump host itself before debugging the client alias. For a Windows jump host forwarding to WSL, run `ssh -vvv -p <WSL_PORT> 127.0.0.1` on Windows A. If that path works but the jump channel still closes, inspect the jump host's `sshd_config` and every matching `Match` block for `AllowTcpForwarding`, `DisableForwarding`, and `PermitOpen`. Permit only the required destination where possible. Treat `UNKNOWN port 65535` as the failed stdio-forward channel, not as a port to configure.

## Codex-specific checks

### Separate Codex homes

Windows A commonly stores tasks under:

```text
C:\Users\<WINDOWS_USER>\.codex
```

WSL A commonly stores tasks under:

```text
/home/<WSL_USER>/.codex
```

They are separate even though they are on the same physical PC. A remote app-server started in WSL reads the WSL home unless configured otherwise.

### Config version skew

Do not share the entire `.codex` directory across Windows and WSL. `config.toml`, auth, app-server control sockets, paths, and versions can be platform-specific. If session discovery must be bridged, limit the bridge to the required data and keep backups. See `chat-portability.md`.

### Project folder versus task index

A saved project folder tells Codex where to run. Chat history is indexed separately. `No chats` does not mean the folder is inaccessible.

## Evidence bundle

Collect and sanitize this bundle before escalating:

### B

```powershell
ssh -V
ssh-add -l
Get-Content "$env:USERPROFILE\.ssh\config"
ssh -G computer-a
ssh -vvv -o BatchMode=yes -o ConnectTimeout=10 computer-a "echo SSH_READY"
Test-NetConnection <ADDRESS> -Port <PORT>
```

### A

```bash
whoami
hostname
command -v codex
codex --version
sshd -T
ss -lntp
systemctl status ssh --no-pager
tailscale status
```

Redact public IPs when unnecessary, private paths if sensitive, emails, account IDs, tokens, cookies, and all private-key material. Host-key and public-key fingerprints are identifiers, not secrets, but still sanitize them in public reports when they identify a private machine.
