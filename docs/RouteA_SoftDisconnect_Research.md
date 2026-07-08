# Route A: Built-in Display Soft-Disconnect Research

This document tracks the native/private-API route for built-in display soft-disconnect.

## Current Conclusion

The stable daily path is still:

```text
HDMI Dummy as main display
+ Keep Awake
+ AppleScript brightness dimming
+ rollback guard
+ CLI recovery
```

The experimental v0.4 private API path is implemented behind a safety gate, but on the target machine the SkyLight helper currently crashes with `SIGSEGV`:

```text
Isolated soft-disconnect helper failed for display 1: exit code 11.
```

Because of this, the app automatically falls back to dimming and blocks repeated soft-disconnect attempts until the block is manually cleared.

## Principles

- Never call private display APIs in the main control process.
- Every private API call must run inside a short-lived helper subprocess.
- A helper crash must be treated as data, not as a fatal app failure.
- The normal `codex-headless on` path must remain safe and recoverable.
- No new private API variant should be wired into `on` until it has a clear isolated test result.

## Current Private API Findings

On the target M1 MacBook Pro:

```text
CoreDisplay Loaded: Yes
Set User Disabled Symbol: Missing
Is User Disabled Symbol: Missing
SkyLight Loaded: Yes
Main Connection Symbol: Available (CGSMainConnectionID)
Configure Display Enabled Symbol: Available (CGSConfigureDisplayEnabled)
```

The current attempted SkyLight shape crashes:

```text
CGSConfigureDisplayEnabled(connection, config, displayID, enabled)
```

This strongly suggests one of:

- The function signature is wrong.
- The display identifier type is not the public `CGDirectDisplayID`.
- The configuration reference type or lifecycle is wrong.
- The call needs additional display transaction state.
- The symbol exists but is not safe for this target macOS/session.

## Candidate Research Paths

### 1. Symbol and String Survey

Goal: collect real symbols from the target system.

Useful commands to try on the target machine:

```bash
codex-headless soft-disconnect probe
strings /System/Library/PrivateFrameworks/SkyLight.framework/SkyLight | grep -i DisplayEnabled
strings /System/Library/PrivateFrameworks/SkyLight.framework/SkyLight | grep -i ConfigureDisplay
strings /System/Library/PrivateFrameworks/CoreDisplay.framework/CoreDisplay | grep -i UserDisabled
```

On newer macOS versions these frameworks may live inside the dyld shared cache, so direct framework files may not exist.

### 2. Isolated Variant Harness

Goal: add a dedicated experiment command, separate from `on`.

Possible shape:

```bash
codex-headless soft-disconnect experiment --variant skylight-configure-display-enabled-v2 --display 1 --action disable --i-understand-this-may-break-display-state
codex-headless soft-disconnect experiment --variant skylight-configure-display-enabled-v2 --display 1 --action enable --i-understand-this-may-break-display-state
```

Every experiment must:

- Require an explicit `--i-understand-this-may-break-display-state` flag.
- Run in a helper subprocess.
- Log stdout, stderr, exit code, and signal-style exit codes.
- Refuse to run unless an external / Dummy display is active and main.

### 3. Candidate Function Shapes

These are hypotheses only. They must not be called from the main process.

```text
CGSConfigureDisplayEnabled(connection, config, displayID, enabled)
CGSConfigureDisplayEnabled(connection, displayID, enabled)
CGSConfigureDisplayEnabled(config, displayID, enabled)
CGSConfigureDisplayEnabled(connection, config, displayID, enabled, flags)
```

The first and second shapes have already crashed in the isolated helper on the target machine. The third shape succeeded on the target machine and is now the default production candidate:

```text
CGSConfigureDisplayEnabled(config, displayID, enabled)
```

The fourth shape is intentionally left untested while the third shape works.

### 4. Rollback Requirements

If any variant ever succeeds:

- Store the exact display ID.
- Store the method name and variant.
- `off` must attempt reconnect before any other display cleanup.
- If reconnect fails, keep Dummy/remote path alive and report exact recovery commands.

## Practical Recommendation

Do not keep enabling `soft-disconnect` for daily use right now.

Use:

```bash
codex-headless config set soft-disconnect off
```

Continue daily operation with the v0.3 path until Route A has a working isolated experiment.
