# CLAUDE.md — Working Rules

Guidance for any AI agent (Claude) working in this repository.
Project context lives in `spec.md`.

## Language
- **User-facing input/output:** Korean.
  - All messages, prompts, questions, and summaries shown to the user are in Korean.
- **Internal work:** English.
  - Code, identifiers, comments, commit messages, internal notes, and reasoning are in English.

## Destructive Operations
- Before deleting any important file, **ask the user first** and wait for explicit confirmation.
  - "Important" includes: source files, spec/CLAUDE docs, config, build scripts, anything not trivially regenerated.
- Never hard-delete without confirmation. Trivial temp/build artifacts may be cleaned without asking.

## Transparency
- Whenever an action is taken, tell the user **what** was done and **why**.
  - Applies to: creating/editing/deleting files, running commands, changing config, installing dependencies.
- Report concisely, after the fact, in Korean.

## General
- Keep changes minimal and scoped; prefer incremental edits over rewrites.
- Follow `spec.md` for architecture and scope; flag any deviation to the user before proceeding.
