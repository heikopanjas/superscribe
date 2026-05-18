# podscribe — Design & Implementation Plan

## Overview

podscribe is a command-line tool that transcribes podcasts from pre-mix isolated speaker tracks. By working with individual tracks rather than a mixed-down recording, podscribe gets speaker attribution for free — no diarization needed — and skips silence to reduce transcription time, producing a precise, speaker-attributed podcast transcript.

The tool is written in Swift, targeting macOS on Apple Silicon.


## Core Insight

Podcasters record each participant on a separate track. Before the episode is mixed and mastered, these tracks exist as individual audio files. podscribe exploits this by:

1. Analyzing each track independently for speech segments (silence detection).
2. Transcribing only the speech segments, tagged with the speaker name from the track.
3. Merging all speakers' transcriptions into a single chronological transcript.

This avoids the error-prone speaker diarization step entirely and skips large stretches of silence (a guest track may be 90% silent), dramatically reducing transcription cost and time.


## Architecture

### Project Structure

```
podscribe/
├── Package.swift
├── Sources/
│   ├── podscribe/                    # CLI executable
│   │   ├── PodscribeCommand.swift    # @main, subcommand routing
│   │   ├── TranscribeCommand.swift
│   │   ├── MergeCommand.swift
│   │   └── RunCommand.swift
│   ├── PodscribeCore/                # library, testable
│   │   ├── Analyzer.swift            # silence detection, RMS
│   │   ├── Transcriber.swift         # protocol + types
│   │   ├── WhisperBackend.swift      # whisper.cpp via C API
│   │   ├── MLXBackend.swift          # mlx-swift whisper
│   │   ├── SpeechBackend.swift       # SFSpeechRecognizer
│   │   ├── OpenAIBackend.swift       # OpenAI Whisper API
│   │   ├── Merger.swift              # chronological interleave
│   │   ├── Segment.swift             # shared types
│   │   ├── Pipeline.swift            # orchestrates transcribe + merge
│   │   └── Format/
│   │       ├── VTTFormatter.swift
│   │       ├── SRTFormatter.swift
│   │       ├── JSONFormatter.swift
│   │       └── TextFormatter.swift
│   └── PodscribeModels/              # model download/cache
│       └── ModelManager.swift
└── Tests/
    └── PodscribeCoreTests/
```

### Dependencies

- **swift-argument-parser** — CLI framework
- **whisper.cpp** — C API, linked via SwiftPM C target or system library
- **mlx-swift** + **mlx-swift-lm** — MLX Whisper inference (minimum macOS 14)
- **Speech.framework** — Apple's on-device speech recognition (system framework)
- **Foundation** — URLSession for OpenAI API calls, JSONEncoder/Decoder
- **AVFoundation / CoreAudio** — audio file reading and PCM decoding


## CLI Design

### Subcommands

podscribe has three subcommands: `transcribe` (Phase 1), `merge` (Phase 2), and `run` (both phases in a single pass).

```
podscribe transcribe [options] --track <name=path> ...
podscribe merge [options] <intermediate-file>
podscribe run [options] --track <name=path> ...
```

### transcribe

Detects speech segments and transcribes each track. Produces an intermediate transcript file.

```
OPTIONS:
  --track <name=path>        Speaker track (repeatable)
  --session <path>           Session manifest (YAML)
  --backend <backend>        whisper|mlx|speech|openai|auto (default: auto)
  --model <model>            Whisper model size (default: large-v3-turbo)
  --language <code>          Language code, e.g. en, de (default: auto-detect)
  --prompt <text>            Context hint for recognition
  --output <path>            Intermediate file (default: transcript.podscribe.json)
  --silence-threshold <dB>   Silence threshold in dB (default: -40)
  --min-silence <seconds>    Minimum silence gap to split (default: 0.5)
  --padding <seconds>        Speech segment padding (default: 0.15)
  --verbose                  Show progress and segment details
```

### merge

Merges an intermediate transcript into a formatted output.

```
ARGUMENTS:
  <intermediate-file>        Path to .podscribe.json

OPTIONS:
  --format <format>          vtt|srt|json|txt (default: vtt)
  --output <path>            Output file (default: stdout)
  --overlap-policy <policy>  preserve|trim|interleave (default: preserve)
  --max-line-length <chars>  Wrap long cues (for vtt/srt)
  --max-cue-duration <secs>  Split cues longer than this
  --gap-threshold <seconds>  Insert paragraph breaks for pauses > this
  --include-words            Keep word-level timestamps (vtt/json)
```

### run

Transcribe and merge in a single pass. Accepts all options from both subcommands.

```
OPTIONS:
  (all transcribe options)
  (all merge options)
  --keep-intermediate        Save the intermediate file (default: discard)
```

### Session Manifest

For repeatable workflows, a YAML manifest can replace CLI flags:

```yaml
session: "Episode 42 - Interview with Bob"
tracks:
  - name: Alice
    file: tracks/alice.wav
  - name: Bob
    file: tracks/bob.wav
backend: mlx
language: en
prompt: "Alice, Bob, Kubernetes, PostgreSQL"
output:
  format: vtt
  file: ep42-transcript.vtt
analyzer:
  silence_threshold_db: -38
  min_silence: 0.4
  padding: 0.15
```

### Shared Option Groups

```swift
struct TranscribeOptions: ParsableArguments {
    @Option var track: [String]
    @Option var session: String?
    @Option var backend: Backend = .auto
    @Option var model: String = "large-v3-turbo"
    @Option var language: String?
    @Option var prompt: String?
    @Option var silenceThreshold: Double = -40.0
    @Option var minSilence: Double = 0.5
    @Option var padding: Double = 0.15
    @Flag   var verbose: Bool = false
}

struct MergeOptions: ParsableArguments {
    @Option var format: OutputFormat = .vtt
    @Option var output: String?
    @Option var overlapPolicy: OverlapPolicy = .preserve
    @Option var maxLineLength: Int?
    @Option var maxCueDuration: Double?
    @Option var gapThreshold: Double?
    @Flag   var includeWords: Bool = false
}
```


## Core Types

```swift
struct TimedWord: Codable, Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

struct SpeechSegment: Codable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
}

struct TranscriptionResult: Sendable {
    let segment: SpeechSegment
    let words: [TimedWord]
}

struct TranscriptionConfig: Sendable {
    let language: String?
    let model: WhisperModel
    let prompt: String?
}

struct AttributedSegment {
    let speaker: String
    let start: TimeInterval
    let end: TimeInterval
    let words: [TimedWord]
}

struct MergedSegment {
    let speaker: String
    var start: TimeInterval
    var end: TimeInterval
    var words: [TimedWord]
    let paragraphBreak: Bool
}
```


## Transcriber Protocol

```swift
protocol Transcriber: Sendable {
    static var isAvailable: Bool { get }

    func transcribe(
        file: URL,
        segment: SpeechSegment,
        config: TranscriptionConfig
    ) async throws -> TranscriptionResult
}
```

The `prompt` field biases recognition toward expected vocabulary. For podcasts, feeding in guest names, show title, or technical terms improves accuracy. Whisper backends use `initial_prompt`, Speech framework uses `contextualStrings`, and OpenAI supports the `prompt` parameter.


## Backends

### Backend Selection

```swift
enum Backend: String, CaseIterable {
    case whisper, mlx, speech, openai, auto
}

func selectBackend(preferred: Backend) -> any Transcriber {
    if preferred != .auto { return resolve(preferred) }

    // Auto priority: MLX > Whisper > Speech > OpenAI
    if MLXBackend.isAvailable    { return MLXBackend() }
    if WhisperBackend.isAvailable { return WhisperBackend() }
    if SpeechBackend.isAvailable { return SpeechBackend() }
    if OpenAIBackend.isAvailable { return OpenAIBackend() }

    fatalError("No transcription backend available")
}
```

Auto-selection rationale:

- **MLX** — fastest on Apple Silicon, GPU-accelerated via Metal unified memory.
- **whisper.cpp** — best accuracy and control, cross-platform, supports initial prompt.
- **Speech framework** — no model download needed, zero setup, decent quality for clear audio.
- **OpenAI API** — requires network and API key, pay-per-use; explicit choice, not a fallback.

### WhisperBackend

Uses whisper.cpp via its C API. The model is loaded once, then `whisper_full()` is called per segment. Thread-safe for concurrent segments with separate `whisper_context` instances. Model files are GGML format, stored in the shared state directory.

### MLXBackend

Uses mlx-swift with the Whisper implementation from mlx-swift-examples. Fastest on Apple Silicon due to unified memory and GPU acceleration. Model format is MLX weights (separate from GGML). Requires macOS 14+.

### SpeechBackend

Uses `SFSpeechRecognizer` and `SFSpeechAudioBufferRecognitionRequest`. On-device recognition, no model download. Limited language control compared to Whisper, no initial prompt support (but has `contextualStrings`). Good as a zero-setup fallback.

### OpenAIBackend

REST calls to `https://api.openai.com/v1/audio/transcriptions`. Requires `OPENAI_API_KEY` environment variable or config file. Sends each segment as a small audio file. Uses `response_format: verbose_json` for word-level timestamps. Supports the `prompt` parameter. Rate limits and cost are the tradeoffs.


## Model Management

Models are downloaded on first use to the platform-appropriate shared state directory:

- **macOS**: `~/Library/Application Support/podscribe/models/`
- **Linux** (future): `$XDG_DATA_HOME/podscribe/models/`

The `ModelManager` handles download with a progress indicator on stderr. It manages two model formats:

- **GGML** — for whisper.cpp (e.g., `ggml-large-v3-turbo.bin`)
- **MLX** — for the MLX backend (MLX weight format from Hugging Face)

Default model: `large-v3-turbo` — good balance of speed and quality for podcast speech.


## Silence Detection

### Configuration

```swift
struct AnalyzerConfig {
    /// RMS threshold in dB below which audio is considered silence.
    /// -40 dB is a reasonable default for studio-recorded vocals.
    var silenceThresholdDB: Double = -40.0

    /// Minimum duration of silence to split segments (seconds).
    /// Short pauses within a sentence should not create new segments.
    var minSilenceDuration: TimeInterval = 0.5

    /// Padding added before and after detected speech (seconds).
    /// Prevents clipping the onset of plosives or trailing sibilants.
    var padding: TimeInterval = 0.15

    /// RMS window size in samples. At 48 kHz, 1024 ≈ 21ms.
    var windowSize: Int = 1024
}
```

### Algorithm

```swift
struct Analyzer {
    let config: AnalyzerConfig

    func detectSpeech(in file: URL) throws -> [SpeechSegment] {
        // 1. Read PCM samples via AVAudioFile / CoreAudio
        // 2. Compute RMS over sliding window: 20 * log10(rms / reference)
        // 3. State machine: flip between silence/speech at threshold crossing
        // 4. Merge segments closer than minSilenceDuration
        // 5. Apply padding, clamp to file duration
        // 6. Drop segments shorter than ~100ms (noise/clicks)
    }
}
```

The state machine walks through RMS values, flipping between "silence" and "speech" states when crossing the dB threshold, then post-processes to merge short gaps and apply padding.


## Intermediate Format

The intermediate file (`.podscribe.json`) is the checkpoint between transcribe and merge phases. It is human-readable, editable, and self-documenting.

```json
{
  "version": 1,
  "session": "Episode 42 - Interview with Bob",
  "created": "2026-05-01T14:23:00Z",
  "tracks": [
    {
      "speaker": "Alice",
      "file": "tracks/alice.wav",
      "segments": [
        {
          "start": 0.85,
          "end": 4.32,
          "words": [
            { "text": "Welcome", "start": 0.85, "end": 1.12 },
            { "text": "to",      "start": 1.13, "end": 1.21 },
            { "text": "the",     "start": 1.22, "end": 1.30 },
            { "text": "show",    "start": 1.31, "end": 1.58 }
          ]
        }
      ]
    }
  ],
  "metadata": {
    "backend": "mlx",
    "model": "large-v3-turbo",
    "language": "en",
    "analyzer": {
      "silence_threshold_db": -40.0,
      "min_silence": 0.5,
      "padding": 0.15
    }
  }
}
```

This format enables key workflows:

- Transcribe once, iterate on formatting (VTT, SRT, plain text) without re-transcribing.
- Hand-edit to fix misrecognized names or remove false segments.
- Incrementally replace a single speaker's track without re-transcribing everyone.


## Merge Algorithm

The merger takes N lists of timestamped, speaker-attributed segments and produces one coherent linear transcript. The pipeline has five steps.

### Step 1: Flatten and Sort

Tag every segment with its speaker and flatten into one list sorted by start time:

```swift
func flatten(_ tracks: [Track]) -> [AttributedSegment] {
    tracks.flatMap { track in
        track.segments.map { segment in
            AttributedSegment(
                speaker: track.speaker,
                start: segment.start,
                end: segment.end,
                words: segment.words
            )
        }
    }
    .sorted { $0.start < $1.start }
}
```

### Step 2: Overlap Resolution

When two segments overlap in time (crosstalk), the tool supports three policies:

```swift
enum OverlapPolicy: String, CaseIterable {
    /// Keep both segments intact with overlapping timestamps.
    /// VTT and SRT support concurrent cues.
    case preserve

    /// Trim the earlier segment at the point where the later starts.
    /// Words after the overlap point are dropped.
    case trim

    /// Split both segments at word boundaries, interleaving
    /// at the word level for maximum fidelity.
    case interleave
}
```

The `interleave` algorithm operates at the word level:

1. Identify the overlap region: `max(a.start, b.start) ..< min(a.end, b.end)`.
2. Split each segment's words into three buckets: before overlap, during overlap, after overlap.
3. Pre-overlap: only the earlier speaker's words.
4. During overlap: merge both speakers' words, sorted by timestamp, then re-chunk into micro-segments by consecutive speaker runs.
5. Post-overlap: remaining words from each speaker.

The `chunkBySpeaker` helper groups consecutive runs of the same speaker into segments, so an overlap region with words Alice-Alice-Bob-Bob-Alice produces three micro-segments, not five single-word entries.

### Step 3: Gap Detection

Long silences between segments produce paragraph breaks:

```swift
func insertBreaks(
    _ segments: [AttributedSegment],
    gapThreshold: TimeInterval
) -> [MergedSegment] {
    segments.enumerated().map { index, segment in
        let gap = index == 0
            ? 0
            : segment.start - segments[index - 1].end

        return MergedSegment(
            speaker: segment.speaker,
            start: segment.start,
            end: segment.end,
            words: segment.words,
            paragraphBreak: gap >= gapThreshold
        )
    }
}
```

### Step 4: Speaker Coalescing

Adjacent segments from the same speaker with no intervening gap or paragraph break merge into one continuous block. A `maxCueDuration` cap prevents excessively long cues — when splitting, the tool breaks at sentence boundaries (period, question mark) or at the nearest word boundary.

```swift
func coalesce(
    _ segments: [MergedSegment],
    maxCueDuration: TimeInterval?,
    maxGap: TimeInterval = 1.0
) -> [MergedSegment] {
    var result: [MergedSegment] = []

    for segment in segments {
        guard let last = result.last,
              last.speaker == segment.speaker,
              !segment.paragraphBreak,
              segment.start - last.end < maxGap
        else {
            result.append(segment)
            continue
        }

        var merged = last
        merged.words += segment.words
        merged.end = segment.end

        if let max = maxCueDuration,
           merged.end - merged.start > max {
            result.append(segment)
        } else {
            result[result.count - 1] = merged
        }
    }

    return result
}
```

### Step 5: Format

The merged segments feed into format-specific output:

- **VTT** — cues with `<v Speaker>` voice tags. Overlapping cues (with `preserve` policy) are valid VTT. Word-level timestamps via `--include-words`.
- **SRT** — similar to VTT but speaker names go in the text body (no native voice tag).
- **Plain text** — script-style format with speaker labels. Requires `trim` or `interleave` policy since the format is strictly linear.
- **JSON** — preserves everything: word-level timestamps, overlap markers, speaker attribution.

### Full Merge Pipeline

```swift
struct Merger {
    let options: MergeOptions

    func merge(_ transcript: IntermediateTranscript) -> FormattedTranscript {
        var segments = flatten(transcript.tracks)
        segments = resolveOverlaps(segments, policy: options.overlapPolicy)
        var merged = insertBreaks(segments, gapThreshold: options.gapThreshold ?? 3.0)
        merged = coalesce(merged, maxCueDuration: options.maxCueDuration)
        if let maxLength = options.maxLineLength {
            merged = wrapLines(merged, maxLength: maxLength)
        }
        return format(merged, as: options.format)
    }
}
```


## Transcription Pipeline

### Concurrency Model

Each speaker's segments are independent, and segments within a speaker are independent. Phase 1 (silence detection) runs all tracks concurrently via `TaskGroup`. Phase 2 (transcription) fans out across segments with concurrency bounded by the backend:

- **whisper.cpp** — parallelize via rayon-style work, or limit to N `whisper_context` instances.
- **MLX** — GPU-bound; likely sequential or lightly parallel.
- **Speech framework** — Apple may limit concurrent recognition requests.
- **OpenAI API** — bounded by rate limits; fan out with throttling.

```swift
func transcribe(session: Session) async throws -> IntermediateTranscript {
    let analyzer = Analyzer(config: session.analyzerConfig)
    let backend = selectBackend(preferred: session.backend)

    // Phase 1: detect speech in all tracks concurrently
    let trackSegments = try await withThrowingTaskGroup(
        of: (Speaker, [SpeechSegment]).self
    ) { group in
        for track in session.tracks {
            group.addTask {
                let segments = try analyzer.detectSpeech(in: track.file)
                return (track.speaker, segments)
            }
        }
        return try await group.reduce(into: []) { $0.append($1) }
    }

    // Phase 2: transcribe all segments concurrently (bounded)
    let results: [(Speaker, TranscriptionResult)] = ...

    return IntermediateTranscript(tracks: results, metadata: ...)
}
```


## Output Formats

### VTT (WebVTT)

Primary output format, aligned with the Podcasting 2.0 `<podcast:transcript>` standard (VTT preferred).

```
WEBVTT

00:00.850 --> 00:08.700
<v Alice>Welcome to the show today we're talking about
so Bob tell us about your project

00:07.900 --> 00:14.200
<v Bob>Yeah thanks Alice so we started building...
```

### SRT (SubRip)

```
1
00:00:00,850 --> 00:00:08,700
[Alice] Welcome to the show today we're talking about
so Bob tell us about your project

2
00:00:07,900 --> 00:00:14,200
[Bob] Yeah thanks Alice so we started building...
```

### Plain Text

```
Alice: Welcome to the show today we're talking about so
Bob tell us about your project—

Bob: Yeah thanks Alice so we started building...
```

### JSON

Preserves full structure for downstream tooling. Word-level timestamps, speaker attribution, and segment boundaries.


## Open Issues

### 1. Track Alignment

If tracks don't start at the same point — someone hit record late, or tracks were exported with different lead-in — all timestamps will be wrong relative to each other.

- [ ] Add per-track offset parameter: `--track "Bob=bob.wav+1.3s"`
- [ ] Add `offset` field to session manifest per track
- [ ] Consider an `align` subcommand for automatic cross-correlation of tracks

### 2. Audio Format Handling

Real-world tracks come as WAV, AIFF, FLAC, MP3, M4A, CAF from DAWs.

- [ ] Accept all formats readable by AVAudioFile (covers all common formats on macOS)
- [ ] Decode to PCM internally via CoreAudio
- [ ] Validate and report unsupported formats early with a clear error message

### 3. Incremental Re-Transcription

If a guest re-records one track, only that speaker should need re-transcription.

- [ ] Support updating a single track in an existing intermediate file
- [ ] CLI: `podscribe transcribe --update existing.podscribe.json --track "Bob=bob_v2.wav"`
- [ ] Preserve other tracks and metadata when replacing

### 4. Progress Reporting

Transcription is slow. The tool needs meaningful progress output.

- [ ] Report on stderr (not stdout, to keep piping clean)
- [ ] Show: current track, current segment, segments remaining, elapsed time
- [ ] Consider a `--progress` style flag (plain, bar, json) for CI/scripting use

### 5. Error Recovery

If transcription fails on segment 47 of 200, all prior work should not be lost.

- [ ] Write intermediate file incrementally (per completed track)
- [ ] On crash or cancellation, produce a partial but valid intermediate file
- [ ] On restart, detect partial file and offer to resume

### 6. Rolling Prompt Context

Whisper supports an initial prompt that can be fed the transcript of earlier segments to improve coherence and consistency.

- [ ] Feed transcript of preceding segments as `initial_prompt` to Whisper backends
- [ ] Map to `contextualStrings` for Speech framework backend
- [ ] Define a reasonable context window (last N words) to stay within prompt token limits

### 7. Naming

- [ ] Decide on final tool name (`podscribe` or alternatives)
- [ ] Check name availability: GitHub, Homebrew, SwiftPM namespace


---

## Appendix A — Backend Research (2026-05-01)

The original design listed `whisper` (whisper.cpp), `mlx`, `speech` (Apple), and `openai` as backends. After a spike, the on-device backend landscape for Swift on Apple Silicon as of late April 2026 looks like this:

### MLX Whisper — not available in Swift

- `mlx-swift` is a low-level array/NN library (MLXArray, MLXNN, autograd). No model implementations.
- `mlx-swift-examples` ships MNIST, LLM, VLM, StableDiffusion — no Whisper.
- `mlx-swift-lm` covers LLMs / VLMs / embedders — no Whisper.
- MLX Whisper exists only in the Python `mlx-examples` repo; porting is out of scope for the MVP.
- **Decision:** drop the `.mlx` backend from the MVP plan. It can be revisited if/when an MLX Whisper Swift port appears.

### FluidAudio (Parakeet TDT v3 on CoreML/ANE) — recommended MVP backend

- Repo: `https://github.com/FluidInference/FluidAudio` — Apache-2.0, v0.14.3 (April 2026), very active.
- Default ASR model: NVIDIA Parakeet TDT v3 0.6B, multilingual (25 European languages); v2 for English-only.
- Inference is ANE-only — minimal CPU, no GPU/MPS contention.
- Quoted ~190× real-time on M4 Pro (≈ 1 hour audio in ≈ 19 s).
- Word-level timestamps are first-class (TDT model exposes them).
- API surface that matches our pipeline:

  ```swift
  let models = try await AsrModels.downloadAndLoad(version: .v3)
  let asr = AsrManager(config: .default)
  try await asr.loadModels(models)
  let result = try await asr.transcribe(samples)        // [Float] @ 16 kHz mono
  // also: transcribe(audioBuffer: AVAudioPCMBuffer)
  // and:  transcribeLong(...) for long-form
  ```

- Audio I/O helper: `AudioConverter().resampleAudioFile(url)` produces 16 kHz mono Float samples directly from any `AVAudioFile`-supported container.
- Auto-downloads CoreML model bundles to `~/.cache/fluidaudio/Models/...` on first use.
- Diarization features are not needed by Superscribe (one track = one speaker) but are available if a future feature ever wants them.

### whisper.cpp (`ggerganov/whisper.cpp`) — secondary backend

- MIT, mature C library, OpenAI Whisper GGML models.
- Supports prompt tokens, word timestamps, Metal GPU via embedded shaders.
- Generally slower than Parakeet on ANE but often more robust on noisy / accented audio.
- Integrated as a static arm64 xcframework built by `_scripts/build-whisper.sh`; models are single `.bin` files from HuggingFace.

### Apple `SpeechAnalyzer` / `SpeechTranscriber` — deferred (macOS 26)

- Brand-new in macOS 26 / iOS 26: `final actor SpeechAnalyzer` (Sendable) plus `SpeechTranscriber(locale:, preset: .offlineTranscription)` modules.
- Native, zero third-party deps; Apple-managed assets via `AssetInventory`; word-level timing via `Result.attributeOptions`.
- Direct file ingestion (`analyzeSequence(from: AVAudioFile)`) and `AsyncSequence` results — fits Swift 6 concurrency natively.
- **Blocker for now:** requires bumping deployment target to macOS 26. Out of scope until we are willing to drop Sonoma/Sequoia support.

### Updated backend plan

- **MVP:** `.parakeet` (FluidAudio) — default and only fully implemented backend.
- **Planned:** `.whisper` (whisper.cpp) for accuracy comparisons.
- **Reserved:** `.appleSpeech` (SpeechAnalyzer) once macOS 26 floor is acceptable.
- **Deferred:** `.openai` (cloud), `.mlx` (re-evaluate if a Swift MLX Whisper appears).

The "Dependencies" and "Backends" sections above are out of date relative to this appendix; they will be rewritten once the MVP backend lands.
