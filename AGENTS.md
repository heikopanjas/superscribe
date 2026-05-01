# Project Instructions for AI Coding Agents

**Last updated:** 2026-05-01

<!-- {mission} -->

## Mission Statement

[Describe your project here - what it does, its purpose, and key features]

## Technology Stack

- **Language:** [e.g., Python, TypeScript, JavaScript]
- **Framework:** [e.g., React, Next.js, Django, FastAPI]
- **Version Control:** Git
- **Package Manager:** [e.g., npm, pip, poetry, yarn]
- **License:** [e.g., MIT, Apache 2.0]

## Session Protocol

When starting a new session, read this entire file and confirm you have
understood the project instructions before proceeding. Summarize the project
purpose and key conventions briefly. Do not make changes until you have
confirmed your understanding.

<!-- {principles} -->

## Primary Instructions

- Avoid making assumptions. If you need additional context to accurately answer the user, ask the user for the missing information. Be specific about which context you need.
- Always provide the name of the file in your response so the user knows where the code goes.
- Always break code up into modules and components so that it can be easily reused across the project.
- All code you write MUST be fully optimized. ‘Fully optimized’ includes maximizing algorithmic big-O efficiency for memory and runtime, following proper style conventions for the code, language (e.g. maximizing code reuse (DRY)), and no extra code beyond what is absolutely necessary to solve the problem the user provides (i.e. no technical debt). If the code is not fully optimized, you will be fined $100.

### Working Together

This file (`AGENTS.md`) is the primary instructions file for AI coding assistants working on this project. Agent-specific instruction files (such as `.github/copilot-instructions.md`, `CLAUDE.md`) reference this document, maintaining a single source of truth.

When initializing a session or analyzing the workspace, refer to instruction files in this order:

1. `AGENTS.md` (this file - primary instructions and single source of truth)
2. Agent-specific reference file (if present - points back to AGENTS.md)

### Update Protocol (CRITICAL)

**PROACTIVELY update this file (`AGENTS.md`) as we work together.** Whenever you make a decision, choose a technology, establish a convention, or define a standard, you MUST update AGENTS.md immediately in the same response.

**Update ONLY this file (`AGENTS.md`)** when coding standards, conventions, or project decisions evolve. Do not modify agent-specific reference files unless the reference mechanism itself needs changes.

**When to update** (do this automatically, without being asked):

- Technology choices (build tools, languages, frameworks)
- Directory structure decisions
- Coding conventions and style guidelines
- Architecture decisions
- Naming conventions
- Build/test/deployment procedures

**How to update AGENTS.md:**

- Maintain the "Last updated" timestamp at the top
- Add content to the relevant section (Project Overview, Coding Standards, etc.)
- Add entries to the "Recent Updates & Decisions" log at the bottom with:
  - Date (with time if multiple updates per day)
  - Brief description
  - Reasoning for the change
- Preserve this structure: title header → timestamp → main instructions → "Recent Updates & Decisions" section

## Best Practices

### When Updating This Repository

1. **Maintain Consistency**: Keep code style consistent across the codebase
2. **Test First**: Write tests before implementing features when applicable
3. **Document Changes**: Update documentation when changing functionality
4. **Code Review**: [Describe your code review process]
5. **Date Changes**: Update the "Last updated" timestamp in this file when making changes
6. **Log Updates**: Add entries to "Recent Updates & Decisions" section below

### Security & Safety

- Never include API keys, tokens, or credentials in code
- Always require explicit human confirmation before commits
- Maintain conventional commit message standards
- Keep change history transparent through commit messages
- [Add project-specific security guidelines]

<!-- {languages} -->

## Swift Coding Standards

Load the `swift-coding-conventions` skill before writing, reviewing, or refactoring Swift code.
Load the `swift-build-commands` skill when building or running the project.
Load the `swift-testing-pro` skill when writing, reviewing, or refactoring tests (Swift Testing or XCTest).

<!-- {integration} -->

## Semantic Versioning

Automatically bump the project version after every code change and include it in the same commit. Load the `semantic-versioning` skill for the full PATCH/MINOR/MAJOR decision rules.

## Commit Protocol

- **NEVER commit automatically** — always wait for explicit user confirmation
- Stage changes, write a conventional commits message (max 50-char subject, 72-char body lines), then commit
- Load the `git-workflow` skill for the full message format, character limits, and examples before committing

---

<!-- {changelog} -->

## Recent Updates & Decisions

### 2026-05-01

- **Backend research recorded.** MLX Whisper does not exist for Swift; Phase 3 spike concluded. Recommended MVP backend is FluidAudio (Parakeet TDT v3, CoreML/ANE, Apache-2.0). WhisperKit is the planned secondary backend; Apple `SpeechAnalyzer` is reserved for when a macOS 26 deployment floor is acceptable. Findings captured in [_docs/podscribe-design.md](_docs/podscribe-design.md) Appendix A and [_docs/superscribe-mvp-implementation-plan.md](_docs/superscribe-mvp-implementation-plan.md). Project paused pending user decision on backend; state frozen in `/memories/repo/superscribe-state.md`.
- Reference the `swift-testing-pro` skill in the Swift Coding Standards section so it is loaded for any test-related work. Reasoning: the skill was added to the project and should be discoverable from AGENTS.md.

### 2025-10-05

- Initial AGENTS.md setup
- Established core coding standards and conventions
- Created agent-specific reference files
- Defined repository structure and governance principles
