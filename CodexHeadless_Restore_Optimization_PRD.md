# CodexHeadless Restore 流程优化小 PRD

## 1. 背景

在无外接显示器的 MacBook Pro 测试环境下，CodexHeadless 启用 Headless Mode 后可正常创建软件虚拟显示器，并通过软断开方式隐藏内建显示器。当前版本相比之前已经明显缩短等待时间，整体效率提高。

但在 Restore Normal Mode 流程中，仍观察到以下体验问题：

1. Restore 后、虚拟显示器消失前，内建显示器已经恢复显示，但部分 App 窗口仍停留在虚拟显示器上，导致内建屏只显示部分窗口或空桌面。
2. 在上述短暂阶段，菜单栏中的 CodexHeadless 状态栏图标可能不可见，用户无法确认当前程序状态。
3. Timing 配置虽然在 CLI / config 层面存在，但 App 菜单中没有入口，用户无法直观找到和调整。

相关日志显示，Restore 时 CoreGraphics 对物理显示器的枚举存在轻微延迟：

```text
[2026-07-09T03:15:42Z] [INFO] [Phase] waitingForPhysicalDisplay, timeout=10s
[2026-07-09T03:15:52Z] [WARN] Physical display not available after 10s; keeping managed virtual display alive.
[2026-07-09T03:15:53Z] [INFO] Continuing paused restore after built-in or external display became available.
[2026-07-09T03:15:53Z] [INFO] [Phase] promotingPhysicalDisplay
[2026-07-09T03:15:56Z] [INFO] [Phase] stoppingVirtualDisplay
```

这说明并非真正 restore 失败，而是物理屏恢复枚举、主屏切换、虚拟屏销毁、窗口迁移之间存在短暂竞态。

## 2. 目标

本次优化目标是改善 Restore Normal Mode 的可见状态和窗口迁移体验，让用户在没有外接显示器的情况下恢复内建屏时，尽可能避免“窗口仍停留在虚拟显示器上”和“状态栏图标不可见导致无法确认状态”的问题。

核心目标：

1. 物理显示器可用并设为主屏后，尽快销毁 managed virtual display。
2. 避免因 CoreGraphics 枚举慢一拍而过早进入 paused restore。
3. Restore 期间提供不依赖菜单栏图标的可视化状态提示。
4. 在 App 菜单中暴露 Timing 配置入口，降低调试和配置门槛。
5. 优化日志表达，让 restorePaused 的进入和恢复原因更清晰。

## 3. 非目标

本次不要求：

1. 重写虚拟显示器实现。
2. 改变 Headless Mode 的基本架构。
3. 支持 App Store 发布或沙盒化。
4. 完全保证所有第三方 App 窗口立即迁移；目标是缩短异常窗口期，并提供清晰状态提示。
5. 解决所有亮度恢复问题；亮度恢复失败只需保持当前 warning 和用户提示。

## 4. 当前问题分析

### 4.1 Restore 顺序导致虚拟显示器存活时间偏长

当前 restore 后半段大致顺序为：

```text
promotingPhysicalDisplay
-> restoringTouchBar
-> restoringBrightness
-> stoppingVirtualDisplay
-> stoppingKeepAwake
```

这个顺序会导致物理显示器已经恢复并被设置为主屏后，虚拟显示器仍继续存活数秒。macOS 可能仍把部分窗口、菜单栏或 Space 状态保留在虚拟显示器上，用户看到内建屏已有显示但窗口不完整。

### 4.2 CoreGraphics 枚举存在短暂延迟

日志显示，`restorePhysicalDisplayWaitSeconds` 超时后 1 秒内，物理显示器又变为可用并继续 paused restore。这说明等待逻辑存在边界竞态：刚好超时并进入 paused restore，但实际物理屏即将完成枚举。

### 4.3 状态栏图标不能作为唯一状态提示

在显示器切换、主屏切换、虚拟屏仍存活期间，NSStatusItem 可能显示在虚拟显示器对应的菜单栏或 Space 上，用户在内建屏上看不到 CodexHeadless 图标。因此 restore 流程需要一个独立于状态栏的可视化提示。

### 4.4 Timing 配置缺少 App 菜单入口

当前 CLI 已支持类似以下命令：

```bash
codex-headless config get timing
codex-headless config set timing.restorePhysicalDisplayWaitSeconds 15
```

但 App 菜单没有 Timing 入口，用户无法从 GUI 发现这些配置项。

## 5. 功能需求

### 5.1 调整 restore 后半段执行顺序

#### 需求描述

在物理显示器可用，并成功设置为主屏后，应尽快停止 managed virtual display，减少窗口和菜单栏继续停留在虚拟显示器上的时间。

#### 建议新顺序

将当前：

```text
promotingPhysicalDisplay
-> restoringTouchBar
-> restoringBrightness
-> stoppingVirtualDisplay
-> stoppingKeepAwake
```

调整为：

```text
promotingPhysicalDisplay
-> short stabilization wait 0.5~1s
-> stoppingVirtualDisplay
-> restoringTouchBar
-> restoringBrightness
-> stoppingKeepAwake
```

#### 实现建议

1. 在 `finishRestoreAfterPhysicalDisplayAvailable` 或等价函数中调整调用顺序。
2. `promotingPhysicalDisplay` 成功后，增加短暂 stabilization wait，默认 0.5~1 秒。
3. 之后立即停止 managed virtual display host。
4. Touch Bar、亮度、caffeinate 清理逻辑保持原有容错。
5. 如果停止虚拟显示器失败，应记录 warning，但继续执行后续清理逻辑。

#### 验收标准

1. Restore 后，物理屏可用并设为主屏后，虚拟显示器应在 1~2 秒内被停止。
2. 日志中 `stoppingVirtualDisplay` 应出现在 `restoringTouchBar` 和 `restoringBrightness` 之前。
3. 内建屏已恢复显示但窗口仍留在虚拟屏的时间应明显缩短。

## 6. 枚举等待与 paused restore 优化

### 6.1 增加 final grace polling

#### 需求描述

当 `restorePhysicalDisplayWaitSeconds` 到达超时时，不要立即进入 paused restore。应增加一个短暂的 final grace polling，用于处理 CoreGraphics 枚举慢一拍的情况。

#### 建议逻辑

```text
wait restorePhysicalDisplayWaitSeconds
if physical display not available:
    enter final grace polling, duration=2~3s, interval=250ms
    if physical display becomes available:
        continue normal finishRestore
    else:
        enter restorePaused
```

#### 建议配置项

新增 Timing 配置：

```json
{
  "restorePhysicalDisplayGraceSeconds": 3,
  "restorePhysicalDisplayGracePollIntervalMilliseconds": 250
}
```

#### 验收标准

1. 如果物理屏在主等待超时后 2~3 秒内出现，不应进入 restorePaused。
2. 日志应明确显示进入 grace polling，以及 grace polling 内是否发现物理屏。
3. 如果 grace polling 后仍未发现物理屏，再进入 restorePaused。

## 7. Restore Progress Overlay

### 7.1 需求描述

Restore 期间增加一个不依赖 NSStatusItem 的小型状态浮窗，用于在菜单栏图标不可见时提示当前状态。

### 7.2 显示时机

Overlay 应在以下阶段显示：

1. Restore Normal Mode requested 后。
2. waitingForPhysicalDisplay 阶段。
3. restorePaused 阶段。
4. promotingPhysicalDisplay 阶段。
5. stoppingVirtualDisplay 阶段。

Overlay 应在 Normal Mode restored 后自动关闭。

### 7.3 窗口行为

建议使用 `NSPanel`：

1. `level` 使用 floating 或更高层级。
2. `collectionBehavior` 包含：
   - `canJoinAllSpaces`
   - `fullScreenAuxiliary`
   - 如有必要可增加 `transient`
3. 尽量在所有当前可见 screen 上显示，或至少显示在当前主屏中心。
4. 不应抢焦点，不应阻塞用户操作。
5. restorePaused 阶段可以显示更明显的提示。

### 7.4 文案建议

普通 restore 阶段：

```text
Restoring Normal Mode…
Switching back to physical display.
Virtual display will close shortly.
```

restorePaused 阶段：

```text
Restore is waiting for a physical display…
The virtual display is kept alive for safety.
Press Restore hotkey again after the built-in display appears.
```

stoppingVirtualDisplay 阶段：

```text
Closing virtual display…
Windows may move back to the built-in display shortly.
```

### 7.5 验收标准

1. Restore 过程中，即使菜单栏图标不可见，用户仍能看到状态提示。
2. Overlay 不应阻塞确认对话框、系统权限弹窗或快捷键响应。
3. Normal Mode restored 后 Overlay 自动关闭。
4. 如果 restore 失败或进入 paused restore，Overlay 显示对应状态。

## 8. Timing 菜单配置

### 8.1 需求描述

在 App 菜单中增加 Timing 子菜单，让用户可以查看和调整当前 timing 配置。

### 8.2 菜单入口

建议路径：

```text
CodexHeadless Menu
-> Settings
   -> Timing
```

或直接：

```text
CodexHeadless Menu
-> Timing
```

### 8.3 至少暴露以下配置项

```text
virtualDisplayEnumerationWaitSeconds
virtualDisplayReportedIDExtraWaitSeconds
softDisconnectDisappearWaitSeconds
restoreBuiltInShortWaitSeconds
restorePhysicalDisplayWaitSeconds
restoreCooldownSeconds
restoreCooldownAfterPausedSeconds
```

新增后也应暴露：

```text
restorePhysicalDisplayGraceSeconds
restorePhysicalDisplayGracePollIntervalMilliseconds
```

### 8.4 交互方式

可以先采用简单子菜单预设值，不要求复杂设置窗口。

例如：

```text
Restore Physical Display Wait
-> 5s
-> 10s
-> 15s
-> 20s
-> 30s
```

```text
Restore Physical Display Grace
-> Off
-> 1s
-> 2s
-> 3s
-> 5s
```

```text
Restore Cooldown
-> 10s
-> 20s
-> 30s
```

同时建议增加：

```text
Open Config Folder
Copy Timing Config Debug Info
Reset Timing to Default
```

### 8.5 验收标准

1. 用户可以从菜单看到 Timing 入口。
2. 修改菜单项后，配置写入 `~/Library/Application Support/CodexHeadless/config.json`。
3. 修改后立即生效，或明确提示需要重启 App。
4. `codex-headless config get timing` 能看到菜单修改后的结果。

## 9. 日志优化

### 9.1 需求描述

当前日志容易让人误以为 restore 失败，例如刚记录：

```text
Physical display not available after 10s; keeping managed virtual display alive.
```

随后又继续 restore：

```text
Continuing paused restore after built-in or external display became available.
```

应让日志更准确地反映状态转换。

### 9.2 建议日志

主等待超时：

```text
Physical display was not enumerated before primary timeout; entering final grace polling.
```

grace polling 成功：

```text
Physical display became available during grace polling; continuing restore without entering paused state.
```

grace polling 失败并进入 paused：

```text
Physical display still unavailable after grace polling; entering paused restore and keeping managed virtual display alive for safety.
```

paused restore 后恢复：

```text
Paused restore resumed after a physical display became available.
```

### 9.3 验收标准

1. 从日志可以清晰判断 restore 是正常完成、grace polling 后完成，还是 paused restore 后完成。
2. 不应出现前后矛盾或容易误读为失败的日志。

## 10. 推荐优先级

### P0

1. 调整 restore 顺序，优先停止虚拟显示器。
2. 增加 final grace polling。
3. 优化相关日志。

### P1

1. 增加 Restore Progress Overlay。
2. 菜单增加 Timing 配置入口。

### P2

1. 增加更完整的 Timing 设置窗口。
2. 增加窗口迁移辅助逻辑，例如主动触发 WindowServer / Space 刷新，但需谨慎评估稳定性。

## 11. 测试场景

### 11.1 无外接显示器测试

测试步骤：

1. 确保没有外接显示器。
2. 启动 CodexHeadless。
3. 通过快捷键启用 Headless Mode。
4. 确认虚拟显示器创建成功，内建屏软断开。
5. 通过快捷键 Restore Normal Mode。
6. 观察内建屏恢复、窗口迁移、状态提示和虚拟显示器销毁顺序。

预期结果：

1. 内建屏恢复后，虚拟显示器尽快销毁。
2. App 窗口回到内建屏的等待时间缩短。
3. 即使状态栏图标不可见，也能看到 Restore Progress Overlay。
4. 日志顺序符合新 restore 流程。

### 11.2 CoreGraphics 慢枚举测试

测试方式：

1. 将 `restorePhysicalDisplayWaitSeconds` 设置为较短值，例如 3 秒。
2. 将 `restorePhysicalDisplayGraceSeconds` 设置为 3 秒。
3. 反复启用和 restore。

预期结果：

1. 如果物理屏在 grace polling 阶段出现，应直接继续 restore。
2. 不应过早进入 restorePaused。
3. 日志明确显示 grace polling 的命中情况。

### 11.3 Timing 菜单测试

测试步骤：

1. 打开 CodexHeadless 菜单。
2. 进入 Timing 子菜单。
3. 修改 restore physical wait、grace polling、cooldown 等配置。
4. 使用 CLI 查看配置。

预期结果：

1. 菜单配置可见、可修改。
2. CLI 读取结果与菜单设置一致。
3. 配置文件持久化成功。

## 12. 建议默认配置

```json
{
  "timing": {
    "virtualDisplayEnumerationWaitSeconds": 5,
    "virtualDisplayReportedIDExtraWaitSeconds": 2,
    "softDisconnectDisappearWaitSeconds": 1,
    "restoreBuiltInShortWaitSeconds": 3,
    "restorePhysicalDisplayWaitSeconds": 10,
    "restorePhysicalDisplayGraceSeconds": 3,
    "restorePhysicalDisplayGracePollIntervalMilliseconds": 250,
    "restoreCooldownSeconds": 10,
    "restoreCooldownAfterPausedSeconds": 20,
    "restorePostPromoteStabilizationMilliseconds": 750
  }
}
```

## 13. 完成定义

本次优化完成后，应满足：

1. Restore 后物理屏恢复显示时，虚拟显示器尽快关闭。
2. 物理屏枚举慢一拍时，优先通过 grace polling 继续正常 restore，而不是立即进入 paused restore。
3. Restore 期间有独立于菜单栏的状态提示。
4. 用户可以通过 App 菜单发现和调整 Timing 配置。
5. 日志能准确解释 restore 的每个阶段和状态转换。
