# agent-guidance-sync

Safely preview and synchronize global agent instructions and a narrow set of portable Codex settings across Windows and Linux machines over SSH.

It started as a way to keep Codex `AGENTS.md` and Claude `CLAUDE.md` aligned across a small fleet without passing files through chat, email, or a cloud-drive folder. The same exact-file engine supports Pi, oh-my-pi, OpenCode, and other harnesses without merging or translating their distinct instructions. An optional semantic projection keeps selected Codex behavior consistent without copying machine-local trust, tools, plugins, or credentials.

## Why this is safer than a copy loop

- Preview-only by default, with readable diffs.
- Remote writes require `-Apply`.
- Every payload is staged on every reachable target before any destination changes.
- Each write is fenced by the remote SHA-256 observed during preview; a concurrent edit aborts that write.
- Existing files receive timestamped backups.
- Replacement is atomic on Unix and Windows.
- Final content is read back and independently hash-verified.
- Unix and Windows targets are detected automatically.
- Codex settings are edited with Codex's own version-fenced config API; unowned TOML survives on each target.

This is not a distributed transaction across the whole fleet. A host can still fail after an earlier host commits. The operation is deliberately rerunnable, and every changed destination retains a backup.

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

This installs the `agent-guidance-sync` command. PowerShell 7.2 or newer is still required at runtime; npm is the delivery mechanism, not a JavaScript rewrite.

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

Create the default private configuration directory and put your `config.json` there:

```powershell
$configDirectory = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config/agent-guidance-sync'
New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
```

If you are working from a repository clone, [`config.example.json`](config.example.json) is a copy-ready starter:

```powershell
Copy-Item ./config.example.json (Join-Path $configDirectory 'config.json')
```

For an npm installation, create `config.json` using this same starter structure:

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

Use [`config.codex-portable.example.json`](config.codex-portable.example.json) when one workstation should define fleet-wide Codex behavior. The projection is key-based, not a `config.toml` copy:

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

[`config.multi-harness.example.json`](config.multi-harness.example.json) contains verified native mappings for five harnesses:

| Harness | Global instruction file | Important behavior |
|---|---|---|
| Codex | `~/.codex/AGENTS.md` | Codex-native global guidance. |
| Claude Code | `~/.claude/CLAUDE.md` | Claude-native global guidance. |
| Pi | `~/.pi/agent/AGENTS.md` | Pi's global context file. |
| oh-my-pi | `~/.omp/agent/AGENTS.md` | Native OMP context; it has the highest OMP discovery priority. |
| OpenCode | `~/.config/opencode/AGENTS.md` | Native OpenCode rules; these take precedence over its Claude compatibility fallback. |

The Pi path and context behavior are documented in [Using Pi](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/usage.md#context-files). OMP documents its native path, provider precedence, and shadowing behavior in [Context files](https://github.com/can1357/oh-my-pi/blob/main/docs/context-files.md). OpenCode documents its global path and Claude fallback in [Rules](https://opencode.ai/docs/rules/).

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

OMP can read several other harness conventions, but creating its native `~/.omp/agent/AGENTS.md` changes which user-level file wins. Keep that mapping only when you maintain genuinely OMP-specific guidance.

## Use

Preview the entire configured fleet with the npm-installed CLI:

```powershell
agent-guidance-sync
```

Apply exactly what was previewed:

```powershell
agent-guidance-sync -Apply
```

Limit a run to one or more targets:

```powershell
agent-guidance-sync -ComputerName host-one
agent-guidance-sync -ComputerName host-one,host-two -Apply
```

If you installed the module directly from a clone, use its PowerShell command instead:

```powershell
Sync-AgentGuidance
```

Apply exactly what was previewed:

```powershell
Sync-AgentGuidance -Apply
```

The same parameters are available:

```powershell
Sync-AgentGuidance -ComputerName host-one
Sync-AgentGuidance -ComputerName host-one,host-two -Apply
```

Existing harness sessions may retain their startup instructions. Start a new session after syncing when you need the new guidance loaded immediately.

## Test

The test suite has no external PowerShell-module dependencies:

```powershell
pwsh -NoProfile -File ./tests/Test-AgentGuidanceSync.ps1
```

It validates config boundaries, semantic TOML preservation, target isolation, safe preview output, escaping, module exports, generated commit logic, stale-hash rejection, corrupt-stage rejection, backups, atomic replacement, and readback receipts without touching a remote host.

## License

[MIT](LICENSE)
