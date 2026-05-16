# homebrew-hugin

Homebrew tap for [Hugin](https://hugin.sourceforge.net) — panorama photo stitcher — built from source for **Apple Silicon (macOS 10.15+)**.

The official Hugin 2025.0.1 release doesn't ship a macOS ARM binary. This tap builds it from source and applies a set of patches that fix issues specific to Apple Silicon / modern macOS:

| Patch | Problem fixed |
|---|---|
| `Executor.cpp` | `execvp(enblend, ...) failed with error 2` — `CFBundleCopyAuxiliaryExecutableURL` returns NULL in child processes; replaced with direct `bindir + name` lookup |
| `huginApp.cpp`, `hugin_executor.cpp`, `PTBatcherGUI.cpp`, `hugin_stitch_project.cpp` | Invisible blocking modal "Cannot set locale to language 'English (UAE)'" on systems with an unsupported system locale (e.g. `en_AE`); pre-check via `setlocale()` and silently fall back to `en_US` |
| `FindVIGRA.cmake` | VIGRA version header uses preprocessor macros, not a string literal; version parsing rewritten to extract `MAJOR`/`MINOR`/`PATCH` individually |
| `CMakeLists.txt` | Deployment target bumped from 10.9 → 10.15 (`std::filesystem` requires Catalina+) |
| `ptbatcher/CMakeLists.txt`, `stitch_project/CMakeLists.txt` | Remove references to pre-built `enblend`/`enfuse` that don't exist in the Homebrew build; binaries are built from source instead |

VIGRA and enblend/enfuse are not in Homebrew core — this formula builds them from source as part of the install.

Internal Hugin dylibs (`libhuginbase`, `libhuginbasewx`, `libceleste`, `libicpfindlib`, `liblocalfeatures`) are embedded into each `.app` bundle with `@executable_path` references so the apps are fully self-contained.

## Install

```sh
brew tap danwald/hugin
brew install hugin-src-2025
```

`hugin-link` symlinks all four apps into `~/Applications` so they appear in Spotlight and Launchpad immediately. Re-run it after `brew upgrade hugin-src-2025` to refresh the symlinks.

> **Note:** macOS sandboxes the Homebrew install process and blocks writes to `~/Applications` — that's why `hugin-link` is a separate step rather than happening automatically.

For a system-wide install in `/Applications` instead:

```sh
sudo cp -R "$(brew --prefix hugin-src-2025)/Applications/Hugin.app" /Applications/
```

## What's included

| App | Description |
|---|---|
| `Hugin.app` | Main panorama stitching GUI |
| `PTBatcherGUI.app` | Batch processor |
| `HuginStitchProject.app` | Stitch a `.pto` project file directly |
| `calibrate_lens_gui.app` | Lens calibration tool |

All tools (`nona`, `enblend`, `enfuse`, `exiftool`, `align_image_stack`, etc.) are bundled inside each `.app`.

## Build time

~2 minutes on Apple M-series (downloads ~50 MB; compiles VIGRA + enblend + Hugin in parallel).

## Caveats

- Requires macOS Catalina (10.15) or later.
- ExifTool is pulled from the `exiftool` Homebrew formula.
- If you already have Hugin installed via DMG, remove it first to avoid conflicts.

