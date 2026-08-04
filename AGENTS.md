# Repository Guidance

## Purpose

`agent-guidance-sync` safely copies a small, explicit set of local guidance files to remote user profiles over SSH. Keep the engine generic; real host inventories and personal guidance belong outside the repository.

## Safety invariants

- Preview is the default. Remote writes require the explicit `-Apply` switch.
- Destination paths remain relative to the remote user's home directory. Reject absolute paths, drive-qualified paths, empty segments, and `..` traversal.
- Stage every payload before replacing any destination.
- Fence each replacement with the hash observed during preview. A changed destination must fail closed.
- Preserve timestamped backups, use atomic replacement, and verify the final SHA-256 independently.
- Never commit private keys, SSH config, auth/session data, personal host inventories, or the synchronized guidance contents.
- Keep Unix and Windows OpenSSH targets supported. Do not weaken one platform to simplify the other.

## Development

- Use PowerShell 7.2 or newer.
- Keep `Sync-AgentGuidance` as the only public command unless a new public surface has a clear operator need.
- Run `pwsh -NoProfile -File tests/Test-AgentGuidanceSync.ps1` after behavior changes.
- Tests must cover configuration validation and transaction failure paths, not only the happy path.
- Do not make live remote writes from automated tests.
