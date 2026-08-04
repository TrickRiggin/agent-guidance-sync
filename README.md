# agent-guidance-sync

Safely preview and synchronize global agent-instruction files across Windows and Linux machines over SSH.

It started as a way to keep Codex `AGENTS.md` and Claude `CLAUDE.md` aligned across a small fleet without passing files through chat, email, or a cloud-drive folder. The file mappings are generic, so it can synchronize other small text configuration files too.

## Why this is safer than a copy loop

- Preview-only by default, with readable diffs.
- Remote writes require `-Apply`.
- Every payload is staged on every reachable target before any destination changes.
- Each write is fenced by the remote SHA-256 observed during preview; a concurrent edit aborts that write.
- Existing files receive timestamped backups.
- Replacement is atomic on Unix and Windows.
- Final content is read back and independently hash-verified.
- Unix and Windows targets are detected automatically.

This is not a distributed transaction across the whole fleet. A host can still fail after an earlier host commits. The operation is deliberately rerunnable, and every changed destination retains a backup.

## Requirements

- PowerShell 7.2 or newer on the source machine.
- `ssh`, `scp`, and `git` available on `PATH`.
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

From the repository root:

```powershell
pwsh -NoProfile -File ./install.ps1
```

For development, install a directory link so edits in the clone become the installed module immediately:

```powershell
pwsh -NoProfile -File ./install.ps1 -DevelopmentLink
```

The installer refuses to replace an existing `AgentGuidanceSync` installation unless `-Force` is supplied. Forced replacements are moved to a timestamped backup instead of deleted.

## Configure

Copy [`config.example.json`](config.example.json) to the default private location:

```powershell
$configDirectory = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config/agent-guidance-sync'
New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
Copy-Item ./config.example.json (Join-Path $configDirectory 'config.json')
```

Then edit the private config:

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

## Use

Preview the entire configured fleet:

```powershell
Sync-AgentGuidance
```

Apply exactly what was previewed:

```powershell
Sync-AgentGuidance -Apply
```

Limit a run to one or more targets:

```powershell
Sync-AgentGuidance -ComputerName host-one
Sync-AgentGuidance -ComputerName host-one,host-two -Apply
```

Existing Codex and Claude sessions may retain startup instructions. Start a new session after syncing when you need the new guidance loaded immediately.

## Test

The test suite has no external PowerShell-module dependencies:

```powershell
pwsh -NoProfile -File ./tests/Test-AgentGuidanceSync.ps1
```

It validates config boundaries, escaping, module exports, generated commit logic, stale-hash rejection, corrupt-stage rejection, backups, atomic replacement, and readback receipts without touching a remote host.

## License

[MIT](LICENSE)
