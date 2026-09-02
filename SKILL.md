---
name: codex-ssh-remote-skill
description: Set up, diagnose, repair, and migrate Codex Desktop SSH Remote Connections across Windows, WSL, Linux, and macOS hosts over Tailscale or another trusted network. Use when built-in Remote Control fails, SSH Connections fail or flap, files open but chats are missing, a canonical Codex host must move, or migrated chats truncate, duplicate, disappear, show AbsolutePathBuf, or appear under Work/the wrong project. Covers OpenSSH, keys, remote PATH/version/VPN, one-source-of-truth chat storage, Hand off limits, safe host cutover, and session-store diagnosis; do not use for generic SSH or claim SSH creates a desktop mirror.
---

# Codex SSH Remote Setup

Build a stable connection in which the desktop app is the UI and the SSH host is the execution environment. Diagnose from evidence, change one layer at a time, and verify every layer before asking the user to restart Codex.

## Establish the architecture

Treat these as different products:

- **Remote Control** controls another running desktop app and can expose that host's existing desktop state.
- **Connections > SSH** starts a remote Codex app-server through SSH. Files, commands, credentials, skills, and new remote chats come from the SSH host.
- **`codex resume --all` over a terminal** is a CLI workflow, not a native Desktop mirror.

Depending on the installed Codex version and connection mode, SSH may start an app-server for the connection or proxy to a managed app-server daemon. In both cases, identify the effective Codex home, process, and control socket on A instead of treating the Desktop UI on B as the source of truth.

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
- <https://learn.chatgpt.com/docs/app-server>

## Apply safety rules

- Never expose the Codex app-server transport directly to a LAN or the internet. Expose SSH only through a trusted network or mesh.
- Prefer public-key authentication, a least-privilege remote account, `PermitRootLogin no`, and password authentication disabled after key access works.
- Never print or copy private keys, tokens, cookies, `auth.json`, or full unsanitized logs.
- Back up SSH config, `known_hosts`, and Codex indexes before editing them.
- Do not rewrite an SSH config with an unreviewed PowerShell `-replace` one-liner. Literal `` `r`n `` text can corrupt the file.
- Do not change ports repeatedly. First prove which address and port actually have a listener.
- Do not restart Codex to test a broken transport. Pass the command-line acceptance gates first.
- Do not manually copy a live task while either host may write to it.
- Never edit a rollout JSONL or task database while an app-server, Desktop instance, CLI task, or migration process can write to that store.
- Do not trust a restart command's final message alone. Read back daemon status/version and, when diagnosing stale state, the actual process holding the control socket.
- Treat manual Codex session-file migration as an unsupported last resort because the storage format can change.

## Run the workflow

### 1. Inventory both ends

Resolve or ask for:

- client OS and host OS;
- SSH alias, resolved address, port, and remote account;
- whether the target shell is Windows, WSL, or Linux;
- whether Tailscale/mesh runs on Windows A, inside WSL A, or both;
- where `codex` is installed for the remote login shell;
- the effective remote `CODEX_HOME`, whether a managed daemon is present, and which process owns its control socket;
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
codex app-server daemon --help
codex app-server daemon version
ss -lntp
sshd -T
```

`daemon version` may fail when no managed daemon is configured or when sandbox permissions block the local control socket. Record that result; do not bootstrap or restart the daemon merely to make the probe green.

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
5. The remote Codex version can start `codex app-server`; if the connection uses a managed daemon, `codex app-server daemon version` reports `running` and compatible CLI/app-server versions.
6. Codex Desktop B enables the SSH host and saves the intended remote project folder.
7. A new test chat runs `pwd` and a harmless file read on A.
8. A follow-up still works after several minutes and after reopening the project.
9. For a host replacement, the old host remains enabled until the destination lists every expected task, a real resume succeeds there, and source history is verified as an exact prefix.

Do not ask the user to keep restarting the desktop app while gates 1-5 fail.

### 5. Verify a managed App Server when present

Do not introduce persistent daemon management unless the selected Codex connection mode needs it. `codex app-server daemon bootstrap` installs durable local management and is a persistent system change; explain why it is needed and obtain authorization before running it.

For an existing daemon, read back its state and actual socket owner:

```bash
codex app-server daemon version
ss -xlpn | grep app-server-control
```

Count a restart as successful only when status is `running`, versions are compatible, the expected socket has one live owner, and a harmless request succeeds. On timeout or PID/socket mismatch, stop; do not kill a guessed PID or restart while a task may be writing. Use `references/troubleshooting.md`.

### 6. Add the host to Codex Desktop

After all CLI gates pass:

1. Open **Settings > Connections > SSH** on B.
2. Enable the concrete SSH alias discovered from the user's SSH config.
3. Choose a project folder that exists on A.
4. Create new chats from that remote project when all work must persist on A.

The selected folder controls the remote workspace; it does not move old local chat history into that folder.

### 7. Decide how chats should behave

- For **new work**, create the chat in the saved remote project. The task, commands, and files belong to A.
- For an **existing Git-project task**, prefer the official Hand off flow and save the same repository/subdirectory on both hosts.
- For a **projectless task**, Hand off may reject it. Read `references/chat-portability.md` before considering a manual migration.
- For a **canonical-host replacement**, read `references/host-cutover.md` before copying project files or task state.
- If Windows Codex on A and WSL Codex on A use different homes, expect `No chats` until the stores are intentionally reconciled. Connecting more project folders does not solve this.

For a one-source-of-truth setup, enforce this invariant: the selected Codex home on A is the only active writer and canonical task store; B is only the Desktop UI and SSH client. Verify important tasks by task ID and host, not title. A refresh delay or stale client index is not proof that a task is missing from A.

Never leave the same manually copied task ID active on B and A. The desktop index can deduplicate identical IDs unpredictably, causing a task to appear and disappear. Fork the imported task on A to a new ID, verify it, then archive the source and temporary import.

### 8. Harden stability

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
- `Invalid request: AbsolutePathBuf deserialized without a base path` after Windows-to-WSL migration points to invalid structural path metadata until disproved; inspect every relevant path field, including hybrid values such as `/home/user/C:\Users\...`.
- A chat under **Work** or the wrong project can retain stale `cwd` or `thread_source` metadata in both the task database and repeated `session_meta` records. Diagnose the exact task before changing either store.

## Use bundled resources

- Read `references/windows-wsl-setup.md` for the full Windows B to WSL A setup and acceptance checklist.
- Read `references/troubleshooting.md` for errors, proof commands, causes, and targeted fixes.
- Read `references/chat-portability.md` for chat visibility, Hand off limits, one-source-of-truth design, and last-resort migration.
- Read `references/host-cutover.md` when moving an entire CodexHub or replacing the always-on SSH host.
- Run `scripts/diagnose-codex-ssh.ps1` on B for read-only SSH and Codex checks.
- Run `scripts/setup-wsl-sshd.sh --help` before any server-side setup.
- Run `scripts/verify-session-clone.py` only to compare two already-created JSONL session files; it never modifies them. Use `--allow-clone-tail` only when the destination was legitimately continued after migration.

## Report the result

Lead with the verified outcome and list:

- resolved topology and execution host;
- passed and failed acceptance gates;
- exact files or services changed;
- backup locations;
- managed daemon status/version and control-socket owner when relevant;
- whether chats are new, handed off, or manually migrated;
- the canonical Codex home and final task/host IDs for any migrated task;
- which VPN/mesh components must remain active;
- any remaining unsupported or version-sensitive behavior.

Never claim a "full mirror" when only files or new remote chats are available.
