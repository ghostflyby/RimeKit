SwiftRime
=========

A lightweight, Swifty wrapper around [librime](https://github.com/rime/librime).

Status: early but useful. It wraps the core lifecycle, sessions, key processing, commit retrieval, and offers safe access to context/status with automatic memory management.

Requirements
- librime installed and discoverable via pkg-config (`rime`). On macOS via Homebrew: `brew install librime`.
- Swift 6 toolchain (Package.swift uses tools-version 6.1).

Installation
Add to your Package.swift dependencies and target:

```
.package(path: "../SwiftRime"),
```

Usage
```
import SwiftRime

// 1) Initialize engine
let engine = RimeEngine.shared
try engine.initialize(.init(
    sharedDataDir: "/usr/local/share/rime",  // adjust to your system
    userDataDir: "~/.local/share/rime"        // adjust to your system
))

// 2) Create a session
let session = try RimeSession()

// 3) Send keys or text
_ = session.input("nihao")
_ = session.send(.space) // select first candidate

// 4) Read commit if any
if let text = session.getCommitText() {
    print("commit:", text)
}

// 5) Inspect context/status safely
if let snap = session.snapshotContext() {
    print("preedit:", snap.preedit)
    print("candidates:", snap.menu?.candidates.map{ $0.text } ?? [])
}

// 6) Finalize when done (optional; deinit also finalizes)
engine.finalize()
```

Notes
- The wrapper provides `withContext {}` and `withStatus {}` closures so you can access the full `RimeContext` / `RimeStatus` structs, while the wrapper handles allocation and freeing.
- `KeyModifier` and `KeyCode` help with common key events; you can also pass raw key codes.
- For deployment and maintenance tasks, see `RimeEngine.deploy*`, `startMaintenance`, and `joinMaintenance`.

