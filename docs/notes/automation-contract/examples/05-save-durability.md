# Save durability interpretation

## Request
<!-- source: accepted immediate-save request capture -->
```json
{
  "command": "session.save",
  "args": {
    "files": [
      "VT_AutomationScripts_20260506_231439.esp"
    ]
  }
}
```

## Response
<!-- source: accepted immediate-save response capture -->
```json
{
  "ok": true,
  "command": "session.save",
  "result": {
    "savedFilesNow": [
      {
        "name": "VT_AutomationScripts_20260506_231439.esp",
        "loadOrder": 10,
        "loadOrderFileId": "09",
        "fileName": "VT_AutomationScripts_20260506_231439.esp",
        "isEditable": true,
        "isESM": false,
        "isLight": false,
        "isMedium": false,
        "modified": false,
        "masters": []
      }
    ],
    "savedFilesPendingShutdown": [],
    "savedNowCount": 1,
    "savePendingShutdownCount": 0,
    "dirtyState": {
      "dirtyFiles": [],
      "unsavedChangeCount": 0,
      "dirty": false
    }
  }
}
```

## Request
<!-- source: accepted pending-save request capture -->
```json
{
  "command": "session.save",
  "args": {
    "files": [
      "VT_Cleaning_Quick_20260504_115128.esp",
      "VT_Cleaning_Auto_20260504_115128.esp",
      "VT_Cleaning_Masters_20260504_115128.esp"
    ]
  }
}
```

## Response
<!-- source: accepted pending-save response capture -->
```json
{
  "ok": true,
  "command": "session.save",
  "result": {
    "savedFilesNow": [],
    "savedFilesPendingShutdown": [
      {
        "name": "VT_Cleaning_Quick_20260504_115128.esp",
        "loadOrder": 9,
        "loadOrderFileId": "09",
        "fileName": "VT_Cleaning_Quick_20260504_115128.esp",
        "isEditable": true,
        "isESM": false,
        "isLight": false,
        "isMedium": false,
        "modified": false,
        "masters": [
          "Fallout4.esm",
          "VT_Cleaning_Source_20260504_115128.esm"
        ]
      },
      {
        "name": "VT_Cleaning_Auto_20260504_115128.esp",
        "loadOrder": 10,
        "loadOrderFileId": "0A",
        "fileName": "VT_Cleaning_Auto_20260504_115128.esp",
        "isEditable": true,
        "isESM": false,
        "isLight": false,
        "isMedium": false,
        "modified": false,
        "masters": [
          "VT_Cleaning_Source_20260504_115128.esm"
        ]
      },
      {
        "name": "VT_Cleaning_Masters_20260504_115128.esp",
        "loadOrder": 11,
        "loadOrderFileId": "0B",
        "fileName": "VT_Cleaning_Masters_20260504_115128.esp",
        "isEditable": true,
        "isESM": false,
        "isLight": false,
        "isMedium": false,
        "modified": false,
        "masters": []
      }
    ],
    "savedNowCount": 0,
    "savePendingShutdownCount": 3,
    "dirtyState": {
      "dirtyFiles": [],
      "unsavedChangeCount": 0,
      "dirty": false
    }
  }
}
```

## What to key on
- `result.savedFilesNow`: files saved immediately by the call.
- `result.savedFilesPendingShutdown`: files whose save succeeded but final on-disk rename/durability is deferred until shutdown.
- `result.dirtyState`: dirty-state readback after the save operation.
- A successful `session.save` response is not a fresh-restart durability proof by itself.

The two source-linked responses above predate the 0.23 pending-queue readback.
In 0.23, every `dirtyState` also carries `pendingShutdownFiles` and
`pendingShutdownCount`, as shown in the complete flow below.

## 0.23 pending-readback and flush flow

### 1. Save an already-loaded plugin

For a memory-mapped plugin whose final file already exists, `session.save` writes
the new bytes to `<name>.save.<timestamp>` in the data path and queues the final
rename:

```json
{
  "ok": true,
  "command": "session.save",
  "result": {
    "savedFilesNow": [],
    "savedFilesPendingShutdown": [
      { "name": "Patch.esp", "fileName": "Patch.esp", "modified": false }
    ],
    "savedNowCount": 0,
    "savePendingShutdownCount": 1,
    "dirtyState": {
      "dirtyFiles": [],
      "unsavedChangeCount": 0,
      "dirty": false,
      "pendingShutdownFiles": [
        {
          "tempFile": "Patch.esp.save.2026_08_11_12_34_56",
          "file": { "name": "Patch.esp", "fileName": "Patch.esp", "modified": false }
        }
      ],
      "pendingShutdownCount": 1
    }
  }
}
```

`dirty:false` means there are no unsaved in-memory modifications. It does not
mean the queued rename has completed.

### 2. Read the lifecycle state

`session.get_dirty_state` returns the same pending queue independently of dirty
state:

```json
{
  "command": "session.get_dirty_state",
  "args": {}
}
```

```json
{
  "ok": true,
  "command": "session.get_dirty_state",
  "result": {
    "dirtyFiles": [],
    "unsavedChangeCount": 0,
    "dirty": false,
    "pendingShutdownFiles": [
      {
        "tempFile": "Patch.esp.save.2026_08_11_12_34_56",
        "file": { "name": "Patch.esp", "fileName": "Patch.esp", "modified": false }
      }
    ],
    "pendingShutdownCount": 1
  }
}
```

### 3. Flush pending renames and exit

The daemon must have been launched with `-IKnowWhatImDoing` because
`session.flush` is consent-gated as `session-mutation`:

```json
{
  "command": "session.flush",
  "args": {}
}
```

```json
{
  "ok": true,
  "command": "session.flush",
  "result": {
    "flushedFiles": [
      { "fileName": "Patch.esp", "renamed": true }
    ],
    "pendingRemaining": [],
    "pendingRemainingCount": 0,
    "dirtyState": {
      "dirtyFiles": [],
      "unsavedChangeCount": 0,
      "dirty": false,
      "pendingShutdownFiles": [
        {
          "tempFile": "Patch.esp.save.2026_08_11_12_34_56",
          "file": { "name": "Patch.esp", "fileName": "Patch.esp", "modified": false }
        }
      ],
      "pendingShutdownCount": 1
    }
  }
}
```

The returned `dirtyState` is the pre-drain safety snapshot. The authoritative
post-drain fields are `pendingRemaining` and `pendingRemainingCount`. A failed
rename carries `renamed:false` plus `error`, remains in `pendingRemaining`, and
gets one final process-exit retry.

The response is written and flushed before the daemon performs its clean
self-exit. Once exit is armed, no further command is accepted. Even an empty
pending queue returns a response and then exits. If unsaved modified files exist,
the command returns `state_conflict` and stays running unless `force:true` is
passed.

### 4. Relaunch and read back

After relaunch, `session.get_dirty_state` must report
`pendingShutdownCount: 0`. Read the mutated record or element again from the
fresh daemon to prove that the final module contains the saved value. This fresh
readback, not the earlier `session.save` success envelope alone, closes the
durability loop.
