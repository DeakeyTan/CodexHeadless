# CodexHeadless

CodexHeadless 是一个 macOS 菜单栏工具和 CLI，用于把一台 MacBook 作为远程开发主机使用。它会在进入 Headless Mode 时保持系统唤醒、优先使用外接显示器/HDMI Dummy/软件虚拟显示器作为远程显示输出，并尽量关闭或隐藏内建屏幕与 Touch Bar UI。

CodexHeadless is a macOS menu bar utility and CLI for using a MacBook as a remote development host. When Headless Mode is enabled, it keeps the system awake, prefers an external display, HDMI dummy plug, or software virtual display for remote output, and attempts to disable or hide the built-in display and Touch Bar UI.

## 目录 / Contents

- [核心功能 / Features](#核心功能--features)
- [安装 / Installation](#安装--installation)
- [快速开始 / Quick Start](#快速开始--quick-start)
- [菜单栏使用 / Menu Bar Usage](#菜单栏使用--menu-bar-usage)
- [CLI 使用 / CLI Usage](#cli-使用--cli-usage)
- [显示布局 / Display Layout](#显示布局--display-layout)
- [配置项 / Configuration](#配置项--configuration)
- [Timing 参数 / Timing Parameters](#timing-参数--timing-parameters)
- [文件位置 / File Locations](#文件位置--file-locations)
- [安全与限制 / Safety and Limitations](#安全与限制--safety-and-limitations)
- [诊断与恢复 / Diagnostics and Recovery](#诊断与恢复--diagnostics-and-recovery)
- [兼容性 / Compatibility](#兼容性--compatibility)
- [构建 / Build](#构建--build)

## 核心功能 / Features

中文：

- 菜单栏 App：启用、确认、恢复 Headless Mode，查看状态，调整配置，复制诊断信息。
- CLI：支持 SSH 远程执行 `status`、`on`、`confirm`、`off`、`doctor`、`log`、`config` 等命令。
- Keep Awake：进入 Headless Mode 时启动，恢复 Normal Mode 时停止。
- 外接屏/Dummy 优先：有外接显示器或 HDMI Dummy 时优先保持它为主显示器。
- 软件虚拟显示器：可按策略创建 `CGVirtualDisplay` 虚拟显示器。
- 安全显示交接：先准备并验证替代显示器，再连续执行主屏切换和内建屏 soft-disconnect。
- 内建屏处理：默认在 soft-disconnect 失败时恢复 Normal Mode；高级用户可选择亮度降级。
- 显示布局备份：进入 Headless Mode 前按物理屏组合保存布局，恢复时尽量回放原来的排列。
- Touch Bar 隐藏：可清空 Control Strip UI，让 OLED 区域黑屏。
- Confirmation Policy：软件虚拟屏路径默认需要 30 秒内确认，外接/Dummy 路径默认直接进入 Headless Mode。
- 日志：关键显示器、睡眠、恢复步骤都会写入日志。

English:

- Menu bar app: enable, confirm, restore Headless Mode, inspect status, update settings, and copy diagnostics.
- CLI: SSH-friendly commands such as `status`, `on`, `confirm`, `off`, `doctor`, `log`, and `config`.
- Keep Awake: starts with Headless Mode and stops when Normal Mode is restored.
- External/dummy display priority: keeps an external display or HDMI dummy plug as the main display when available.
- Software virtual display: can create a `CGVirtualDisplay` based on policy.
- Safe display handoff: prepares and verifies a replacement before promoting it and soft-disconnecting the built-in display.
- Built-in display handling: restores Normal Mode by default if soft-disconnect fails; advanced users may opt into brightness fallback.
- Display layout backup: saves the physical display arrangement before Headless Mode and restores it when returning to Normal Mode.
- Touch Bar hiding: clears the Control Strip UI so the OLED area is black.
- Confirmation policy: the managed virtual display path requires confirmation by default; external/dummy paths enter Headless Mode directly.
- Logging: records key display, sleep, and restore operations.

## 安装 / Installation

中文：

```bash
./scripts/install.sh
```

安装脚本会构建 release 版本，并安装：

- CLI：`/usr/local/bin/codex-headless`
- App：`/Applications/CodexHeadless.app`

安装前建议先开启 SSH，确保出现显示器问题时可以远程恢复：

```bash
sudo systemsetup -setremotelogin on
codex-headless status
codex-headless off
```

English:

```bash
./scripts/install.sh
```

The installer builds a release version and installs:

- CLI: `/usr/local/bin/codex-headless`
- App: `/Applications/CodexHeadless.app`

Before first use, enable SSH so you can recover remotely if display state becomes confusing:

```bash
sudo systemsetup -setremotelogin on
codex-headless status
codex-headless off
```

## 快速开始 / Quick Start

中文：

1. 打开 `/Applications/CodexHeadless.app`。
2. 点击菜单栏 `CH` → `Enable Headless Mode`，或按 `⌃⌥⌘⇧E`。
3. 如果状态变为 `CH: Wait`，确认远程显示、SSH、Touch Bar 和内建屏状态正常。
4. 点击 `Confirm`，或按 `⌃⌥⌘⇧C`。外接/Dummy 路径按默认策略不需要确认。
5. 需要恢复时点击 `Restore Normal Mode`，或按 `⌃⌥⌘⇧R`。

CLI 等价流程：

```bash
codex-headless on
codex-headless confirm
codex-headless status
codex-headless off
```

English:

1. Open `/Applications/CodexHeadless.app`.
2. Click `CH` → `Enable Headless Mode`, or press `⌃⌥⌘⇧E`.
3. If the status becomes `CH: Wait`, verify remote display, SSH, Touch Bar, and built-in display state.
4. Click `Confirm`, or press `⌃⌥⌘⇧C`. External/dummy paths do not require confirmation under the default policy.
5. To restore, click `Restore Normal Mode`, or press `⌃⌥⌘⇧R`.

Equivalent CLI flow:

```bash
codex-headless on
codex-headless confirm
codex-headless status
codex-headless off
```

## 菜单栏使用 / Menu Bar Usage

### 状态文字 / Status Title

| 状态 / Status | 中文说明 | English |
| --- | --- | --- |
| `CH` | Normal Mode，Headless Mode 未开启。 | Normal Mode. Headless Mode is off. |
| `CH: Prep` | 正在准备进入 Headless Mode。 | Preparing Headless Mode. |
| `CH: Wait` | 等待确认，回滚计时器正在运行。 | Waiting for confirmation; rollback timer is active. |
| `CH: On` | Headless Mode 已确认。 | Headless Mode is confirmed. |
| `CH: Fall` | Fallback 状态，部分首选操作未成功。 | Fallback mode; not all preferred actions succeeded. |
| `CH: Restoring` | 正在恢复 Normal Mode。 | Restoring Normal Mode. |
| `CH: Cooldown` | 恢复已完成，暂时延迟再次 Enable。 | Restore finished; Enable is temporarily delayed. |
| `CH: Err` | 错误状态，建议查看日志或执行 restore。 | Error state; check logs or restore. |

### 主要操作 / Main Actions

| 菜单项 / Menu Item | 中文说明 | English |
| --- | --- | --- |
| `Enable Headless Mode` | 启动 Keep Awake，安全交接替代显示器并处理内建屏和 Touch Bar；是否确认由策略决定。 | Starts Keep Awake, safely hands off to a replacement display, and handles built-in display and Touch Bar; confirmation depends on policy. |
| `Confirm Headless Mode` | 确认当前显示状态正常，取消自动回滚。 | Confirms the current display state and cancels rollback. |
| `Rollback Now` | 在确认窗口内立即恢复 Normal Mode。 | Restores Normal Mode immediately during the confirmation window. |
| `Restore Normal Mode` | 恢复内建屏和 Touch Bar，关闭本工具创建的虚拟显示器，停止 Keep Awake。 | Restores built-in display and Touch Bar, closes managed virtual display, and stops Keep Awake. |
| `Apply Recommended v0.5 Config` | 写入当前推荐配置。 | Applies the current recommended settings. |
| `Reset All Settings to Default...` | 重置配置文件，不改变当前运行状态。Headless Mode 中请先 restore。 | Resets config only; does not change runtime state. Restore first if Headless Mode is active. |

### 子菜单 / Submenus

| 子菜单 / Submenu | 中文说明 | English |
| --- | --- | --- |
| `Virtual Display` | 设置软件虚拟显示器策略、分辨率和缩放模式。 | Configures software virtual display policy, resolution, and scale mode. |
| `Display & Touch Bar Safety` | 控制内建屏 soft-disconnect 和 Touch Bar hide。 | Controls built-in display soft-disconnect and Touch Bar hiding. |
| `Keep Awake Backend` | 选择 `caffeinate` 或 App 内 native assertion。 | Chooses `caffeinate` or in-app native assertion. |
| `Hotkeys` | 开关全局快捷键并显示注册状态。 | Enables/disables global hotkeys and shows registration status. |
| `Confirmation` | 设置确认策略、超时和确认弹窗。 | Configures confirmation policy, timeout, and dialog. |
| `Timing` | 调整显示器等待、恢复、冷却等时间参数。 | Tunes display wait, restore, and cooldown timings. |
| `Diagnostics` | 复制状态、Doctor、自测报告，打开日志和配置目录。 | Copies status, Doctor, self-test reports, and opens log/config folders. |

## CLI 使用 / CLI Usage

### 常用命令 / Common Commands

```bash
codex-headless status
codex-headless on
codex-headless confirm
codex-headless off
codex-headless log --tail 100
codex-headless layout status
codex-headless layout backup
codex-headless layout restore
codex-headless doctor
codex-headless self-test
```

中文：

- `status`：查看当前模式、显示器、虚拟显示器、Touch Bar、回滚状态和配置。
- `on`：进入 Headless Mode；是否启动确认窗口由 Confirmation Policy 决定。
- `confirm`：确认 Headless Mode。
- `off`：恢复 Normal Mode。
- `log --tail N`：查看最近 N 行日志。
- `layout status`：查看当前显示器布局和当前物理屏组合 profile。
- `layout backup`：手动备份当前物理屏布局。
- `layout restore`：按当前物理屏组合恢复最近备份的布局。
- `doctor`：只读诊断，不修改系统状态。
- `self-test`：运行内置自测。

English:

- `status`: shows mode, displays, virtual display, Touch Bar, rollback state, and config.
- `on`: enters Headless Mode; Confirmation Policy decides whether a confirmation window is required.
- `confirm`: confirms Headless Mode.
- `off`: restores Normal Mode.
- `log --tail N`: prints the latest N log lines.
- `layout status`: shows the current display layout and physical-display profile.
- `layout backup`: manually backs up the current physical display arrangement.
- `layout restore`: restores the saved layout for the current physical-display profile.
- `doctor`: read-only diagnostics; does not change system state.
- `self-test`: runs built-in checks.

### 配置命令 / Config Commands

```bash
codex-headless config get resolution
codex-headless config set resolution 2560x1440
codex-headless config get scale-mode
codex-headless config set scale-mode hidpi
codex-headless config get virtual-display-policy
codex-headless config set virtual-display-policy auto
codex-headless config get soft-disconnect
codex-headless config set soft-disconnect on
codex-headless config get touchbar-hide
codex-headless config set touchbar-hide on
codex-headless config get keep-awake-backend
codex-headless config set keep-awake-backend caffeinate
codex-headless config get hotkeys
codex-headless config set hotkeys.enabled true
codex-headless config get confirm-dialog
codex-headless config set confirm-dialog.enabled true
codex-headless config get confirmation.policy
codex-headless config set confirmation.policy software-virtual-display-only
codex-headless config set confirmation.timeout-seconds 30
codex-headless config get display-handoff
codex-headless config set display-handoff.on-soft-disconnect-failure restore
codex-headless config get timing
codex-headless config set timing.restorePhysicalDisplayGraceSeconds 5
codex-headless config reset defaults
codex-headless config reset soft-disconnect-block
```

## 显示布局 / Display Layout

中文：

- `codex-headless on` 会在修改显示拓扑前保存当前物理屏布局。
- `codex-headless off` 会在物理显示器恢复可用后、关闭本工具创建的虚拟显示器前，尝试恢复保存的布局。
- 布局按物理屏组合保存：例如内建屏 A + 外接屏 B、内建屏 A + 外接屏 C 会分别保存，不会互相覆盖。
- 物理屏组合 profile 使用内建/外接类型、vendor、model 和当前分辨率生成；同一组合再次备份会覆盖该组合的上一份布局。
- 默认备份文件是一个布局库，适合自动恢复；`layout export PATH` 会导出当前组合的一份独立配置文件，适合手动保存或迁移。

```bash
codex-headless layout status
codex-headless layout backup
codex-headless layout restore
codex-headless layout export ~/Desktop/codex-layout.json
codex-headless layout import ~/Desktop/codex-layout.json
```

English:

- `codex-headless on` saves the current physical display layout before changing display topology.
- `codex-headless off` restores the saved layout after physical displays return and before the managed virtual display is closed.
- Layouts are saved per physical-display profile: built-in A + external B and built-in A + external C are stored separately.
- A profile is derived from built-in/external type, vendor, model, and current resolution; backing up the same profile replaces its previous layout.
- The default snapshot file is a layout library for automatic restore; `layout export PATH` writes a standalone snapshot for manual backup or migration.

```bash
codex-headless layout status
codex-headless layout backup
codex-headless layout restore
codex-headless layout export ~/Desktop/codex-layout.json
codex-headless layout import ~/Desktop/codex-layout.json
```

## 配置项 / Configuration

### 推荐默认值 / Recommended Defaults

| 配置 / Setting | 默认值 / Default | 中文说明 | English |
| --- | --- | --- | --- |
| `resolution` | `2560x1440` | 软件虚拟显示器 backing 分辨率。 | Backing resolution for the software virtual display. |
| `refreshRate` | `60Hz` | 软件虚拟显示器刷新率。 | Refresh rate for the software virtual display. |
| `scale-mode` | `hidpi` | 使用 HiDPI 缩放。macOS 可能显示为一半 logical resolution。 | Uses HiDPI scaling. macOS may report half-size logical resolution. |
| `virtual-display-policy` | `auto` | 无外接/Dummy 时创建虚拟屏；有外接/Dummy 时优先使用现有显示器。 | Creates a virtual display only when no external/dummy display exists. |
| `soft-disconnect` | `on` | 有替代显示器时尝试 soft-disconnect 内建屏。 | Attempts built-in display soft-disconnect when an alternative display exists. |
| `touchbar-hide` | `on` | Headless Mode 中清空 Touch Bar Control Strip UI。 | Clears the Touch Bar Control Strip UI in Headless Mode. |
| `keep-awake-backend` | `caffeinate` | 使用 macOS 自带 `caffeinate` 保持唤醒。 | Uses macOS built-in `caffeinate` to keep the system awake. |
| `confirmation.policy` | `software-virtual-display-only` | 仅使用 managed virtual display 时要求确认。 | Requires confirmation only when the managed virtual display is used. |
| `confirmation.timeoutSeconds` | `30` | 需要确认时的自动回滚倒计时。 | Auto-rollback countdown when confirmation is required. |
| `hotkeys.enabled` | `true` | 开启全局快捷键。 | Enables global hotkeys. |
| `confirm-dialog.enabled` | `true` | 菜单栏 App 中显示确认/回滚弹窗。 | Shows Confirm/Rollback dialog in the menu bar app. |
| `display-handoff.on-soft-disconnect-failure` | `restore` | soft-disconnect 失败时恢复 Normal Mode。 | Restores Normal Mode when soft-disconnect fails. |

### Confirmation Policy

| 值 / Value | 中文说明 | English |
| --- | --- | --- |
| `always` | 所有显示路径都要求确认。 | Requires confirmation for every display path. |
| `software-virtual-display-only` | 只有实际使用本工具创建的软件虚拟屏时要求确认。 | Requires confirmation only when the managed virtual display is used. |
| `never` | 所有路径直接进入 Headless；仍可随时使用 Restore。 | Enters Headless directly for all paths; Restore remains available. |

Prepare 阶段始终保留当前安全物理输出；只有替代显示器已验证可用后才执行 Commit。Restore 则先恢复并提升物理显示器，最后停止 managed virtual display。

Prepare always keeps a safe physical output available. Commit starts only after the replacement display is verified. Restore brings back and promotes a physical display before stopping the managed virtual display.

### Virtual Display Policy

| 值 / Value | 中文说明 | English |
| --- | --- | --- |
| `auto` | 有外接/Dummy 时不创建虚拟屏；没有替代显示器时创建虚拟屏。 | Uses existing external/dummy display; creates virtual display only when needed. |
| `always` | 每次 `on` 都创建虚拟屏；有外接/Dummy 时仍保持物理显示器为主屏。 | Always creates virtual display; keeps physical external/dummy display as main when available. |
| `off` | 不创建虚拟屏；没有替代显示器时不会断开唯一内建屏。 | Never creates virtual display; will not disconnect the only built-in display. |

### Scale Mode

| 值 / Value | 中文说明 | English |
| --- | --- | --- |
| `standard` | 标准缩放。 | Standard scaling. |
| `hidpi` | HiDPI 缩放。`2560x1440` 可能显示为 `1280x720` logical points。 | HiDPI scaling. `2560x1440` may appear as `1280x720` logical points. |

### Keep Awake

中文：

- 单纯打开菜单栏 App 不会防休眠。
- `Enable Headless Mode` / `codex-headless on` 会开启 Keep Awake。
- `Restore Normal Mode` / `codex-headless off` 会停止本工具管理的 Keep Awake。
- `caffeinate` 是 macOS 自带命令，不需要额外安装。
- `pmset` 是 best-effort：没有 sudo 缓存时会跳过，不会阻塞。

English:

- Opening the menu bar app alone does not keep the Mac awake.
- `Enable Headless Mode` / `codex-headless on` starts Keep Awake.
- `Restore Normal Mode` / `codex-headless off` stops the Keep Awake process managed by CodexHeadless.
- `caffeinate` is built into macOS; no extra installation is needed.
- `pmset` is best-effort: it is skipped when sudo credentials are unavailable and will not block.

### Hotkeys

| 动作 / Action | 默认快捷键 / Default Shortcut |
| --- | --- |
| Enable Headless Mode | `⌃⌥⌘⇧E` |
| Confirm Headless Mode | `⌃⌥⌘⇧C` |
| Restore Normal Mode | `⌃⌥⌘⇧R` |

## Timing 参数 / Timing Parameters

默认 Timing / Default Timing:

```json
{
  "timing": {
    "virtualDisplayEnumerationWaitSeconds": 5,
    "virtualDisplayReportedIDExtraWaitSeconds": 2,
    "softDisconnectDisappearWaitSeconds": 1,
    "restoreBuiltInShortWaitSeconds": 3,
    "restorePhysicalDisplayWaitSeconds": 5,
    "restorePhysicalDisplayGraceSeconds": 5,
    "restorePhysicalDisplayGracePollIntervalMilliseconds": 250,
    "restorePostPromoteStabilizationMilliseconds": 500,
    "restoreCooldownSeconds": 5,
    "restoreCooldownAfterPausedSeconds": 5
  }
}
```

| 参数 / Parameter | 中文说明 | English |
| --- | --- | --- |
| `virtualDisplayEnumerationWaitSeconds` | 启动虚拟屏后等待 CoreGraphics 枚举的时间。 | Time to wait for CoreGraphics to enumerate the virtual display. |
| `virtualDisplayReportedIDExtraWaitSeconds` | host 已返回 displayID 但系统枚举较慢时的额外等待。 | Extra wait when the host reports a display ID before system enumeration catches up. |
| `softDisconnectDisappearWaitSeconds` | soft-disconnect 后等待内建屏从显示器列表消失。 | Wait for the built-in display to disappear after soft-disconnect. |
| `restoreBuiltInShortWaitSeconds` | restore 初期等待已知内建屏 ID 回来的短等待。 | Short initial wait for the known built-in display ID to return. |
| `restorePhysicalDisplayWaitSeconds` | restore 时等待任意物理显示器可用的主等待时间。 | Main wait for any physical display to become available during restore. |
| `restorePhysicalDisplayGraceSeconds` | 主等待结束后的最终 grace polling，减少误入 paused restore。 | Final grace polling after the main wait to reduce false paused-restore cases. |
| `restorePhysicalDisplayGracePollIntervalMilliseconds` | grace polling 的轮询间隔。 | Poll interval during the grace wait. |
| `restorePostPromoteStabilizationMilliseconds` | 物理屏设为主屏后，关闭虚拟屏前的稳定等待。 | Stabilization wait after promoting physical display and before closing virtual display. |
| `restoreCooldownSeconds` | 正常 restore 后再次允许 enable 的冷却时间。 | Cooldown before Enable is available after a normal restore. |
| `restoreCooldownAfterPausedSeconds` | paused restore 完成后的冷却时间。 | Cooldown after a paused restore finishes. |

中文提示：除调试外，不建议把等待时间设为 `0`。恢复不稳定时，优先增加 `restorePhysicalDisplayWaitSeconds` 或 `restorePhysicalDisplayGraceSeconds`。

English note: Do not set waits to `0` unless debugging. If restore is unstable, increase `restorePhysicalDisplayWaitSeconds` or `restorePhysicalDisplayGraceSeconds` first.

## 文件位置 / File Locations

| 项目 / Item | 路径 / Path |
| --- | --- |
| 配置 / Config | `~/Library/Application Support/CodexHeadless/config.json` |
| 运行状态 / Runtime state | `~/Library/Application Support/CodexHeadless/state.json` |
| 显示布局 / Display layouts | `~/Library/Application Support/CodexHeadless/snapshot.json` |
| 日志 / Log | `~/Library/Logs/CodexHeadless.log` |
| CLI | `/usr/local/bin/codex-headless` |
| App | `/Applications/CodexHeadless.app` |

## 安全与限制 / Safety and Limitations

中文：

- 不会在没有替代显示器时断开唯一内建屏。
- 私有 API 调用通过 helper 子进程执行，崩溃不会带崩主流程。
- 只会停止本工具创建并记录 PID 的虚拟显示器 host。
- 只会停止本工具管理的 `caffeinate` PID。
- 显示布局恢复是 best-effort：如果某个显示器没有重新枚举、ID/硬件签名变化、分辨率变化导致 profile 不匹配，可能只能恢复部分布局。
- 两台外接显示器 vendor、model、分辨率完全相同且系统 display ID 变化时，无法可靠区分左右位置，建议手动执行 `layout backup` 更新当前组合。
- 如果用户在 Headless Mode 期间手动调整了系统显示器排列，`off` 会优先恢复进入 Headless Mode 前保存的布局。
- Touch Bar hide 是清空 UI，不是硬件断电。
- soft-disconnect、Touch Bar hide、软件虚拟显示器依赖 macOS 私有或半公开行为，系统更新后可能失效。
- AppleScript 亮度 fallback 可能需要给 Terminal、iTerm 或 CodexHeadless 授予“辅助功能”权限。

English:

- It will not disconnect the only built-in display when no alternative display exists.
- Private API calls run in helper subprocesses; helper crashes do not crash the main flow.
- It only stops virtual display hosts created and recorded by CodexHeadless.
- It only stops `caffeinate` PIDs managed by CodexHeadless.
- Display layout restore is best-effort: if a display is not enumerated again, its ID/signature changes, or resolution changes make the profile mismatch, only a partial layout may be restored.
- When two external displays share the same vendor, model, and resolution and macOS changes their display IDs, CodexHeadless cannot reliably distinguish left/right placement; run `layout backup` manually after arranging them.
- If the user changes display arrangement manually while Headless Mode is active, `off` restores the layout saved before entering Headless Mode.
- Touch Bar hiding clears UI; it is not hardware power-off.
- Soft-disconnect, Touch Bar hiding, and software virtual display depend on private or semi-public macOS behavior and may break after macOS updates.
- AppleScript brightness fallback may require Accessibility permission for Terminal, iTerm, or CodexHeadless.

## 诊断与恢复 / Diagnostics and Recovery

中文：

推荐排障顺序：

1. SSH 登录目标 Mac。
2. 查看状态：

   ```bash
   codex-headless status
   ```

3. 恢复 Normal Mode：

   ```bash
   codex-headless off
   ```

4. 查看日志：

   ```bash
   codex-headless log --tail 120
   ```

5. 做只读诊断：

   ```bash
   codex-headless doctor
   ```

English:

Recommended recovery order:

1. SSH into the target Mac.
2. Check status:

   ```bash
   codex-headless status
   ```

3. Restore Normal Mode:

   ```bash
   codex-headless off
   ```

4. Inspect logs:

   ```bash
   codex-headless log --tail 120
   ```

5. Run read-only diagnostics:

   ```bash
   codex-headless doctor
   ```

## 兼容性 / Compatibility

中文：

- 当前默认运行目标是 macOS 13.0，App bundle 也会写入 `LSMinimumSystemVersion=13.0`。
- SwiftPM manifest 使用 Swift tools 5.7，以兼容更多 Xcode / Command Line Tools 版本。
- 软件虚拟显示器会在运行时探测 `CGVirtualDisplay`，如果当前 macOS 不支持，对应功能会失败并写入诊断日志。
- 如果构建机安装了多个 SDK，或者默认选到了不兼容的 SDK，可以显式指定 SDK 和部署目标：

```bash
CODEX_HEADLESS_DEPLOYMENT_TARGET=13.0 \
CODEX_HEADLESS_SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" \
./scripts/install.sh
```

如果需要固定到某个 SDK，例如 `MacOSX15.4.sdk`：

```bash
CODEX_HEADLESS_DEPLOYMENT_TARGET=13.0 \
CODEX_HEADLESS_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
./scripts/install.sh
```

其他机器构建失败时，先收集这些信息：

```bash
sw_vers
xcodebuild -version
swift --version
xcrun --sdk macosx --show-sdk-path
```

English:

- The default runtime deployment target is macOS 13.0, and the app bundle writes `LSMinimumSystemVersion=13.0`.
- The SwiftPM manifest uses Swift tools 5.7 for broader Xcode / Command Line Tools compatibility.
- Software virtual display support probes `CGVirtualDisplay` at runtime. If the current macOS does not support it, the feature fails gracefully and records diagnostics.
- If the build machine has multiple SDKs, or the default SDK is incompatible, specify the SDK and deployment target explicitly:

```bash
CODEX_HEADLESS_DEPLOYMENT_TARGET=13.0 \
CODEX_HEADLESS_SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" \
./scripts/install.sh
```

To pin a specific SDK, such as `MacOSX15.4.sdk`:

```bash
CODEX_HEADLESS_DEPLOYMENT_TARGET=13.0 \
CODEX_HEADLESS_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
./scripts/install.sh
```

When another machine fails to build, collect:

```bash
sw_vers
xcodebuild -version
swift --version
xcrun --sdk macosx --show-sdk-path
```

## 构建 / Build

```bash
swift build --build-system native
swift build -c release --build-system native
bash scripts/build_app_bundle.sh
```

只有 Xcode Command Line Tools 的机器上，`--build-system native` 是当前验证过的构建方式。

On machines with only Xcode Command Line Tools, `--build-system native` is the verified build mode.
