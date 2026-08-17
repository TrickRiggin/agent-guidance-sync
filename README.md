# agent-guidance-sync

Safely preview and synchronize global agent instructions and a narrow set of portable Codex settings across Windows and Linux machines over SSH.

It started as a way to keep Codex `AGENTS.md` and Claude `CLAUDE.md` aligned across a small fleet without passing files through chat, email, or a cloud-drive folder. The same exact-file engine supports Pi, oh-my-pi, OpenCode, and other harnesses without merging or translating their distinct instructions. An optional semantic projection keeps selected Codex behavior consistent without copying machine-local trust, tools, plugins, or credentials.

## Start here

```powershell
npm install --global agent-guidance-sync
ag-sync -init
```

`-init` writes `~/.config/agent-guidance-sync/config.json`, includes any usual local guidance files it can see, and leaves `host-one` / `host-two` as placeholders. Replace those with SSH aliases from `~/.ssh/config`, then:

```powershell
ag-sync            # preview
ag-sync -apply     # write
```

Preview is the default. `-apply` is the only way to change a remote file. Switches are case-insensitive, so `-Apply` still works. The long command `agent-guidance-sync` is the same program.

## Why this is safer than a copy loop

- Preview-only by default, with readable diffs.
- Remote writes require `-apply`.
- Every payload is staged on every reachable target before any destination changes.
- Each write is fenced by the remote SHA-256 observed during preview; a concurrent edit aborts that write.
- Existing files receive timestamped backups.
- Replacement is atomic on Unix and Windows.
- Final content is read back and independently hash-verified.
- Targets with a hard SSH reachability failure are reported and skipped while reachable targets continue.
- Unix and Windows targets are detected automatically.
- Codex settings are edited with Codex's own version-fenced config API; unowned TOML survives on each target.

This is not a distributed transaction across the whole fleet. A host can still fail after an earlier host commits. The operation is deliberately rerunnable, and every changed destination retains a backup.

An unavailable target is skipped only when its initial SSH probe reports a hard network failure such as a timeout, refused connection, missing route, or unresolved hostname. Authentication failures, host-key failures, missing remote tools, invalid paths, and failures after inventory begins still stop the run. If every configured target is unavailable, the command fails without changing anything.

## Requirements

- PowerShell 7.2 or newer on the source machine.
- `ssh`, `scp`, and `git` available on `PATH`.
- Codex CLI 0.146 or newer on the source machine when `codexConfig` is enabled. Targets do not need Codex for projection.
- SSH access to every target. Passwordless keys are strongly recommended because the command uses SSH batch mode and will not stop for password prompts.
- Unix targets need `sha256sum`, `diff`, `cp`, `mv`, `mkdir`, `chmod`, and `rm`.
- Windows targets need OpenSSH Server and Windows PowerShell available as `powershell.exe`.

Put ports, usernames, identity files, and unusual addresses in `~/.ssh/config`; keep the sync config limited to stable SSH aliases.

For passwordless operation, generate a keypair on the source machine, install only its `.pub` file on each target, and point an SSH alias at the private key:

```sshconfig
Host host-one
    HostName host-one.example.net
    User your-user
    IdentityFile ~/.ssh/id_ed25519_agent_guidance
    IdentitiesOnly yes
```

Verify the exact non-interactive path the module uses before syncing:

```powershell
ssh -o BatchMode=yes host-one hostname
```

Never copy a private key to the repository or to the destination machines.

## Install

Install the published CLI from npm:

```powershell
npm install --global agent-guidance-sync
```

This installs `ag-sync` and the longer `agent-guidance-sync` name. PowerShell 7.2 or newer is still required at runtime; npm is the delivery mechanism, not a JavaScript rewrite. A module install from this repo exports the same `ag-sync` alias.

To install directly from a repository clone instead, run:

```powershell
pwsh -NoProfile -File ./install.ps1
```

For development, install a directory link so edits in the clone become the installed module immediately:

```powershell
pwsh -NoProfile -File ./install.ps1 -DevelopmentLink
```

The installer refuses to replace an existing `AgentGuidanceSync` installation unless `-Force` is supplied. Forced replacements are moved to a timestamped backup instead of deleted.

## Configure

The usual path is `ag-sync -init`. That creates the default private config directory and writes a starter `config.json` without overwriting an existing file.

If you prefer to copy a preset by hand:

```powershell
$configDirectory = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config/agent-guidance-sync'
New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
```

From a repository clone, [`config.example.json`](config.example.json) is a copy-ready starter:

```powershell
Copy-Item ./config.example.json (Join-Path $configDirectory 'config.json')
```

For an npm installation, the starter has this shape:

```json
{
  "sourceLabel": "primary-workstation",
  "targets": ["host-one", "host-two"],
  "files": [
    {
      "name": "AGENTS.md",
      "sourcePath": "~/.codex/AGENTS.md",
      "destinationPath": ".codex/AGENTS.md"
    }
  ]
}
```

`sourcePath` may be absolute, `~`-relative, or relative to the config file. `destinationPath` must be relative to the remote user's home directory. Absolute paths and parent traversal are rejected.

The default config is `~/.config/agent-guidance-sync/config.json`. Override it with `-ConfigPath` or the `AGENT_GUIDANCE_SYNC_CONFIG` environment variable.

Do not commit the private config, guidance files, SSH configuration, keys, or authentication/session data. None are needed by this repository.

### Portable Codex settings

Use [`config.codex-portable.example.json`](config.codex-portable.example.json) when one workstation should define fleet-wide Codex behavior. The projection is key-based, not a `config.toml` copy. Putting `codexConfig` in the JSON makes those settings available; it does not include them in a normal run.

```powershell
ag-sync -settings            # preview portable Codex settings
ag-sync -settings -apply     # write only that projection
```

A default `ag-sync -apply` still writes instruction files only.

```json
{
  "codexConfig": {
    "sourcePath": "~/.codex/config.toml",
    "destinationPath": ".codex/config.toml",
    "keyPaths": [
      "model_reasoning_effort",
      "service_tier",
      "desktop.followUpQueueMode",
      "tui.status_line"
    ],
    "windowsKeyPaths": ["windows.sandbox"],
    "removeKeyPaths": ["features.js_repl"]
  }
}
```

For every target, the module downloads that target's current config, verifies its hash, asks the local Codex app-server to edit a temporary copy, and stages the resulting target-specific candidate. The normal preview hash remains the commit fence. Existing targets retain file permissions; a newly created Unix `config.toml` is mode `0600`.

The allowed settings are deliberately compiled into the module. Projection cannot address:

- `projects` trust entries or paths.
- MCP servers, apps/connectors, plugins, marketplaces, or skill rules.
- Provider endpoints, headers, hooks, shell policy, or notification commands.
- Auth, sessions, local databases, generated notices, or NUX state.

This keeps "same behavior" separate from "same machine." Raw file mappings are also barred from targeting settings, auth, model, session, state, database, or private-key files. If a new portable setting is genuinely useful, add it to the reviewed allowlist and cover it with a test.

### Multi-harness configuration

[`config.multi-harness.example.json`](config.multi-harness.example.json) contains verified native mappings for six harnesses:

| Harness | Global instruction file | Important behavior |
|---|---|---|
| Codex | `~/.codex/AGENTS.md` | Codex-native global guidance. |
| Claude Code | `~/.claude/CLAUDE.md` | Claude-native global guidance. |
| Grok | `~/.grok/AGENTS.md` | Grok-native global rules. Applies to every project. |
| Pi | `~/.pi/agent/AGENTS.md` | Pi's global context file. |
| oh-my-pi | `~/.omp/agent/AGENTS.md` | Native OMP context; it has the highest OMP discovery priority. |
| OpenCode | `~/.config/opencode/AGENTS.md` | Native OpenCode rules; these take precedence over its Claude compatibility fallback. |

The Pi path and context behavior are documented in [Using Pi](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/usage.md#context-files). OMP documents its native path, provider precedence, and shadowing behavior in [Context files](https://github.com/can1357/oh-my-pi/blob/main/docs/context-files.md). OpenCode documents its global path and Claude fallback in [Rules](https://opencode.ai/docs/rules/). Grok documents global rules under `~/.grok/` in [AGENTS.md](https://docs.x.ai/build/features/project-rules); the named home file is `~/.grok/AGENTS.md`.

Copy the broader preset instead of the two-file starter when you use those harnesses:

```powershell
Copy-Item ./config.multi-harness.example.json (Join-Path $configDirectory 'config.json')
```

Each source file remains distinct and is copied byte-for-byte to the same native path on every target. Remove mappings for harnesses you do not use; a configured source file that does not exist fails closed before networking begins.

The preset intentionally excludes:

- API keys, tokens, SSH keys, and authentication files.
- Settings, provider configuration, model catalogs, and session history.
- Pi's `SYSTEM.md` and `APPEND_SYSTEM.md`, which alter the system prompt rather than serving as ordinary global guidance.
- OMP's `RULES.md`, which is short, sticky, and precedence-sensitive. Add it as a separate explicit mapping only when you deliberately want identical sticky rules on every target.
- Grok's `config.toml`, `auth.json`, sessions, and `~/.grok/rules/` directory. Those are machine-local settings, credentials, or a folder of files rather than one global instruction file.

OMP can read several other harness conventions, but creating its native `~/.omp/agent/AGENTS.md` changes which user-level file wins. Keep that mapping only when you maintain genuinely OMP-specific guidance.

## Use

If you do not have a config yet:

```powershell
ag-sync -init
```

Preview the entire configured fleet:

```powershell
ag-sync
```

Apply exactly what was previewed:

```powershell
ag-sync -apply
```

Limit a run to one or more targets:

```powershell
ag-sync -ComputerName host-one
ag-sync -ComputerName host-one,host-two -apply
```

Portable Codex settings, if configured, are a separate run:

```powershell
ag-sync -settings
ag-sync -settings -apply
```

`agent-guidance-sync` and `Sync-AgentGuidance` accept the same parameters. After a module-only install, `ag-sync` is the exported alias for `Sync-AgentGuidance`.

Existing harness sessions may retain their startup instructions. Start a new session after syncing when you need the new guidance loaded immediately.

## Test

The test suite has no external PowerShell-module dependencies:

```powershell
pwsh -NoProfile -File ./tests/Test-AgentGuidanceSync.ps1
```

It validates config boundaries, semantic TOML preservation, target isolation, safe preview output, escaping, module exports, generated commit logic, stale-hash rejection, corrupt-stage rejection, backups, atomic replacement, and readback receipts without touching a remote host.

## Release

Update the matching versions in `package.json` and `AgentGuidanceSync/AgentGuidanceSync.psd1`, merge the change to `main`, then push an annotated version tag:

```powershell
$version = (Get-Content package.json -Raw | ConvertFrom-Json).version
git tag -a "v$version" -m "agent-guidance-sync $version"
git push origin "v$version"
```

The tag must exactly match the npm version with a `v` prefix. GitHub Actions tests the tagged source and publishes through npm trusted publishing; no npm token is stored in GitHub.

## License

[MIT](LICENSE)
