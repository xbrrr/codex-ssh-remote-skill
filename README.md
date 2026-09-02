# Codex SSH Remote Setup

A practical Codex skill for building stable SSH remote projects between computers. Codex Desktop runs on a client as the UI, while files, commands, tools, and remote tasks execute and persist on one canonical always-on host.

The skill is based on real Windows → Tailscale → WSL and macOS-host deployments. It also covers safely replacing the canonical host without losing chat history or leaving two active sources of truth.

> Independent community skill. Manual Codex session migration is an unsupported, version-sensitive fallback.

## What it covers

- Windows, WSL, Linux, OpenSSH, and Tailscale setup
- SSH keys, `ssh-agent`, `known_hosts`, and BatchMode authentication
- Codex app-server daemon lifecycle, stale socket/PID diagnosis, remote `PATH`, and version/config mismatches
- `Connection failed`, `Connection reset`, connection flapping, and `ProxyJump` failures
- `No chats`, `AbsolutePathBuf`, hybrid Windows/WSL paths, and wrong Work/project grouping
- VPN placement, Git Hand off limits, and safe projectless-task migration
- Full Codex host replacement, canary migration, semantic history checks, attachment transfer, cleanup, and rollback

## Recommended topology

~~~text
Codex Desktop on computer B
  -> Windows OpenSSH client
  -> Tailscale or another trusted mesh network
  -> sshd inside WSL/Linux on computer A
  -> remote login shell
  -> codex app-server on computer A
~~~

Prefer direct SSH to WSL or Linux. A Windows SSH hop forwarding through `ProxyJump` to `127.0.0.1` adds another server, host key, account, port, forwarding rule, and failure domain.

## Install

Ask Codex to install the skill from GitHub:

~~~text
Use $skill-installer to install the skill from
https://github.com/xbrrr/codex-ssh-remote-skill
~~~

Or clone it manually.

Linux or WSL:

~~~bash
git clone https://github.com/xbrrr/codex-ssh-remote-skill.git \
  "$HOME/.agents/skills/codex-ssh-remote-skill"
~~~

Windows PowerShell:

~~~powershell
git clone https://github.com/xbrrr/codex-ssh-remote-skill.git `
  "$env:USERPROFILE\.agents\skills\codex-ssh-remote-skill"
~~~

For SSH remote projects, install the skill on the remote host under the account that starts Codex app-server. Restart Codex only if the skill is not detected automatically.

## Use

Invoke it explicitly:

~~~text
Use $codex-ssh-remote-skill to diagnose why the Codex SSH connection
computer-a disconnects before app-server starts.
~~~

It can also trigger automatically for Codex SSH, Remote Connections, WSL, Tailscale, app-server, missing-chat, Hand off, and session-migration requests.

## How it diagnoses problems

The skill verifies the connection in order and stops at the first failed gate:

1. Network address and SSH port
2. Effective alias configuration from `ssh -G`
3. Non-interactive key authentication
4. Remote login-shell `PATH` and Codex availability
5. App-server and configuration compatibility
6. Codex Desktop project persistence

This avoids repeated app restarts while the underlying SSH transport is still broken.

## Included resources

| Path | Purpose |
|---|---|
| [SKILL.md](SKILL.md) | Core workflow and agent discovery metadata |
| [references/windows-wsl-setup.md](references/windows-wsl-setup.md) | Complete Windows B → WSL A setup |
| [references/troubleshooting.md](references/troubleshooting.md) | Error map, proof commands, and targeted fixes |
| [references/chat-portability.md](references/chat-portability.md) | Chat visibility, Hand off, and fallback migration |
| [references/host-cutover.md](references/host-cutover.md) | Replace the canonical Codex host and retire the old one safely |
| [scripts/diagnose-codex-ssh.ps1](scripts/diagnose-codex-ssh.ps1) | Read-only Windows client diagnostics |
| [scripts/setup-wsl-sshd.sh](scripts/setup-wsl-sshd.sh) | Controlled WSL sshd setup |
| [scripts/verify-session-clone.py](scripts/verify-session-clone.py) | Read-only JSONL session comparison |

## Important limits

- SSH remote projects are not a live mirror of another Codex Desktop instance.
- A project folder does not contain or automatically import chat history.
- Windows Codex and WSL Codex may use separate homes and version-dependent task indexes such as SQLite state plus rollout JSONL.
- Do not symlink a live SQLite state database or assume `session_index.jsonl` is the only active index.
- Never expose Codex app-server directly to a LAN or the internet.
- Never publish private keys, `auth.json`, tokens, cookies, or unsanitized logs.
- Do not keep the same manually copied task ID active on two hosts.

## Documentation

- [OpenAI: Build skills](https://learn.chatgpt.com/docs/build-skills)
- [OpenAI: Remote connections](https://learn.chatgpt.com/docs/remote-connections)
