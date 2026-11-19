# Harpy Dock

A native macOS configuration app for the **Kreo Harpy Gaming Mouse**, which uses the
Instant Microelectronics **A825** controller (`30FA:1440`).

It replaces the Windows DevDock utility for the settings that matter day to day:
six DPI stages, stage colors, the active stage, USB polling rate, button mapping,
lighting effects, rapid-fire interval, and double-click timing.

No firmware is ever written. No driver or kernel extension is installed.

## First run: Input Monitoring

macOS treats the mouse's configuration interface as an input device, so the app
must be allowed to open it. On first launch Harpy Dock shows an Input Monitoring
banner:

1. Click **Open Settings**.
2. Enable **Harpy Dock** under Privacy & Security > Input Monitoring.
3. Click **Retry** in the app, or quit and reopen it.

The app keeps its own profile and backups in
`~/Library/Application Support/HarpyDock/`.

Without this permission the app can see the mouse but cannot read or write its
configuration reports. The permission is tied to the app's signature; rebuilding
the bundle may require granting it again.

## Downloaded release

The GitHub release is a universal build (Apple Silicon and Intel) signed ad-hoc,
not notarized. macOS will warn on first launch:

1. Unzip `HarpyDock-1.0.0-macOS-universal.zip`.
2. Move `HarpyDock.app` to Applications.
3. Right-click the app and choose **Open**, or clear the quarantine flag:

   ```sh
   xattr -dr com.apple.quarantine /Applications/HarpyDock.app
   ```

4. Grant Input Monitoring when the app asks (see above).

## Build and run

```sh
make app     # builds HarpyDock.app
open HarpyDock.app
```

Or run from source while developing:

```sh
swift test
swift run HarpyDock
```

Requirements: macOS 13 or later, Xcode command line tools.

## What it reads and writes

The mouse exposes a vendor feature report: report ID `0x07`, seven data bytes,
eight bytes including the report ID. The app opens the HID interface that declares
that report, reads the documented configuration blocks, and writes only the blocks
that differ from what the mouse currently holds. A shared lock serializes every
transaction, so the app and `harpyctl` can never interleave frames.

| Block | Field |
| --- | --- |
| `0x0008` | six button registers |
| `0x0010` | six DPI scale nibbles at `0x0015..0x0017` |
| `0x0018` | active stage, enabled mask, double-click ms, polling divisor |
| `0x0020`, `0x0028` | six stage-indicator colors (nine bytes of inverted nibbles) |

Before a write the app:

1. reads every owned block,
2. saves them to `~/Library/Application Support/HarpyDock/Backups/`,
3. writes only changed eight-byte blocks using the vendor `0x18` transaction,
4. sends the vendor finalize sequence,
5. reads every written block back and verifies it,
6. restores the original bytes if anything fails.

The mouse keeps a persistent configuration and a live runtime. DPI changes take
effect immediately. The button table is a known exception: the controller may keep
using the old table until the mouse is unplugged for about ten seconds. The app
verifies the stored bytes, not the firmware reload.

Lighting effects and the rapid-fire interval are **live reports**. They are not
stored in the mouse and are forgotten on power loss, so the Lighting and Advanced
panes have their own send buttons.

## Command line

```sh
swift run harpyctl list       # find the mouse
swift run harpyctl dump       # read and decode the current state
swift run harpyctl probe      # raw eight-byte blocks
swift run harpyctl selftest   # rewrite block 0x0008 with identical bytes and verify
```

`selftest` is the only command that writes, and it writes back the exact bytes it
just read. It is intended to prove the write path without changing the mouse.

## Scope

Implemented:

- six DPI stages with enable flags, values from the A825 table (200 to 12800 DPI)
- active stage
- stage indicator colors (4-bit RGB, matching the hardware)
- USB polling rate: 125, 250, 500, 1000 Hz
- six button actions: native DPI button, left, right, middle, back, forward,
  DPI up/down, double click, rapid fire, next profile, next lighting, disabled
- lighting modes exposed by the Windows app (constant, breathing, flowing water,
  mono water, comet tail, neon, ambilight, flashing, star trek, ripple,
  enraptured, response, off) with brightness, speed, direction, and color
- rapid-fire interval, 10 to 1000 ms
- double-click interval, 100 to 255 ms

Not implemented in this version:

- keyboard, media, and per-button macro assignments (the Windows app stores these
  in a different action space and uses a macro engine)
- macro editor and recording
- profile slots beyond the hardware's active profile
- update UI
- reading the current lighting mode (the controller does not expose it)

## Notes on the protocol

The byte layouts were cross-checked against the Windows DevDock binary extracted
from the Kreo installer and against the open-source EvoFox Phantom Air Linux
project, which documents the same A825 chip and the same `30FA:1440` device:

- `<https://github.com/Navadeep-Reddy/evofox-phantom-air-linux>`

That project's protocol notes and constants were used to confirm the memory
transaction, the persistent field addresses, the DPI scale-code wrapping, and the
lighting frame layout. The app here is an independent Swift implementation.

Four-bit color channels are inverted on the wire, and the DPI scale code wraps
every 16 values, so a stored nibble can mean two DPI values. The app keeps the
value read from the mouse and tells you when a stage is ambiguous instead of
guessing.

## Safety

- Only the five documented blocks above are ever written.
- No arbitrary address or firmware upload is exposed.
- Every write is backed up and verified.
- Changes are staged in the UI and sent only after the confirmation sheet.
- The app is signed with a local Apple Development identity when one is present,
  otherwise ad-hoc. It is not notarized.
