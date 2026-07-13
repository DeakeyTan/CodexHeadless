# CodexHeadless Recovery Guide / 恢复指南

## 中文

### 首选恢复流程

恢复热键为 `Control+Option+Command+Shift+R`。也可使用状态栏菜单的 **Restore Normal Mode**，或在本地/SSH 终端运行 `codex-headless off`。

1. 通过 SSH 登录目标 Mac，运行 `codex-headless status` 和 `codex-headless doctor`。
2. 运行 `codex-headless off`。Restore 即使无法读取 config，也会使用 Safe Restore timing 继续。
3. 只有输出 `Normal Mode restored.` 或 `Normal Mode is already restored.` 且退出码为 `0`，才表示恢复完成。
4. `Restore paused for safety` 表示物理屏尚未安全接管；保留虚拟显示器和 Keep Awake，接入物理屏后重试。
5. `Restore cleanup is incomplete` 表示 journal 已记录真实 cleanup 进度；修复提示的问题后再次运行 `off`，不会重复终止已停止的资源。
6. `Recovery is still required` 表示缺少可信凭据。不要手工 kill，先保存日志和 journal。
7. UI 不可见时，优先使用 SSH/本地终端。先保存 `~/Library/Logs/CodexHeadless.log`，再运行 `status`、`doctor` 和 `off`。
8. 卸载前运行 `codex-headless uninstall-check`。只有它返回 `Uninstall check: SAFE` 和 exit code 0 时才可以删除 App 与 CLI；`scripts/uninstall.sh` 会自动执行 Restore 和这项权威预检，任何失败都会保留恢复工具、配置与日志。

紧急重启通常会重新启用物理显示输出，但不会自动证明 managed helper、Journal 或 Touch Bar 已清理。重启后仍需运行 `status`、`doctor` 和 `off`。不要仅因为屏幕亮起就删除状态文件或手工终止 PID。

### Recovery Journal

路径：`~/Library/Application Support/CodexHeadless/recovery-journal.json`。

Journal 独立于 `state.json`，记录内建屏 ID、soft-disconnect 方法、替代显示器、Keep Awake/虚拟屏可信进程身份和 Restore cleanup 进度。它在最终 Normal state 成功写入后才删除。损坏副本保存为 `recovery-journal.damaged.<hash>.json`。

Future schema 与损坏文件严格分流：如果 Journal schema 高于当前程序支持版本，原文件不会被备份、删除、覆盖、降级或重建，也不会执行进程清理；请升级 CodexHeadless 后再 Restore。当前 schema 损坏时也不能仅凭 RuntimeState 自动认领或终止进程。

Cleanup Progress 分别记录 brightness restore/verification、virtual host stop、virtual display disappearance、Keep Awake holder stop、assertion disappearance、Touch Bar、RuntimeState persistence 和 Journal finalization。再次运行 Restore 会跳过已独立验证完成的阶段，并重新观察 unknown 阶段。

R4 要求所有 Restore 成功出口经过同一个最终门：先用一张共享进程快照确认非 Journal 的 Clean Normal 条件，再写 RuntimeState、finalize/delete Journal，最后轻量复核 RuntimeState、Journal 和物理显示器。Touch Bar 如果由 CodexHeadless 修改但无法确认恢复，Restore 返回 `cleanupIncomplete` 并保留 Journal，后续 Restore 会重试。

App 菜单显示的 `Safety: Checking...` 是后台展示缓存；它不替代 Core 门禁。菜单或热键会立即给出反馈，Core 仍在 workflow lock 后重新读取 RuntimeState、Journal、进程快照和显示事实。

### 常见场景

- **state 损坏、journal 正常**：`off` 根据 journal 恢复 soft-disconnect 内建屏，验证物理接管，再清理受管理资源。
- **config 损坏或 future schema**：不会阻止 Restore；Enable 会保持禁用，检查 `config.damaged.<hash>.json` 后可运行 `config reset defaults`。
- **state 与 config 同时损坏**：journal 正常时仍可 Safe Restore。
- **journal 损坏**：只能依赖健康 state 和系统观测；无法形成可信所有权时进入 Recovery Required。
- **state 与 journal 都损坏/缺失**：只恢复可明确识别的物理显示输出，不终止无法证明所有权的进程。
- **内建屏已 soft-disconnect**：journal 中的 built-in display ID 用于重新连接；不要先关闭最后一个虚拟显示输出。
- **Keep Awake owner mismatch**：保留 On，退出旧 owner 或按提示恢复后重试；不得直接按 PID kill。
- **Brightness restore required**：当前版本禁用不可验证的键盘亮度 fallback。若旧状态记录 brightness dimmed 且无法验证恢复，最后一个 replacement 和 Keep Awake 会保留。
- **virtual display drift**：PID 退出但显示仍枚举时保持恢复状态；等待或重启 WindowServer/系统后再重试。
- **App/CLI 交叉恢复**：专用 helper 直接持有 IOPM assertion；App 创建的资源只有在 holder 身份与 Journal 完全匹配时才可由 CLI 恢复。
- **孤立 host 检查**：`repair --inspect-orphan-hosts` 只列出 found/preserved，不会自动终止。

终止进程前必须同时匹配 journal、PID、规范化可执行路径、命令 marker、instance ID、进程启动时间和可用的文件身份。任何一项不匹配都必须保留资源。

## English

### Preferred recovery flow

The Restore hotkey is `Control+Option+Command+Shift+R`. You may also choose **Restore Normal Mode** from the menu bar or run `codex-headless off` locally or over SSH.

1. Connect over SSH and run `codex-headless status` plus `codex-headless doctor`.
2. Run `codex-headless off`. Restore continues with Safe Restore timing even when config cannot be decoded.
3. Recovery is complete only when output is `Normal Mode restored.` or `Normal Mode is already restored.` and exit code is `0`.
4. `Restore paused for safety` means no physical display has safely taken over. Preserve the virtual display and Keep Awake, attach a physical display, and retry.
5. `Restore cleanup is incomplete` means the journal contains the actual cleanup progress. Correct the reported issue and retry; already stopped resources are not killed again.
6. `Recovery is still required` means trusted recovery evidence is missing. Do not kill processes manually; preserve logs and the journal.
7. If the UI is unavailable, use a local or SSH terminal. Preserve `~/Library/Logs/CodexHeadless.log`, then run `status`, `doctor`, and `off`.
8. Run `codex-headless uninstall-check` before uninstalling. Delete the App and CLI only when it returns `Uninstall check: SAFE` with exit code 0. `scripts/uninstall.sh` performs Restore and this authoritative preflight automatically; any failure preserves recovery tools, configuration, and logs.

An emergency restart normally re-enables physical display output, but it does not prove that managed helpers, the Journal, or Touch Bar state were cleaned. After restart, still run `status`, `doctor`, and `off`. Do not delete persistence files or kill a PID merely because the screen is visible.

### Recovery Journal

Path: `~/Library/Application Support/CodexHeadless/recovery-journal.json`.

The journal is independent of `state.json`. It records the built-in display ID, soft-disconnect method, replacement display, trusted Keep Awake/virtual-display process identities, and Restore cleanup progress. It is deleted only after final Normal state persistence succeeds. Damaged copies are stored as `recovery-journal.damaged.<hash>.json`.

Future schema is handled separately from damage. If the Journal schema is newer than this build, the original file is not backed up, deleted, overwritten, downgraded, or rebuilt, and no process cleanup runs. Upgrade CodexHeadless before retrying Restore. A damaged current-schema Journal also cannot use RuntimeState alone to claim or terminate a process.

Cleanup Progress independently records brightness restore/verification, virtual host stop, virtual display disappearance, Keep Awake holder stop, assertion disappearance, Touch Bar, RuntimeState persistence, and Journal finalization. A later Restore skips independently verified completed stages and re-observes unknown stages.

R4 routes every successful Restore through one final gate: one shared process snapshot verifies non-Journal Clean Normal conditions, RuntimeState and Journal are finalized, then a lightweight RuntimeState/Journal/physical-display check runs. If CodexHeadless changed the Touch Bar but cannot verify restoration, Restore returns `cleanupIncomplete`, preserves the Journal, and retries later.

`Safety: Checking...` in the App is a background presentation cache and never replaces the Core gate. Menu and hotkey actions acknowledge immediately; Core still rereads RuntimeState, Journal, process snapshot, and display facts after the workflow lock.

### Common scenarios

- **Damaged state, healthy journal:** `off` reconnects the built-in display from journal data, verifies physical takeover, then cleans managed resources.
- **Damaged or future-schema config:** Restore continues; Enable stays blocked until the config is inspected or reset.
- **State and config both damaged:** Safe Restore can continue when the journal is healthy.
- **Damaged journal:** healthy state plus observed resources may be used; otherwise the result is Recovery Required.
- **State and journal both damaged/missing:** only identifiable physical output may be restored; unverifiable processes are preserved.
- **Soft-disconnected built-in display:** the journal's display ID is used to reconnect it. Never stop the final virtual output first.
- **Keep Awake owner mismatch:** state remains On. Exit the old owner or follow recovery guidance, then retry.
- **Brightness restore required:** unverifiable keyboard brightness fallback is disabled. If legacy state records a dimmed display and restoration cannot be verified, the final replacement and Keep Awake remain active.
- **Virtual-display drift:** if the PID is gone but the display is still enumerated, recovery state is retained.
- **App/CLI cross-recovery:** a dedicated helper directly owns the IOPM assertion. Cross-process cleanup requires full holder identity plus Recovery Journal verification.

Internal helper commands are not recovery commands. They require an expiring one-time capability and cannot be invoked manually to bypass workflow locks or the Journal.
- **Orphan inspection:** `repair --inspect-orphan-hosts` reports found/preserved hosts and never terminates them automatically.

Before termination, the journal, PID, canonical executable path, command marker, instance ID, process start time, and available file identity must all match. Any mismatch preserves the resource.
