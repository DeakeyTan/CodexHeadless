# CodexHeadless

CodexHeadless 是一个 macOS 菜单栏工具和命令行工具，用于把 MacBook 作为远程主机使用。它可以保持系统唤醒，优先使用外接显示器、HDMI Dummy 或软件虚拟显示器作为远程显示输出，并在安全条件满足时处理内建屏幕和 Touch Bar。

CodexHeadless is a macOS menu bar utility and CLI for using a MacBook as a remote host. It keeps the system awake, prefers an external display, HDMI dummy plug, or managed software virtual display, and handles the built-in display and Touch Bar only after safety checks pass.

## 目录 / Contents

- [主要功能 / Features](#主要功能--features)
- [安装 / Installation](#安装--installation)
- [快速开始 / Quick Start](#快速开始--quick-start)
- [菜单栏 / Menu Bar](#菜单栏--menu-bar)
- [CLI](#cli)
- [配置 / Configuration](#配置--configuration)
- [Timing 参数 / Timing Parameters](#timing-参数--timing-parameters)
- [诊断日志 / Diagnostic Logging](#诊断日志--diagnostic-logging)
- [安全机制 / Safety](#安全机制--safety)
- [恢复与排障 / Recovery and Troubleshooting](#恢复与排障--recovery-and-troubleshooting)
- [文件位置 / File Locations](#文件位置--file-locations)
- [已知限制 / Known Limitations](#已知限制--known-limitations)
- [兼容性 / Compatibility](#兼容性--compatibility)
- [卸载 / Uninstall](#卸载--uninstall)

## 主要功能 / Features

| 功能 / Feature | 说明 / Description |
| --- | --- |
| 菜单栏 App | 启用、确认和恢复 Headless Mode，查看当前安全状态，修改常用参数。 / Enables, confirms, and restores Headless Mode, displays safety state, and manages settings. |
| CLI | 适合通过 SSH 执行状态检查、启用、确认、恢复、诊断、布局和配置命令。 / SSH-friendly status, enable, confirm, restore, diagnostics, layout, and configuration commands. |
| 替代显示器选择 | 优先使用已有外接显示器或 HDMI Dummy；没有可用替代显示器时可创建软件虚拟显示器。 / Prefers an external display or dummy plug and can create a managed virtual display when needed. |
| 安全显示交接 | 在替代显示器完成枚举、可用性检查和主屏切换后，才处理内建屏幕。 / Handles the built-in display only after the replacement is enumerated, usable, and promoted. |
| 替代显示器连续性检查 | Confirm Required 或 Headless 状态会核对精确替代显示器 ID；可信的持续丢失会调用现有 Restore 流程。 / Verifies the exact replacement display during Confirm Required and Headless; confirmed loss submits the existing Restore workflow. |
| 自动回滚 | 按确认策略启动倒计时；未确认时自动恢复 Normal Mode。 / Starts a confirmation countdown according to policy and restores Normal Mode when confirmation expires. |
| Keep Awake | 使用受管理 helper 持有 IOPM assertion，不修改全局 `pmset`。 / Uses a managed helper that owns an IOPM assertion without changing global `pmset`. |
| 显示布局 | 进入前按物理显示器组合保存布局，恢复时尽量回放原排列。 / Saves layout per physical-display profile and restores it when returning to Normal Mode. |
| Touch Bar | 可选清空 Control Strip UI；这是 UI 隐藏，不是硬件断电。 / Can clear the Control Strip UI; this hides UI but does not power off the hardware. |
| Clean Normal | Enable 前同时检查 RuntimeState、Recovery Journal、显示器和受管理资源，不只依赖模式字段。 / Gates Enable on runtime state, recovery journal, displays, and managed resources rather than mode alone. |
| Recovery Journal | 在显示副作用前记录资源身份和阶段，使 App/CLI 重启后仍能继续 Restore。 / Records resource identity and phases before display side effects so Restore can resume after restart. |
| 诊断日志开关 | 持久诊断日志默认关闭，可从菜单或 CLI 动态启停；关闭时不创建日志文件和日志锁。 / Persistent diagnostic logging is off by default and can be toggled from the app or CLI without restart. |
| 并发保护 | App、CLI、自动回滚、周期检查和卸载使用 workflow lock 串行化有副作用的操作。 / Serializes mutating app, CLI, rollback, maintenance, and uninstall operations with a workflow lock. |

## 安装 / Installation

### 使用 PKG / Install from PKG

双击 PKG，或在终端中安装：

```bash
sudo installer -pkg /path/to/CodexHeadless.pkg -target /
```

安装内容：

- App：`/Applications/CodexHeadless.app`
- CLI：`/usr/local/bin/codex-headless`

打开 App：

```bash
open /Applications/CodexHeadless.app
```

未签名的 PKG 只应在确认来源可信时使用；Finder 或 Gatekeeper 可能阻止直接打开。面向其他用户分发时，应对 App 和安装包完成 Developer ID 签名与公证。

Use an unsigned PKG only when you trust its source. Finder or Gatekeeper may block it. Public distribution should use Developer ID signing and notarization for both the app and installer package.

### 从源码安装 / Install from Source

```bash
bash scripts/install.sh
```

安装前建议开启 SSH，确保显示状态异常时仍可远程恢复：

```bash
sudo systemsetup -setremotelogin on
codex-headless status
codex-headless off
```

## 快速开始 / Quick Start

### 菜单栏 / Menu Bar

1. 打开 `/Applications/CodexHeadless.app`。
2. 点击 `Enable Headless Mode`，或按 `⌃⌥⌘⇧E`。
3. 如果进入 `Confirm Required`，确认远程画面和输入正常。
4. 点击 `Confirm Headless Mode`，或按 `⌃⌥⌘⇧C`。
5. 需要恢复时点击 `Restore Normal Mode`，或按 `⌃⌥⌘⇧R`。

### CLI

```bash
codex-headless status
codex-headless on
codex-headless confirm
codex-headless off
```

使用 managed virtual display 且确认策略要求确认时，`on` 后必须在倒计时结束前执行 `confirm`。外接显示器或 Dummy 路径在默认策略下不要求确认。

When confirmation is required, run `confirm` before the countdown expires. External or dummy-display paths do not require confirmation under the default policy.

## 菜单栏 / Menu Bar

### 状态标题 / Status Title

| 标题 / Title | 含义 / Meaning |
| --- | --- |
| `CH` | Normal Mode。 |
| `CH: Prep` | 正在准备替代显示器和资源。 / Preparing replacement display and managed resources. |
| `CH: Wait` | 等待确认，自动回滚倒计时有效。 / Waiting for confirmation with rollback countdown active. |
| `CH: On` | Headless Mode 已确认。 / Headless Mode confirmed. |
| `CH: Fall` | Fallback 状态，需要检查状态。 / Fallback state; inspect status. |
| `CH: Restoring` | 正在恢复 Normal Mode。 / Restoring Normal Mode. |
| `CH: Cooldown` | Restore 已完成，暂时禁止再次 Enable。 / Restore completed; Enable is temporarily delayed. |
| `CH: Err` | 操作失败，需要查看状态或执行 Restore。 / Operation failed; inspect status or Restore. |
| `CH: Recovery` | 恢复信息不完整或状态未知，必须先 Restore。 / Recovery data is incomplete or state is unknown; Restore first. |

### 主要操作 / Main Actions

| 菜单项 / Menu Item | 说明 / Description |
| --- | --- |
| `Enable Headless Mode` | 启动 Keep Awake，准备替代显示器，执行安全显示交接。 / Starts Keep Awake, prepares a replacement display, and performs the safe handoff. |
| `Confirm Headless Mode` | 确认当前远程显示正常并取消自动回滚。 / Confirms the remote display and cancels automatic rollback. |
| `Rollback Now` | 在确认窗口中立即恢复 Normal Mode。 / Immediately restores Normal Mode during confirmation. |
| `Restore Normal Mode` | 恢复内建屏和 Touch Bar，验证物理显示器接管后清理 managed resources。 / Restores built-in display and Touch Bar, then cleans managed resources after physical takeover is verified. |
| `Configuration Profiles` | 应用预设参数组合。 / Applies a preset group of settings. |
| `Reset All Settings to Default...` | 重置配置，不直接改变当前运行状态。 / Resets configuration without directly changing runtime state. |
| `Start at Login` | 安装或移除当前用户 LaunchAgent。 / Installs or removes the current-user LaunchAgent. |
| `Diagnostics → Enable Diagnostic Logging` | 开关持久诊断日志，默认关闭。 / Toggles persistent diagnostic logging; off by default. |

### 默认快捷键 / Default Hotkeys

| 动作 / Action | 快捷键 / Shortcut |
| --- | --- |
| Enable Headless Mode | `⌃⌥⌘⇧E` |
| Confirm Headless Mode | `⌃⌥⌘⇧C` |
| Restore Normal Mode | `⌃⌥⌘⇧R` |

## CLI

### 常用命令 / Common Commands

```bash
codex-headless status
codex-headless on
codex-headless on --resolution 2560x1440
codex-headless confirm
codex-headless off
codex-headless doctor
codex-headless self-test
codex-headless log --tail 120
codex-headless uninstall-check
codex-headless repair --inspect-orphan-hosts
```

| 命令 / Command | 说明 / Description |
| --- | --- |
| `status` | 显示 Mode、Operational Safety、Normal Readiness、显示器、Journal、受管理资源和配置。 / Shows mode, operational safety, normal readiness, displays, journal, managed resources, and config. |
| `on` | 进入 Headless Mode。 / Enters Headless Mode. |
| `on --resolution WIDTHxHEIGHT` | 仅覆盖本次 managed virtual display 分辨率。 / Overrides the managed virtual-display resolution for this run. |
| `on --no-rollback` | 禁用本次自动回滚；只应在已有可靠远程恢复通道时使用。 / Disables automatic rollback for this run; use only with reliable remote recovery. |
| `confirm` | 确认 Headless Mode。 / Confirms Headless Mode. |
| `off` | 执行完整 Restore；可用于 Normal 状态下的残留清理。 / Runs the full Restore workflow and can clean residual resources from Normal state. |
| `doctor` | 进行只读诊断，不修改系统状态。 / Performs read-only diagnostics. |
| `self-test` | 检查路径、权限、配置和基础运行环境。 / Checks paths, permissions, configuration, and basic environment. |
| `log [--tail N]` | 读取已有日志；日志未启用或尚未创建时会提示无日志文件。 / Reads existing logs and reports when no log exists. |
| `uninstall-check` | 检查当前状态是否允许安全卸载。 / Checks whether the current state is safe for uninstall. |
| `repair --inspect-orphan-hosts` | 只检查疑似孤立 helper，不会终止无法验证的进程。 / Inspects possible orphan helpers without terminating unverifiable processes. |

### 布局命令 / Layout Commands

```bash
codex-headless layout status
codex-headless layout backup
codex-headless layout restore
codex-headless layout export ~/Desktop/codex-layout.json
codex-headless layout import ~/Desktop/codex-layout.json
```

布局按当前物理显示器组合保存。不同外接屏组合使用不同 profile，避免互相覆盖。

Layouts are stored per physical-display profile so different external-display combinations do not overwrite one another.

### 高级命令 / Advanced Commands

以下命令直接操作虚拟显示器或私有显示接口，只适合排障；正常使用应通过 `on`、`confirm` 和 `off`：

```bash
codex-headless virtual-display probe
codex-headless virtual-display start --resolution 2560x1440 --scale-mode hidpi
codex-headless virtual-display stop
codex-headless soft-disconnect check
codex-headless soft-disconnect probe
codex-headless touchbar check
codex-headless touchbar probe
```

带 `experiment` 的命令需要显式风险确认参数，可能改变显示状态。除非正在恢复或验证特定硬件，不建议使用。

Commands containing `experiment` require explicit risk acknowledgement and may alter display state. They are not recommended for normal operation.

## 配置 / Configuration

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
codex-headless config get hotkeys
codex-headless config set hotkeys.enabled true
codex-headless config get confirmation
codex-headless config set confirmation.policy software-virtual-display-only
codex-headless config set confirmation.timeout-seconds 30
codex-headless config get display-handoff
codex-headless config set display-handoff.on-soft-disconnect-failure restore
codex-headless config get logging.enabled
codex-headless config set logging.enabled true
codex-headless config get timing
codex-headless config set timing.restorePhysicalDisplayGraceSeconds 5
codex-headless config reset defaults
codex-headless config reset soft-disconnect-block
```

配置修改要求当前没有其他 workflow 操作，并且系统处于 Clean Normal。日志开关由运行中的 App 周期同步，因此通过 CLI 修改后不需要重启 App。

Configuration changes require no active workflow and Clean Normal. The running app synchronizes the logging setting, so CLI changes do not require an app restart.

### 默认值 / Defaults

| 配置 / Setting | 默认值 / Default | 说明 / Description |
| --- | --- | --- |
| `resolution` | `1920x1080` | managed virtual display backing 分辨率。 / Backing resolution. |
| `refreshRate` | `60` | managed virtual display 刷新率。 / Refresh rate. |
| `scale-mode` | `standard` | `standard` 或 `hidpi`。 / Standard or HiDPI scaling. |
| `virtual-display-policy` | `auto` | 仅在没有外接/Dummy 时创建虚拟屏。 / Creates a virtual display only when no external/dummy display is available. |
| `soft-disconnect` | `off` | 默认不调用实验性内建屏 soft-disconnect。 / Experimental built-in soft-disconnect is off by default. |
| `touchbar-hide` | `off` | 默认不修改 Touch Bar。 / Touch Bar UI is unchanged by default. |
| `keep-awake-backend` | `caffeinate` | 兼容配置名称；实际由受管理 helper 直接持有 IOPM assertion。 / Compatibility setting; the managed helper directly owns the IOPM assertion. |
| `hotkeys.enabled` | `true` | 开启全局快捷键。 / Enables global hotkeys. |
| `confirmation.policy` | `software-virtual-display-only` | 仅 managed virtual display 路径要求确认。 / Requires confirmation only for the managed virtual-display path. |
| `confirmation.timeout-seconds` | `30` | 确认倒计时。 / Confirmation countdown. |
| `confirm-dialog.enabled` | `true` | 显示确认/回滚弹窗。 / Shows the confirmation/rollback dialog. |
| `display-handoff.on-soft-disconnect-failure` | `restore` | soft-disconnect 失败时恢复 Normal Mode。 / Restores Normal Mode when soft-disconnect fails. |
| `logging.enabled` | `false` | 持久诊断日志默认关闭。 / Persistent diagnostic logging is off by default. |
| `startAtLogin` | `false` | 默认不自动登录启动。 / Does not start at login by default. |

### Virtual Display Policy

| 值 / Value | 行为 / Behavior |
| --- | --- |
| `auto` | 优先使用外接/Dummy；没有替代显示器时创建 managed virtual display。 / Prefers external/dummy and creates a managed virtual display only when needed. |
| `always` | 每次 Enable 都创建 managed virtual display；实际主屏仍由安全交接逻辑决定。 / Creates a managed virtual display on every Enable; main-display selection still follows safety rules. |
| `off` | 不创建 managed virtual display；没有替代显示器时不会断开唯一内建屏。 / Never creates a managed virtual display and will not disconnect the only built-in display. |

### Confirmation Policy

| 值 / Value | 行为 / Behavior |
| --- | --- |
| `always` | 所有显示路径都要求确认。 / Requires confirmation for every display path. |
| `software-virtual-display-only` | 仅实际使用 managed virtual display 时要求确认。 / Requires confirmation only when a managed virtual display is used. |
| `never` | 不显示确认阶段；仍可随时 Restore。 / Skips confirmation; Restore remains available at all times. |

### Scale Mode

| 值 / Value | 说明 / Description |
| --- | --- |
| `standard` | 标准缩放。 / Standard scaling. |
| `hidpi` | HiDPI 缩放；例如 `2560x1440` 可能显示为 `1280x720` logical points。 / HiDPI scaling; `2560x1440` may appear as `1280x720` logical points. |

### Configuration Profiles

| Profile | 说明 / Description |
| --- | --- |
| `safe-default` | 1920×1080 standard、virtual auto、soft-disconnect off、Touch Bar hide off。 |
| `2018-intel-macbook-pro` | 2560×1440 HiDPI，并启用实验性 soft-disconnect 和 Touch Bar hide。 |
| `remote-development` | 2560×1440 HiDPI，保留较保守的物理显示器处理。 |
| `experimental-maximum-headless` | 始终创建 managed virtual display，并启用实验性内建屏与 Touch Bar 处理。 |

```bash
codex-headless config profile safe-default
codex-headless config profile 2018-intel-macbook-pro
codex-headless config profile remote-development
codex-headless config profile experimental-maximum-headless
```

应用 profile 时会保留 Start at Login、Hotkeys 和 Diagnostic Logging 等不应被意外覆盖的偏好；`config reset defaults` 会把全部设置恢复为默认值，包括关闭诊断日志。

Applying a profile preserves preferences that should not be changed unexpectedly, including Start at Login, hotkeys, and diagnostic logging. `config reset defaults` restores every setting, including disabling diagnostic logging.

## Timing 参数 / Timing Parameters

默认值：

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

| 参数 / Parameter | 说明 / Description |
| --- | --- |
| `virtualDisplayEnumerationWaitSeconds` | 等待 CoreGraphics 枚举新虚拟屏。 / Waits for CoreGraphics to enumerate a new virtual display. |
| `virtualDisplayReportedIDExtraWaitSeconds` | helper 已报告 display ID，但系统枚举仍较慢时的额外等待。 / Extra wait after the helper reports an ID but enumeration is still catching up. |
| `softDisconnectDisappearWaitSeconds` | soft-disconnect 后等待内建屏从显示器列表消失。 / Waits for the built-in display to disappear after soft-disconnect. |
| `restoreBuiltInShortWaitSeconds` | Restore 初期等待已知内建屏 ID 返回。 / Initial wait for the known built-in display ID to return. |
| `restorePhysicalDisplayWaitSeconds` | Restore 时等待物理显示器可用的主等待时间。 / Main wait for a physical display during Restore. |
| `restorePhysicalDisplayGraceSeconds` | 主等待后继续进行 grace polling。 / Additional grace polling after the main wait. |
| `restorePhysicalDisplayGracePollIntervalMilliseconds` | grace polling 间隔。 / Grace-poll interval. |
| `restorePostPromoteStabilizationMilliseconds` | 物理屏成为主屏后，清理虚拟屏前的稳定等待。 / Stabilization wait after physical promotion and before virtual-display cleanup. |
| `restoreCooldownSeconds` | 普通 Restore 后再次允许 Enable 的冷却时间。 / Cooldown before Enable after a normal Restore. |
| `restoreCooldownAfterPausedSeconds` | paused Restore 完成后的冷却时间。 / Cooldown after a paused Restore completes. |

除排障外，不建议把等待值设为 `0`。Restore 不稳定时，优先适度增加物理显示器等待或 grace 时间，而不是缩短检查。

Do not set wait values to `0` except for troubleshooting. When Restore is unstable, increase physical-display wait or grace time rather than weakening checks.

## 诊断日志 / Diagnostic Logging

持久诊断日志默认关闭。

Persistent diagnostic logging is disabled by default.

开启或关闭：

```bash
codex-headless config get logging.enabled
codex-headless config set logging.enabled true
codex-headless config set logging.enabled false
```

也可以使用菜单：

```text
Diagnostics → Enable Diagnostic Logging
```

行为：

- 关闭时，App、普通 CLI 和 helper 不创建或追加 `CodexHeadless.log`。
- 关闭时不会为了日志创建 `.lock`、执行轮转或 `fsync`。
- 开启后记录显示交接、受管理资源、Recovery Journal、安全状态和性能信息。
- CLI 修改配置后，运行中的 App 会在现有配置刷新周期内同步，无需重启。
- `Reset All Settings to Default...` 会关闭日志。
- 关闭日志不会删除历史日志。
- 日志开关不影响错误弹窗、CLI 输出、退出码、helper 协议或安全决策。

When disabled, no persistent log or log lock is created. Enabling restores the complete diagnostic stream. The switch never suppresses user-visible errors or changes safety behavior.

日志位置：

```text
~/Library/Logs/CodexHeadless.log
```

读取最近日志：

```bash
codex-headless log --tail 120
```

## 安全机制 / Safety

### Clean Normal

`Mode: Normal` 不代表系统一定可以安全 Enable。Clean Normal 还要求：

- RuntimeState 和配置可读；
- 没有活动 Recovery Journal；
- 没有已观察到的 Keep Awake holder 或 managed virtual-display host；
- 没有仍枚举的 managed virtual display；
- 内建屏没有记录为 soft-disconnected；
- Touch Bar 没有记录为 hidden；
- 存在 active、online、main 的物理显示器；
- 资源所有权不是 unknown。

Core 在取得 workflow lock 后执行权威检查。菜单里的缓存状态只用于显示，不能绕过 Core 检查。

Core performs the authoritative assessment after acquiring the workflow lock. Menu cache state is presentation only and cannot bypass Core checks.

### 安全显示交接 / Safe Display Handoff

1. 启动并验证 Keep Awake。
2. 检查已有外接/Dummy；按策略创建 managed virtual display。
3. 保存当前物理显示器布局。
4. 验证精确替代显示器 ID、active/online 状态和主屏切换。
5. 仅在替代显示器可用后处理内建屏和 Touch Bar。
6. 按确认策略进入 Confirm Required 或 Headless。

Prepare 阶段尽量保留当前安全物理输出，不会在没有替代显示器时断开唯一内建屏。

The preparation phase preserves a safe physical output and never disconnects the only built-in display without a replacement.

### 替代显示器丢失 / Replacement Loss

在 Confirm Required 或 Headless 状态中，周期检查会核对 RuntimeState 中记录的精确替代显示器 ID：

- 单次可信丢失先进入短暂复核；
- 相同 workflow 中再次确认丢失后，调用现有完整 Restore；
- 显示器重新出现、模式变化或 operation 变化会取消复核；
- 进程快照、Journal 或所有权无法验证时，不会仅凭未知证据自动执行破坏性恢复。

During Confirm Required or Headless, the exact replacement ID is rechecked. A trusted persistent loss submits the existing full Restore workflow; unknown evidence alone does not trigger destructive recovery.

### Restore 顺序 / Restore Order

Restore 只有在以下步骤完成后才返回成功：

1. 恢复或找到物理显示器；
2. 将物理显示器提升为主屏；
3. 恢复保存的布局；
4. 验证物理接管稳定；
5. 停止 managed virtual display；
6. 停止 Keep Awake holder；
7. 恢复 Touch Bar；
8. 持久化 Normal 状态并移除 Recovery Journal；
9. 再次验证 Clean Normal。

如果无法确认资源所有权或清理完成，状态和 Journal 会保留，CLI 返回非零，不会虚假声明 Normal。

If ownership or cleanup cannot be verified, state and journal are preserved and the CLI returns nonzero instead of claiming false Normal.

### 资源所有权 / Resource Ownership

- helper capability 是短时、一次性的，并绑定 operation、helper 类型、父进程、可执行文件和 Journal stage；
- 停止 Keep Awake 或 virtual-display host 前会核对 PID、规范化路径、文件身份、启动时间、operation 和 instance token；
- PID 仍存在但身份不匹配时，不会误杀；
- Operational Evidence 与 mode 和 operation ID 绑定，旧 workflow 的证据不能证明新 workflow 健康；
- 有副作用的操作由 workflow lock 串行执行。

### 卸载安全 / Uninstall Safety

卸载流程在最终检查到删除 App/CLI 完成期间持续持有 workflow lock。LaunchAgent 状态只有明确确认 `not loaded` 才允许继续；timeout、signal、未知退出码或未知输出都会拒绝卸载并保留 App 和 CLI。

The uninstall flow keeps the workflow lock from final verification through deletion. Unknown LaunchAgent state fails closed and preserves the recovery tools.

## 恢复与排障 / Recovery and Troubleshooting

推荐顺序：

```bash
# 1. 查看状态
codex-headless status

# 2. 执行完整恢复
codex-headless off

# 3. 只读诊断
codex-headless doctor

# 4. 在已开启日志时查看记录
codex-headless log --tail 120

# 5. 检查疑似孤立 helper，不进行终止
codex-headless repair --inspect-orphan-hosts
```

如果状态为 `Recovery Required`，优先执行 `off`。Restore 不依赖健康的用户配置；配置不可读时使用内置安全恢复 timing。

If status is `Recovery Required`, run `off` first. Restore can use built-in safe timing even when user configuration is unreadable.

CLI 退出码：

- `0`：操作和必要验证完成；
- 非 `0`：操作被拒绝、恢复未完成、资源所有权不确定或参数无效。

不要在 Restore 未完成时手工删除 `state.json` 或 `recovery-journal.json`，否则会丢失资源身份和清理进度。

Do not manually delete runtime state or the recovery journal while Restore is incomplete; they contain ownership and cleanup progress.

## 文件位置 / File Locations

| 项目 / Item | 路径 / Path |
| --- | --- |
| 配置 / Config | `~/Library/Application Support/CodexHeadless/config.json` |
| 配置健康状态 / Config health | `~/Library/Application Support/CodexHeadless/config.health.json` |
| RuntimeState | `~/Library/Application Support/CodexHeadless/state.json` |
| Recovery Journal | `~/Library/Application Support/CodexHeadless/recovery-journal.json` |
| Workflow lock | `~/Library/Application Support/CodexHeadless/operation.lock` |
| 显示布局 / Display layouts | `~/Library/Application Support/CodexHeadless/snapshot.json` |
| Touch Bar 备份 / Touch Bar backup | `~/Library/Application Support/CodexHeadless/touchbar-controlstrip-backup.plist` |
| helper capabilities | `~/Library/Application Support/CodexHeadless/helper-capabilities/` |
| 诊断日志 / Diagnostic log | `~/Library/Logs/CodexHeadless.log` |
| App | `/Applications/CodexHeadless.app` |
| CLI | `/usr/local/bin/codex-headless` |
| Start at Login LaunchAgent | `~/Library/LaunchAgents/com.codexheadless.app.plist` |

## 已知限制 / Known Limitations

- soft-disconnect、Touch Bar UI 修改和 managed virtual display 依赖 macOS 私有或半公开行为，系统更新后可能变化。
- Touch Bar hide 只是清空 UI，不是硬件断电。
- 显示布局恢复是 best-effort；显示器未重新枚举、硬件签名或分辨率变化时可能只恢复部分布局。
- 两台外接显示器 vendor、model 和分辨率完全相同时，macOS 改变 display ID 后可能无法可靠区分左右位置。
- 当前不会盲目发送亮度降低/增加按键；无法读取并验证原始亮度时，不使用不可逆 brightness fallback。
- 诊断日志关闭时不会留下周期运行记录；需要排障时应先开启日志并复现问题。
- `--no-rollback`、直接 virtual-display 操作和带 `experiment` 的命令会降低保护，应只在可靠 SSH/远程控制可用时使用。

- Soft-disconnect, Touch Bar UI control, and managed virtual displays depend on private or semi-public macOS behavior.
- Layout restoration is best-effort and may be partial when display identity or resolution changes.
- Risk-acknowledged commands should be used only with a reliable remote recovery path.

## 兼容性 / Compatibility

- 最低运行目标：macOS 13.0。
- 支持 Apple Silicon 和 Intel 架构；实际支持取决于安装包包含的架构。
- managed virtual display 会在运行时探测 `CGVirtualDisplay`；当前系统不支持时会安全失败。
- 全局快捷键、私有显示接口和 Touch Bar 行为可能受 macOS 权限或系统更新影响。

- Minimum deployment target: macOS 13.0.
- Apple Silicon and Intel are supported when the installed package contains the corresponding architecture.
- Managed virtual-display support is probed at runtime and fails safely when unavailable.

## 卸载 / Uninstall

在源码目录中执行：

```bash
bash scripts/uninstall.sh
```

卸载脚本会先请求 Restore，执行最终 Clean Normal 检查，停止并验证 App/LaunchAgent，然后在持有 workflow lock 的情况下删除：

- `~/Library/LaunchAgents/com.codexheadless.app.plist`
- `/Applications/CodexHeadless.app`
- `/usr/local/bin/codex-headless`

如果系统不安全、状态未知或停止验证失败，卸载会拒绝继续并保留 App 和 CLI。配置、日志、RuntimeState 和 Recovery Journal 不会被自动删除。

The uninstaller restores and verifies Clean Normal, stops app entry points, and keeps the workflow lock through deletion. Unsafe or unknown conditions preserve the app and CLI.
