# Chat visibility and portability

## Contents

1. Mental model
2. New remote chats
3. Official Hand off
4. Windows and WSL stores
5. Last-resort projectless migration
6. Verification
7. Rollback

## Mental model

An SSH project connection is not a screen mirror and does not automatically clone every local Codex task.

Three things are independent:

- the project folder where commands run;
- the Codex home that stores sessions and indexes;
- the host ID that Desktop associates with the task.

Adding more folders only changes available workspaces. It does not move session history.

## New remote chats

For the most reliable single-source workflow:

1. Connect B to A through **Connections > SSH**.
2. Save the intended project on A.
3. Start every new task from that remote project on B.
4. Do not open a second local copy of the same task on B.

The app-server, session writes, commands, and files then belong to A. B is the UI and SSH client.

## Official Hand off

Prefer Hand off when the source task is scoped to a saved Git repository and both hosts have a saved project for the same repository and subdirectory.

Hand off can reject projectless tasks with:

```text
Only project-scoped Git repository chats can be handed off.
```

Do not promise that an existing projectless task can be retroactively made eligible. The supported behavior can change; check the current official Remote connections documentation.

## Windows and WSL stores

On a Windows host running WSL, these are usually different:

```text
Windows: C:\Users\<user>\.codex
WSL:     /home/<user>/.codex
```

Consequences:

- Remote WSL projects can work while showing no Windows Desktop chats.
- A task created through WSL SSH may not appear in Windows Codex on A if the stores are separate.
- The same project folder can show different chats under different Codex homes.

If one physical A must expose existing Windows tasks through WSL, an advanced bridge can point only WSL `sessions` and `session_index.jsonl` at the Windows equivalents. Do not share the full `.codex` directory.

Example shape:

```bash
~/.codex/sessions -> /mnt/c/Users/<windows-user>/.codex/sessions
~/.codex/session_index.jsonl -> /mnt/c/Users/<windows-user>/.codex/session_index.jsonl
```

Before bridging:

1. Stop task writers or guarantee only one computer will work at a time.
2. Back up both stores.
3. Compare Codex versions.
4. Keep WSL config/auth/control sockets separate.
5. Validate JSONL files and permissions.

This is version-sensitive and not a substitute for Remote Control.

## Last-resort projectless migration

Use this only when Hand off is unavailable and preserving a projectless task is more important than staying on supported paths.

### Phase 1: Freeze and back up

1. Wait for the source task to become idle.
2. Do not write to it during migration.
3. Locate the exact source session JSONL by task ID.
4. Copy, do not move, the source JSONL to a staging folder on A.
5. Copy referenced attachments and visualization artifacts if the task depends on them.
6. Record byte size and SHA-256 for every copied artifact.
7. Keep an independent readable export when available.

Never delete the source during this phase.

### Phase 2: Validate the staged copy

1. Parse every JSONL line.
2. Confirm the first and last records are valid.
3. Compare size and SHA-256 with the source.
4. Verify attachment/archive extraction without overwriting existing targets.
5. Confirm the remote app-server can discover the imported task by exact ID.

### Phase 3: Repair path compatibility

Imported history may carry a Windows cwd that is invalid in WSL. Prefer a narrow compatibility symlink or a new valid fork over rewriting thousands of historical records.

Run a harmless `pwd -P` test. If the task resolves to `/` or another wrong directory, stop before real work.

### Phase 4: Eliminate duplicate IDs

Manual copy preserves the source task ID. Desktop can then see the same ID on local B and remote A, even if one copy is archived. This can cause intermittent list deduplication, wrong-host resolution, or disappearing chats.

After the import is readable on A:

1. Ensure every source turn is complete or accept that only completed history can be forked.
2. Fork the imported A task in the same directory to create a new unique ID.
3. Rename the fork to the intended final title.
4. Pin it temporarily.
5. Verify content and execution on A.
6. Archive the local B source.
7. Archive the temporary imported A task that still has the old ID.
8. Keep only the new-ID A task visible.

Do this before routine work. Renaming alone does not resolve an ID collision.

### Phase 5: Verify semantic preservation

Use `scripts/verify-session-clone.py` to compare source and forked JSONL files. Use strict mode immediately after the fork. If the destination has already received legitimate new turns, add `--allow-clone-tail`; this still requires every source semantic record to match in order and permits only an appended destination tail.

The verifier compares:

- response items after normalizing serialization-only null fields;
- compaction records;
- world-state records;
- task start/complete ID sequence.

A native fork may intentionally normalize timestamps, repeated turn-context records, or token-count telemetry. Compare model-visible content and task structure, not raw file hashes alone.

### Phase 6: Acceptance test

Confirm all of the following:

- Desktop B lists only the final new-ID task as active.
- Its host ID is A.
- `pwd -P` resolves to the intended project on A.
- A harmless marker response completes.
- A new follow-up remains visible after reconnecting B.
- The archived B source still exists as a backup.

## Verification

Use host-specific inspection whenever duplicate IDs might exist. A title is not enough to identify the execution host.

Record:

- source task ID and final task ID;
- source and destination host IDs;
- session paths and checksums;
- attachment/archive checksums;
- final cwd;
- archive state of old copies.

## Rollback

If the final task fails verification:

1. Stop writing to it.
2. Leave all source backups intact.
3. Unarchive the original B task if necessary.
4. Remove only newly created staging artifacts after resolving exact paths and preserving a backup.
5. Do not overwrite the source JSONL with a fork or normalized file.

The source remains authoritative until the new-ID A task passes every acceptance check.
