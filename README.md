# superscribe

Transcribe podcast recordings into time-aligned VTT, SRT, JSON, or TXT output. Use isolated tracks for named speakers, mixed recordings with on-device speaker diarization, or both. Optional [vocal isolation](#vocal-isolation) removes accompaniment before speech detection and diarization. superscribe transcribes speech segments in parallel, aligns the results on a shared timeline, and merges them into output ready for editing or publishing.

Core logic lives in **SuperscribeKit**, a Swift library you can import from your own macOS apps; the `superscribe` CLI is a thin wrapper around it.

## Requirements

Runtime:

- macOS 14 or later on Apple Silicon (M1 or later)
- macOS 26 or later for the **Apple Speech** backend (`appleSpeech`)

Building from source also requires:

- Swift 6.4.2, managed with Swiftly (`.swift-version`), plus Xcode 26 or later for Apple SDKs and native tools
- Xcode's Metal Toolchain component — install with `xcodebuild -downloadComponent MetalToolchain` and verify with `xcrun metal --version`. If lookup still reports the component missing after installation, run `xcrun --kill-cache` and retry
- `cmake` and `ninja` — required once to build the whisper.cpp xcframework (`brew install cmake ninja`)

## Quick start

```sh
# 1. Build the whisper.cpp static xcframework (one-time)
./_scripts/bootstrap.sh

# 2. Build superscribe
swiftly install
source "$HOME/.swiftly/env.sh"
swift build -c release
export PATH="$(swift build -c release --show-bin-path):$PATH"

# 3. Transcribe two tracks and produce a VTT file
superscribe run \
  --track Alice=alice.wav \
  --track Bob=bob.wav \
  --language en \
  > transcript.vtt
```

Parakeet and whisper.cpp models download automatically on first use (progress on stderr). Apple Speech requires macOS 26+ and also installs locale assets automatically on first use; `model --download` is optional when you want to pre-install a model or locale.

The PATH change applies to the current shell. Check the installed version with `superscribe --version`.

Use `superscribe --help` to list subcommands and `superscribe <subcommand> --help` for that command's complete usage.

For automatic toolchain selection in future Zsh sessions, source `"$HOME/.swiftly/env.sh"` from your login (`.zprofile`) and interactive (`.zshrc`) startup files. Swiftly then reads `.swift-version` when you run `swift`; verify the selected toolchain with `swift --version`.

## Speech detection and time-sliced transcription

For isolated tracks, speaker identity comes from the file mapping. For shared-microphone recordings, use `--mixed` to infer speakers; see [Mixed recordings](#mixed-recordings-speaker-diarization).

**Silence-aware time slicing** avoids running ASR over long silent stretches. superscribe uses energy-based detection on isolated tracks and speaker activity on mixed tracks, then transcribes only the resulting speech spans. Word timestamps are mapped back onto the full recording timeline.

### End-to-end flow

```mermaid
flowchart TB
  subgraph per_track ["Per source track: bounded preparation"]
    A["Source file"] --> O{"--isolate?"}
    O -->|Yes| V["HTDemucs vocal isolation<br/>htdemucs or htdemucs_ft"]
    O -->|No| B["Convert or reuse cached audio<br/>16 kHz mono Float32 PCM"]
    V --> B
    B --> K{"Track type"}
    K -->|Named speaker| C["RMS silence detection"]
    K -->|Mixed recording| L["Nemotron speaker diarization"]
    C --> D["Speaker tracks and speech segments"]
    L --> M["Build speaker turns<br/>one virtual track per speaker"]
    M --> D
  end
  subgraph transcribe ["Per speech segment (bounded parallel)"]
    D --> E[Slice PCM for segment]
    E --> F["Transcription backend<br/>Parakeet / whisper.cpp / Apple Speech"]
    F --> G[Words with absolute timestamps]
  end
  subgraph merge_phase ["All tracks"]
    G --> H[Intermediate transcript containing all tracks]
    H --> I[Flatten + sort by time]
    I --> J[Merge → VTT / SRT / JSON / TXT]
  end
```

1. **Optionally isolate vocals** — `--isolate` runs the configured isolation backend before segmentation. HTDemucs processes stereo audio at 44.1 kHz in bounded sections; `--fine-tune` selects its `htdemucs_ft` model. Without `--isolate`, this step is skipped.
2. **Prepare PCM** — Audio is normalized to the transcription backend format (today: **16 kHz, mono, 32-bit float PCM**) and retained as file-backed `PreparedAudio`. The audio cache stores ordinary conversion and isolated vocals under separate identities; `--no-cache` bypasses both.
3. **Detect or diarize** — `Analyzer` finds speech spans in named-speaker tracks. The configured diarizer identifies speakers in mixed tracks and produces a virtual track per voice. Both paths use the same gap merging, bounded padding, and minimum-duration rules. Boundaries stay on the original track timeline.
4. **Slice and transcribe** — `PreparedAudio` reads active segment samples, and the transcription backend returns word timestamps anchored to the original track.
5. **Merge** — The intermediate transcript is combined chronologically across speakers (overlap policies, paragraph breaks, cue formatting). `transcribe` saves it to JSON; `run` renders it directly and saves it only with `--keep-intermediate`. Isolation, detection, and diarization do not run again during `merge`.

Preparation handles at most **2** source tracks at once by default, or **1** when isolation is enabled. Cached PCM persists; uncached temporary PCM is removed when its final owner releases it. Segments across all tracks share one global limit of **2** concurrent ASR calls. A Whisper context has exclusive access on its own serial worker; it is never shared by concurrent C inference calls.

### Mixed recordings (speaker diarization)

A track passed with `--mixed path` (or marked `"diarize": true` in the mapping file) holds several speakers. Instead of silence detection, superscribe runs [NVIDIA Nemotron 3 Diarization](https://huggingface.co/nvidia/Nemotron-3-Diarization) on the Neural Engine via FluidAudio (Core ML, streaming `fast128` preset, up to **8** speakers):

1. The prepared 16 kHz PCM is streamed through the diarizer in 30-second windows, producing per-speaker probabilities every 10 ms.
2. Each frame goes to its most likely speaker at or above 0.5, so overlapping speech in the shared recording is transcribed once.
3. Turns are smoothed with the same `--min-silence`, `--padding`, and minimum-segment rules as silence detection; padding never crosses into a neighbor's turn.
4. Every diarized speaker becomes its own track in the intermediate transcript, so merging and all output formats work unchanged.

Name speakers in the mapping file with `"speakers"`, in order of first appearance; mapping two slots to the same name merges them. Unnamed speakers receive consecutive `Speaker 1…N` labels across all mixed tracks. Mixed and isolated tracks can be combined in one session.

```sh
superscribe run --mixed panel.wav --language en > panel.vtt
```

The diarizer model (~190 MiB, `FluidInference/nemotron-3-diarization-coreml`, OpenMDW-1.1) downloads into `~/.cache/superscribe/models/diarizer/` on the first mixed run, or ahead of time with `superscribe model --diarizer --download nemotron-3-diarization`.

### Silence detection algorithm

Detection is **energy-based**, not ML-based: fast, deterministic, and tunable from the CLI. It operates on the **converted** PCM (same sample rate the recognizer uses), so slice boundaries match what the backend actually hears.

**Step 1 — Windowed RMS.** The buffer is scanned in non-overlapping windows (default **1024 samples** → **64 ms** at 16 kHz). For each window the root-mean-square level is computed. The CLI threshold `--silence-threshold` (default **−40 dB**) is converted to a linear amplitude; windows at or above that level count as **speech**, below as **non-speech**.

**Step 2 — Raw speech regions.** A simple state machine walks the windows: transitions from non-speech to speech open a region; transitions back close it. Adjacent speech windows become one contiguous raw region in sample indices.

**Step 3 — Merge short gaps.** Regions separated by less than `--min-silence` (default **0.5 s**) are merged into a single segment. Brief pauses inside a sentence therefore do not split transcription into dozens of tiny calls.

**Step 4 — Padding.** Each merged region is expanded by up to `--padding` (default **0.15 s**) before and after, capped at half of the adjacent silence and clamped to `[0, track duration]`. Padding reduces clipped consonants without making neighboring segments overlap.

**Step 5 — Drop short segments.** Padded regions shorter than **0.1 s** (`minSegmentDuration` in code, not exposed on the CLI) are discarded.

The result is an ordered list of `SpeechSegment` values `{ start, end }` in seconds. When you transcribe, superscribe writes an **intermediate transcript** (default `transcript.superscribe.<backend>.json`). Its `metadata` block includes an `analyzer` object with `silence_threshold_db`, `min_silence`, and `padding` so you can see exactly which detection settings were used when you merge later.

### Time slicing and timestamp alignment

For each `SpeechSegment`:

1. **Slice** — `PreparedAudio.samples(in:)` maps `start`/`end` to sample indices and reads that subrange from the prepared file.
2. **Transcribe and re-anchor** — The backend receives only those samples and adds the segment’s `start` to model timings when mapping its result. The `Transcriber` API returns **absolute** word times on the track clock, which are stored directly in the intermediate file.

Segment boundaries in the JSON (`start` / `end`) come from detection or diarization. Word timestamps usually sit inside that range but can extend slightly when model alignment differs.

Input files must already share a common time origin. superscribe preserves that clock through conversion and isolation; it does not align recordings that started late or apply per-track offsets.

### What gets omitted

After transcription, the pipeline drops:

- **Segments with no words** — e.g. breath, FX, or music that crossed the RMS threshold but produced no ASR output.
- **Entire tracks with no surviving segments** — typical for FX or noise-only stems.

Those tracks do not appear in the intermediate transcript.

### Tuning detection

On isolated tracks, lower `--silence-threshold` (e.g. `-50`) if quiet speech is missed; raise it (e.g. `-30`) if noise or microphone bleed causes false detections. Reduce `--min-silence` to split at shorter pauses, or increase `--padding` to include more audio at segment edges. Mixed tracks use the diarizer's activity threshold, so `--silence-threshold` does not affect them; `--min-silence` and `--padding` still apply. See the [option reference](#transcribe) for defaults.

`transcribe` and `run` always emit progress on stderr: preparation lines such as `Converting alice.wav [42%]` or `Isolating alice.wav [42%]`, then segment lines such as `[Alice] segment 3/12 — overall 7/18`.

## Backends

Transcription, vocal isolation, and speaker diarization have independent backend defaults. Use [`backend`](#backend) to inspect or select an implementation and [`model`](#model) to manage its weights. Selecting a backend does not enable an optional stage: isolation still requires `--isolate`, and diarization requires a mixed input.

### Transcription backends

| Name | Backend id | Default model | Notes |
|---|---|---|---|
| Parakeet (FluidAudio) | `parakeet` | `v3` | CoreML / Neural Engine; fast, low power |
| whisper.cpp | `whisper.cpp` | `large-v3-turbo` | GGML `.bin`; Core ML encoder on ANE when installed, Metal fallback; Metal decoder |
| Apple Speech | `appleSpeech` | locale from system (e.g. `en-US`) | macOS 26+; system locale assets; no Hugging Face download |

Parakeet is the default backend. Switch per run with `--backend whisper.cpp` or `--backend appleSpeech`, or set a permanent default:

```sh
superscribe backend --set-default whisper.cpp
superscribe model --set-default large-v3-turbo --backend whisper.cpp
```

### Parakeet models

| Id | Description |
|---|---|
| `v3` | Multilingual TDT (default) |
| `v2` | English-only TDT |
| `tdt-ctc-110m` | Compact 110M TDT/CTC model |
| `tdt-ja` | Japanese |

Only these supported model families are offered in the catalog; unknown model identifiers are rejected.

### whisper.cpp models

Any `ggml-<name>.bin` from the [whisper.cpp Hugging Face repo](https://huggingface.co/ggerganov/whisper.cpp) — e.g. `large-v3-turbo`, `base`, `medium-q5_0`. Quantized ids keep the quant suffix; the Core ML encoder bundle uses the base name (e.g. `medium-q5_0` → `ggml-medium-encoder.mlmodelc.zip`).

### Apple Speech locales

Models are **BCP-47 locale ids** (e.g. `en-US`, `de-DE`). The default resolves `Locale.current` to a supported equivalent locale, then falls back to supported `en-US`. Locale is selected with `--model`, not `--language`. Apple manages assets via `AssetInventory`; superscribe auto-installs missing locales on first `transcribe` / `run`, and the `model` subcommand can pre-install or release them explicitly:

```sh
superscribe model --download en-US --backend appleSpeech
superscribe model --list --remote --backend appleSpeech
superscribe run \
  --track Alice=alice.wav \
  --backend appleSpeech \
  --model en-US \
  --format vtt \
  > transcript.vtt
```

Default intermediate output: `transcript.superscribe.appleSpeech.json`. The `metadata.backend` field uses the same string (`appleSpeech`).

Selecting Apple Speech on macOS versions below 26 fails with a clear error.

Use `model --rm <locale> --backend appleSpeech` to release a locale reservation when you hit system limits.

## Configuration and storage

User defaults persist in the configuration file below. `defaultBackend` selects the transcription backend; `defaultIsolatorBackend` and `defaultDiarizerBackend` select the optional processors. `defaultModels` holds per-transcription-backend model preferences. For example:

```json
{
  "defaultBackend": "whisper.cpp",
  "defaultIsolatorBackend": "htdemucs",
  "defaultDiarizerBackend": "nemotron",
  "defaultModels": { "whisper.cpp": "large-v3-turbo" }
}
```

All backend preferences are optional. Missing or unknown backend ids fall back to the built-in default for that type; older configuration files continue to load. Prefer the `backend --set-default` and `model --set-default` commands over editing this file by hand.

| What | Location |
|---|---|
| User config | `~/.config/superscribe/config.json` |
| Model catalog cache | `~/.cache/superscribe/catalog.json` (Parakeet/whisper from Hugging Face; Apple Speech from system locale APIs) |
| Converted audio cache | `~/.cache/superscribe/audio/` |
| Parakeet models | `~/.cache/superscribe/models/transcriber/parakeet/<folder>/` |
| whisper.cpp GGML weights | `~/.cache/superscribe/models/transcriber/whisper/<id>.bin` |
| whisper.cpp Core ML encoder | `~/.cache/superscribe/models/transcriber/whisper/<base>-encoder.mlmodelc/` (auto-downloaded with the `.bin`) |
| Speaker diarizer | `~/.cache/superscribe/models/diarizer/nemotron-3-diarization-fast128/` |
| Vocal isolator | `~/.cache/superscribe/models/isolator/<id>/` |
| Apple Speech locales | System-managed via `AssetInventory` (install marker: `apple-speech://locale/<id>`) |

superscribe owns transcription, isolation, and diarizer model downloads; Apple Speech assets are system-managed. FluidAudio runs in offline mode, and Demucs inference disables upstream downloads.

To reuse transcription models stored directly in `models/parakeet/` and `models/whisper/`, move those two directories into `models/transcriber/` before running the updated CLI. The CLI uses the new layout without automatically migrating existing folders.

**Upgrading from 1.x:** models now live under `~/.cache/superscribe/models` and are downloaded again on first use. Earlier installs are no longer read and can be deleted: superscribe's folders in `~/Library/Application Support/FluidAudio/Models` (`parakeet-tdt-0.6b-v2`, `parakeet-tdt-0.6b-v3`, `parakeet-tdt-ctc-110m`, `parakeet-ja`) and `~/Library/Caches/superscribe/whisper`. Leave other folders in the FluidAudio directory alone if another app uses FluidAudio.

## Subcommands

### `transcribe`

Detects speech, runs ASR on each track, and writes an intermediate `transcript.superscribe.<backend>.json` file. See [Speech detection and time-sliced transcription](#speech-detection-and-time-sliced-transcription) for how detection, slicing, and timestamps work.

```sh
superscribe transcribe \
  --track Alice=alice.flac \
  --track Bob=bob.flac \
  --language de \
  --backend whisper.cpp \
  --model large-v3-turbo
```

| Option | Default | Description |
|---|---|---|
| `--track name=path` | — | Speaker track; repeatable (required unless `--mixed`, `--input`, or `--create-input`) |
| `--mixed path` | — | Mixed multi-speaker recording, diarized into `Speaker 1…N`; repeatable, combinable with `--track` |
| `--input file` | — | Load a track mapping JSON file |
| `--create-input dir` | — | Scan directory → write `tracks.superscribe.json` in cwd |
| `--backend` | configured default | `parakeet`, `whisper.cpp`, or `appleSpeech` |
| `--model` | configured default | Model variant (see [Backends](#backends)); Apple Speech locale id |
| `--language` | auto-detect | ISO language code (e.g. `en`, `de`, `ja`); does not affect `appleSpeech` recognition, but may appear in intermediate metadata |
| `--prompt` | — | Context hint for `whisper.cpp`; accepted but ignored for Parakeet and `appleSpeech` |
| `--output` | `transcript.superscribe.<backend>.json` | Intermediate path (`<backend>` is the resolved backend, e.g. `appleSpeech`) |
| `--silence-threshold` | `-40.0` dB | Energy threshold for isolated tracks; unused for mixed tracks |
| `--min-silence` | `0.5` s | Minimum gap to count as silence |
| `--padding` | `0.15` s | Padding around speech segments, capped at half the adjacent silence |
| `--verbose` | off | Currently accepted but unused; progress is always shown on stderr |
| `--no-cache` | off | Bypass ordinary conversion and isolated-vocal caches |
| `--isolate` | off | Run the configured isolator before detection, diarization, and transcription; applies to every input track |
| `--fine-tune` | off | Select `htdemucs_ft`; requires `--isolate` |

`--input` cannot be combined with `--track` or `--mixed`. `--create-input` cannot be combined with those input options or `--isolate`; it only writes a template. Relative paths in mapping files resolve against the current working directory; absolute paths stay absolute.

**Directory workflow**

```sh
# Scan a directory and create tracks.superscribe.json in the current directory
superscribe transcribe --create-input /path/to/recordings

# Rename speakers in tracks.superscribe.json, then transcribe
superscribe transcribe --input tracks.superscribe.json --language de
```

`--create-input` scans regular files with these extensions: `mp3`, `wav`, `m4a`, `aac`, `flac`, `ogg`, `mp4`, `mov`, `caf`, `opus`.

Example mapping file:

```json
{
  "speaker-1": "recordings/alice.flac",
  "speaker-2": "recordings/bob.flac"
}
```

A value can also be an object describing a mixed recording; `speakers` names diarized voices in order of first appearance (unnamed ones become `Speaker N`):

```json
{
  "host": "recordings/host.flac",
  "panel": { "file": "recordings/panel.flac", "diarize": true, "speakers": ["Carol", "Dave"] }
}
```

### `merge`

Merge an intermediate file into formatted output without re-transcribing.

```sh
superscribe merge transcript.superscribe.whisper.cpp.json \
  --format vtt \
  --overlap-policy preserve \
  > transcript.vtt
```

| Option | Default | Description |
|---|---|---|
| `--format` | `vtt` | `vtt`, `srt`, `json`, or `txt` |
| `--merge-output` | stdout | Output file path |
| `--overlap-policy` | format-dependent | `preserve` for VTT/SRT/JSON; `interleave` for TXT. Explicit `preserve` is invalid for TXT |
| `--gap-threshold` | `3.0` s | Paragraph breaks at longer pauses |
| `--max-cue-duration` | — | Split cues longer than this |
| `--max-line-length` | — | Greedy VTT/SRT wrapping by Swift character count; long words stay intact |
| `--include-words` | off | VTT inline timestamps, SRT word cues, or timestamped TXT words. JSON always keeps word timings |

### Output behavior

- **Preserve** retains overlapping segments in stable chronological order.
- **Trim** ends the earlier speaker's segment when the next competing speaker starts; crossing words are clamped and words starting beyond the boundary are dropped.
- **Interleave** orders every timed word exactly once, breaking ties by track, segment, and word input order, then groups consecutive same-speaker runs.
- Cue splitting prefers the latest sentence boundary within the duration limit, then the latest word boundary. An indivisible timed word/span may exceed the limit; no timing is fabricated.
- VTT escapes text and voice annotations and restricts inline timestamps to increasing times inside the cue. SRT uses numbered cues, comma milliseconds, and `[Speaker]` labels. Quantized cues always have positive duration.
- TXT writes `Speaker: text` runs with blank lines at paragraph breaks. With word output, each word is prefixed by `[HH:MM:SS.mmm]`.
- JSON emits a version-1 document with a `segments` array. Each segment has `speaker`, numeric-second `start`/`end`, `text`, `paragraphBreak`, `overlap`, and complete `words`. Keys are sorted deterministically.

`merge` and `run` use the same renderer. Invalid transcript versions, nonfinite timestamps, reversed intervals, and invalid numeric options throw before rendering.

### `run`

Transcribe and merge in one pass. Accepts `transcribe` and `merge` options **except** `--create-input` and `--input` (those are `transcribe`-only; use `--track` / `--mixed`, or run `transcribe` followed by `merge`).

```sh
superscribe run \
  --track Alice=alice.wav \
  --track Bob=bob.wav \
  --language en \
  --format vtt \
  > transcript.vtt
```

| Option | Default | Description |
|---|---|---|
| (transcribe options) | — | `--track`, `--mixed`, `--backend`, `--model`, `--isolate`, `--fine-tune`, silence tuning, `--no-cache`, etc. |
| (merge options) | — | `--format`, `--overlap-policy`, `--gap-threshold`, `--include-words`, `--merge-output`, etc. |
| `--keep-intermediate` | off | Also write `transcript.superscribe.<backend>.json` (discarded by default) |

On `run`, `--output` only affects the intermediate JSON path when `--keep-intermediate` is set. Use `--merge-output <file>` to write the final rendered output without shell redirection.

### `model`

List, download, and manage models (or Apple Speech locales). `--list` is the default when no other verb is given. Model-type selectors are mutually exclusive: `--transcriber` (the default), `--diarizer`, or `--isolator`.

Local listings use aligned model, size, and location columns. Installed models show their paths; unknown sizes appear as `—`. Diarizer and isolator listings also show supported models that are not installed.

```sh
# Installed models for the configured backend
superscribe model
superscribe model --transcriber  # same as omitting the selector

# Remote catalog — Parakeet/whisper: Hugging Face (standalone --remote refreshes catalog.json)
superscribe model --remote --backend whisper.cpp

# Remote catalog — Apple Speech: system-supported locales (also cached)
superscribe model --remote --backend appleSpeech

# Refresh the remote catalog cache, then list
superscribe model --list --remote --refresh

# Download / remove
superscribe model --download medium-q5_0 --backend whisper.cpp
superscribe model --rm medium-q5_0 --backend whisper.cpp --yes
superscribe model --download de-DE --backend appleSpeech

# Defaults and machine-readable output
superscribe model --set-default v3 --backend parakeet
superscribe model --json --remote

# Speaker diarizer for --mixed tracks
superscribe model --diarizer
superscribe model --diarizer --download nemotron-3-diarization
superscribe model --diarizer --rm nemotron-3-diarization --yes

# Vocal-isolation models
superscribe model --isolator --list
superscribe model --isolator --download htdemucs
superscribe model --isolator --download htdemucs_ft
superscribe model --isolator --rm htdemucs --yes
```

| Option | Description |
|---|---|
| `--transcriber` | Manage transcription models for the selected backend (implicit default) |
| `--backend` | Target transcription backend (defaults to its configured default); invalid with `--isolator` or `--diarizer` |
| `--list` | List models (implicit default) |
| `--remote` | Show the remote catalog; with explicit `--list`, use the cache; alone, refresh first |
| `--refresh` | Re-fetch the catalog only; combine with `--list --remote` to refresh and print remote entries |
| `--download <id>` | Install a model (HF download or Apple Speech locale asset) |
| `--rm <id>` | Remove an installed model or release a locale (`--yes` to skip confirmation) |
| `--set-default <id>` | Set the default transcription model for the backend |
| `--diarizer` | Manage the speaker diarizer instead of a backend; combines only with `--list`, `--download`, `--rm`, `--yes` |
| `--isolator` | Manage `htdemucs` or `htdemucs_ft`; combines only with `--list`, `--download`, `--rm`, `--yes` |
| `--json` | JSON output for list operations (explicit `--list` or implicit default); invalid with `--download`, `--rm`, or `--set-default` |
| `--yes` | Skip confirmation prompts for `--rm` |

`--remote`, `--refresh`, `--set-default`, and `--json` apply only to transcription models. Isolation and diarization support local listing, download, and removal; neither accepts `model --backend`. Backend defaults for all three types are managed separately by [`backend`](#backend).

Parakeet installs fetch only the Core ML bundles and vocabulary FluidAudio loads (v3 ≈ 460 MiB instead of the 3.4 GiB repository). Downloads show progress on stderr and publish validated staged assets atomically. Apple Speech locale installs show asset progress and are system-managed via `AssetInventory`.

### `backend`

List backends, set the default, or show capabilities for a processing type. Selectors are mutually exclusive: `--transcriber` (the default), `--isolator`, or `--diarizer`. Listing is the default when no other verb is given.

```sh
superscribe backend
superscribe backend --transcriber  # same as omitting the selector
superscribe backend --isolator     # htdemucs
superscribe backend --diarizer     # nemotron
superscribe backend --set-default parakeet
superscribe backend --set-default appleSpeech
superscribe backend --isolator --set-default htdemucs
superscribe backend --diarizer --set-default nemotron
superscribe backend --capabilities   # alias: --caps
superscribe backend --isolator --capabilities
superscribe backend --diarizer --caps
```

| Option | Description |
|---|---|
| `--transcriber` | Manage transcription backends: `parakeet`, `whisper.cpp`, `appleSpeech` (implicit default) |
| `--isolator` | Manage vocal-isolation backends: `htdemucs` (models: `htdemucs`, `htdemucs_ft`) |
| `--diarizer` | Manage speaker-diarization backends: `nemotron` (model: `nemotron-3-diarization`) |
| `--list` | List backends (implicit default) |
| `--set-default <backend>` | Persist the selected type's default backend; preserves the other types' defaults and model preferences |
| `--capabilities` / `--caps` | Print the selected type's default backend display name, audio format, built-in default model, and model-list command |

The built-in defaults are `parakeet`, `htdemucs`, and `nemotron`. Older configuration files retain their transcription preferences and use the built-in isolation and diarization defaults. The pipeline uses those defaults when isolation or mixed-track diarization is requested. `appleSpeech` is annotated with `(requires macOS 26+)` when the host OS is below 26.

### `cache`

Manage prepared-audio PCM in `~/.cache/superscribe/audio/`. Ordinary conversion is shared when the required format matches. Isolated vocals use separate cache identities for each model and processing revision.

```sh
superscribe cache              # location, entry count, total size
superscribe cache --list      # one line per entry (size, age, source filename)
superscribe cache --rm /path/to/recording.flac
superscribe cache --clear      # prompts [y/N]
superscribe cache --clear --yes
```

| Option | Description |
|---|---|
| `--list` | List cached audio with size, age, and source filename |
| `--clear` | Delete all cached audio after confirmation |
| `--rm <path>` | Remove all cached variants recorded for a source path, including isolated vocals |
| `--yes` | Skip confirmation for `--clear`; invalid with other operations |

Omitting an operation prints the cache location, entry count, and total size. List, clear, and remove are mutually exclusive. Cache operations affect prepared audio, not installed models.

## Vocal isolation

Add `--isolate` to `transcribe` or `run` to remove accompaniment before speech detection, speaker diarization, and transcription. It applies to all tracks in that invocation, including mixed recordings and input templates. Source filenames and timestamps are preserved.

```sh
superscribe run --track "Alice=alice.wav" --isolate --merge-output transcript.vtt
superscribe run --mixed panel.m4a --isolate --fine-tune --merge-output panel.vtt
```

`--isolate` uses the configured isolation backend (currently `htdemucs`) with its `htdemucs` model; add `--fine-tune` for `htdemucs_ft`. `--fine-tune` requires `--isolate`. The selected model downloads on its first use (about 160 MiB or 641 MiB respectively), with size and SHA-256 verification. Subsequent use is entirely local, without model update checks or automatic replacement downloads. Audio is never uploaded.

Models live in `~/.cache/superscribe/models/isolator/<model-id>/`. Successful-installation receipts live alongside configuration under `~/.config/superscribe/`; removal preserves the receipt. A previously installed model that is missing or corrupt requires explicit repair.

Use [`model --isolator --download <id>`](#model) to repair the selected installation. `backend --isolator --set-default htdemucs` selects the implementation; it does not select `htdemucs_ft` or enable isolation by itself.

Explicit downloads reuse valid installations and repair missing or invalid ones. Failed initial downloads can be retried. Existing ASR and diarizer model installation policies still apply.

Isolation processes 30-second sections with two-second overlaps, retaining stereo input until separation and blending the mono vocals before backend conversion. Memory is bounded independently of recording length; temporary PCM needs disk space proportional to the recording. Fine-tuning runs only the vocals member of the ensemble, though the full upstream weights file is downloaded. The converted vocals are cached separately for each model; `--no-cache` recomputes them, and `cache --rm <source>` removes all cached variants.

Demucs separates music sources; improvement in spoken-word recognition depends on the recording. Input decoding uses the existing macOS audio facilities. Release archives include a required Metal resource bundle: keep it beside the executable when installing or moving superscribe. If installing into a directory on `PATH`, copy the executable and every `.bundle` directory together. Alternatively, keep the extracted directory intact and symlink its executable into your tools directory; resource lookup follows the executable symlink.

## Intermediate format

The intermediate document has version 1 and contains results for every surviving track. Diarized speakers appear as separate tracks referencing the same mixed source file. A top-level `session` field may be present when set by library callers.

```json
{
  "version": 1,
  "created": "2026-05-18T17:09:30Z",
  "metadata": {
    "backend": "whisper.cpp",
    "model": "large-v3-turbo",
    "language": "en",
    "analyzer": {
      "silence_threshold_db": -40,
      "min_silence": 0.5,
      "padding": 0.15
    }
  },
  "tracks": [
    {
      "speaker": "Alice",
      "file": "/path/to/alice.flac",
      "segments": [
        {
          "start": 1.24,
          "end": 3.80,
          "words": [
            { "text": "Hello", "start": 1.24, "end": 1.56 },
            { "text": "world", "start": 1.60, "end": 2.10 }
          ]
        }
      ]
    }
  ]
}
```

## Using SuperscribeKit in a Swift app

The package references a local, generated whisper.cpp xcframework. Clone the repository and run `_scripts/bootstrap.sh` before adding that checkout as a local package dependency (`.package(path: "/path/to/superscribe")`). Add the `SuperscribeKit` product to your target's dependencies, then import it. See [Building the whisper.cpp xcframework](#building-the-whispercpp-xcframework).

Given an input URL `audioURL`, run the following from an async context:

```swift
import SuperscribeKit

// Install or preflight all requested model assets before running the pipeline.
let transcriber = try Backend.parakeet.makeTranscriber(model: "v3")
let config = PipelineConfig(
    tracks: [TrackInput(speaker: "Alice", file: audioURL)],
    backend: .parakeet,
    transcriptionConfig: TranscriptionConfig(language: "en", prompt: nil)
)
let pipeline = TranscribePipeline(
    transcriber: transcriber,
    config: config,
    audioCache: ConvertedAudioCache()
)
let transcript = try await pipeline.run()

let vtt = try TranscriptRenderer.render(
    transcript, configuration: RenderConfiguration(format: .vtt)
)
```

`audioCache` is opt-in for library callers; pass `ConvertedAudioCache()` to match the CLI default. See `Sources/SuperscribeKit/` for `TranscribePipeline`, `Analyzer`, `Merger`, and backends. The CLI under `Sources/superscribe/` demonstrates model install, `BackendManager`, and formatters.

For mixed inputs, mark the track for diarization and provide a diarizer. To isolate vocals as well, supply an isolator:

```swift
let mixedConfig = PipelineConfig(
    tracks: [TrackInput(
        speaker: "Panel", file: audioURL,
        diarization: TrackDiarization(speakerNames: ["Alice", "Bob"])
    )],
    backend: .parakeet,
    transcriptionConfig: TranscriptionConfig(language: "en"),
    diarizer: try DiarizerBackend.nemotron.makeDiarizer(),
    isolator: try IsolatorBackend.htdemucs.makeIsolator(model: .htdemucs)
)
```

Pass this configuration to `TranscribePipeline`. Install the requested models first; mixed input without a diarizer throws. `PipelineConfig` accepts any `Diarizer` and `VocalIsolator` implementation. The library does not implicitly load CLI defaults; callers can resolve them through `UserConfig` and the corresponding backend factories, as `PipelineRunner` does.

## Building the whisper.cpp xcframework

The [quick start](#quick-start) runs `_scripts/bootstrap.sh` before SwiftPM. The script downloads whisper.cpp v1.7.5, compiles with CMake/Ninja for `arm64` with **Metal and Core ML in a single static archive**, and produces the gitignored `whisper-build/whisper.xcframework`. Re-running is a no-op if the xcframework already exists. After a whisper build change, delete `whisper-build/` and run the script again.

CPU compilation uses `GGML_NATIVE=OFF` and an explicit M1-compatible `armv8.4-a+dotprod+fp16` target so binaries remain independent of the build host.

The first transcription with a newly installed Core ML encoder bundle may be slow while macOS compiles the graph for the Neural Engine.

## Project structure

```
Sources/
  SuperscribeKit/          Core library (importable by Swift apps)
    Backends/              ParakeetBackend, WhisperBackend, AppleSpeechBackend (+ registries, LiveAPI)
    Backend.swift          Transcription backend ids
    AppleSpeechAssetInstaller.swift  Locale install via AssetInventory
    Format/                VTT/SRT/TXT/JSON formatters and shared cue utilities
    Diarization/           Diarizer protocol, DiarizerBackend, Nemotron 3 diarizer + model, speaker turns
    IsolatorBackend.swift  Vocal-isolation capabilities and processor factory
    DemucsVocalIsolator.swift  File-backed vocal isolation, overlap blending, and cache reuse
    Analyzer.swift         Silence detection
    AudioPreparer.swift    Audio conversion + slicing (16 kHz mono f32 PCM)
    ConvertedAudioCache.swift
    UserConfig.swift       Independent backend defaults and transcription model preferences
    ModelDownloader.swift  Hugging Face downloads with progress
    ModelInstaller.swift   Atomic ASR, diarizer, and isolator installs; Apple Speech locale lifecycle
    TranscribePipeline.swift  File-backed preparation and global scheduling
    ...
  superscribe/             CLI executable (one file per subcommand)
    TranscribeCommand.swift, MergeCommand.swift, RunCommand.swift
    ModelCommand.swift, BackendCommand.swift, CacheCommand.swift
    BackendTypeOptions.swift  Shared transcriber, isolator, and diarizer selectors
    BackendManager.swift, ModelManager.swift, PipelineRunner.swift, ...
Tests/superscribeTests/    Swift Testing suite
_scripts/
  bootstrap.sh             xcframework build (one-time)
  test.sh                  Serial test runner (recommended)
  coverage.sh              100% SuperscribeKit line + region coverage gate
```

## Development

The [architecture document](_docs/podscribe-design.md) explains processing stages and backend boundaries. The [implementation status](_docs/superscribe-mvp-implementation-plan.md) maps implemented features to source and validation; [AGENTS.md](AGENTS.md) owns development conventions and test policies.

Run the isolated unit suite **serially**, as required by the project's test harness. Select the pinned toolchain through Swiftly first:

```sh
_scripts/test.sh
# or:
swift test --no-parallel -Xswiftc -strict-concurrency=complete
```

Coverage gate (SuperscribeKit line **and** region coverage must stay at 100%):

```sh
_scripts/coverage.sh --run-tests
```

Unit tests use stubs and repository-owned fixtures without downloading models or relying on local caches. Integration tests are opt-in via `SUPERSCRIBE_INTEGRATION_TESTS=1`: inference checks require supplied audio and installed models; the Metal compilation probe needs no model assets and explicitly skips GPU execution when unavailable. See [AGENTS.md](AGENTS.md#test-coverage-mandatory) for the integration commands, documented coverage exclusions, and coverage receipt rules.

## License

MIT — see [LICENSE](LICENSE).
