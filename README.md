# TimeTrack3

A minimal macOS menu-bar time tracker.

## Usage

1. Click the ⏱ icon in the menu bar.
2. Type what you're working on and press **Start** (or Enter).
3. Switch back and click **Stop** when done.

## Data Storage

Time records are stored locally in `~/.local/share/timetrack3/records.json`.
Only today's records are kept in memory.

## Architecture

- **Rust** (`src/lib.rs`) — core logic, exposed as a static library via C FFI.
- **Swift** (`swift/App.swift`) — macOS UI: menu bar, floating window, file save panel.
- `build.sh` compiles Rust, bundles the static library, and links the Swift binary into a `.app`.

## Build

```bash
./build.sh
cp -r TimeTrack3.app /Applications/
```

Requires `cargo` and `swiftc`.