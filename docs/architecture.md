# drive-beagle — Architecture

## What it is

`drive-beagle` is a cross-platform desktop sync utility for Google-Drive-backed
folders. It uses [`rclone`](https://rclone.org) as the actual sync engine and
shells out to `inotifywait` (Linux) or `fswatch` (macOS) for filesystem
events. The Flutter desktop app hosts a small UI plus an in-process engine
that watches local changes, debounces them, runs `rclone` safely, and writes
an authoritative change journal that coding agents (Claude Code, Codex, etc.)
can consume.

This document describes the *what* and *why*. The CLI surface and JSON
schemas live in [agent-integration.md](./agent-integration.md).

## Top-level shape

```
+---------------------------------------------------------------+
|                       drive-beagle.app                        |
|                                                               |
|   +---------+      +-----------+      +---------------+      |
|   |  UI     | <--> |  Engine   | <--> |  Watcher(s)   |      |
|   | (Riverpod)     | (in-proc) |      | inotify / fsw |      |
|   +---------+      +-----------+      +---------------+      |
|        ^                |  |                                  |
|        |                v  v                                  |
|        |        +-------+  +---------+   +---------------+    |
|        |        | Queue |  | Sched   |   | rclone (proc) |    |
|        |        +-------+  +---------+   +---------------+    |
|        |                |                                     |
|        |                v                                     |
|        |        +---------------+    +-----------------+      |
|        |        | Journal +     |    | Snapshots dir   |      |
|        |        | SQLite index  |    | (lsjson, walk)  |      |
|        |        +---------------+    +-----------------+      |
|        |                                                      |
|        +-------- Control socket (Unix domain) ----------------+
|                                                       ^       |
+-------------------------------------------------------|-------+
                                                        |
                                              +----------------+
                                              |  drive-beagle  |
                                              |   (CLI exe)    |
                                              +----------------+
```

* All boxes inside the dotted area run in the **same Dart isolate** as the
  Flutter UI — that's the all-in-one architecture the user requested.
  Subprocesses (rclone, inotifywait, fswatch) are spawned via `Process.start`.
* The CLI is a separate `dart compile exe` binary. It connects to the running
  app over a Unix domain socket for live state (RPC). For read-only journal /
  snapshot / cursor commands it bypasses the socket and reads files directly,
  so it works even when the app isn't running.

## Why an all-in-one app?

* Simpler operational model: no separate daemon to start/stop/upgrade.
* On macOS the app marks itself `LSUIElement` and lives as a menu-bar agent
  — perfect for a long-running background process.
* On Linux the user opens the Flutter window when they want to interact, and
  the engine keeps running as long as the process does.
* Persistent state lives on disk (config dir, journal JSONL, SQLite index,
  snapshots). The CLI uses these directly when the app is offline, so agent
  workflows don't lose continuity.

## Sync algorithm

```
watcher event ──► debounce (4s default, max 5×) ──► trigger
reconciler ────────────────────────────────────► trigger    │
manual sync / dry-run / bootstrap ──────────────► trigger   ▼
                                                       SyncQueue
                                                  (per-pair, 1 follow-up)
                                                            │
                              ┌─────────────────────────────┘
                              ▼
                          SyncEngine.runOnce()
                              │
                              ├── pre-snapshot (local walk + rclone lsjson)
                              ├── rclone sync | bisync | mirror
                              ├── post-snapshot
                              └── snapshot diff → ChangeEntry rows → Journal
```

* The sync queue strictly serializes runs per pair. While a run is in flight,
  *one* additional trigger is held in a single follow-up slot; further
  triggers collapse into it.
* `manual` and `bootstrap` triggers always win the coalesce contest over
  passive `watcher` and `reconcile` triggers.
* The reconciliation timer (default 10 minutes) is the source of eventual
  consistency. Watcher events are hints — Linux inotify can drop events on
  freshly-created directories, so we never trust them as authoritative.

## Per-pair finite state machine

```
       start         changeDetected        dispatch
idle ──────► watching ──────────────► pending ───────► syncing
              ▲                                          │
              │                                  runSucceeded
              │                                          │
              └──────────────────────────────────────────┘
                                runFailedRecoverable → warning
                                runFailedFatal       → error
                                pause ⇄ resume       → paused
```

State transitions are unit-tested in
`packages/beagle_core/test/pair_state_machine_test.dart`. Anything not covered
by an explicit transition is rejected — there are no "best-effort" implicit
moves.

## Sync run lifecycle

```
queued → started → snapshotting_pre → syncing → snapshotting_post → journaling
                                                                       │
                                              succeeded | failed | partial
```

Each run has a `SyncRun` row persisted in the per-pair state file plus an
authoritative set of `ChangeEntry` rows in the journal.

## Data on disk

```
~/.config/drive-beagle/                        (Linux)
~/Library/Application Support/drive-beagle/    (macOS)
├── config.yaml
├── cursors.json
├── drive-beagle.lock
├── logs/
│   └── drive-beagle.YYYY-MM-DD.jsonl
├── journal/
│   ├── <pair_id>.jsonl       — durable, append-only source of truth
│   └── <pair_id>.db          — SQLite index (rebuildable from JSONL)
├── snapshots/
│   ├── <pair_id>.local.pre.<run>.json
│   ├── <pair_id>.remote.pre.<run>.json
│   └── ...
└── state/
    ├── state.json            — last run / lifecycle / counters per pair
    ├── filters.<pair_id>.txt — generated rclone filter file
    └── bisync.<pair_id>/     — rclone bisync workdir
```

Recovery: if the SQLite index is corrupt or missing, `Journal.open()` detects
the gap and replays from the JSONL. `drive-beagle doctor --rebuild-index`
can do the same on demand.

## Watcher backends

Both backends produce a normalized `WatcherEvent { pairId, backend, path,
kind, tsUtc, raw }` stream. The supervisor restarts a crashed watcher with
exponential backoff (1s → 30s, capped) and surfaces a `warning` health state
after 5 consecutive restarts.

* **inotifywait** (`-m -r --csv --format '%w,%e,%f' -e modify,create,delete,move,attrib`)
  — manual CSV parser handles filenames containing commas/quotes/newlines.
  Linux watch-limit (`/proc/sys/fs/inotify/max_user_watches`) is read at
  startup and surfaced via `doctor`.
* **fswatch** (`-0 -r -x --event-flag-separator=, --latency 0.5`) — NUL-
  delimited record reader; FSEvents-backed monitor scales well for large
  trees.

## rclone integration

`RcloneCommandBuilder` is a pure command-vector factory — it never builds a
shell string. Defaults baked in (overridable via `RcloneFlagPreset`):

* `--use-json-log --stats-one-line --stats=10s`
* `--transfers=4 --checkers=8 --retries=3 --low-level-retries=5`
* `--fix-case --no-slow-hash --create-empty-src-dirs`
* `--drive-skip-gdocs` (Google Docs don't round-trip as files)
* `--compare size,modtime`

Bisync flags: `--resilient --recover` plus a per-pair `--workdir` under the
config dir. Conflict policies map onto rclone's `--conflict-resolve`/
`--conflict-suffix` options.

## Change journal & cursor model

Per pair we keep `<pair_id>.jsonl` (one entry per line) and `<pair_id>.db`
(SQLite). The two are written transactionally; on open we reconcile them.

Each entry distinguishes **tentative** events (watcher source) from
**authoritative** events (sync/reconcile source). The default behaviour of
`drive-beagle changes` is authoritative-only; `--include-tentative` opts in.

Cursors live in `cursors.json`, keyed by `(pair_id, consumer)`. `ack` is
idempotent and only ever advances. A request to ack a cursor beyond the
journal's latest sequence is rejected with `CURSOR_MISMATCH`.

See [agent-integration.md](./agent-integration.md) for the full flow.

## Error model

`BeagleError` carries a stable `code` (e.g. `RCLONE_MISSING`,
`BISYNC_NEEDS_RESYNC`, `CURSOR_MISMATCH`), a human message, and an optional
`remedy`. CLI exit codes map onto these classes (see `cli_runner.dart`).
The same codes appear in UI error banners and `doctor` output.

## Test strategy

Pure-Dart tests live under `packages/beagle_core/test/`:
* command-builder + filter-generator goldens
* inotifywait CSV / fswatch NUL parser tests with weird filenames
* sync queue serialization properties
* FSM transition matrix
* journal append/read/replay
* cursor at-least-once semantics
* snapshot diff classifier

Integration tests gated on `RCLONE_AVAILABLE` set up an `rclone local:` remote
and exercise the full pipeline.

## Known limitations

* Inotify can miss events on directories created and populated within a few
  ms; the periodic reconciler is the safety net.
* Google native docs (`gdoc`, `gsheet`) are skipped by default — they don't
  round-trip as files.
* Bisync requires a one-time explicit `--resync` bootstrap; we never perform
  it implicitly.
* Conflict UI is intentionally minimal: rclone writes `*.conflict.local` /
  `.remote` files in the local folder and we surface a badge. The user
  resolves them in their editor.
* Linux: no GTK tray icon in MVP. The Flutter window is the UI; you can
  minimize but not hide-into-tray.
