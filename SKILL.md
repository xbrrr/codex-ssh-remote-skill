---
name: codex-ssh-remote-skill
description: Set up and troubleshoot Codex Desktop SSH Remote Connections and projects between computers, especially Windows-to-WSL/Linux/Windows through Tailscale. Use when OpenAI's built-in Remote Connections or Remote Control fails, shows Couldn't enable remote control. Try again, Connection failed, or repeated disconnects, and an SSH alternative is needed. Also use for Codex over SSH, Settings / Connections / SSH, computer A/B, OpenSSH/sshd, keys, ssh-agent, BatchMode, known_hosts, Connection reset/flapping, ProxyJump/UNKNOWN port 65535, remote PATH/codex not found, app-server, config.toml/service_tier mismatch, VPN placement, files visible but No chats, separate Windows/WSL Codex homes/indexes, project folders vs chat storage, Hand off limits, projectless chat migration, duplicate/disappearing task IDs, and JSONL verification. Choose a direct WSL/Linux topology, prove network/auth/shell/app-server gates, explain sync limits, and move tasks safely. Do not use for generic SSH or claim SSH creates a desktop mirror.
---

# Codex SSH Remote Setup

Build a stable connection in which the desktop app is the UI and the SSH host is the execution environment. Diagnose from evidence, change one layer at a time, and verify every layer before asking the user to restart Codex.

## Establish the architecture

Treat these as different products:

- **Remote Control** controls another running desktop app and can expose that host's existing desktop state.
- **Connections > SSH** starts a remote Codex app-server through SSH. Files, commands, credentials, skills, and new remote chats come from the SSH host.
- **`codex resume --all` over a terminal** is a CLI workflow, not a native Desktop mirror.

Prefer this topology for an always-on Windows host that uses WSL:

```text
Codex Desktop on B
  -> Windows OpenSSH client
  -> Tailscale or another trusted mesh
  -> sshd inside WSL on A
  -> remote login shell
  -> codex app-server on A
```

Use a direct SSH endpoint whenever possible. Avoid a Windows SSH hop that forwards to `127.0.0.1` inside WSL; it adds a second host key, account, service, port, and failure domain.

Before relying on product behavior, consult the current official OpenAI documentation:

- <https://learn.chatgpt.com/docs/remote-connections>
- <https://learn.chatgpt.com/docs/build-skills>

## Apply safety rules

- Never expose the Codex app-server transport directly to a LAN or the internet. Expose SSH only through a trusted network or mesh.
- Prefer public-key authentication, a least-privilege remote account, `PermitRootLogin no`, and password authentication disabled after key access works.
- Never print or copy private keys, tokens, cookies, `auth.json`, or full unsanitized logs.
- Back up SSH config, `known_hosts`, and Codex indexes before editing them.
- Do not rewrite an SSH config with an unreviewed PowerShell `-replace` one-liner. Literal `` `r`n `` text can corrupt the file.
- Do not change ports repeatedly. First prove which address and port actually have a listener.
- Do not restart Codex to test a broken transport. Pass the command-line acceptance gates first.
- Do not manually copy a live task while either host may write to it.
- Treat manual Codex session-file migration as an unsupported last resort because the storage format can change.

## Run the workflow

### 1. Inventory both ends

Resolve or ask for:

- client OS and host OS;
- SSH alias, resolved address, port, and remote account;
- whether the target shell is Windows, WSL, or Linux;
- whether Tailscale/mesh runs on Windows A, inside WSL A, or both;
- where `codex` is installed for the remote login shell;
- whether the goal is new remote work, access to existing chats, or a full chat move.

Do not assume a Microsoft email address, Windows display name, PIN, and SSH account name are interchangeable. Ask the remote shell for `whoami` or use the actual WSL account.

### 2. Collect read-only evidence

On Windows B, run:

```powershell
ssh -G computer-a | Select-String '^(hostname|user|port|identityfile|hostkeyalias|proxycommand|proxyjump)'
ssh-add -l
ssh -vvv -o BatchMode=yes -o ConnectTimeout=10 computer-a "echo SSH_READY"
```

Prefer `scripts/diagnose-codex-ssh.ps1` for a repeatable report. Treat `ssh -G` as ground truth; it exposes inherited `ProxyJump`, stale ports, loopback targets, and unexpected identities that are easy to miss in the visible host block.

On A, inspect without changing state:

```bash
whoami
command -v codex
codex --version
ss -lntp
sshd -T
```

Also confirm the VPN/mesh address, service state, sleep policy, and outbound access to OpenAI from the host that runs the app-server.

### 3. Choose one SSH topology

Use one of these, in preference order:

1. Direct WSL/Linux `sshd` on a Tailscale address and dedicated port.
2. Direct Windows OpenSSH when Codex and the intended projects truly live in that Windows account.
3. ProxyJump only when direct reachability is impossible and both hops are independently tested.

For direct WSL setup, read `references/windows-wsl-setup.md`. Use `scripts/setup-wsl-sshd.sh` only after reviewing its address, port, account, and public-key inputs.

### 4. Prove the acceptance gates in order

Stop at the first failed gate:

1. `Test-NetConnection <address> -Port <port>` succeeds from B.
2. `ssh -G <alias>` resolves to the intended address, port, user, and identity with no accidental proxy.
3. `ssh -o BatchMode=yes <alias> "echo SSH_READY"` succeeds without a password or key-passphrase prompt.
4. `ssh <alias> "command -v codex; codex --version"` succeeds in the non-interactive login shell.
5. The remote Codex version can start `codex app-server`; isolate or upgrade incompatible config before continuing.
6. Codex Desktop B enables the SSH host and saves the intended remote project folder.
7. A new test chat runs `pwd` and a harmless file read on A.
8. A follow-up still works after several minutes and after reopening the project.

Do not ask the user to keep restarting the desktop app while gates 1-5 fail.

### 5. Add the host to Codex Desktop

After all CLI gates pass:

1. Open **Settings > Connections > SSH** on B.
2. Enable the concrete SSH alias discovered from the user's SSH config.
3. Choose a project folder that exists on A.
4. Create new chats from that remote project when all work must persist on A.

The selected folder controls the remote workspace; it does not move old local chat history into that folder.

### 6. Decide how chats should behave

- For **new work**, create the chat in the saved remote project. The task, commands, and files belong to A.
- For an **existing Git-project task**, prefer the official Hand off flow and save the same repository/subdirectory on both hosts.
- For a **projectless task**, Hand off may reject it. Read `references/chat-portability.md` before considering a manual migration.
- If Windows Codex on A and WSL Codex on A use different homes, expect `No chats` until the stores are intentionally reconciled. Connecting more project folders does not solve this.

Never leave the same manually copied task ID active on B and A. The desktop index can deduplicate identical IDs unpredictably, causing a task to appear and disappear. Fork the imported task on A to a new ID, verify it, then archive the source and temporary import.

### 7. Harden stability

Use conservative client keepalives:

```sshconfig
ServerAliveInterval 30
ServerAliveCountMax 3
TCPKeepAlive yes
```

Also ensure:

- A stays awake and online;
- Tailscale/mesh and `sshd` start automatically;
- the key is available non-interactively to the Windows OpenSSH client;
- the remote login shell exports the directory containing `codex`;
- remote and client Codex versions remain compatible;
- A keeps the outbound VPN if OpenAI is reachable only through it;
- B keeps Tailscale active and uses a separate VPN only if its own app/auth traffic requires it.

## Route failures precisely

Read `references/troubleshooting.md` whenever an exact error is present. Match the message first, collect its proof command, and apply only the corresponding fix.

Useful rules:

- `Connection reset` before authentication is a transport/listener problem, not a password problem.
- `Connection closed by UNKNOWN port 65535` commonly points to a failed ProxyJump stdio-forward target; inspect `ssh -G` and test each hop.
- `No chats` with working files is a Codex-home or task-index problem, not an SSH transport problem.
- `stream disconnected ... backend-api/codex/responses` points to outbound network/authentication on the machine running the remote app-server.
- `unknown variant priority, expected fast or flex` indicates config/CLI version skew; do not edit unrelated session data.

## Use bundled resources

- Read `references/windows-wsl-setup.md` for the full Windows B to WSL A setup and acceptance checklist.
- Read `references/troubleshooting.md` for errors, proof commands, causes, and targeted fixes.
- Read `references/chat-portability.md` for chat visibility, Hand off limits, Codex-home bridging, and last-resort migration.
- Run `scripts/diagnose-codex-ssh.ps1` on B for read-only SSH and Codex checks.
- Run `scripts/setup-wsl-sshd.sh --help` before any server-side setup.
- Run `scripts/verify-session-clone.py` only to compare two already-created JSONL session files; it never modifies them. Use `--allow-clone-tail` only when the destination was legitimately continued after migration.

## Report the result

Lead with the verified outcome and list:

- resolved topology and execution host;
- passed and failed acceptance gates;
- exact files or services changed;
- backup locations;
- whether chats are new, handed off, or manually migrated;
- which VPN/mesh components must remain active;
- any remaining unsupported or version-sensitive behavior.

Never claim a "full mirror" when only files or new remote chats are available.
