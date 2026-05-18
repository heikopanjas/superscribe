# superscribe

Transcribe multi-track podcast recordings into a single time-aligned VTT/SRT file. Each speaker is recorded on an isolated audio track; superscribe transcribes every track in parallel, aligns the results on a shared timeline, and merges them into a subtitle format ready for editing or publishing.

## Requirements

- macOS 14 or later
- Apple Silicon (M1 or later) — both backends use Neural Engine / Metal GPU acceleration
- Swift 6.2 (Xcode 16.3 or later)
- `cmake` and `ninja` — required once to build the whisper.cpp xcframework (`brew install cmake ninja`)

## Quick start

```sh
# 1. Build the whisper.cpp static xcframework (one-time, ~2 min)
./_scripts/build-whisper.sh

# 2. Build superscribe
swift build -c release

# 3. Transcribe two tracks and produce a VTT file
superscribe run \
  --track Alice=alice.wav \
  --track Bob=bob.wav \
  --language en \
  > transcript.vtt
```

## Backends

| Name | Flag | Default model | Notes |
|---|---|---|---|
| Parakeet (FluidAudio) | `parakeet` | `v3` | CoreML, Neural Engine, fast |
| whisper.cpp | `whisper.cpp` | `large-v3-turbo` | Metal GPU, GGML binary |
| Apple Speech | `apple-speech` | — | Reserved, not yet implemented |

Parakeet is the default backend. Switch with `--backend whisper.cpp` or set a permanent default:

```sh
superscribe model --set-default large-v3-turbo --backend whisper.cpp
```

## Model management

Models are downloaded on first use. You can also manage them explicitly:

```sh
# List installed models
superscribe model --list

# List available remote models for a backend
superscribe model --list --remote --backend whisper.cpp

# Download a specific model
superscribe model --download medium-q5_0 --backend whisper.cpp

# Remove a model
superscribe model --rm medium-q5_0 --backend whisper.cpp

# Set the default model for a backend
superscribe model --set-default large-v3-turbo --backend whisper.cpp
```

Model storage locations:

| Backend | Location |
|---|---|
| Parakeet | `~/Library/Application Support/FluidAudio/Models/<name>/` |
| whisper.cpp | `~/Library/Caches/superscribe/whisper/<name>.bin` |

## Subcommands

### `transcribe`

Detects speech, runs the ASR backend on each track, and writes an intermediate `.superscribe.<backend>.json` file.

```sh
superscribe transcribe \
  --track Alice=alice.flac \
  --track Bob=bob.flac \
  --language de \
  --backend whisper.cpp \
  --model large-v3-turbo
```

**Options**

| Option | Default | Description |
|---|---|---|
| `--track name=path` | required | Speaker track, repeatable |
| `--backend` | configured default | `parakeet` or `whisper.cpp` |
| `--model` | configured default | Model variant |
| `--language` | auto-detect | ISO language code (e.g. `en`, `de`, `ja`) |
| `--prompt` | — | Context hint to bias recognition |
| `--output` | `transcript.superscribe.<backend>.json` | Intermediate file path |
| `--silence-threshold` | `-40.0` dB | Silence detection threshold |
| `--min-silence` | `0.5` s | Minimum gap to count as silence |
| `--padding` | `0.15` s | Padding added around speech segments |
| `--verbose` | off | Show per-segment progress |
| `--no-cache` | off | Disable the audio conversion cache |

**Scanning a directory**

If your tracks are in a directory, generate a mapping file automatically:

```sh
# Scan directory and create tracks.superscribe.json in the current directory
superscribe transcribe --create-input /path/to/recordings

# Edit tracks.superscribe.json to rename speakers, then transcribe
superscribe transcribe --input tracks.superscribe.json --language de
```

`tracks.superscribe.json` maps speaker names to file paths relative to the current directory:

```json
{
  "speaker-1" : "recordings/alice.flac",
  "speaker-2" : "recordings/bob.flac"
}
```

### `merge`

Merges an existing intermediate file into a formatted output. Useful for re-rendering without re-transcribing.

```sh
superscribe merge transcript.superscribe.whisper.cpp.json \
  --format vtt \
  --overlap-policy preserve \
  > transcript.vtt
```

**Options**

| Option | Default | Description |
|---|---|---|
| `--format` | `vtt` | Output format (`vtt`; `srt`, `json`, `txt` planned) |
| `--merge-output` | stdout | Output file path |
| `--overlap-policy` | `preserve` | How to handle overlapping speech |
| `--gap-threshold` | `3.0` s | Insert paragraph breaks at gaps longer than this |
| `--max-cue-duration` | — | Split cues longer than this |
| `--include-words` | off | Embed word-level timestamps in the output |

### `run`

Transcribe and merge in a single pass. Accepts all options from both `transcribe` and `merge`.

```sh
superscribe run \
  --track Alice=alice.wav \
  --track Bob=bob.wav \
  --language en \
  --format vtt \
  > transcript.vtt
```

Add `--keep-intermediate` to also save the `.superscribe.json` file.

### `model`

Manage models. See [Model management](#model-management) above.

### `backends`

List available backends and their capabilities:

```sh
superscribe backends
superscribe backends --capabilities
```

### `cache`

Manage the converted-audio cache. superscribe converts source audio to 16 kHz mono PCM on first use and stores the result in `~/.cache/superscribe/audio/`. Subsequent runs skip re-conversion.

```sh
# Show cache location, entry count, and total size
superscribe cache

# List all cached entries with source filename, size, and age
superscribe cache --list

# Remove the cache entry for a specific source file
superscribe cache --rm /path/to/recording.flac

# Delete the entire cache (prompts for confirmation)
superscribe cache --clear

# Delete without confirmation
superscribe cache --clear --yes
```

## Intermediate format

`transcribe` writes a `.superscribe.<backend>.json` file containing the raw transcription results before merging. Tracks with no speech are omitted.

```json
{
  "version": 1,
  "created": "2026-05-18T17:09:30Z",
  "metadata": {
    "backend": "whisper.cpp",
    "model": "large-v3-turbo",
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

## Building the whisper.cpp xcframework

The xcframework is not included in the repository (it is gitignored). Build it once before the first `swift build`:

```sh
./_scripts/build-whisper.sh
```

The script downloads whisper.cpp v1.7.5, compiles it with CMake/Ninja targeting `arm64` with Metal GPU support, and produces `whisper-build/whisper.xcframework`. Re-running is a no-op if the xcframework already exists. To rebuild from scratch, delete `whisper-build/` and re-run.

## Project structure

```
Sources/
  SuperscribeKit/          Core library (importable by Swift apps)
    Backends/              ParakeetBackend, WhisperBackend
    Format/                VTTFormatter
    Analyzer.swift         Silence detection
    AudioPreparer.swift    Audio conversion and slicing
    ConvertedAudioCache.swift
    Merger.swift           Timeline alignment and overlap resolution
    Pipeline.swift         Orchestrates conversion + transcription
    Transcriber.swift      Transcriber protocol
    Types.swift            Core value types
  superscribe/             CLI executable (thin wrapper over SuperscribeKit)
    Commands/
      Options.swift
      Subcommands.swift
    SuperscribeCommand.swift
Tests/
  superscribeTests/        Unit and integration tests
_scripts/
  build-whisper.sh         xcframework build script
```

## Running tests

```sh
swift test
```

## License

See LICENSE.
