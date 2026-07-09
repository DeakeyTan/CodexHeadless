# CodexHeadless Iteration PRD: Waiting Optimization and Status Phases

## 1. Document Purpose

This document describes an experience and stability iteration for CodexHeadless based on the current v0.5/v0.6 implementation.

This iteration focuses on the following issues:

1. `Enable Headless Mode` can feel slow.
2. `Restore Normal Mode` can feel slow.
3. The app does not provide enough visible progress information while waiting.
4. Some restore paths may briefly appear as `Error` even though the app can continue restoring shortly afterward.
5. Some current wait durations are conservative and should be configurable for daily personal use.
6. The optimized progress and phase system must work both with and without an external display or HDMI Dummy Plug.
7. All user-facing messages must be in English.

This iteration does not rewrite the existing core functionality for display management, virtual display creation, soft-disconnect, Touch Bar hiding, Keep Awake, CLI, global hotkeys, or Confirm Dialog. It optimizes wait behavior, status visibility, configuration, and user feedback on top of the existing architecture.

## 2. Current Known Behavior

Based on real-world logs, the current no-external-display workflow with `virtual-display-policy=always` and `scale-mode=hidpi` behaves roughly as follows:

```text
enable
→ wait for built-in display and Touch Bar to turn off
→ automatic rollback if not confirmed
→ wait for built-in display and Touch Bar to restore
→ wait for cooldown
→ enable again
→ wait for built-in display and Touch Bar to turn off
→ confirm
→ restore
→ wait for built-in display and Touch Bar to restore
→ wait for cooldown
```

The logs show several visible wait points:

1. The software virtual display host reports a `displayID` quickly, but the app continues waiting for CoreGraphics display enumeration for about 20 seconds.
2. After soft-disconnect, the app waits for the built-in display to disappear from display enumeration.
3. The rollback confirmation window defaults to 30 seconds.
4. During restore, the app waits for the built-in display to reappear.
5. During restore, if no physical display is detected briefly, the app may enter paused restore or `Error`, but then continue restoring shortly afterward.
6. After restore completes, the app enforces an enable cooldown.

These waits are safety-oriented, but some of them are too conservative for daily use on the current target machine.

## 3. Product Goals

### 3.1 Core Goals

This iteration aims to:

1. Reduce the perceived time required to enable Headless Mode.
2. Reduce the perceived time required to restore Normal Mode.
3. Provide clear progress messages during waits.
4. Avoid showing `Error` for normal “waiting for physical display” restore states.
5. Preserve all important safety mechanisms:
   - Do not destroy the only usable display output.
   - Do not disconnect the only display.
   - Keep the CLI recovery path.
   - Keep rollback guard.
   - Keep paused restore protection.
6. Make key wait durations configurable.
7. Support both workflows:
   - External display / HDMI Dummy path.
   - Software virtual display path.
8. Use English for all user-facing messages.

### 3.2 User Experience Goals

After this iteration, the user should be able to understand:

1. Whether the app is checking displays.
2. Whether the app is using an external / HDMI Dummy display.
3. Whether the app is creating a software virtual display.
4. Whether the app is waiting for macOS to detect the virtual display.
5. Whether the app is promoting a display to main display.
6. Whether the app is disconnecting the built-in display.
7. Whether the app is hiding Touch Bar UI.
8. Whether the app is waiting for confirmation.
9. Whether the app is restoring the built-in display.
10. Whether the app is waiting for a physical display to become available.
11. Whether the app is cooling down and how long until Enable is available again.

### 3.3 Non-Goals

This iteration does not include:

1. Rewriting the `CGVirtualDisplay` host.
2. Rewriting the soft-disconnect private API implementation.
3. Rewriting Touch Bar hide behavior.
4. Adding power disconnect gestures.
5. Adding lid close/open gestures.
6. Adding USB insertion/removal gestures.
7. Redesigning the whole menu bar UI.
8. Replacing existing CLI commands.
9. Removing rollback guard.
10. Removing restore paused protection.
11. Localizing the UI into multiple languages.

## 4. Problem Analysis

## 4.1 Software Virtual Display Wait Is Too Long

### Current Behavior

Example log:

```text
Virtual display host reported displayID=16; waiting for CoreGraphics display enumeration.
20 seconds later:
Virtual display host reported displayID=16; accepting reported ID for promotion attempt.
```

This means:

1. The virtual display host reports `displayID` quickly.
2. CoreGraphics enumeration does not show the new display immediately.
3. The app continues waiting for about 20 seconds.
4. The app eventually accepts the reported display ID and continues successfully.

### Problem

On the current target machine, this 20-second wait is likely too conservative.

### Required Change

When the host has already reported a display ID:

1. Wait for CoreGraphics enumeration for up to `virtualDisplayEnumerationWaitSeconds`.
2. If the host has reported a display ID, wait only `virtualDisplayReportedIDExtraWaitSeconds` more.
3. If CoreGraphics still does not enumerate the display, accept the host-reported display ID.
4. Continue with the promotion attempt.

Recommended defaults:

```text
virtualDisplayEnumerationWaitSeconds = 5
virtualDisplayReportedIDExtraWaitSeconds = 2
```

## 4.2 Soft-Disconnect Verification Wait Is Too Conservative

### Current Behavior

After soft-disconnect succeeds, the app waits for the built-in display to disappear from CoreGraphics enumeration. It may log:

```text
Built-in display 1 is still visible immediately after soft-disconnect.
```

### Problem

This wait is mainly a verification step. It should not block the main flow for too long.

### Required Change

Reduce the wait to:

```text
softDisconnectDisappearWaitSeconds = 1
```

If the display is still visible after this wait, log a warning and continue.

## 4.3 Restore Wait Is Too Long and Not Clear Enough

### Current Behavior

During restore:

```text
Built-in display restored via helper
10 seconds later:
Built-in display did not reappear during restore wait
Then:
Restore paused: no built-in or external display is available
Then shortly after:
Continuing paused restore after built-in or external display became available
```

### Problem

1. A successful helper call does not mean CoreGraphics will immediately enumerate the built-in display.
2. The current restore path may first wait for the specific built-in display ID, then wait again for any physical display.
3. The UI may briefly show `Error` even though the app is still safely waiting and can continue restoring.
4. This makes the app feel stuck or broken.

### Required Change

Restore must use clearer progress phases:

```text
Restoring built-in display…
Waiting for a physical display to become available…
Setting physical display as main display…
Restoring Touch Bar UI…
Restoring brightness…
Stopping virtual display…
Stopping Keep Awake…
Waiting for display state to stabilize…
```

Key rules:

1. After calling the helper to restore the built-in display, perform a short wait.
2. If the built-in display is not detected immediately, do not show `Error`.
3. Enter a visible “waiting for physical display” phase.
4. Keep the managed virtual display alive.
5. Once a built-in, external, or HDMI Dummy display becomes available, set that physical display as the main display.
6. Only then stop the managed virtual display.
7. Only show `Error` for truly unrecoverable failures.

## 4.4 Cooldown Is Too Long for Normal Restores

### Current Behavior

Restore completion currently sets an enable cooldown of about 20 seconds.

### Problem

20 seconds is useful for safety, but too long for normal daily use and testing.

### Required Change

Make cooldown configurable:

```json
{
  "restore": {
    "cooldownSeconds": 10,
    "cooldownAfterPausedRestoreSeconds": 20
  }
}
```

Default behavior:

```text
Normal restore success: 10 seconds cooldown.
Restore after paused/error path: 20 seconds cooldown.
```

## 4.5 Rollback Guard Should Remain Configurable

### Current Behavior

Confirm Required uses a 30-second rollback window.

### Recommendation

Keep the default at 30 seconds for safety unless the user explicitly changes it.

Allowed future values:

```text
15 / 20 / 30 / 60 seconds
```

The existing Confirm Dialog and global hotkeys reduce the need to wait manually, so the default does not need to be shortened immediately.

## 4.6 External Display / HDMI Dummy Path Compatibility

The progress phase system must apply to external display and HDMI Dummy workflows as well.

### External / HDMI Dummy Enable Path

When an external display or HDMI Dummy is already available, the app should skip software virtual display creation and virtual display enumeration waits.

Expected phases:

```text
Starting Keep Awake…
Checking displays…
Using external display as main display…
Disconnecting built-in display…
Hiding Touch Bar UI…
Waiting for confirmation…
```

The following phases should not appear unless actually needed:

```text
Creating virtual display…
Waiting for macOS to detect the virtual display…
Using the reported virtual display ID…
Setting virtual display as main display…
```

### External / HDMI Dummy Restore Path

When an external display or HDMI Dummy remains available during restore, the app should not unnecessarily wait for a physical display for a long time.

Expected phases:

```text
Restoring built-in display…
Restoring Touch Bar UI…
Restoring brightness…
Keeping external display as main display…
Stopping Keep Awake…
Waiting for display state to stabilize…
```

### Requirement

Phase and progress messages are universal, but each path must show only the steps that are actually being performed.

External / HDMI Dummy paths should be faster and should not inherit the virtual display wait behavior.

## 5. User-Facing Language Requirement

All user-facing messages must be in English.

This includes:

1. Menu bar labels.
2. Confirm / Rollback dialog text.
3. CLI output.
4. Error messages.
5. Status messages.
6. Phase messages.
7. Copy Status output.
8. Log messages.
9. README examples.
10. Doctor output.
11. Self-test output where applicable.

### Examples

Use:

```text
Creating virtual display…
Waiting for macOS to detect the virtual display…
Restoring built-in display…
Waiting for a physical display to become available…
Enable ignored: restore cooldown active, 8s remaining.
```

Do not use:

```text
正在创建虚拟显示器…
正在等待物理显示器恢复…
```

### Internal Identifiers

Internal enum values and config keys may remain English camelCase, for example:

```text
waitingForVirtualDisplayEnumeration
waitingForPhysicalDisplay
restoreCooldownSeconds
```

## 6. Phase Design

## 6.1 Add a Lightweight Phase Field

The existing mode can remain:

```text
Normal
Preparing
ConfirmRequired
Headless
Fallback
Restoring
Error
```

Add a lightweight `phase` field for more specific progress information.

### 6.1.1 Phase Examples

```text
idle
startingKeepAwake
checkingDisplays
usingExternalDisplay
creatingVirtualDisplay
waitingForVirtualDisplayEnumeration
acceptingReportedVirtualDisplayID
promotingVirtualDisplay
promotingExternalDisplay
disconnectingBuiltInDisplay
waitingForBuiltInDisplayDisconnect
hidingTouchBar
waitingForConfirmation
rollbackExpired
restoringBuiltInDisplay
waitingForPhysicalDisplay
promotingPhysicalDisplay
keepingExternalDisplayAsMain
restoringTouchBar
restoringBrightness
stoppingVirtualDisplay
stoppingKeepAwake
coolingDown
restorePaused
error
```

### 6.1.2 English Phase Messages

| Phase | User-facing message |
|---|---|
| idle | Ready. |
| startingKeepAwake | Starting Keep Awake… |
| checkingDisplays | Checking displays… |
| usingExternalDisplay | Using external display as main display… |
| creatingVirtualDisplay | Creating virtual display… |
| waitingForVirtualDisplayEnumeration | Waiting for macOS to detect the virtual display… |
| acceptingReportedVirtualDisplayID | Using the reported virtual display ID… |
| promotingVirtualDisplay | Setting virtual display as main display… |
| promotingExternalDisplay | Setting external display as main display… |
| disconnectingBuiltInDisplay | Disconnecting built-in display… |
| waitingForBuiltInDisplayDisconnect | Checking built-in display state… |
| hidingTouchBar | Hiding Touch Bar UI… |
| waitingForConfirmation | Waiting for confirmation… |
| rollbackExpired | Rollback deadline expired. Restoring Normal Mode… |
| restoringBuiltInDisplay | Restoring built-in display… |
| waitingForPhysicalDisplay | Waiting for a physical display to become available… |
| promotingPhysicalDisplay | Setting physical display as main display… |
| keepingExternalDisplayAsMain | Keeping external display as main display… |
| restoringTouchBar | Restoring Touch Bar UI… |
| restoringBrightness | Restoring display brightness… |
| stoppingVirtualDisplay | Stopping virtual display… |
| stoppingKeepAwake | Stopping Keep Awake… |
| coolingDown | Waiting for display state to stabilize… |
| restorePaused | Restore paused. Waiting for a physical display… |
| error | An error occurred. Check the log or run restore. |

## 6.2 RuntimeState Additions

Add the following fields to runtime state:

```json
{
  "phase": "creatingVirtualDisplay",
  "phaseMessage": "Creating virtual display…",
  "phaseStartedAt": "2026-07-09T02:20:08Z",
  "phaseDeadlineAt": "2026-07-09T02:20:15Z",
  "lastProgressAt": "2026-07-09T02:20:09Z"
}
```

Field meanings:

| Field | Meaning |
|---|---|
| phase | Current phase identifier |
| phaseMessage | English user-facing phase message |
| phaseStartedAt | When the current phase started |
| phaseDeadlineAt | Expected deadline for the current wait, nullable |
| lastProgressAt | Last time meaningful progress was observed |

## 6.3 State Update Rules

1. Every major step must update `phase`.
2. Every wait step must set `phaseDeadlineAt` where applicable.
3. Meaningful progress must update `lastProgressAt`.
4. Entering `Normal`, `Headless`, or `Fallback` should set phase to `idle` or `waitingForConfirmation` as appropriate.
5. Cooldown should set phase to `coolingDown`.

## 7. UI Requirements

## 7.1 Menu Bar Title

The menu bar title may remain short:

```text
CH
CH: On
CH: Wait
CH: Err
```

During waiting states, it should show a clearer short status where possible:

```text
CH: Preparing
CH: Restoring
CH: Cooldown
```

## 7.2 Menu Content: Current Step

The menu must display the current step during non-idle phases:

```text
Current Step: Creating virtual display…
Elapsed: 3s
Timeout: 7s
```

Example during virtual display creation:

```text
CodexHeadless
-------------------------
Status: Preparing
Current Step: Waiting for macOS to detect the virtual display…
Elapsed: 2s
Timeout: 5s

Open Log
Copy Status
Quit
```

Example during Confirm Required:

```text
Status: Confirm Required
Current Step: Waiting for confirmation…
Auto rollback in: 21s

Confirm Headless Mode   ⌃⌥⌘⇧C
Rollback Now            ⌃⌥⌘⇧R
```

Example during restore:

```text
Status: Restoring
Current Step: Waiting for a physical display to become available…
Elapsed: 5s
The virtual display will be kept alive until a physical display is available.

Open Log
Copy Status
Quit
```

Example during cooldown:

```text
Status: Normal
Current Step: Waiting for display state to stabilize…
Enable available in: 8s
```

## 7.3 Confirm Dialog

Confirm Dialog keeps its existing behavior, but all visible text must be in English.

Dialog title:

```text
Headless Mode Enabled
```

Dialog body:

```text
Confirm that remote access, display output, and built-in display state are working as expected.

Confirm: ⌃⌥⌘⇧C
Rollback: ⌃⌥⌘⇧R

If you do not confirm, CodexHeadless will automatically restore Normal Mode.
```

Buttons:

```text
Confirm
Rollback Now
```

Countdown:

```text
Auto rollback in 30s
```

### Requirement

Confirm Dialog must only appear after the app enters `ConfirmRequired`.

It must not appear during `Preparing`.

## 7.4 Restore Progress

A restore popup is not required for the first iteration.

However, the menu bar menu must clearly show restore progress:

```text
Status: Restoring
Current Step: Waiting for a physical display to become available…
```

## 7.5 Copy Status

`Copy Status` must include phase information:

```text
Mode: Restoring
Phase: waitingForPhysicalDisplay
Phase Message: Waiting for a physical display to become available…
Phase Elapsed: 6s
Phase Deadline: 10s
Cooldown Remaining: 0s
```

## 8. Timing Configuration

## 8.1 New Config Fields

Add the following config section:

```json
{
  "timing": {
    "virtualDisplayEnumerationWaitSeconds": 5,
    "virtualDisplayReportedIDExtraWaitSeconds": 2,
    "softDisconnectDisappearWaitSeconds": 1,
    "restoreBuiltInShortWaitSeconds": 3,
    "restorePhysicalDisplayWaitSeconds": 10,
    "restoreCooldownSeconds": 10,
    "restoreCooldownAfterPausedSeconds": 20
  }
}
```

## 8.2 Default Values

| Config key | Default | Description |
|---|---:|---|
| virtualDisplayEnumerationWaitSeconds | 5 | Base wait for CoreGraphics to enumerate a new virtual display |
| virtualDisplayReportedIDExtraWaitSeconds | 2 | Extra wait after the host reports a display ID |
| softDisconnectDisappearWaitSeconds | 1 | Wait for built-in display to disappear after soft-disconnect |
| restoreBuiltInShortWaitSeconds | 3 | Short wait after enabling the built-in display |
| restorePhysicalDisplayWaitSeconds | 10 | Max wait for any physical display to become available |
| restoreCooldownSeconds | 10 | Cooldown after normal restore |
| restoreCooldownAfterPausedSeconds | 20 | Cooldown after paused/error restore path |

## 8.3 Compatibility

If an existing config file does not contain `timing`:

1. Use defaults automatically.
2. Do not overwrite existing settings.
3. Do not reset resolution, hotkeys, confirmDialog, virtual-display-policy, soft-disconnect, touchbar-hide, or keep-awake-backend.

## 9. CLI Requirements

## 9.1 Status Output

`codex-headless status` must include phase information:

```text
Mode: Preparing
Phase: waitingForVirtualDisplayEnumeration
Phase Message: Waiting for macOS to detect the virtual display…
Phase Elapsed: 2s
Phase Deadline: 5s
```

## 9.2 Config Get Timing

Add:

```bash
codex-headless config get timing
```

Example output:

```text
virtualDisplayEnumerationWaitSeconds=5
virtualDisplayReportedIDExtraWaitSeconds=2
softDisconnectDisappearWaitSeconds=1
restoreBuiltInShortWaitSeconds=3
restorePhysicalDisplayWaitSeconds=10
restoreCooldownSeconds=10
restoreCooldownAfterPausedSeconds=20
```

## 9.3 Config Set Timing

Recommended support:

```bash
codex-headless config set timing.virtualDisplayReportedIDExtraWaitSeconds 2
codex-headless config set timing.restoreCooldownSeconds 10
```

If this is too much for the first iteration, manual config editing is acceptable, but `config get timing` should still work.

## 9.4 Doctor Output

`doctor` should include a timing summary:

```text
Timing:
  Virtual display enumeration wait: 5s
  Reported ID extra wait: 2s
  Restore physical display wait: 10s
  Restore cooldown: 10s
```

## 10. Enable Headless Mode Flow

## 10.1 External / HDMI Dummy Path

When an external display or HDMI Dummy is available:

```text
1. phase = startingKeepAwake
2. Start Keep Awake

3. phase = checkingDisplays
4. Enumerate displays

5. phase = usingExternalDisplay or promotingExternalDisplay
6. Use external / HDMI Dummy display as main display

7. phase = disconnectingBuiltInDisplay
8. Try soft-disconnect for built-in display

9. phase = waitingForBuiltInDisplayDisconnect
10. Wait up to softDisconnectDisappearWaitSeconds
11. If still visible, log warning and continue

12. phase = hidingTouchBar
13. Hide Touch Bar UI

14. phase = waitingForConfirmation
15. Start rollback guard
16. Enter ConfirmRequired
17. Show Confirm Dialog
```

### External Path Acceptance Criteria

1. The app must not create a software virtual display unless policy requires it.
2. The app must not show virtual display wait messages unless virtual display creation is actually used.
3. Enable should be faster than the no-external-display path.
4. Confirm Dialog appears only after `ConfirmRequired`.

## 10.2 Software Virtual Display Path

When no external display or HDMI Dummy is available, or policy requires software virtual display:

```text
1. phase = startingKeepAwake
2. Start Keep Awake

3. phase = checkingDisplays
4. Enumerate displays

5. phase = creatingVirtualDisplay
6. Start virtual display host

7. phase = waitingForVirtualDisplayEnumeration
8. Wait for CoreGraphics enumeration up to virtualDisplayEnumerationWaitSeconds

9. If the host reported displayID:
   - phase = acceptingReportedVirtualDisplayID
   - Wait virtualDisplayReportedIDExtraWaitSeconds
   - If still not enumerated, accept reported displayID

10. phase = promotingVirtualDisplay
11. Set virtual display as main display

12. phase = disconnectingBuiltInDisplay
13. Try soft-disconnect for built-in display

14. phase = waitingForBuiltInDisplayDisconnect
15. Wait up to softDisconnectDisappearWaitSeconds
16. If still visible, log warning and continue

17. phase = hidingTouchBar
18. Hide Touch Bar UI

19. phase = waitingForConfirmation
20. Start rollback guard
21. Enter ConfirmRequired
22. Show Confirm Dialog
```

### Software Virtual Display Path Acceptance Criteria

1. After host reports displayID, the app should not wait 20 seconds by default.
2. The extra wait after reported displayID should default to about 2 seconds.
3. The app should continue with the reported displayID if CoreGraphics enumeration is delayed.
4. The menu must show the current phase during each wait.
5. Confirm Dialog appears only after `ConfirmRequired`.

## 11. Restore Normal Mode Flow

## 11.1 General Restore Rules

Restore must be safe for both paths:

1. External / HDMI Dummy path.
2. Software virtual display path.

The app must not stop a managed virtual display until a physical display is available and promoted, unless the user explicitly uses a dangerous force option. No force option is required in this iteration.

## 11.2 New Restore Flow

```text
1. phase = restoringBuiltInDisplay
2. Call helper to restore built-in display

3. phase = waitingForPhysicalDisplay
4. Wait restoreBuiltInShortWaitSeconds
5. Check if built-in, external, or HDMI Dummy display is available

6. If a physical display is available:
   - phase = promotingPhysicalDisplay or keepingExternalDisplayAsMain
   - Promote or keep physical display as main
   - Continue restore

7. If no physical display is available:
   - Keep managed virtual display alive
   - Do not immediately show Error
   - Continue waiting for up to restorePhysicalDisplayWaitSeconds

8. If a physical display appears:
   - phase = promotingPhysicalDisplay
   - Set physical display as main
   - phase = restoringTouchBar
   - Restore Touch Bar UI
   - phase = restoringBrightness
   - Restore brightness
   - phase = stoppingVirtualDisplay
   - Stop managed virtual display if it exists
   - phase = stoppingKeepAwake
   - Stop caffeinate
   - phase = coolingDown
   - Enter Normal with cooldown

9. If no physical display appears after restorePhysicalDisplayWaitSeconds:
   - phase = restorePaused
   - Keep managed virtual display alive
   - Keep checking through menu bar timer / CLI status
   - Show status as Restoring or Restore Paused, not immediate unrecoverable Error
```

## 11.3 Error Display Rules

Do not display `Error` just because the physical display is not immediately available during restore.

Recommended display:

```text
Status: Restoring
Current Step: Restore paused. Waiting for a physical display…
```

Only show `Error` when:

1. A critical restore operation fails.
2. There is no safe continuation path.
3. The app cannot keep a safe display output alive.
4. The state file or managed display host is inconsistent in a way that prevents recovery.

## 11.4 Restore Acceptance Criteria

1. Restore must not show Error too early.
2. If a physical display becomes available shortly afterward, the app continues restoring cleanly.
3. The managed virtual display remains alive until a physical display is available.
4. Restore progress appears in the menu.
5. Normal restore cooldown defaults to 10 seconds.
6. Paused/error restore cooldown defaults to 20 seconds.

## 12. Cooldown Behavior

## 12.1 New Rules

```text
Normal restore success:
cooldown = restoreCooldownSeconds, default 10s

Restore after paused/error path:
cooldown = restoreCooldownAfterPausedSeconds, default 20s
```

## 12.2 UI

During cooldown:

```text
Status: Normal
Current Step: Waiting for display state to stabilize…
Enable available in: 8s
```

If the user presses `⌃⌥⌘⇧E` or clicks Enable during cooldown:

```text
Enable ignored: restore cooldown active, 8s remaining.
```

## 13. Logging Requirements

## 13.1 Phase Logs

Log every phase change:

```text
[Phase] creatingVirtualDisplay
[Phase] waitingForVirtualDisplayEnumeration, timeout=5s
[Phase] acceptingReportedVirtualDisplayID, displayID=17, extraWait=2s
[Phase] promotingVirtualDisplay, displayID=17
```

## 13.2 External Display Path Logs

Example:

```text
[Phase] checkingDisplays
External display detected: displayID=3
[Phase] usingExternalDisplay
Using external display as main display: displayID=3
```

## 13.3 Virtual Display Wait Logs

Example:

```text
Virtual display host reported displayID=17; extra wait 2s for CoreGraphics enumeration.
CoreGraphics did not enumerate displayID=17 after 2s; accepting reported ID.
```

## 13.4 Restore Logs

Example:

```text
[Phase] waitingForPhysicalDisplay, shortWait=3s, maxWait=10s
Physical display not available after short wait; keeping managed virtual display alive.
Physical display became available: displayID=1
```

## 13.5 Cooldown Logs

Example:

```text
Normal Mode restored. Enable cooldown until ..., duration=10s.
```

If restore was paused:

```text
Normal Mode restored after paused restore. Enable cooldown until ..., duration=20s.
```

## 14. Safety Requirements

## 14.1 Do Not Sacrifice Restore Safety

The following protections must remain:

1. Keep managed virtual display alive until a physical display is available.
2. Keep paused restore mechanism.
3. Keep CLI `off` recovery path.
4. Keep rollback guard.
5. Keep safety checks that prevent disconnecting the only display.

## 14.2 Virtual Display Must Not Be Stopped Too Early

During restore, only stop the managed virtual display host after at least one of the following is true:

1. The built-in display appears in CoreGraphics enumeration.
2. An external / HDMI Dummy display appears in CoreGraphics enumeration.
3. A physical display has been successfully promoted or kept as the main display.

## 14.3 Distinguish RestorePaused from Error

`restorePaused` is not the same as unrecoverable `Error`.

Recommended distinction:

```text
RestorePaused:
The managed virtual display is still alive, and the app is waiting for a physical display.

Error:
A critical restore step failed, and the app has no safe continuation path.
```

## 15. Implementation Order

### Phase 1: Config and Runtime State

1. Add `timing` config.
2. Add `phase` runtime fields.
3. Update ConfigManager defaults.
4. Update StateManager backward compatibility.
5. Update status and Copy Status outputs.

### Phase 2: Virtual Display Wait Optimization

1. Modify `VirtualDisplayManager.waitForNewDisplayID()`.
2. Replace 20-second reported ID wait with config value, default 2 seconds.
3. Add phase updates and logs.
4. Verify no-external-display enable time improves.

### Phase 3: External Display Path Phase Support

1. Add `checkingDisplays`.
2. Add `usingExternalDisplay` or `promotingExternalDisplay`.
3. Ensure virtual display wait phases are skipped when not used.
4. Ensure external path remains fast.

### Phase 4: Soft-Disconnect Wait Optimization

1. Make soft-disconnect disappear wait configurable.
2. Default to 1 second.
3. If still visible, log warning and continue.
4. Add phase updates and logs.

### Phase 5: Restore Flow Optimization

1. Shorten initial built-in restore wait.
2. Add `waitingForPhysicalDisplay` phase.
3. Avoid showing Error for normal physical-display wait.
4. Keep managed virtual display alive until physical display is available.
5. Apply different cooldown durations depending on restore path.

### Phase 6: UI Progress

1. Add Current Step to menu.
2. Show phase elapsed time.
3. Show phase deadline/timeout where applicable.
4. Show cooldown remaining.
5. Ensure Confirm Dialog uses English text only.

### Phase 7: Documentation and Testing

1. Update README.
2. Update recommended test workflow.
3. Add Timing Configuration section.
4. Add Waiting and Progress Phases section.
5. Add examples for external display and no-external-display paths.

## 16. Acceptance Tests

## 16.1 No External Display Enable Test

Preconditions:

```text
virtual-display-policy=always
scale-mode=hidpi
No external display
```

Steps:

```bash
codex-headless on
```

Expected:

1. After the host reports displayID, the app does not wait 20 seconds by default.
2. Reported ID extra wait is about 2 seconds by default.
3. Virtual display becomes main display.
4. Built-in display soft-disconnect is attempted.
5. Touch Bar UI is hidden.
6. App enters ConfirmRequired.
7. Confirm Dialog appears.
8. Menu shows current step.
9. Logs include phase changes.

## 16.2 External / HDMI Dummy Enable Test

Preconditions:

```text
External display or HDMI Dummy connected
virtual-display-policy=auto
```

Steps:

```bash
codex-headless on
```

Expected:

1. App detects external / HDMI Dummy display.
2. App skips software virtual display creation.
3. App does not show virtual display wait phases.
4. App uses or promotes external display.
5. App processes built-in display and Touch Bar.
6. App enters ConfirmRequired.
7. Enable is faster than the no-external-display path.

## 16.3 Automatic Rollback Test

Steps:

```bash
codex-headless on
# Do not confirm
# Wait for rollback timeout
```

Expected:

1. Rollback timeout triggers restore.
2. Restore menu shows `Waiting for a physical display to become available…` when applicable.
3. App does not show Error prematurely.
4. Managed virtual display remains alive until a physical display is available.
5. Virtual display stops only after physical display is available.
6. Touch Bar is restored.
7. Keep Awake stops.
8. App returns to Normal.
9. Cooldown defaults to 10 seconds or 20 seconds if restore paused.

## 16.4 Confirm + Restore Test

Steps:

```bash
codex-headless on
codex-headless confirm
codex-headless off
```

Or with hotkeys:

```text
⌃⌥⌘⇧E
⌃⌥⌘⇧C
⌃⌥⌘⇧R
```

Expected:

1. Confirm enters Headless.
2. Restore enters Restoring.
3. Waiting phases are visible.
4. Restore eventually enters Normal.
5. Cooldown is applied.
6. Cooldown duration matches config.

## 16.5 Cooldown Test

Steps:

1. Restore Normal Mode.
2. Immediately press `⌃⌥⌘⇧E`.
3. Check menu and logs.

Expected:

1. Enable is ignored.
2. Menu shows cooldown remaining.
3. Logs show remaining seconds.
4. Enable works after cooldown expires.

## 16.6 Config Compatibility Test

With an old config file that does not contain `timing`:

1. App starts normally.
2. CLI runs normally.
3. Default timing values apply.
4. Existing hotkeys, confirmDialog, resolution, virtual-display-policy, soft-disconnect, and touchbar-hide settings remain unchanged.

## 16.7 English Text Test

Verify all user-facing text is English in:

1. Menu bar menu.
2. Confirm Dialog.
3. CLI output.
4. Copy Status.
5. Logs.
6. Doctor output.
7. README examples.

No Chinese UI or CLI strings should remain in the product output.

## 17. README Update Requirements

Add a section:

```text
## Waiting and Progress Phases
```

Explain:

1. Enable and Restore show the current step in the menu.
2. Software virtual display creation may require waiting for macOS detection.
3. When using an external display or HDMI Dummy, virtual display wait phases are skipped.
4. During restore, the managed virtual display remains alive until a physical display is available.
5. Restore paused does not always mean failure; it usually means the app is waiting for the built-in display or external display to become available.

Add a section:

```text
## Timing Configuration
```

Example:

```json
{
  "timing": {
    "virtualDisplayEnumerationWaitSeconds": 5,
    "virtualDisplayReportedIDExtraWaitSeconds": 2,
    "softDisconnectDisappearWaitSeconds": 1,
    "restoreBuiltInShortWaitSeconds": 3,
    "restorePhysicalDisplayWaitSeconds": 10,
    "restoreCooldownSeconds": 10,
    "restoreCooldownAfterPausedSeconds": 20
  }
}
```

Add notes:

1. Do not set wait durations to 0 unless debugging.
2. If restore becomes unstable, increase `restorePhysicalDisplayWaitSeconds`.
3. If virtual display creation is stable, `virtualDisplayReportedIDExtraWaitSeconds` can be reduced carefully.
4. Defaults are optimized for the current target machine.

## 18. Final Conclusion

This iteration should not remove all waits. It should classify waits into three types:

```text
Necessary safety waits
Overly conservative waits that can be shortened
Waits that need clear UI explanation
```

Recommended outcome:

1. Virtual display reported ID wait reduced from about 20 seconds to about 2 seconds.
2. Soft-disconnect verification wait reduced from about 2 seconds to about 1 second.
3. Restore initial wait reduced to about 3 seconds.
4. Restore physical-display waiting is shown as a normal restore phase instead of premature Error.
5. Normal cooldown reduced from 20 seconds to 10 seconds.
6. Paused/error restore cooldown remains 20 seconds.
7. External display / HDMI Dummy path uses the same phase system but skips virtual display waits.
8. All user-facing messages are in English.

The final goal is to make CodexHeadless faster, clearer, and more suitable for daily use while preserving its safety-first recovery design.
