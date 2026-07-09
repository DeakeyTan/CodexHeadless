# CodexHeadless

CodexHeadless 是一个自用的 macOS 菜单栏工具和 CLI，用于把闲置 MacBook Pro 改造成稳定在线的远程 Codex 开发主机。

它的目标不是把 MacBook 变成真正意义上的无头服务器，而是让它在开盖或半开盖、长期接电的情况下：

- 尽量保持系统不休眠。
- 尽量让内建屏幕不常亮、不作为主要显示输出。
- 优先使用外接显示器或 HDMI Dummy Plug 作为远程桌面输出。
- 保留 SSH 可用的 CLI 恢复入口，避免显示器切换失败后无法救回。
- 记录关键日志，方便远程排查。

English summary: CodexHeadless is a personal macOS menu bar utility and CLI for turning an idle MacBook Pro into a remote Codex development host.

The current implementation targets the PRD's v0.5 path:

- Menu bar app.
- CLI recovery path.
- `caffeinate`-based Keep Awake.
- `pmset` best-effort sleep/display sleep configuration.
- CoreGraphics display enumeration.
- External / HDMI Dummy display promotion.
- Built-in display brightness fallback.
- Experimental built-in display soft-disconnect through an isolated private API helper.
- Software virtual display host through `CGVirtualDisplay`.
- Optional Touch Bar UI hiding through reversible Control Strip defaults.
- Configurable virtual display resolution.
- 30-second rollback guard.
- Logs at `~/Library/Logs/CodexHeadless.log`.

当前稳定路径对应 PRD 的 v0.5 阶段：在目标机器上已验证外接 / Dummy 主屏、内建屏 soft-disconnect、软件虚拟显示器 host、Touch Bar UI hide、rollback guard、`on/confirm/off` 恢复闭环。

## 当前能力

- 菜单栏 App：显示状态、启用 Headless Mode、恢复 Normal Mode、切换 Keep Awake、选择分辨率预设、打开日志、复制状态。
- CLI：支持远程 SSH 执行 `status`、`on`、`off`、`confirm`、`log`、`doctor`、`self-test`、`config get/set` 和各实验子命令。
- Keep Awake：通过 `caffeinate` 保持系统运行，并尽力用 `pmset` 设置系统不自动睡眠。
- 显示器识别：通过 CoreGraphics 枚举内建屏幕、外接屏幕或 HDMI Dummy。
- HDMI Dummy Headless：检测到外接 / Dummy 显示器时，尝试把它移动到主显示器位置。
- 内建屏处理：优先使用已验证的 soft-disconnect v3 路径；不可用或关闭时，会依次尝试 IOKit、已安装的 `brightness` 命令、AppleScript 亮度键，把亮度降到 0。
- 软件虚拟显示器：可通过 `virtual-display-policy` 配置为 `auto`、`always` 或 `off`，并显示 requested/observed/backing scale。
- Touch Bar：可选清空 Control Strip UI，让 OLED 区域黑屏；`off` 时从备份恢复。
- 自动回滚：开启 Headless Mode 后默认进入 30 秒确认窗口，避免黑屏后长期卡住。
- 配置文件：保存默认虚拟显示器分辨率。
- 日志：写入 `~/Library/Logs/CodexHeadless.log`。

## 快速开始

日常使用建议优先使用安装后的菜单栏 App，CLI 作为 SSH 恢复入口保留。

1. 安装或更新：

   ```bash
   ./scripts/install.sh
   ```

2. 打开 `/Applications/CodexHeadless.app`。

3. 第一次使用前确认 SSH 可用，并至少能远程执行：

   ```bash
   codex-headless status
   codex-headless off
   ```

4. 推荐默认配置已经内置：

   - Virtual Display: `2560x1440 @ 60Hz`
   - Scale Mode: `hidpi`
   - Virtual Display Policy: `auto`
   - Soft Disconnect: `on`
   - Touch Bar Hide: `on`
   - Keep Awake Lifecycle: `enable/off`
   - Keep Awake Backend: `caffeinate`
   - Restore Physical Wait: `5s`
   - Restore Grace: `5s`

5. 点击菜单栏 `CH` → `Enable Headless Mode`，或按 `⌃⌥⌘⇧E`。

6. 确认显示器、远程连接、Touch Bar 状态正常后，点击弹窗 `Confirm`，或按 `⌃⌥⌘⇧C`。

7. 需要恢复时点击 `Restore Normal Mode`，或按 `⌃⌥⌘⇧R`。如果显示器恢复较慢，工具会先保留虚拟显示器，等物理显示器可用后再关闭虚拟显示器。

## 状态栏菜单使用说明

菜单栏图标会显示简短状态：

- `CH`：Normal，未启用 Headless Mode。
- `CH: Prep`：正在准备启用。
- `CH: Wait`：等待确认，rollback guard 正在计时。
- `CH: On`：Headless Mode 已确认。
- `CH: Fall`：Fallback 状态，未完整进入理想 Headless 状态。
- `CH: Restoring`：正在恢复 Normal Mode。
- `CH: Cooldown`：刚恢复完成，短时间内暂缓再次 Enable。
- `CH: Err`：出现错误，优先查看日志或执行 restore/off。

菜单顶部状态项：

- `Mode`：当前运行模式。
- `Keep Awake`：当前是否由工具保持唤醒。
- `Virtual Display`：本工具托管的软件虚拟显示器是否存在。
- `Built-in`：内建屏当前处理方式，可能是 `Active`、`Dimmed` 或 `Soft-disconnected`。
- `Touch Bar`：Touch Bar UI 是否被隐藏。
- `Operation: Running...`：菜单或快捷键触发的 Enable/Restore 正在后台执行；此时菜单仍可打开，但新的重操作会被拒绝，避免显示器状态互相打架。
- `Current Step` / `Elapsed` / `Timeout` / `Enable available in`：当前阶段、耗时、剩余等待时间和冷却倒计时。

主要操作：

- `Enable Headless Mode`：开启 Headless Mode。会启动 Keep Awake、按策略创建或使用替代显示器、处理内建屏和 Touch Bar，然后进入确认窗口。
- `Confirm Headless Mode`：确认本次 Headless Mode 正常，取消自动 rollback。
- `Rollback Now`：在确认窗口内立即恢复 Normal Mode。
- `Restore Normal Mode`：恢复内建屏、Touch Bar、亮度、关闭本工具创建的虚拟显示器，并停止本工具管理的 Keep Awake。
- `Apply Recommended v0.5 Config`：写入当前推荐配置。适合重置到已验证的目标机参数。
- `Reset All Settings to Default...`：把配置文件恢复为代码内置默认值。它不会修改当前运行状态；如果已经处于 Headless Mode，请先执行 `Restore Normal Mode`。

`Virtual Display` 子菜单：

- `Policy: auto`：有外接屏或 HDMI Dummy 时优先使用现有物理替代显示器；没有替代显示器时才创建软件虚拟显示器。
- `Policy: always`：每次 Enable 都创建软件虚拟显示器；如果已有外接屏或 Dummy，仍保持外接屏/Dummy 为主显示器。
- `Policy: off`：不创建软件虚拟显示器。没有外接屏或 Dummy 时不会 soft-disconnect 唯一内建屏。
- `Scale: standard`：标准缩放模式。
- `Scale: hidpi`：HiDPI 模式。macOS 可能把 `2560x1440` backing 显示为 `1280x720` logical points，这是正常缩放表现。
- `Preset: WIDTHxHEIGHT`：选择虚拟显示器 backing 分辨率。
- `Custom Resolution...`：输入自定义虚拟显示器分辨率。宽高必须在允许范围内并且为偶数。

`Display & Touch Bar Safety` 子菜单：

- `Soft Disconnect: On/Off`：是否允许使用已验证的私有 API helper soft-disconnect 内建屏。关闭后会改用亮度 fallback。
- `Touch Bar Hide: On/Off`：是否在 Headless Mode 中清空 Touch Bar Control Strip UI。它不是硬件断电，但 OLED 黑色区域不发光。
- `Soft Disconnect Blocked` / `Clear Soft Disconnect Block`：如果私有 API helper 崩溃，工具会自动关闭 soft-disconnect 并记录 block reason；确认要重新实验时可清除。

`Keep Awake Backend` 子菜单：

- `caffeinate (CLI-safe)`：默认推荐。使用 macOS 自带 `/usr/bin/caffeinate`，CLI 退出后仍能保持唤醒。
- `native (App only)`：使用 App 内 IOKit assertion，只适合菜单栏 App 常驻；CLI 场景会自动回退到 `caffeinate`。

默认配置不会在菜单栏 App 启动时自动开启 Keep Awake。Keep Awake 会跟随 Headless 生命周期：`Enable Headless Mode` 时开启，`Restore Normal Mode` / `codex-headless off` 时关闭。菜单中的 `Keep Awake: On/Off` 可用于临时手动切换当前运行状态。

`Hotkeys` 子菜单：

- `Hotkeys: On/Off`：启用或关闭全局快捷键。
- `Enable` / `Confirm` / `Restore`：显示当前快捷键和注册状态。默认分别是 `⌃⌥⌘⇧E`、`⌃⌥⌘⇧C`、`⌃⌥⌘⇧R`。

`Confirm Dialog` 子菜单：

- `Confirm Dialog: On/Off`：是否在进入 `Confirm Required` 后显示确认/回滚弹窗。
- `Hotkey hints`：弹窗中是否显示快捷键提示。
- `Countdown`：弹窗中是否显示 rollback 剩余时间。

`Timing` 子菜单：

- `Virtual Display Enumeration`：启动虚拟显示器后，等待 CoreGraphics 枚举到新显示器的时间。
- `Reported ID Extra Wait`：虚拟显示器 host 已报告 displayID 但系统枚举较慢时，额外等待的时间。
- `Soft Disconnect Verify`：soft-disconnect 内建屏后，等待内建屏从显示器列表消失的验证时间。
- `Restore Built-in Short Wait`：restore 初期，在已知内建屏 ID 上做的短等待。
- `Restore Physical Wait`：restore 时等待任意物理显示器恢复可用的主等待时间，默认 `5s`。
- `Restore Grace`：主等待结束后最后一次 grace polling，默认 `5s`。它用于吸收 macOS 显示器枚举慢半拍的问题，减少进入 `restorePaused` 的概率。
- `Grace Poll Interval`：grace polling 的轮询间隔，默认 `250ms`。
- `Post-promote Stabilization`：物理显示器被设为主显示器后，关闭虚拟显示器前的稳定等待，默认 `500ms`。
- `Restore Cooldown`：正常 restore 完成后，再次允许 Enable 前的冷却时间。
- `Paused Restore Cooldown`：从 `restorePaused` 恢复完成后的冷却时间。
- 每个 Timing 项都有预设和 `Custom...` 输入。秒级参数允许 `0-120`，毫秒级参数允许 `0-10000`。除调试外不建议设置为 `0`。
- `Copy Timing Config Debug Info`：复制当前 Timing 配置，方便贴日志或 UAT 记录。
- `Reset Timing to Default`：恢复代码内置默认 Timing。

`Diagnostics` 子菜单：

- `Copy Status`：复制 `codex-headless status` 等价状态和 App 交互状态。
- `Copy Doctor Report`：复制只读诊断报告。
- `Copy Self Test Report`：复制内置 self-test 报告。
- `Open Log`：打开 `~/Library/Logs/CodexHeadless.log`。
- `Open Config Folder`：打开配置和状态文件目录。

菜单响应说明：Enable/Restore 涉及显示器枚举、等待和子进程清理。菜单栏 App 会把这些重操作放到后台串行队列，主线程只负责菜单、弹窗和状态刷新；因此长 restore 期间菜单应该仍可打开。如果看到 `Operation: Running...`，请等当前操作结束后再触发下一次 Enable/Restore。

## 安全边界

这个版本仍然优先保证可恢复：

- 不会在没有替代显示器时断开内建屏幕。
- 私有 API 调用会放到 helper 子进程中执行；崩溃不会带崩主流程。
- 软件虚拟显示器只会停止本工具创建并记录 PID 的 host。
- 不会销毁任何非本工具创建的显示器。
- 不会误杀用户自己启动的其他 `caffeinate`，只管理状态文件里记录的 PID。
- `pmset` 使用非交互式 `sudo -n`；没有 sudo 缓存时会跳过，不会要求输入密码或阻塞 `on`。
- AppleScript 亮度键 fallback 可能需要给 Terminal、iTerm 或菜单栏 App 授予“系统设置 → 隐私与安全性 → 辅助功能”权限。

建议在目标 Mac 上先开启 SSH：

```bash
sudo systemsetup -setremotelogin on
```

第一次测试 Headless Mode 前，最好已经能从另一台机器 SSH 进入，并确认可以执行：

```bash
swift run codex-headless off
```

## Build

```bash
swift build --build-system native
```

当前机器只有 Xcode Command Line Tools 时，普通 `swift build` 可能触发 SwiftPM/XCBuild 的 plist 初始化错误；已验证可用的命令是上面的 native build system。

## Run

```bash
swift run CodexHeadless
swift run codex-headless status
```

## CLI

```bash
swift run codex-headless status
swift run codex-headless on
swift run codex-headless on --resolution 2560x1440
swift run codex-headless confirm
swift run codex-headless off
swift run codex-headless log --tail 100
swift run codex-headless config get resolution
swift run codex-headless config set resolution 1920x1080
swift run codex-headless config get scale-mode
swift run codex-headless config set scale-mode hidpi
swift run codex-headless config get virtual-display-policy
swift run codex-headless config set virtual-display-policy always
swift run codex-headless config get soft-disconnect
swift run codex-headless config set soft-disconnect on
swift run codex-headless config get touchbar-hide
swift run codex-headless config set touchbar-hide on
swift run codex-headless config get hotkeys
swift run codex-headless config set hotkeys.enabled true
swift run codex-headless config get confirm-dialog
swift run codex-headless config set confirm-dialog.enabled true
swift run codex-headless config get keep-awake-backend
swift run codex-headless config set keep-awake-backend caffeinate
swift run codex-headless config reset defaults
swift run codex-headless doctor
swift run codex-headless self-test
swift run codex-headless soft-disconnect check
swift run codex-headless soft-disconnect probe
```

`on` 默认会启动回滚窗口。确认当前显示和远程连接都正常后执行：

```bash
swift run codex-headless confirm
```

`on` 是幂等的：如果已经处于可用 Headless 状态，它会直接输出当前状态，不会重复发送亮度降低按键，也不会重启回滚计时。如果上次内建屏降暗失败，重新执行 `on` 会继续尝试 fallback。

恢复默认配置：

```bash
codex-headless config reset defaults
```

这个命令只重置配置文件，不会主动改变当前显示器拓扑或运行状态。若当前已经启用 Headless Mode，请先执行 `codex-headless off`，再重置配置。

如果超过确认时间，下一次菜单栏 App 定时检查或 CLI `status` 检查会触发恢复 Normal Mode。

常用恢复命令：

```bash
swift run codex-headless off
```

查看最近日志：

```bash
swift run codex-headless log --tail 100
```

设置默认分辨率：

```bash
swift run codex-headless config set resolution 2560x1440
```

支持的预设包括：

- `1280x720`
- `1600x900`
- `1920x1080`
- `2560x1440`
- `3008x1692`
- `3840x2160`

## Doctor

`doctor` 会做只读检查，不会修改显示器、亮度或睡眠设置：

```bash
codex-headless doctor
```

它会输出：

- HDMI Dummy / 外接显示器是否存在。
- 当前主显示器是谁。
- 配置、状态和日志文件是否存在。
- Keep Awake 和本工具管理的 `caffeinate` 状态。
- `pmset` 中 sleep / displaysleep / disksleep 的摘要。
- IOKit 亮度读取、`brightness` 命令、AppleScript fallback 的可用性提示。

## Keep Awake Backend

默认后端是 macOS 自带的 `/usr/bin/caffeinate`，适合 CLI 和 SSH 场景，因为 CLI 退出后 `caffeinate` 进程仍可继续保持系统唤醒。

单纯打开菜单栏 App 不会防休眠；`Enable Headless Mode` 会开启 Keep Awake，`Restore Normal Mode` / `codex-headless off` 会关闭本工具管理的 Keep Awake。

也预留了 App 内原生 IOKit power assertion 后端：

```bash
codex-headless config get keep-awake-backend
codex-headless config set keep-awake-backend caffeinate
codex-headless config set keep-awake-backend native
```

注意：

- `caffeinate` 不需要额外安装，是 macOS 自带命令。
- `native` 只适合菜单栏 App 常驻时使用。
- 从 CLI 执行 `on` 时，如果配置为 `native`，工具会自动回退到 `caffeinate`，避免 CLI 退出后不休眠能力失效。
- `pmset` 只是 best-effort 辅助设置。`on` 会使用非交互式 `sudo -n pmset`；如果当前没有 sudo 缓存，工具会跳过 `pmset` 并继续，不会要求输入密码或阻塞主流程。

## Self Test

`self-test` 不依赖 XCTest，适合只有 Xcode Command Line Tools 的机器：

```bash
codex-headless self-test
```

它会验证分辨率解析、非法输入拦截、奇数尺寸拦截、推荐预设、虚拟显示器 scale/policy 解析、Keep Awake 后端解析、helper 路径解析，以及私有 API probe 不崩溃。

## Global Hotkeys

全局快捷键仅在菜单栏 App 正在运行时生效，不替代 CLI recovery path。

默认快捷键：

- Enable Headless Mode：`⌃⌥⌘⇧E`
- Confirm Headless Mode：`⌃⌥⌘⇧C`
- Rollback Now / Restore Normal Mode：`⌃⌥⌘⇧R`

状态限制：

- Enable 只在 `Normal` 状态生效。
- Confirm 只在 `Confirm Required` 状态生效。
- Restore 在 `Preparing` / `Confirm Required` / `Headless` / `Fallback` / `Error` 状态生效。
- 无效状态下触发快捷键只写入日志，不修改显示器、睡眠、Touch Bar 或虚拟显示器状态。

查看或开关快捷键：

```bash
codex-headless config get hotkeys
codex-headless config set hotkeys.enabled true
codex-headless config set hotkeys.enabled false
```

如果快捷键被其他 App 占用，菜单栏 App 仍可启动，菜单栏和 `Copy Status` 会显示注册失败状态；CLI 仍可用于恢复。

## Confirm Dialog

菜单栏 App 运行时，进入 `Confirm Required` 后会显示非阻塞 Confirm / Rollback 弹窗。弹窗不会阻塞 rollback guard、菜单栏操作或 CLI 操作。

- 点击 `Confirm` 等价于 `codex-headless confirm`。
- 点击 `Rollback Now` 等价于 `codex-headless off`。
- 关闭弹窗不等于确认；状态会继续等待自动 rollback。
- CLI `confirm/off`、全局快捷键、自动 rollback 导致状态变化后，弹窗会自动关闭。

查看或开关弹窗：

```bash
codex-headless config get confirm-dialog
codex-headless config set confirm-dialog.enabled true
codex-headless config set confirm-dialog.enabled false
```

## 已验证工作流

当前已在目标机器上验证通过的日常路径：

```bash
codex-headless on
codex-headless confirm
codex-headless status
codex-headless off
```

预期状态：

- `on` 后进入 `Confirm Required`。
- `confirm` 后进入 `Headless`。
- `off` 后回到 `Normal`。
- Dummy / 外接显示器保持主显示器。
- `caffeinate` 在 `on` 后启动，在 `off` 后停止。
- 内建屏通过 `CGSConfigureDisplayEnabled/v3` soft-disconnect，或在关闭实验开关时通过 fallback 降暗。
- 如果启用 `virtual-display-policy=always`，会创建 `Managed Virtual`，但已有外接 / Dummy 时仍保持外接 / Dummy 为主显示器。
- 如果启用 `touchbar-hide=on`，Touch Bar UI 会隐藏，`off` 后恢复。

## 已知限制

- `Built-in Brightness: Unknown` 是当前机器上的正常现象，表示 IOKit 读不到亮度；实际亮度由 AppleScript 亮度键 fallback 控制。
- soft-disconnect 和 Touch Bar hide 都依赖私有/非公开行为，macOS 更新后可能失效；失效时应保留 CLI/SSH 恢复路径。
- 软件虚拟显示器依赖 `CGVirtualDisplay` 运行时类；当前 CLT SDK 没有公开 header，因此通过运行时反射使用。
- AppleScript 亮度键 fallback 依赖辅助功能权限。
- 多次运行 `on` 前建议先看 `status`；当前实现已做幂等保护，成功 Headless 后不会重复降低亮度。

## v0.4 Soft-Disconnect

v0.4 增加内建屏幕 soft-disconnect 的实验性实现。它默认关闭；开启后，`codex-headless on` 会在满足安全条件时动态加载 CoreDisplay / SkyLight 私有 API 尝试 soft-disconnect 内建屏。私有调用会隔离在 helper 子进程中执行；如果 API 不可用、调用失败或子进程崩溃，主流程会自动回退到 v0.3 已验证的亮度降低路径。

```bash
codex-headless config get soft-disconnect
codex-headless config set soft-disconnect on
codex-headless config set soft-disconnect off
codex-headless config get soft-disconnect-block
codex-headless config reset soft-disconnect-block
codex-headless soft-disconnect probe
codex-headless soft-disconnect check
codex-headless soft-disconnect variants
codex-headless soft-disconnect experiment --variant NAME --display ID --action disable|enable --i-understand-this-may-break-display-state
```

使用前建议先执行：

```bash
codex-headless soft-disconnect probe
codex-headless soft-disconnect check
```

安全条件：

- 有 Dummy / 外接显示器时才允许尝试。
- 内建屏不能是主显示器。
- CoreDisplay 私有符号必须存在。
- 失败时自动 fallback 到亮度降低。
- `off` 必须先恢复内建屏，再清理其他显示输出。
- 始终保留 CLI 恢复路径。

注意：CoreDisplay 是私有 API，macOS 更新后可能失效。这个功能只适合自用实验，默认不要在无人值守时第一次尝试。

如果 helper 子进程因为私有 API 崩溃，工具会自动关闭 `soft-disconnect` 并写入 block reason。确认要再次实验时，先手动清除：

```bash
codex-headless config get soft-disconnect-block
codex-headless config reset soft-disconnect-block
codex-headless config set soft-disconnect on
```

路线 A 的新私有 API 变体必须通过独立实验命令验证，不能直接接入 `on`：

```bash
codex-headless soft-disconnect variants
codex-headless soft-disconnect experiment --variant skylight-configure-display-enabled-v2 --display 1 --action disable --i-understand-this-may-break-display-state
codex-headless soft-disconnect experiment --variant skylight-configure-display-enabled-v2 --display 1 --action enable --i-understand-this-may-break-display-state
```

实验命令会先做安全检查，并把真正私有 API 调用放到 helper 子进程中。helper 崩溃不会影响主流程。
如果看到 `The file “codex-headless” doesn’t exist.`，说明当前安装版还没有包含 helper 路径解析修复；重新运行 `./scripts/install.sh` 后再试。
当前目标机上 `skylight-configure-display-enabled-v1` 和 `skylight-configure-display-enabled-v2` 都已确认会让 helper 以 SIGSEGV 退出。`skylight-configure-display-enabled-v3` 已验证可以关闭内建屏，并提升为默认 soft-disconnect 路径。`v4` 暂停测试，除非后续 v3 在其他系统版本上失效。

```bash
codex-headless soft-disconnect experiment --variant skylight-configure-display-enabled-v3 --display 1 --action enable --i-understand-this-may-break-display-state
```

路线 A 的逆向记录见：

```text
docs/RouteA_SoftDisconnect_Research.md
```

## v0.5 Virtual Display / Touch Bar

v0.5 已接入软件虚拟显示器 host，以及可选隐藏 Touch Bar UI。两者都属于系统私有/半公开能力，因此仍保留 probe 和隔离实验入口；日常路径则通过 `on/confirm/off` 管理。

```bash
codex-headless virtual-display probe
codex-headless config get virtual-display-policy
codex-headless config set virtual-display-policy auto
codex-headless config get scale-mode
codex-headless config set scale-mode standard
codex-headless virtual-display start --resolution 1920x1080 --scale-mode standard
codex-headless status
codex-headless virtual-display stop
codex-headless config set scale-mode hidpi
codex-headless virtual-display start --resolution 1920x1080 --scale-mode hidpi
codex-headless status
codex-headless virtual-display stop

codex-headless config get touchbar-hide
codex-headless config set touchbar-hide on
codex-headless touchbar probe
codex-headless touchbar check
codex-headless touchbar variants
codex-headless touchbar experiment --variant dfr-get-status-int32 --action hide --i-understand-this-may-affect-touchbar-state
codex-headless touchbar experiment --variant defaults-presentation-function-keys --action hide --i-understand-this-may-affect-touchbar-state
codex-headless touchbar experiment --variant defaults-presentation-function-keys --action show --i-understand-this-may-affect-touchbar-state
codex-headless touchbar experiment --variant defaults-control-strip-empty --action hide --i-understand-this-may-affect-touchbar-state
codex-headless touchbar experiment --variant defaults-control-strip-empty --action show --i-understand-this-may-affect-touchbar-state
```

软件虚拟显示器通过常驻 host 子进程持有 `CGVirtualDisplay`。CLI 创建虚拟显示器后会记录 host PID 和 displayID；停止时会结束 host 进程。单独调试时可以使用 `virtual-display start/stop`，日常 Headless 流程则由 `virtual-display-policy` 控制是否在 `on/off` 中自动接入。
`status` 会同时显示 requested resolution、observed resolution 和 backing scale；macOS 可能把 1920x1080 backing resolution 枚举成 960x540 logical points，这是系统缩放/HiDPI 表现，不一定表示创建失败。
`scale-mode` 支持 `standard` 和 `hidpi` 两种模式；目标机上建议分别启动一次并对比系统设置里的缩放选项、`status` 的 observed resolution，以及远程桌面/截图的实际可用面积。
`virtual-display-policy` 控制 `codex-headless on` 是否自动接入软件虚拟屏：

- `auto`：默认策略。有 HDMI Dummy/外接屏时优先使用现有显示器；没有替代显示器时自动创建软件虚拟屏。
- `always`：总是创建软件虚拟屏；如果已有 HDMI Dummy/外接屏，会保持原外接屏为主显示器，只有没有替代显示器时才把软件虚拟屏设为主显示器。
- `off`：不创建软件虚拟屏，只使用已有 HDMI Dummy/外接屏；如果没有替代显示器，会进入 fallback，不会强制断开唯一内建屏。

参考项目 `clemstation/hide-my-bar` 的公开 README 说明 Touch Bar 关闭依赖私有 API，因此这里延续 v0.4 的策略：先 probe，再手动实验，确认可恢复后才接入 `on/off` 主流程。
目标机上 `dfr-display-brightness-float`、`dfr-display-brightness-int-float`、`dfr-display-brightness-int-double` 已确认会让 helper 以 SIGSEGV 退出；`DFRGetStatus()` 已验证可读出状态，`DFRSetStatus(Int32)` 已验证 API 可调用，但用户确认物理 Touch Bar 没有关闭。`defaults-presentation-function-keys` 会切换到 Function Keys，`defaults-presentation-app-with-control-strip` 会切换到随当前窗口变化的功能区，也不是真正隐藏。`defaults-control-strip-empty` 已验证可以让 Touch Bar 图标全部消失；它不是硬件级断电，但对 OLED 来说黑色区域不发光，满足隐藏 UI / 降低静态显示的目标。开启 `touchbar-hide=on` 后，`codex-headless on` 会使用 `defaults-control-strip-empty` 清空 Touch Bar UI，`codex-headless off` 会从备份恢复 `com.apple.controlstrip`。

## Waiting and Progress Phases

CodexHeadless records a lightweight runtime phase while enabling, confirming, restoring, or cooling down. The menu bar menu and `codex-headless status` show the current step, elapsed time, timeout, and cooldown remaining when applicable.

Common enable phases include:

- `startingKeepAwake`: Starting Keep Awake.
- `checkingDisplays`: Reading the current display topology.
- `usingExternalDisplay`: Keeping an external display or HDMI Dummy as the main display.
- `creatingVirtualDisplay`: Starting the software virtual display host.
- `waitingForVirtualDisplayEnumeration`: Waiting for macOS to detect the software virtual display.
- `acceptingReportedVirtualDisplayID`: Continuing with the display ID reported by the host when CoreGraphics enumeration is delayed.
- `disconnectingBuiltInDisplay`: Soft-disconnecting or dimming the built-in display.
- `hidingTouchBar`: Hiding Touch Bar UI.
- `waitingForConfirmation`: Waiting for the rollback confirmation window.

Common restore phases include:

- `restoringBuiltInDisplay`: Requesting the built-in display to return.
- `waitingForPhysicalDisplay`: Waiting for a built-in, external, or HDMI Dummy display to become available.
- `promotingPhysicalDisplay`: Setting the physical display as main before stopping the virtual display.
- `stoppingVirtualDisplay`: Closing the managed software virtual display as soon as a physical display is promoted.
- `restoringTouchBar`: Restoring Touch Bar UI.
- `stoppingKeepAwake`: Stopping Keep Awake.
- `coolingDown`: Waiting for display state to stabilize before Enable is available again.

When an external display or HDMI Dummy is already available, virtual display creation and virtual display wait phases are skipped unless `virtual-display-policy=always` requires a software virtual display. During restore, the managed virtual display remains alive until a physical display is available. Once a physical display is promoted, CodexHeadless waits briefly and then closes the virtual display before restoring Touch Bar UI and brightness, reducing the time windows can remain on the virtual display.

If CoreGraphics is slow to enumerate the physical display, CodexHeadless performs a short final grace polling step before entering `restorePaused`. `restorePaused` usually means CodexHeadless is still waiting safely, not that recovery has failed.

The menu bar app also shows a small non-blocking restore overlay during restore, waiting, paused restore, physical display promotion, and virtual display shutdown. This helps when the NSStatusItem temporarily appears on the virtual display or another Space during display topology changes.

## Timing Configuration

Timing values are optional. Existing config files that do not contain `timing` continue to work and use these defaults:

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

CLI helpers:

```bash
codex-headless config get timing
codex-headless config set timing.virtualDisplayReportedIDExtraWaitSeconds 2
codex-headless config set timing.restorePhysicalDisplayGraceSeconds 5
codex-headless config set timing.restorePostPromoteStabilizationMilliseconds 750
codex-headless config set timing.restoreCooldownSeconds 10
```

The app menu includes a `Timing` submenu with presets for restore physical wait, grace polling, poll interval, post-promote stabilization, and cooldown values. Changes are written to `~/Library/Application Support/CodexHeadless/config.json` and can be verified with `codex-headless config get timing`.

Do not set wait durations to `0` unless debugging. If restore becomes unstable, increase `restorePhysicalDisplayWaitSeconds` or `restorePhysicalDisplayGraceSeconds`. If virtual display creation is stable on the target machine, `virtualDisplayReportedIDExtraWaitSeconds` can be reduced carefully. The defaults are optimized for the current target machine and keep the CLI recovery path intact.

## Install

安装脚本会构建 release 版本，把 CLI 安装到 `/usr/local/bin/codex-headless`，并把状态栏 App 打包安装到 `/Applications/CodexHeadless.app`。

```bash
./scripts/install.sh
```

菜单栏 executable 仍然保留在 SwiftPM 的 release build 目录中；安装后的日常入口建议使用 `/Applications/CodexHeadless.app`。App 是 `LSUIElement` 状态栏应用，不会显示 Dock 图标。安装脚本会使用项目根目录的 `icon.png` 生成 App 图标并封装到 `.app` 中。

## 文件位置

- 配置文件：`~/Library/Application Support/CodexHeadless/config.json`
- 运行状态：`~/Library/Application Support/CodexHeadless/state.json`
- 日志文件：`~/Library/Logs/CodexHeadless.log`
- CLI 安装位置：`/usr/local/bin/codex-headless`
- App 安装位置：`/Applications/CodexHeadless.app`

## 推荐测试流程

1. 构建项目：

   ```bash
   swift build --build-system native
   ```

2. 查看状态：

   ```bash
   swift run codex-headless status
   ```

3. 如需手动确认默认远程桌面参数，可设置为当前推荐默认值：

   ```bash
   swift run codex-headless config set resolution 2560x1440
   swift run codex-headless config set scale-mode hidpi
   ```

4. 插入 HDMI Dummy Plug。

5. 开启 Headless Mode：

   ```bash
   swift run codex-headless on
   ```

6. 确认远程连接和显示状态正常后确认：

   ```bash
   swift run codex-headless confirm
   ```

7. 需要恢复时执行：

   ```bash
   swift run codex-headless off
   ```

## 后续路线

- v0.4：内建屏幕 soft-disconnect 已完成目标机验证，继续保留隔离 helper 和 circuit breaker。
- v0.5：软件虚拟显示器、Touch Bar UI hide、外接屏主屏保持策略已完成目标机验证。
- v1.0：整理为日常自用稳定版，完善 `.app` 打包、安装、启动项和实机测试文档。
