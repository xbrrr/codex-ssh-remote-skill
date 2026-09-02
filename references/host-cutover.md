# Replace the canonical Codex SSH host

Use this procedure when an existing always-on Codex host is being replaced, for example by a Mac mini. It is a migration and cutover, not ordinary SSH setup.

## Completion criteria

Define the expected task IDs before changing anything. The cutover is complete only when:

- the project tree is synchronized to the destination without deleting the source;
- every expected active task has one destination ID and the intended title;
- destination tasks resolve to the destination project and host, not merely the correct `cwd`;
- attachments referenced by migrated tasks exist and match their source hashes;
- a real harmless continuation succeeds on the destination;
- semantic verification proves the source history is an exact prefix of the continued destination;
- old destination-local test tasks are removed from the active store after backup;
- source tasks are archived and the old SSH host is disabled only after all prior checks pass.

## Safe sequence

1. Inventory active source tasks by internal ID, title, rollout path, archive state, and pin state. Do not mix unrelated cloud chats or historical archived tasks into the scope unless requested.
2. Back up the destination Codex home and source rollout files. Keep auth, config, sockets, and platform-specific databases separate.
3. Synchronize the project additively. Do not use `rsync --delete` during migration. Exclude non-portable virtual environments when moving between architectures.
4. Remove old destination-local test tasks only through the app-server's task deletion method and only after resolving exact IDs and confirming a backup.
5. Move one idle canary task and validate it before batching the rest.
6. Transfer the currently active coordination task last. Wait until its rollout stops changing, capture its final tail, verify it, then archive the source.
7. Keep the old host reachable until a client lists the destination project and a harmless continuation succeeds there.
8. Disable the old host's SSH service or saved connection only after the destination passes every completion criterion. Record a rollback command and backup location.

## Canary lessons

A native app-server import followed by `thread/fork` may return a readable task while preserving only paginated or partial history. Do not infer success from the title, first prompt, or task count. Compare response items, compaction records, world state, and task boundaries. If the canary truncates history, delete only the failed destination fork and stop the batch.

Old, previously merged rollouts may contain multiple `session_meta` records. Multiple records are not automatically corruption. A migration must inspect and consistently handle every repeated structural metadata record while preserving line order and model-visible content.

For a last-resort manual import:

- assign a fresh destination UUID so the UI cannot deduplicate source and destination;
- rewrite only proven structural IDs, project roots, and attachment roots;
- never bulk-replace path-looking text in historical messages or command output;
- parse every JSONL line and compare normalized records before import;
- copy attachments separately and verify each referenced file by hash;
- preserve the original rollout outside the active destination store.

After indexing, a destination task can have the correct `cwd` but still have no saved-project association. Verify host ID and project ID in the desktop task list. A supported metadata action such as setting the task title can cause the desktop index to associate an indexed task with the saved project; verify the result rather than relying on this behavior universally.

## Real continuation test

Reading a migrated task is not enough. Continue one canary on the destination with a harmless request such as:

```text
Run pwd -P and git rev-parse --show-toplevel. Do not modify files.
```

Confirm both paths identify the destination project. Then run the semantic verifier with source-prefix mode so legitimate new destination turns are allowed but all source history must remain an exact ordered prefix.

## Cutover and rollback

Archive rather than delete source tasks during acceptance. Back up destination-local test tasks before deleting them. If final-tail transfer, indexing, project association, or continuation fails, leave the old SSH host enabled and restore visibility from the archived source. Do not let both hosts write to copies of the same logical task.
