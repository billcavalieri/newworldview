# NewWorldView

A read-only macOS 26 app for inspecting NewWorld Mac OS ROM files (`tbxi` bootinfo images such as Mac OS 9.2.1).

Open a ROM with **File → Open**. The app parses the CHRP bootscript, Trampoline ELF, Toolbox parcels, PowerPC ROM (ConfigInfo / NanoKernel / emulator), and the embedded 68k SuperMario ROM and resources. Each node can be viewed as text, a hex dump, or disassembly (PowerPC or 68k) when the region is identified as code.

The viewer never writes back to the ROM. Save is disabled.

## ROM files stay local

ROM images are **not** part of this repository. Do not commit them.

A typical 9.2.1 file lives at:

```text
~/Downloads/Mac OS ROM
```

`.gitignore` excludes `*.rom`, `*.tbxi`, and `Mac OS ROM`.

## Build

Open `App/NewWorldView.xcodeproj` in Xcode 26 and run the **NewWorldView** scheme, or:

```bash
swift test
xcodebuild -project App/NewWorldView.xcodeproj -scheme NewWorldView -configuration Debug build
```

The parser library is a Swift package (`NewWorldROM`) that the app links against. Disassembly uses [Capstone](https://github.com/Lakr233/libcapstone-spm). After a ROM opens, the app builds a static **analysis database** (functions, 68k A-traps, call/jump xrefs) using the SheepShaver map of 4 MB MacROM at `0x50000000`. Use **Export Ghidra** to write `analysis.json`, `analysis.xml`, and `LoadNewWorldROM.py`; ROM bytes are never exported. In Ghidra, map your local MacROM at `0x50000000` (and/or 68k Toolbox at `0x00000000`), then run the load script.

## Optional parity check

If [tbxi](https://github.com/elliotnunn/tbxi) is installed, you can dump a local ROM and compare the tree:

```bash
pip install tbxi
tbxi dump "$HOME/Downloads/Mac OS ROM" /tmp/tbxi-ref
```

Set `TBXI_ROM_PATH` when running tests to parse that file as an integration check:

```bash
TBXI_ROM_PATH="$HOME/Downloads/Mac OS ROM" swift test
```

## Credits

- [elliotnunn/tbxi](https://github.com/elliotnunn/tbxi): ROM layout and dump model
- Apple Technote 1167: NewWorld ROM architecture
- Capstone: PowerPC and 68k disassembly

## Mill analysis handoff (macemu)

NewWorldView classifies skip-68k candidates with on-device Apple Foundation Models, human approval, and optional Grok Build escalation. Approved judgments export as `mill-annotations.json`. Historical log analysis produces a ranked **`mill-histogram.json`** and a combined **macemu pipeline** bundle.

### Workflow

1. In NewWorldView: open **Mill logs** → **Analyze logs** (full histogram by default) → review the bar chart and offset tables.
2. **Triage top 68k hotspots** or classify addresses in the Research inspector → review on **Annotations** → Approve / Reject.
3. **Export macemu pipeline** (toolbar or File menu) → writes `mill-histogram.json`, `mill-annotations.json`, `mill-research-report.json`, and `mill-pipeline.json`.
4. For ambiguous sites: **Escalate to Grok Build** → `pack-escalation.md` + `grok-prompt.md`.

### macemu driver

From the macemu repo:

```bash
cd research-score/g3_driver

# Skip-68k: approved NW annotations first, then histogram ranks, then runtime map.
export G3_ANNOTATIONS=/path/to/mill-annotations.json
export G3_HISTOGRAM=/path/to/mill-histogram.json
./run

# Or pass flags explicitly
./g3_driver.py run --annotations mill-annotations.json --histogram mill-histogram.json
```

When annotations or histogram are loaded, `pack-slim.md` includes **NewWorldView annotations** and **histogram** sections for run-wide Grok Build escalation.

CLI parity (no Apple FM in CLI):

```bash
swift run NewWorldViewCLI analyze-logs ~/Documents/GitHub/macemu/research-score --histogram-limit 0
swift run NewWorldViewCLI build-grok-pack-from-log /tmp/ss-g3-mill-6613.log 68K:0005C86C --rom "$ROM" -o /tmp/nw-6613-escalate
swift run NewWorldViewCLI export-histogram ~/Documents/GitHub/macemu/research-score -o /tmp/nw-pipeline --histogram-limit 0
swift run NewWorldViewCLI export-pipeline ~/Documents/GitHub/macemu/research-score -o /tmp/nw-pipeline --annotations /path/to/store.json
swift run NewWorldViewCLI build-grok-pack "$ROM" 68K:00026E90 -o /tmp/nw-pack
swift run NewWorldViewCLI export-annotations /path/to/store.json -o /tmp/nw-export
```

