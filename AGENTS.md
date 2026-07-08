# AGENTS.md

## Goal

Build a macOS menu bar utility for a 2018 Intel MacBook Pro used as a remote Codex development machine.

## Priorities

1. Stability and recoverability first.
2. Always keep a CLI recovery path.
3. Do not disconnect the only active display.
4. Avoid private APIs in v0.1 to v0.3.
5. Add private display APIs only after the public API version is stable.
6. Always write logs for display and sleep changes.
7. Virtual display resolution must be configurable.
8. Default virtual display resolution is 1920x1080 @ 60Hz.

## Commands

- Build: `swift build --build-system native`
- Run menu bar app: `swift run CodexHeadless`
- CLI Status: `swift run codex-headless status`
- CLI On: `swift run codex-headless on`
- CLI Off: `swift run codex-headless off`
- Set Resolution: `swift run codex-headless config set resolution 2560x1440`

## Safety Rules

- Before changing display topology, save runtime state and display status to logs.
- When entering Headless Mode, start a 30-second rollback guard unless disabled.
- Never destroy a virtual display before restoring the built-in display.
- If an operation fails, fallback to brightness dimming instead of force-disconnect.
- Validate custom resolution before creating a virtual display.
