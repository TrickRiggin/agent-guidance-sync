# Repository Guidance

## Purpose

`agent-guidance-sync` safely copies a small, explicit set of local guidance files and can project reviewed portable Codex settings to remote user profiles over SSH. Keep the engine generic; real host inventories and personal guidance belong outside the repository.

## Safety invariants

- Preview is the default. Remote writes require the explicit `-apply` switch. Parameter names are case-insensitive; `-Apply` is the same switch.
- Default preview and `-apply` write instruction files only. A `codexConfig` block is inert until `-settings` is passed. `-settings` previews or applies the semantic Codex projection and must not copy instruction files in the same run.
- `-init` may write only a local starter config and must not overwrite an existing config. The interactive wizard may make read-only SSH probes to see which agent directories already exist; it never writes remotely. Probe failures skip that alias instead of failing the wizard. `-init -NonInteractive` stays local-only.
- Destination paths remain relative to the remote user's home directory. Reject absolute paths, drive-qualified paths, empty segments, and `..` traversal.
- Stage every payload before replacing any destination.
- Fence each replacement with the hash observed during preview. A changed destination must fail closed.
- Preserve timestamped backups, use atomic replacement, and verify the final SHA-256 independently.
- Treat every mapping as an exact file copy. Do not merge, translate, or normalize guidance between harnesses.
- Treat `codexConfig` as a semantic, target-specific projection. Use Codex's config API, preserve unowned TOML, and keep the compiled key allowlist narrow.
- Never commit private keys, SSH config, auth/session data, personal host inventories, or the synchronized guidance contents.
- Exact-copy presets include instruction files only. Settings may use the semantic Codex projection; credentials, providers, trust paths, tools, plugins, models, sessions, and sticky-rule files stay out.
- Keep Unix and Windows OpenSSH targets supported. Do not weaken one platform to simplify the other.

## Development

- Use PowerShell 7.2 or newer.
- Keep `Sync-AgentGuidance` as the only public command unless a new public surface has a clear operator need. `ag-sync` is an allowed alias of that command, not a second engine.
- Verify harness paths and precedence against current first-party documentation before changing compatibility claims or examples.
- Run `pwsh -NoProfile -File tests/Test-AgentGuidanceSync.ps1` after behavior changes.
- Tests must cover configuration validation and transaction failure paths, not only the happy path.
- Do not make live remote writes from automated tests.
