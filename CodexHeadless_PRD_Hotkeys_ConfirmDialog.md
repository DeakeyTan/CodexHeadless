# CodexHeadless PRD Addendum：全局快捷键与 Confirm/Rollback 弹窗

## 1. 文档目的

本文档用于描述 CodexHeadless 在现有 v0.5 功能基础上的交互增强需求。

本阶段新增能力包括：

1. Enable Headless Mode 后显示 Confirm / Rollback 弹窗。
2. 增加全局快捷键。
3. 通过快捷键执行 Enable、Confirm、Rollback / Restore。
4. 将快捷键、弹窗、菜单栏、CLI 和 rollback guard 纳入同一状态机。
5. 保持原有 CLI recovery path 和自动 rollback 机制不变。

本次需求不涉及重新设计 soft-disconnect、虚拟显示器、Touch Bar hide、分辨率配置、Keep Awake 等底层能力。

## 2. 当前功能基础

CodexHeadless 当前已经具备以下能力：

1. 菜单栏 App。
2. CLI recovery path。
3. `caffeinate`-based Keep Awake。
4. `pmset` best-effort sleep/display sleep configuration。
5. CoreGraphics display enumeration。
6. External / HDMI Dummy display promotion。
7. Built-in display brightness fallback。
8. Experimental built-in display soft-disconnect。
9. Software virtual display host through `CGVirtualDisplay`。
10. Optional Touch Bar UI hiding。
11. Configurable virtual display resolution。
12. 30-second rollback guard。
13. 日志记录。

现有日常路径：

```bash
codex-headless on
codex-headless confirm
codex-headless status
codex-headless off
```

现有预期状态：

1. `on` 后进入 `Confirm Required`。
2. `confirm` 后进入 `Headless`。
3. `off` 后回到 `Normal`。
4. 超过确认时间后，下一次菜单栏 App 定时检查或 CLI `status` 检查会触发恢复 Normal Mode。

## 3. 背景与问题

当前 Headless Mode 的确认主要依赖：

1. 菜单栏操作。
2. CLI `confirm`。
3. 30 秒自动 rollback。

但存在以下体验问题：

1. 用户通过菜单栏点击 `Enable Headless Mode` 后，缺少一个明确的可视化确认入口。
2. 如果用户已经在本机旁边，使用 CLI confirm 不够顺手。
3. 如果切换显示器后鼠标或远程桌面不方便操作，需要一个比菜单点击更直接的本机输入方式。
4. 当前自动 rollback 只能“等待超时”，缺少一个快速 rollback 的本机快捷入口。
5. 需要降低误操作风险，并保持状态机一致性。

因此，本阶段增加：

1. Confirm / Rollback 弹窗。
2. 全局快捷键。
3. 快捷键状态限制。
4. 快捷键注册失败提示与日志。

## 4. 产品目标

### 4.1 核心目标

新增交互能力后，用户可以通过以下方式完成 Headless Mode 生命周期：

```text
开启：
- 菜单栏 Enable Headless Mode
- 全局快捷键 ⌃⌥⌘⇧E
- CLI codex-headless on

确认：
- 弹窗 Confirm
- 全局快捷键 ⌃⌥⌘⇧C
- CLI codex-headless confirm

回滚 / 恢复：
- 弹窗 Rollback Now
- 全局快捷键 ⌃⌥⌘⇧R
- CLI codex-headless off
- 自动 rollback guard
```

### 4.2 设计目标

1. 降低使用 Headless Mode 的心理负担。
2. 提供清晰的 Confirm / Rollback 可视化入口。
3. 提供无需鼠标、无需远程桌面的本机快捷操作方式。
4. 避免快捷键误触发造成显示状态异常。
5. 不破坏现有 CLI 恢复路径。
6. 不绕过现有状态机。
7. 不引入合盖、电源通断等可能影响系统稳定性的默认手势。

## 5. 非目标

本阶段不做：

1. 快捷键图形化自定义编辑器。
2. Touch Bar 自定义 Confirm / Rollback 按钮。
3. 电源通断 Confirm / Restore。
4. 合盖 / 开盖 Restore。
5. USB 设备插拔 Confirm / Restore。
6. 修改虚拟显示器创建逻辑。
7. 修改 soft-disconnect 逻辑。
8. 修改 Touch Bar hide 逻辑。
9. 修改分辨率配置逻辑。
10. 将弹窗作为唯一确认方式。

## 6. 快捷键方案

### 6.1 默认快捷键

采用以下默认全局快捷键：

```text
Enable Headless Mode:
⌃ Control + ⌥ Option + ⌘ Command + ⇧ Shift + E

Confirm Headless Mode:
⌃ Control + ⌥ Option + ⌘ Command + ⇧ Shift + C

Rollback Now / Restore Normal Mode:
⌃ Control + ⌥ Option + ⌘ Command + ⇧ Shift + R
```

### 6.2 快捷键语义

| 快捷键 | 语义 | 触发动作 |
|---|---|---|
| ⌃⌥⌘⇧E | Enable | 开启 Headless Mode |
| ⌃⌥⌘⇧C | Confirm | 确认 Headless Mode |
| ⌃⌥⌘⇧R | Rollback / Restore | 在确认窗口中回滚；在 Headless 状态下恢复 Normal Mode |

### 6.3 快捷键设计理由

1. 四个修饰键组合复杂度足够高，误触发概率低。
2. `E / C / R` 分别对应 Enable / Confirm / Restore，记忆成本低。
3. 快捷键不依赖鼠标、不依赖远程桌面。
4. 快捷键不会像合盖一样触发睡眠或显示拓扑变化。
5. 快捷键比电源通断更可控，不容易被电源线松动误触发。

## 7. 状态机要求

所有快捷键必须经过统一状态机处理，不允许直接绕过 `HeadlessController` 操作显示器。

### 7.1 状态定义

当前状态至少包括：

```text
Normal
Preparing
ConfirmRequired
Headless
Fallback
Restoring
Error
```

### 7.2 快捷键在不同状态下的行为

| 当前状态 | ⌃⌥⌘⇧E | ⌃⌥⌘⇧C | ⌃⌥⌘⇧R |
|---|---|---|---|
| Normal | Enable Headless Mode | 无效 | 无效或提示 already normal |
| Preparing | 无效 | 无效 | Rollback / Restore |
| ConfirmRequired | 无效或提示 already pending | Confirm Headless Mode | Rollback Now |
| Headless | 无效或提示 already headless | 无效 | Restore Normal Mode |
| Fallback | 无效或提示 already fallback | 无效 | Restore Normal Mode |
| Restoring | 无效 | 无效 | 无效 |
| Error | 无效 | 无效 | Restore Normal Mode |

### 7.3 状态限制原则

1. `Enable` 只允许在 `Normal` 状态触发。
2. `Confirm` 只允许在 `ConfirmRequired` 状态触发。
3. `Rollback` 只允许在 `Preparing` / `ConfirmRequired` 状态触发。
4. `Restore` 只允许在 `Headless` / `Fallback` / `Error` 状态触发。
5. 无效快捷键不得修改显示器、睡眠、Touch Bar 或虚拟显示器状态。
6. 无效快捷键应写入日志，可选择轻量提示。

## 8. Confirm / Rollback 弹窗

### 8.1 触发时机

以下动作成功进入 `ConfirmRequired` 状态后，应显示 Confirm / Rollback 弹窗：

1. 用户点击菜单栏 `Enable Headless Mode`。
2. 用户按下 `⌃⌥⌘⇧E`。
3. 用户执行 `codex-headless on`，且菜单栏 App 正在运行。

### 8.2 弹窗类型

建议使用非阻塞式 floating panel，而不是阻塞式系统 alert。

要求：

1. 不阻塞主线程状态机。
2. 不影响 rollback timer。
3. 不阻塞菜单栏操作。
4. 不阻塞 CLI `confirm/off`。
5. 可以在状态变化后自动关闭。

### 8.3 弹窗内容

弹窗标题：

```text
Headless Mode 已启用
```

弹窗正文：

```text
请确认远程连接、显示输出和内建屏状态是否正常。

Confirm：⌃⌥⌘⇧C
Rollback：⌃⌥⌘⇧R

如果 30 秒内未确认，将自动恢复 Normal Mode。
```

按钮：

```text
Confirm
Rollback Now
```

可选显示倒计时：

```text
Auto rollback in 30s
```

### 8.4 弹窗按钮行为

点击 `Confirm`：

1. 调用统一状态机的 `confirm()`。
2. 等价于执行 `codex-headless confirm`。
3. 状态从 `ConfirmRequired` 变为 `Headless`。
4. 取消 rollback guard。
5. 关闭弹窗。
6. 写入日志。

点击 `Rollback Now`：

1. 调用统一状态机的 `off()` 或 `rollback()`。
2. 等价于执行 `codex-headless off`。
3. 状态变为 `Restoring`，随后恢复 `Normal`。
4. 关闭弹窗。
5. 写入日志。

### 8.5 弹窗关闭行为

用户点击窗口关闭按钮时，不应等价于 Confirm。

建议行为：

```text
关闭窗口 = 保持 ConfirmRequired 状态，继续等待自动 rollback
```

或：

```text
关闭窗口 = 最小化为菜单栏状态提示
```

不要把关闭窗口解释为 Confirm，以避免误操作。

### 8.6 弹窗消失规则

以下情况下弹窗必须自动关闭：

1. 用户点击 Confirm。
2. 用户点击 Rollback Now。
3. 用户通过快捷键 `⌃⌥⌘⇧C` Confirm。
4. 用户通过快捷键 `⌃⌥⌘⇧R` Rollback。
5. 用户通过 CLI `codex-headless confirm` Confirm。
6. 用户通过 CLI `codex-headless off` Restore。
7. rollback guard 超时并恢复 Normal Mode。
8. App 状态变为 `Normal` / `Headless` / `Fallback` / `Error`。

## 9. 菜单栏 UI 调整

### 9.1 Normal 状态菜单

```text
CodexHeadless
-------------------------
Status: Normal

Enable Headless Mode    ⌃⌥⌘⇧E
Restore Normal Mode     ⌃⌥⌘⇧R

Virtual Display
  Resolution: 1920x1080
  Preset: 1280x720
  Preset: 1600x900
  Preset: 1920x1080
  Preset: 2560x1440
  Preset: 3008x1692
  Preset: 3840x2160
  Custom Resolution...

Keep Awake: Off
Start at Login: Off

Hotkeys
  Enable:  ⌃⌥⌘⇧E
  Confirm: ⌃⌥⌘⇧C
  Restore: ⌃⌥⌘⇧R

Open Log
Copy Status
Quit
```

### 9.2 ConfirmRequired 状态菜单

```text
CodexHeadless
-------------------------
Status: Confirm Required

Confirm Headless Mode   ⌃⌥⌘⇧C
Rollback Now            ⌃⌥⌘⇧R

Auto rollback in: 30s

Virtual Display: 2560x1440 @ 60Hz
Keep Awake: On

Open Log
Copy Status
Quit
```

### 9.3 Headless / Fallback 状态菜单

```text
CodexHeadless
-------------------------
Status: Headless

Restore Normal Mode     ⌃⌥⌘⇧R

Virtual Display: Active
Keep Awake: On

Open Log
Copy Status
Quit
```

### 9.4 Error 状态菜单

```text
CodexHeadless
-------------------------
Status: Error

Restore Normal Mode     ⌃⌥⌘⇧R

Open Log
Copy Status
Quit
```

## 10. 配置文件新增项

### 10.1 配置路径

继续使用现有配置文件：

```text
~/Library/Application Support/CodexHeadless/config.json
```

### 10.2 新增配置示例

```json
{
  "hotkeys": {
    "enabled": true,
    "enable": {
      "key": "E",
      "modifiers": ["control", "option", "command", "shift"]
    },
    "confirm": {
      "key": "C",
      "modifiers": ["control", "option", "command", "shift"]
    },
    "restore": {
      "key": "R",
      "modifiers": ["control", "option", "command", "shift"]
    }
  },
  "confirmDialog": {
    "enabled": true,
    "timeoutSeconds": 30,
    "showHotkeyHints": true,
    "showCountdown": true
  }
}
```

### 10.3 默认值

```text
hotkeys.enabled = true
hotkeys.enable = control + option + command + shift + E
hotkeys.confirm = control + option + command + shift + C
hotkeys.restore = control + option + command + shift + R

confirmDialog.enabled = true
confirmDialog.timeoutSeconds = 30
confirmDialog.showHotkeyHints = true
confirmDialog.showCountdown = true
```

### 10.4 配置兼容性

如果旧配置文件没有 `hotkeys` 或 `confirmDialog` 字段：

1. 自动使用默认值。
2. 不破坏旧配置。
3. 不重置用户已有分辨率、soft-disconnect、virtual-display-policy、touchbar-hide、keep-awake-backend 等配置。

## 11. CLI 调整

### 11.1 现有 CLI 保持不变

继续支持：

```bash
codex-headless status
codex-headless on
codex-headless confirm
codex-headless off
codex-headless log
```

### 11.2 新增 hotkey config 命令

第一版可以不提供快捷键编辑 CLI，只读展示即可。

建议新增：

```bash
codex-headless config get hotkeys
```

输出示例：

```text
hotkeys.enabled=true
hotkeys.enable=control+option+command+shift+E
hotkeys.confirm=control+option+command+shift+C
hotkeys.restore=control+option+command+shift+R
```

可选新增：

```bash
codex-headless config set hotkeys.enabled true
codex-headless config set hotkeys.enabled false
```

暂不要求支持：

```bash
codex-headless config set hotkeys.enable ...
```

### 11.3 新增 confirm dialog config 命令

建议支持：

```bash
codex-headless config get confirm-dialog
codex-headless config set confirm-dialog.enabled true
codex-headless config set confirm-dialog.enabled false
```

## 12. 技术实现建议

### 12.1 HotkeyManager

新增模块：

```text
HotkeyManager.swift
```

职责：

1. 注册全局快捷键。
2. 注销全局快捷键。
3. 处理快捷键注册失败。
4. 将快捷键事件转发给 HeadlessController。
5. 写入日志。

### 12.2 推荐实现方式

优先使用：

```text
Carbon RegisterEventHotKey
```

原因：

1. 适合菜单栏 App。
2. 可注册全局快捷键。
3. 通常不需要辅助功能权限。
4. 比 CGEvent Tap 更轻量。
5. 不需要拦截或监听所有键盘事件。

暂不建议第一版使用：

```text
CGEvent Tap
```

原因：

1. 通常需要辅助功能权限。
2. 实现更重。
3. 对本需求没有明显必要。

### 12.3 ConfirmDialogController

新增模块：

```text
ConfirmDialogController.swift
```

职责：

1. 展示 Confirm / Rollback 弹窗。
2. 更新倒计时。
3. 处理 Confirm 按钮。
4. 处理 Rollback Now 按钮。
5. 响应状态变化并关闭弹窗。
6. 不直接操作显示器，只调用 HeadlessController。

### 12.4 HeadlessController 调整

HeadlessController 应成为唯一状态入口。

新增方法或统一方法：

```swift
func handleEnableRequested(source: ActionSource)
func handleConfirmRequested(source: ActionSource)
func handleRestoreRequested(source: ActionSource)
func handleRollbackRequested(source: ActionSource)
```

其中 `ActionSource` 可包括：

```swift
enum ActionSource {
    case menu
    case hotkey
    case dialog
    case cli
    case rollbackGuard
}
```

所有入口都必须写入日志，方便排查：

```text
Action requested: enable, source=hotkey
Action accepted: state=Normal
Action result: ConfirmRequired
```

或：

```text
Action requested: confirm, source=hotkey
Action ignored: currentState=Normal
```

## 13. 快捷键注册失败处理

### 13.1 失败场景

可能失败原因：

1. 快捷键已被其他 App 占用。
2. Carbon 注册失败。
3. App 初始化时状态异常。
4. 配置文件中的快捷键非法。

### 13.2 失败处理要求

如果快捷键注册失败：

1. 不影响 App 启动。
2. 不影响 CLI。
3. 不影响菜单栏手动操作。
4. 菜单栏显示 Hotkeys: Error 或 Disabled。
5. 写入日志。
6. `Copy Status` 中包含错误原因。

日志示例：

```text
Hotkey registration failed: action=enable, shortcut=⌃⌥⌘⇧E, error=eventHotKeyExistsErr
```

菜单栏示例：

```text
Hotkeys: Error
  Enable: Failed
  Confirm: OK
  Restore: OK
```

## 14. 日志要求

新增日志内容：

1. App 启动时是否启用 hotkeys。
2. 每个快捷键注册结果。
3. 快捷键触发事件。
4. 快捷键事件是否被状态机接受。
5. 弹窗展示时间。
6. 弹窗按钮点击。
7. 弹窗关闭原因。
8. 倒计时结束与 rollback 触发。
9. 配置文件读取到的 hotkeys / confirmDialog 配置摘要。

示例：

```text
[Hotkey] Register enable: ⌃⌥⌘⇧E OK
[Hotkey] Register confirm: ⌃⌥⌘⇧C OK
[Hotkey] Register restore: ⌃⌥⌘⇧R OK

[Hotkey] Trigger enable
[State] enable accepted, source=hotkey, from=Normal to=ConfirmRequired

[Dialog] Show confirm dialog, timeout=30
[Dialog] Confirm clicked
[State] confirm accepted, source=dialog, from=ConfirmRequired to=Headless
```

## 15. Copy Status 调整

`Copy Status` 中增加：

```text
Hotkeys:
  Enabled: Yes
  Enable: ⌃⌥⌘⇧E / Registered
  Confirm: ⌃⌥⌘⇧C / Registered
  Restore: ⌃⌥⌘⇧R / Registered

Confirm Dialog:
  Enabled: Yes
  Visible: Yes / No
  Countdown: 23s
```

## 16. 安全要求

### 16.1 快捷键不得绕过安全检查

`⌃⌥⌘⇧E` 触发 Enable 时，必须执行与菜单栏 Enable / CLI on 相同的安全流程：

1. 保存状态快照。
2. 开启 rollback guard。
3. 开启 Keep Awake。
4. 检测显示器。
5. 创建或使用虚拟显示器 / Dummy。
6. 处理内建屏。
7. 进入 ConfirmRequired。
8. 显示弹窗。

### 16.2 Confirm 不得重复执行

`⌃⌥⌘⇧C` 在非 `ConfirmRequired` 状态不得产生任何副作用。

### 16.3 Restore 必须安全恢复

`⌃⌥⌘⇧R` 在 `Headless` / `Fallback` / `Error` 状态下，应执行与 CLI `off` 相同的恢复逻辑。

### 16.4 弹窗不是唯一救援路径

即使弹窗显示失败，仍必须保留：

1. CLI `codex-headless confirm`。
2. CLI `codex-headless off`。
3. 菜单栏菜单项。
4. 自动 rollback guard。

## 17. 验收测试

### 17.1 快捷键注册测试

测试项：

1. App 启动后自动注册三个快捷键。
2. 菜单栏显示快捷键。
3. 日志记录注册成功。
4. 快捷键注册失败时，App 仍可正常启动。
5. 注册失败状态可在菜单栏或 Copy Status 中看到。

### 17.2 Normal 状态测试

前置状态：

```text
Mode: Normal
```

测试：

1. 按 `⌃⌥⌘⇧E`。
2. 预期进入 `ConfirmRequired`。
3. Confirm / Rollback 弹窗出现。
4. rollback guard 开始倒计时。
5. 日志记录 source=hotkey。

测试：

1. 按 `⌃⌥⌘⇧C`。
2. 预期无状态变化。
3. 日志记录 ignored。

测试：

1. 按 `⌃⌥⌘⇧R`。
2. 预期无状态变化，或提示 already normal。
3. 日志记录 ignored。

### 17.3 ConfirmRequired 状态测试

前置状态：

```text
Mode: ConfirmRequired
```

测试 Confirm：

1. 按 `⌃⌥⌘⇧C`。
2. 预期进入 `Headless`。
3. rollback guard 取消。
4. 弹窗关闭。
5. 日志记录 source=hotkey。

测试 Rollback：

1. 重新进入 `ConfirmRequired`。
2. 按 `⌃⌥⌘⇧R`。
3. 预期执行 rollback。
4. 状态恢复 `Normal`。
5. 弹窗关闭。
6. 日志记录 source=hotkey。

测试 Enable：

1. 在 `ConfirmRequired` 状态按 `⌃⌥⌘⇧E`。
2. 预期无重复 on。
3. 不重复降低亮度。
4. 不重复创建虚拟显示器。
5. 日志记录 ignored 或 already pending。

### 17.4 Headless / Fallback 状态测试

前置状态：

```text
Mode: Headless
```

测试：

1. 按 `⌃⌥⌘⇧R`。
2. 预期执行 Restore Normal Mode。
3. 状态恢复 `Normal`。
4. `caffeinate` 停止。
5. 内建屏恢复。
6. 虚拟显示器按原逻辑停止。
7. 日志记录 source=hotkey。

测试：

1. 在 `Headless` 状态按 `⌃⌥⌘⇧E`。
2. 预期无重复 on。
3. 日志记录 ignored 或 already headless。

测试：

1. 在 `Headless` 状态按 `⌃⌥⌘⇧C`。
2. 预期无状态变化。
3. 日志记录 ignored。

### 17.5 Error 状态测试

前置状态：

```text
Mode: Error
```

测试：

1. 按 `⌃⌥⌘⇧R`。
2. 预期尝试 Restore Normal Mode。
3. 日志记录 source=hotkey。
4. 如果恢复成功，状态为 `Normal`。
5. 如果恢复失败，状态仍为 `Error`，并写入失败原因。

### 17.6 弹窗测试

测试：

1. 菜单栏点击 `Enable Headless Mode`。
2. 弹窗出现。
3. 弹窗显示 Confirm 快捷键。
4. 弹窗显示 Rollback 快捷键。
5. 弹窗显示倒计时。
6. 点击 Confirm，状态进入 `Headless`。
7. 重新测试，点击 Rollback Now，状态恢复 `Normal`。
8. 重新测试，关闭弹窗但不点击按钮，状态仍为 `ConfirmRequired`，并最终自动 rollback。
9. CLI `confirm` 后，弹窗自动关闭。
10. CLI `off` 后，弹窗自动关闭。

### 17.7 自动 rollback 兼容测试

测试：

1. 进入 `ConfirmRequired`。
2. 不点击弹窗。
3. 不按快捷键。
4. 不执行 CLI confirm。
5. 等待 30 秒。
6. 预期自动恢复 `Normal`。
7. 弹窗自动关闭。
8. 日志记录 rollback timeout。

### 17.8 CLI 兼容测试

测试：

1. 通过 CLI `codex-headless on` 进入 `ConfirmRequired`。
2. 如果菜单栏 App 正在运行，弹窗出现。
3. 执行 CLI `codex-headless confirm`。
4. 弹窗关闭。
5. 状态进入 `Headless`。

测试：

1. 通过 CLI `codex-headless on` 进入 `ConfirmRequired`。
2. 执行 CLI `codex-headless off`。
3. 弹窗关闭。
4. 状态恢复 `Normal`。

## 18. 实施顺序

建议按以下顺序开发：

### Phase 1：ConfirmDialogController

1. 新增非阻塞 Confirm / Rollback 弹窗。
2. 菜单栏 Enable 后显示弹窗。
3. 弹窗按钮接入现有 confirm/off。
4. 弹窗支持倒计时展示。
5. CLI confirm/off 后弹窗自动关闭。

### Phase 2：HotkeyManager

1. 使用 Carbon `RegisterEventHotKey` 注册三个快捷键。
2. 快捷键事件转发 HeadlessController。
3. 菜单栏显示快捷键。
4. 日志记录注册与触发。

### Phase 3：状态机收敛

1. 确保 menu/dialog/hotkey/CLI/rollbackGuard 共享状态机。
2. 增加无效状态下的 ignored 日志。
3. 增加 Copy Status 输出。

### Phase 4：配置与文档

1. 增加 config.json 默认字段。
2. 增加 CLI 查看 hotkeys / confirm-dialog。
3. 更新 README。
4. 增加测试流程。

## 19. README 更新建议

README 中应新增章节：

```text
## Global Hotkeys
```

内容包括：

```text
Enable Headless Mode:
⌃⌥⌘⇧E

Confirm Headless Mode:
⌃⌥⌘⇧C

Rollback Now / Restore Normal Mode:
⌃⌥⌘⇧R
```

并说明：

1. 快捷键仅在菜单栏 App 运行时生效。
2. 快捷键不会替代 CLI recovery path。
3. Confirm 快捷键只在 Confirm Required 状态生效。
4. Restore 快捷键在 Headless / Fallback / Error 状态生效。
5. 如果快捷键注册失败，可以继续使用菜单栏和 CLI。

README 中应新增章节：

```text
## Confirm Dialog
```

说明：

1. Enable Headless Mode 后会显示 Confirm / Rollback 弹窗。
2. 30 秒内未确认会自动 rollback。
3. 弹窗关闭不等于 confirm。
4. CLI confirm/off 和全局快捷键都会同步关闭弹窗。

## 20. 最终结论

本次新增功能的目标是改善 Headless Mode 的确认体验，并提供更安全、直接的本机物理操作方式。

最终交互优先级为：

```text
1. 自动 rollback guard：最后安全保险
2. CLI confirm/off：远程恢复后门
3. 菜单栏菜单项：常规图形入口
4. Confirm / Rollback 弹窗：可视化确认入口
5. 全局快捷键：本机快速确认和恢复入口
```

采用的默认快捷键为：

```text
⌃⌥⌘⇧E = Enable Headless Mode
⌃⌥⌘⇧C = Confirm Headless Mode
⌃⌥⌘⇧R = Rollback Now / Restore Normal Mode
```

该方案不依赖合盖、通断电源或额外硬件，不会主动触发睡眠或改变显示拓扑，是当前 CodexHeadless 最适合默认启用的交互增强方案。
