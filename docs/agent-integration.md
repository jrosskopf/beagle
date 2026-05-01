# Agent integration

`drive-beagle` exposes a stable JSON API through its CLI so coding agents like
Claude Code or Codex can determine exactly what changed in a watched folder
since the last sync — and acknowledge each batch independently of every other
consumer.

## Why this matters

`rclone` already syncs files. What it doesn't give you is a clean answer to:

> "What has changed in `~/memory` since the last time **I** looked at it?"

Multiple agents may want to consume the same sync pair (e.g. an indexer, a
memory updater, an embedding pipeline). They should be able to consume
independently, idempotently, and at-least-once. That's exactly the
`drive-beagle changes` / `ack` pair below.

## The agent loop

```
                       ┌──────────────────────────────┐
                       │  drive-beagle (running app)  │
                       │  watching ~/memory           │
                       └──────────────────────────────┘
                                     │
                            sync run completes
                                     │
                                     ▼
                       writes authoritative entries
                       to journal/<pair>.jsonl + .db
                                     │
            ┌────────────────────────┴────────────────────────┐
            ▼                        ▼                        ▼
   ┌──────────────┐         ┌──────────────┐         ┌──────────────┐
   │ claude-code  │         │ codex        │         │ memory-agent │
   │ cursor: 42   │         │ cursor: 17   │         │ cursor: 99   │
   └──────────────┘         └──────────────┘         └──────────────┘
```

Each consumer keeps its own cursor. New journal entries are visible to all of
them; ack only advances the calling consumer's cursor.

## End-to-end example: Claude Code reacts to remote markdown updates

Suppose `~/memory` is a sync pair named `memory`, mirrored from Google Drive
in bidirectional mode.

```bash
# 1. Ask "what's new for me?"
drive-beagle changes \
  --pair memory \
  --consumer claude-code \
  --unacked \
  --extensions .md \
  --format json
```

Sample response (abridged):

```json
{
  "schema_version": "1.0",
  "pair":   { "id": "4f3c4f8d-…", "name": "memory" },
  "consumer": "claude-code",
  "cursor": 173,
  "generated_at": "2026-05-01T10:11:12Z",
  "authoritative": true,
  "count": 2,
  "changes": [
    {
      "id": 172,
      "pair_id": "4f3c4f8d-…",
      "sync_run_id": "f10c…",
      "timestamp": "2026-05-01T10:09:55Z",
      "source": "sync",
      "side": "remote",
      "kind": "modified",
      "path": "memory/project-x/notes.md",
      "previous_path": null,
      "extension": ".md",
      "fingerprint": {
        "strategy": "size_modtime",
        "size": 4193,
        "modtime": "2026-05-01T10:09:50Z"
      },
      "sync_status": "applied",
      "agent_visibility": true,
      "authoritative": true,
      "metadata": {}
    },
    {
      "id": 173,
      "kind": "created",
      "side": "remote",
      "path": "memory/project-x/queries.md",
      "extension": ".md",
      "authoritative": true,
      "...": "..."
    }
  ]
}
```

```bash
# 2. Read the changed files locally — they're already mirrored.
cat ~/memory/project-x/notes.md
cat ~/memory/project-x/queries.md
# … the agent updates its own indexes / memory / actions …

# 3. Acknowledge the batch.
drive-beagle ack \
  --pair memory \
  --consumer claude-code \
  --cursor 173

# 4. Next call returns no further changes until something else syncs.
drive-beagle changes --pair memory --consumer claude-code --unacked --format json
# {"count": 0, "cursor": 173, "changes": [], …}
```

## CLI reference (agent commands)

All commands return JSON by default and include `schema_version: "1.0"`.
Pin on the major component — additive changes bump the minor.

### `drive-beagle changes`

```
drive-beagle changes
  --pair <id-or-name>            # required
  [--consumer <name>]            # required if --unacked
  [--unacked]                    # auto-resolve cursor for this consumer
  [--cursor <seq>]               # explicit numeric journal id
  [--since <ISO-8601>]           # explicit timestamp
  [--kinds created,modified,deleted,moved,conflict]
  [--extensions .md,.json,…]
  [--limit N]                    # default 500
  [--include-tentative]          # also include watcher events (off by default)
  [--format json|jsonl|table]
```

### `drive-beagle changes-since`

Alias of `changes` with mandatory `--since`. Both commands share the same
flag set.

```
drive-beagle changes-since --pair memory --since 2026-05-01T12:00:00Z --format json
```

### `drive-beagle last-sync`

Returns the last attempted run and last successful run for a pair.
Includes start/end, duration, exit code, counts, command summary,
and optional error message.

### `drive-beagle snapshot`

Captures or prints the current indexed view.

```
drive-beagle snapshot --pair memory --side remote --fresh
```

### `drive-beagle diff`

```
drive-beagle diff --pair memory --from last-sync --to now --against local
```

Output classifies created / modified / deleted / moved entries.

### `drive-beagle watch-events`

Streams **tentative** watcher events as JSONL. Requires the app to be
running. Use sparingly — these events are hints, not authoritative truth.

```
drive-beagle watch-events --pair memory
```

### `drive-beagle ack`

Advance a consumer cursor. Idempotent: replaying a cursor below the current
high-water mark is silently accepted. Cursors above the latest journal
sequence return `CURSOR_MISMATCH`.

```
drive-beagle ack --pair memory --consumer claude-code --cursor 173
```

## Authoritative vs tentative

| Source     | Authoritative | When to use                       |
|------------|--------------|-----------------------------------|
| `sync`     | yes          | confirmed change after rclone run |
| `reconcile`| yes          | confirmed by periodic reconciler  |
| `bootstrap`| yes          | from initial bisync resync        |
| `manual`   | yes          | confirmed by manual sync run      |
| `watcher`  | no           | filesystem hint, may be missed/stale |

Default `changes` queries return authoritative-only — that's what agents
should rely on. `--include-tentative` is for tools that explicitly want
near-real-time hints (e.g. live preview).

## Exit codes

| Code | Meaning                            |
|------|------------------------------------|
| 0    | OK                                 |
| 2    | User error (bad args, bad config)  |
| 3    | App not running (and required)     |
| 4    | rclone failure                     |
| 5    | Watcher failure / dependency missing |
| 6    | Journal / cursor error             |
| 1    | Internal error                     |

Errors print a JSON object to stderr:

```json
{ "code": "BISYNC_NEEDS_RESYNC", "message": "...", "remedy": "..." }
```

## Suggested usage patterns

* **Indexer agent**: poll `drive-beagle changes --unacked --consumer indexer
  --pair <pair>` every minute, walk the resulting paths, update the index,
  then `ack`.
* **Memory updater**: subscribe with `--include-tentative` for snappier UX;
  rely on the next authoritative batch to reconcile.
* **CI / cron**: use `--since 2026-05-01T00:00:00Z` to harvest changes for
  daily summaries; no need for cursors.
