# CodexHeadless PRD

## 1. 产品名称

**CodexHeadless**

一个用于将闲置 MacBook Pro 改造成远程 Codex 开发主机的 macOS 菜单栏工具。

## 2. 产品背景

用户有一台闲置的 **MacBook Pro 15 寸 2018 Intel 机型**，计划将其作为专门用于 Codex 开发项目的远程设备。该设备大概率不会直接使用内建屏幕，而是通过 SSH、Tailscale、VS Code Remote、远程桌面或 Codex CLI 进行远程开发。

当前痛点包括：

1. MacBook 开盖使用时，内建屏幕没有必要常亮，占用显示资源，也可能造成屏幕老化。
2. 合盖使用虽然可以关闭屏幕，但可能触发睡眠或 clamshell 模式，影响远程连接稳定性。
3. 2018 款 Intel MacBook Pro 长时间高负载运行时散热压力较大，合盖状态不利于散热。
4. 用户希望设备长期在线，稳定运行 Codex、构建、测试、脚本和开发服务。
5. 用户希望内建屏幕不亮，或不作为主显示器使用。
6. 用户希望远程桌面分辨率固定，并且可以自定义虚拟显示器分辨率。
7. 用户希望有一个简单 UI，不希望每次手动执行复杂命令。
8. 工具仅供自用，不计划上架 App Store，也不计划分发给其他人，因此可以降低产品化、签名、公证、兼容性和视觉设计要求。

因此需要开发一个轻量级 macOS 工具，通过菜单栏和 CLI 两种方式，帮助用户一键进入“远程开发 / Headless”模式。

## 3. 产品目标

### 3.1 核心目标

CodexHeadless 的核心目标是让一台 2018 款 MacBook Pro 在开盖或半开盖状态下，稳定作为远程 Codex 开发主机运行。

具体包括：

1. 保持系统不休眠。
2. 尽量关闭、隐藏、断开或降亮度处理内建屏幕。
3. 创建或使用虚拟显示器 / 假显示器作为远程桌面显示输出。
4. 支持虚拟显示器自定义分辨率。
5. 提供简单菜单栏 UI。
6. 保留 CLI 后门，方便远程恢复。
7. 降低误操作导致黑屏、断连或无法恢复的风险。

### 3.2 非目标

本项目不追求：

1. 复刻 BetterDisplay 的全部能力。
2. 适配所有 MacBook 型号。
3. 适配所有 macOS 版本。
4. 上架 App Store。
5. 面向普通用户发布。
6. 完整图形设置面板。
7. 高级显示器色彩、DDC、HDR、EDID 管理。
8. 复杂多显示器布局管理。
9. 本地 AI 推理性能优化。
10. 物理断开内建屏幕或修改硬件。
11. 多虚拟显示器管理。
12. 完整 HiDPI / Retina 缩放系统。

## 4. 目标用户

### 4.1 主要用户

用户本人。

### 4.2 使用设备

主要目标设备：

- MacBook Pro 15 寸 2018
- Intel CPU
- macOS 版本以当前设备实际安装版本为准
- 长期接电
- 大概率半开盖或开盖放置
- 通过远程方式使用

### 4.3 使用场景

1. 用户在主力 Mac 上通过 SSH / VS Code Remote 连接这台 MBP。
2. 用户在这台 MBP 上运行 Codex CLI。
3. 用户通过远程桌面偶尔操作图形界面。
4. 用户希望设备长期在线，不因合盖或系统睡眠中断任务。
5. 用户希望内建屏幕不亮，或不作为主显示器使用。
6. 用户希望远程桌面分辨率固定，例如 1920×1080 或 2560×1440。
7. 用户希望可以根据网络环境、远程设备和使用习惯，自定义虚拟显示器分辨率。

## 5. 核心设计原则

### 5.1 稳定性优先

该工具的第一目标不是功能最强，而是避免远程开发主机失联。任何可能导致黑屏、断连、睡眠、无法恢复的功能，都必须有回滚机制。

### 5.2 先公开 API，后私有 API

第一阶段优先使用稳定方案：

- `pmset`
- `caffeinate`
- CoreGraphics 公开显示器枚举接口
- IOKit 亮度控制
- HDMI Dummy Plug / 外接假显示器

后续再逐步探索：

- soft-disconnect 内建屏幕
- CoreDisplay / CGVirtualDisplay 相关私有能力
- 软件虚拟显示器

### 5.3 UI 简单

只做菜单栏 App，不做完整窗口 App。

菜单栏只承担：

- 显示状态
- 一键开启 Headless Mode
- 一键恢复 Normal Mode
- 保持唤醒开关
- 虚拟显示器分辨率选择
- 查看日志
- 退出

### 5.4 CLI 必须保留

即使有菜单栏 UI，也必须提供 CLI，因为一旦显示器切换失败或远程桌面黑屏，用户仍然可以通过 SSH 执行恢复命令。

### 5.5 自用优先

不为通用性过度设计。优先保证在用户自己的 2018 款 MBP 上稳定运行。

### 5.6 分辨率可控

虚拟显示器默认不追求高分辨率。远程开发场景下，优先保证流畅、稳定、低负载。

默认推荐：

```text
1920x1080 @ 60Hz
```

主力远程开发推荐：

```text
2560x1440 @ 60Hz
```

低带宽环境推荐：

```text
1600x900 @ 60Hz
```

## 6. 产品形态

CodexHeadless 包含两个组件：

### 6.1 菜单栏 App

名称：

```text
CodexHeadless.app
```

运行方式：

- 登录后自动启动，可选
- 常驻菜单栏
- 点击图标显示菜单

### 6.2 CLI 工具

名称：

```bash
codex-headless
```

支持命令：

```bash
codex-headless status
codex-headless on
codex-headless off
codex-headless confirm
codex-headless log
codex-headless config get resolution
codex-headless config set resolution 2560x1440
```

CLI 用于：

1. SSH 远程控制。
2. 自动化脚本调用。
3. 菜单栏 App 的底层调用。
4. 异常情况下恢复显示器和睡眠设置。
5. 设置虚拟显示器默认分辨率。

## 7. 功能需求

## 7.1 状态展示

### 7.1.1 菜单栏状态

菜单栏显示当前模式：

- `CH: Normal`
- `CH: Preparing`
- `CH: Headless`
- `CH: Fallback`
- `CH: Error`

也可以后续替换为图标。

| 状态 | 含义 |
|---|---|
| Normal | 正常模式，内建屏幕可用 |
| Preparing | 正在切换模式 |
| Headless | 已进入远程开发模式 |
| Fallback | 未完全断开内建屏幕，但已降亮度 / 防睡眠 |
| Error | 切换失败，需要恢复 |

### 7.1.2 Status 菜单项

点击菜单中的 `Status`，展示简要状态：

```text
Mode: Headless
Keep Awake: On
Built-in Display: Disconnected / Dimmed / Active
Virtual Display: Active / Not Available
Virtual Display Resolution: 2560x1440 @ 60Hz
Configured Resolution: 2560x1440
Main Display: Virtual / External / Built-in
Rollback Guard: Confirmed / Pending
Log: ~/Library/Logs/CodexHeadless.log
```

### 7.1.3 CLI 状态输出

执行：

```bash
codex-headless status
```

输出示例：

```text
CodexHeadless Status
--------------------
Mode: Normal
Keep Awake: Off
Caffeinate PID: Not Running

Displays:
  - ID: 1
    Type: Built-in
    Resolution: 2880x1800
    Main: Yes
    Active: Yes

  - ID: 2
    Type: External / Dummy / Virtual
    Resolution: 1920x1080
    Main: No
    Active: Yes

Virtual Display:
  Active: No
  Resolution: Not Active

Configured Virtual Display:
  Resolution: 1920x1080
  Refresh Rate: 60Hz
  Scale Mode: Standard

pmset:
  sleep: 0
  displaysleep: 1
  disksleep: 0
```

## 7.2 Keep Awake

### 7.2.1 功能说明

保持系统不休眠，确保远程 SSH、Codex、构建、测试、tmux session 不因系统睡眠中断。

### 7.2.2 实现方式

使用：

```bash
caffeinate
```

以及：

```bash
sudo pmset -a sleep 0
sudo pmset -a displaysleep 1
sudo pmset -a disksleep 0
```

### 7.2.3 菜单项

菜单栏提供：

```text
Keep Awake: On / Off
```

点击后切换状态。

### 7.2.4 行为要求

开启 Keep Awake 时：

1. 启动 `caffeinate` 进程。
2. 记录 `caffeinate` PID。
3. 设置系统不自动 sleep。
4. 允许显示器快速 sleep。
5. 写入日志。

关闭 Keep Awake 时：

1. 停止由本工具启动的 `caffeinate` 进程。
2. 可选恢复原始 `pmset` 配置。
3. 写入日志。

### 7.2.5 注意事项

不要误杀用户自己手动启动的其他 `caffeinate` 进程。工具只管理自己创建的进程。

## 7.3 Headless Mode

### 7.3.1 功能说明

Headless Mode 是本工具的核心模式，用于让 MacBook 进入远程开发状态。

目标效果：

1. 系统保持运行，不休眠。
2. 内建屏幕不作为主要显示输出。
3. 远程桌面使用外接显示器、HDMI Dummy 或虚拟显示器。
4. 内建屏幕尽可能关闭、断开、隐藏或降亮度。
5. 虚拟显示器分辨率可配置。
6. 发生失败时可以自动回滚。

### 7.3.2 菜单项

菜单栏提供：

```text
Enable Headless Mode
Restore Normal Mode
```

### 7.3.3 CLI 命令

开启：

```bash
codex-headless on
```

恢复：

```bash
codex-headless off
```

确认：

```bash
codex-headless confirm
```

指定本次虚拟显示器分辨率：

```bash
codex-headless on --resolution 2560x1440
```

### 7.3.4 开启流程

执行 `Enable Headless Mode` 或 `codex-headless on` 后，按照以下顺序执行：

1. 写入当前状态快照。
2. 启动 rollback guard。
3. 开启 Keep Awake。
4. 检测当前显示器列表。
5. 判断是否已有外接显示器或 HDMI Dummy。
6. 如果已有外接 / Dummy 显示器，则优先使用它。
7. 如果没有外接 / Dummy 显示器，则读取虚拟显示器分辨率配置。
8. 如果 CLI 指定了 `--resolution`，则优先使用 CLI 指定分辨率。
9. 校验分辨率是否合法。
10. 按指定分辨率创建虚拟显示器。
11. 将外接 / Dummy / 虚拟显示器设置为主显示器。
12. 尝试断开内建屏幕。
13. 如果断开失败，将内建屏幕亮度降到 0。
14. 设置 displaysleep 为 1。
15. 将状态设为 `Headless` 或 `Fallback`。
16. 写入日志。
17. 等待用户确认。
18. 如果用户 30 秒内未确认，自动恢复 Normal Mode。

### 7.3.5 成功状态定义

如果满足以下条件，则状态为 `Headless`：

1. Keep Awake 开启。
2. 外接 / Dummy / 虚拟显示器可用。
3. 主显示器不是内建屏幕。
4. 内建屏幕已断开、隐藏或不参与桌面布局。
5. rollback guard 已确认或已完成。

如果满足以下条件，则状态为 `Fallback`：

1. Keep Awake 开启。
2. 外接 / Dummy / 虚拟显示器可用，或远程使用不依赖 GUI。
3. 内建屏幕未能断开，但亮度已降到 0。
4. 系统仍可远程连接。

如果发生以下情况，则状态为 `Error`：

1. 创建虚拟显示器失败。
2. 外接 / Dummy 显示器不可用。
3. 内建屏幕仍是唯一主显示器，且断开操作不可执行。
4. 设置失败导致显示状态异常。
5. 无法启动 Keep Awake。
6. 回滚失败。

## 7.4 Restore Normal Mode

### 7.4.1 功能说明

恢复正常显示和睡眠状态，避免用户无法直接使用 MacBook。

### 7.4.2 恢复流程

执行 `Restore Normal Mode` 或：

```bash
codex-headless off
```

后：

1. 取消 rollback guard。
2. 尝试恢复内建屏幕。
3. 如果存在由本工具创建的虚拟显示器，则销毁虚拟显示器。
4. 恢复内建屏幕亮度。
5. 可选恢复原始显示器布局。
6. 停止本工具启动的 `caffeinate`。
7. 可选恢复原始 `pmset` 配置。
8. 状态设为 `Normal`。
9. 写入日志。

### 7.4.3 恢复优先级

恢复时，必须优先保证用户能重新看到或远程访问图形界面。

优先级：

1. 恢复内建屏幕。
2. 恢复主显示器。
3. 恢复亮度。
4. 停止虚拟显示器。
5. 停止 Keep Awake。
6. 恢复 pmset。

不要先销毁虚拟显示器，再恢复内建屏幕。否则可能导致短暂或持续黑屏。

## 7.5 内建屏幕处理

### 7.5.1 功能目标

让内建屏幕不再影响远程开发体验。

目标包括：

1. 不常亮。
2. 不作为主显示器。
3. 不让窗口跑到内建屏幕。
4. 尽量降低显示和背光资源占用。
5. 尽量避免合盖触发睡眠或散热变差。

### 7.5.2 处理方式优先级

优先级从高到低：

1. soft-disconnect 内建屏幕。
2. 从显示布局中隐藏或禁用内建屏幕。
3. 将外接 / Dummy / 虚拟显示器设为主显示器。
4. 将内建屏幕亮度降到 0。
5. 设置 displaysleep 为 1。
6. 仅保持开盖但低亮度。

### 7.5.3 约束

1. 不做物理断电。
2. 不拆屏。
3. 不依赖磁铁模拟合盖。
4. 不在没有替代显示器时断开内建屏幕。
5. 不把断开内建屏幕作为 v0.1 必须能力。

## 7.6 虚拟显示器

### 7.6.1 功能目标

在没有真实外接显示器的情况下，为远程桌面提供一个稳定显示输出。

目标包括：

1. 创建软件虚拟显示器。
2. 将虚拟显示器设置为主显示器。
3. 允许用户自定义虚拟显示器分辨率。
4. 远程桌面可以识别虚拟显示器。
5. Restore Normal Mode 时可以安全销毁虚拟显示器。

### 7.6.2 默认规格

默认虚拟显示器规格：

```text
Default Resolution: 1920x1080
Refresh Rate: 60Hz
Scale Mode: Standard
Role: Main Display
```

### 7.6.3 预设分辨率

推荐提供以下预设：

| 分辨率 | 使用场景 | 推荐度 |
|---|---|---|
| 1280×720 | 手机远程、低带宽环境 | 中 |
| 1600×900 | 轻量远程桌面 | 中 |
| 1920×1080 | 默认推荐 | 高 |
| 2560×1440 | 主力电脑远程开发 | 高 |
| 3008×1692 | 接近 Mac 16:9 高分辨率体验 | 中 |
| 3840×2160 | 4K 远程桌面 | 低 |

### 7.6.4 自定义分辨率

用户可以自定义：

```text
Width
Height
Refresh Rate
Scale Mode
```

第一版只要求支持：

```text
Width
Height
```

刷新率默认固定为：

```text
60Hz
```

Scale Mode 默认固定为：

```text
Standard
```

后续版本再支持：

```text
HiDPI
Native
Scaled
```

### 7.6.5 自定义分辨率限制

为避免创建异常显示器，第一版应限制输入范围：

```text
Minimum Width: 1024
Minimum Height: 768
Maximum Width: 3840
Maximum Height: 2160
Default Refresh Rate: 60Hz
```

可选高级限制：

```text
Width 必须为偶数
Height 必须为偶数
不允许 Width 或 Height 为 0
不允许超出显著异常比例，例如 32:9 以上，除非开启高级模式
```

### 7.6.6 分辨率校验

当用户输入自定义分辨率时，必须进行校验：

1. 宽度必须是数字。
2. 高度必须是数字。
3. 宽度不得小于 1024。
4. 高度不得小于 768。
5. 宽度不得大于 3840。
6. 高度不得大于 2160。
7. 校验失败时不得创建虚拟显示器。
8. 校验失败时应在菜单栏或 CLI 中提示错误。

错误提示示例：

```text
Invalid resolution: width must be between 1024 and 3840, height must be between 768 and 2160.
```

### 7.6.7 实现策略

分阶段实现。

#### v0.3

不创建软件虚拟显示器，优先支持 HDMI Dummy Plug。

逻辑：

1. 检测是否有外接 / Dummy 显示器。
2. 如果有，将其设置为主显示器。
3. 如果没有，提示用户插入 HDMI Dummy 或进入 fallback。
4. 提前保留虚拟显示器分辨率配置结构。

#### v0.5

尝试软件虚拟显示器。

可能使用：

- CoreDisplay 私有接口
- CGVirtualDisplay 相关能力
- Objective-C / C bridge

### 7.6.8 风险

1. 私有 API 不稳定。
2. macOS 更新可能导致失效。
3. Intel 和 Apple Silicon 行为可能不同。
4. 创建失败可能影响显示布局。
5. 销毁虚拟显示器前必须确认内建屏幕已经恢复。

## 7.7 Virtual Display Resolution UI

### 7.7.1 菜单栏新增 Virtual Display 菜单

菜单栏结构：

```text
CodexHeadless
-------------------------
Status: Normal

Enable Headless Mode
Restore Normal Mode

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

Open Log
Copy Status
Quit
```

### 7.7.2 Custom Resolution 弹窗

点击：

```text
Custom Resolution...
```

后弹出简单输入窗口。

字段：

```text
Width: 1920
Height: 1080
```

按钮：

```text
Cancel
Save
```

第一版不需要复杂设置页。

### 7.7.3 当前分辨率显示

菜单中应显示当前虚拟显示器配置：

```text
Virtual Display: 1920x1080 @ 60Hz
```

如果虚拟显示器未启用：

```text
Virtual Display: Not Active
Configured Resolution: 1920x1080
```

### 7.7.4 Headless Mode 开启时使用已保存分辨率

点击：

```text
Enable Headless Mode
```

时，应使用用户当前选择或保存的虚拟显示器分辨率。

例如用户已选择：

```text
2560x1440
```

则进入 Headless Mode 时创建：

```text
Virtual Display: 2560x1440 @ 60Hz
```

## 7.8 Rollback Guard

### 7.8.1 功能说明

防止开启 Headless Mode 后黑屏或无法远程操作。

### 7.8.2 行为设计

开启 Headless Mode 后，自动启动 30 秒回滚计时器。

如果 30 秒内用户执行：

```bash
codex-headless confirm
```

或在菜单栏中点击：

```text
Confirm Headless Mode
```

则确认当前状态，不再自动回滚。

如果 30 秒内未确认，则自动执行：

```bash
codex-headless off
```

### 7.8.3 菜单栏提示

进入待确认状态时，菜单栏显示：

```text
CH: Confirm?
```

菜单中显示：

```text
Confirm Headless Mode
Rollback Now
```

### 7.8.4 日志

记录：

1. 开始切换时间。
2. 切换前显示器状态。
3. 切换后显示器状态。
4. 是否收到确认。
5. 是否自动回滚。
6. 回滚是否成功。

## 7.9 日志

### 7.9.1 日志路径

```text
~/Library/Logs/CodexHeadless.log
```

### 7.9.2 日志内容

日志应记录：

1. App 启动。
2. App 退出。
3. Keep Awake 开启 / 关闭。
4. caffeinate PID。
5. pmset 修改前后状态。
6. 显示器列表。
7. Headless Mode 开启流程。
8. Restore Normal Mode 流程。
9. 虚拟显示器分辨率配置。
10. 虚拟显示器创建 / 销毁。
11. 错误信息。
12. 回滚信息。

### 7.9.3 虚拟显示器日志

创建虚拟显示器时，应记录：

```text
Requested Virtual Display Resolution: 2560x1440
Validated Resolution: OK
Creating Virtual Display: 2560x1440 @ 60Hz
Virtual Display Created: DisplayID=xxx
Set Main Display: DisplayID=xxx
```

如果失败，记录：

```text
Requested Virtual Display Resolution: 5120x2880
Validation Failed: width exceeds maximum 3840
Fallback: disabled
```

### 7.9.4 菜单项

菜单栏提供：

```text
Open Log
```

点击后打开日志文件。

CLI 提供：

```bash
codex-headless log
codex-headless log --tail 100
```

用于输出最近日志。

## 7.10 开机自启

### 7.10.1 功能说明

用户可以选择是否登录后自动启动菜单栏 App。

### 7.10.2 菜单项

```text
Start at Login: On / Off
```

### 7.10.3 实现方式

可通过：

1. macOS Login Items。
2. LaunchAgent。

自用版本优先使用 LaunchAgent。

### 7.10.4 默认值

默认关闭开机自启，由用户手动开启。

## 8. CLI 设计

## 8.1 status

```bash
codex-headless status
```

显示当前完整状态。

## 8.2 on

```bash
codex-headless on
```

开启 Headless Mode。

可选参数：

```bash
codex-headless on --resolution 1920x1080
codex-headless on --resolution 2560x1440
codex-headless on --no-rollback
codex-headless on --dummy-only
codex-headless on --virtual
codex-headless on --fallback-brightness-only
```

第一版不一定全部实现。

## 8.3 off

```bash
codex-headless off
```

恢复 Normal Mode。

## 8.4 confirm

```bash
codex-headless confirm
```

确认当前 Headless Mode，不再自动回滚。

## 8.5 log

```bash
codex-headless log
codex-headless log --tail 100
```

查看日志。

## 8.6 config get resolution

```bash
codex-headless config get resolution
```

输出示例：

```text
resolution=2560x1440
```

## 8.7 config set resolution

```bash
codex-headless config set resolution 2560x1440
```

设置默认虚拟显示器分辨率。

## 8.8 分辨率参数优先级

分辨率优先级从高到低：

```text
1. CLI 临时参数：--resolution
2. 菜单栏当前选择
3. 配置文件中保存的 resolution
4. 默认值 1920x1080
```

示例：

```bash
codex-headless on --resolution 1280x720
```

只对本次开启生效，不一定覆盖配置文件。

如果用户希望持久保存，应执行：

```bash
codex-headless config set resolution 1280x720
```

## 9. 配置文件

### 9.1 配置文件路径

```text
~/Library/Application Support/CodexHeadless/config.json
```

### 9.2 配置文件示例

```json
{
  "keepAwakeOnLaunch": false,
  "startAtLogin": false,
  "virtualDisplay": {
    "enabled": true,
    "resolution": {
      "width": 1920,
      "height": 1080
    },
    "refreshRate": 60,
    "scaleMode": "standard"
  },
  "rollback": {
    "enabled": true,
    "timeoutSeconds": 30
  }
}
```

### 9.3 配置项说明

| 配置项 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| keepAwakeOnLaunch | Boolean | false | App 启动后是否自动 Keep Awake |
| startAtLogin | Boolean | false | 是否登录后自动启动 |
| virtualDisplay.enabled | Boolean | true | 是否启用虚拟显示器 |
| virtualDisplay.resolution.width | Number | 1920 | 虚拟显示器宽度 |
| virtualDisplay.resolution.height | Number | 1080 | 虚拟显示器高度 |
| virtualDisplay.refreshRate | Number | 60 | 刷新率 |
| virtualDisplay.scaleMode | String | standard | 缩放模式 |
| rollback.enabled | Boolean | true | 是否启用自动回滚 |
| rollback.timeoutSeconds | Number | 30 | 回滚等待时间 |

## 10. UI 设计

## 10.1 菜单栏显示

第一版可以直接用文字：

```text
CH
```

不同状态：

```text
CH
CH: On
CH: Wait
CH: Err
```

后续可替换为图标。

## 10.2 菜单结构

正常状态：

```text
CodexHeadless
-------------------------
Status: Normal

Enable Headless Mode
Restore Normal Mode

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

Open Log
Copy Status
Quit
```

进入 Headless 待确认状态时：

```text
CodexHeadless
-------------------------
Status: Confirm Required

Confirm Headless Mode
Rollback Now

Virtual Display: 2560x1440 @ 60Hz
Keep Awake: On
Open Log
Quit
```

异常状态时：

```text
CodexHeadless
-------------------------
Status: Error

Restore Normal Mode
Open Log
Copy Status

Quit
```

## 10.3 菜单项说明

### Enable Headless Mode

进入远程开发模式。

### Restore Normal Mode

恢复正常显示模式。

### Virtual Display

选择或配置虚拟显示器分辨率。

### Custom Resolution

打开简单输入窗口，允许用户输入宽度和高度。

### Keep Awake

只控制防睡眠，不改变显示器状态。

### Start at Login

控制是否登录后自动启动。

### Open Log

打开日志文件。

### Copy Status

复制当前状态到剪贴板，方便发给 Codex 或用于排查。

### Quit

退出菜单栏 App。退出前如果 Keep Awake 正由工具管理，需要询问或自动停止。

## 11. 技术方案

## 11.1 技术栈

推荐：

- Swift
- AppKit
- Objective-C bridge
- CoreGraphics
- IOKit
- shell command wrapper
- launchd / LaunchAgent

不建议第一版使用：

- SwiftUI 完整窗口
- DriverKit
- Kernel Extension
- 复杂私有 API
- 完整安装器
- App Store 分发

## 11.2 项目结构

```text
CodexHeadless/
  CodexHeadless.xcodeproj
  CodexHeadless/
    AppDelegate.swift
    StatusBarController.swift
    HeadlessController.swift
    SleepManager.swift
    DisplayManager.swift
    BuiltInDisplayManager.swift
    VirtualDisplayManager.swift
    ResolutionManager.swift
    RollbackGuard.swift
    LaunchAgentManager.swift
    ConfigManager.swift
    Logger.swift
    Shell.swift

    ObjCBridge/
      DisplayPrivateBridge.h
      DisplayPrivateBridge.m
      IOKitBrightness.h
      IOKitBrightness.m

  codex-headless-cli/
    main.swift
```

### AppDelegate

负责 App 生命周期。

### StatusBarController

负责菜单栏 UI。

### HeadlessController

负责 Headless Mode 总流程。

### SleepManager

负责：

- caffeinate
- pmset
- sleep 状态管理

### DisplayManager

负责：

- 枚举显示器
- 识别内建屏幕
- 识别主屏
- 设置主屏
- 输出显示状态

### BuiltInDisplayManager

负责：

- 内建屏幕亮度控制
- soft-disconnect 尝试
- 恢复内建屏幕

### VirtualDisplayManager

负责：

- 创建虚拟显示器
- 销毁虚拟显示器
- 维护虚拟显示器 ID

### ResolutionManager

负责：

- 预设分辨率列表
- 自定义分辨率校验
- 分辨率解析
- 分辨率格式化

### ConfigManager

负责：

- 读取配置文件
- 保存配置文件
- 管理默认分辨率
- 管理启动项设置

### RollbackGuard

负责：

- 创建回滚任务
- 取消回滚任务
- 处理 confirm
- 触发 off

### Logger

负责日志写入。

### Shell

负责安全执行命令行。

## 11.3 VirtualDisplayManager 数据结构

```swift
struct VirtualDisplayResolution {
    let width: Int
    let height: Int
}

struct VirtualDisplayConfig {
    let resolution: VirtualDisplayResolution
    let refreshRate: Int
    let scaleMode: ScaleMode
}

enum ScaleMode {
    case standard
    case hidpi
}
```

第一版可以只实现：

```swift
case standard
```

### 11.3.1 VirtualDisplayManager 方法

```swift
func createVirtualDisplay(config: VirtualDisplayConfig) throws -> DisplayID
func destroyVirtualDisplay(id: DisplayID) throws
func validateResolution(_ resolution: VirtualDisplayResolution) throws
func defaultConfig() -> VirtualDisplayConfig
```

### 11.3.2 校验逻辑示例

```swift
func validateResolution(_ resolution: VirtualDisplayResolution) throws {
    guard resolution.width >= 1024 && resolution.width <= 3840 else {
        throw ResolutionError.invalidWidth
    }

    guard resolution.height >= 768 && resolution.height <= 2160 else {
        throw ResolutionError.invalidHeight
    }

    guard resolution.width % 2 == 0 && resolution.height % 2 == 0 else {
        throw ResolutionError.mustBeEven
    }
}
```

## 12. 安全与恢复机制

## 12.1 不断开唯一显示器

任何断开内建屏幕的操作前，必须检查：

1. 是否存在其他 active display。
2. 其他 display 是否可以设为主屏。
3. 是否可以通过 SSH 恢复。

如果没有替代显示器，禁止断开内建屏幕。

## 12.2 自动回滚

Headless Mode 默认开启自动回滚。

默认时间：

```text
30 秒
```

未来可以配置为：

```text
15 秒 / 30 秒 / 60 秒
```

## 12.3 快照

切换前记录：

1. 当前显示器列表。
2. 主屏 ID。
3. 内建屏幕亮度。
4. pmset 状态。
5. caffeinate 状态。
6. 虚拟显示器状态。
7. 虚拟显示器分辨率配置。

恢复时尽量基于快照恢复。

## 12.4 SSH 恢复

用户应提前开启：

```bash
sudo systemsetup -setremotelogin on
```

一旦 GUI 出现问题，可以 SSH 登录后执行：

```bash
codex-headless off
```

## 12.5 日志排查

所有关键操作必须写日志，避免远程排障没有信息。

## 13. 权限需求

可能涉及的权限：

1. 管理员权限：修改 pmset。
2. 开发者工具权限：开发调试阶段可能需要。
3. 辅助功能权限：如果后续通过 UI 自动化方式处理显示设置，可能需要。
4. 登录项权限：开机自启。
5. 屏幕录制权限：本工具本身不一定需要，远程桌面工具可能需要。

第一版尽量避免复杂权限，仅在必要时通过 `sudo` 修改 pmset。

## 14. 安装方式

## 14.1 自用安装

推荐安装路径：

```text
/Applications/CodexHeadless.app
/usr/local/bin/codex-headless
```

目标机是 Intel MBP，因此优先使用：

```text
/usr/local/bin/codex-headless
```

## 14.2 安装脚本

提供：

```bash
install.sh
```

功能：

1. 复制 App 到 `/Applications`。
2. 复制 CLI 到 `/usr/local/bin`。
3. 创建日志目录。
4. 创建配置目录。
5. 可选创建 LaunchAgent。

## 14.3 卸载脚本

提供：

```bash
uninstall.sh
```

功能：

1. 停止 App。
2. 停止本工具启动的 caffeinate。
3. 恢复 pmset。
4. 恢复内建屏幕。
5. 销毁虚拟显示器。
6. 删除 CLI。
7. 删除 App。
8. 可选保留日志和配置文件。

## 15. 开发环境

目标开发环境：

1. macOS。
2. Xcode。
3. Xcode Command Line Tools。
4. Git。
5. Codex CLI。
6. Homebrew。

初始化命令：

```bash
xcode-select --install
brew install git jq ripgrep
```

如果使用 Swift Package：

```bash
swift build
swift run codex-headless status
```

如果使用 Xcode：

```bash
xcodebuild -scheme CodexHeadless -configuration Debug
```

## 16. Codex 协作方式

建议在项目根目录放置：

```text
AGENTS.md
```

内容示例：

```md
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
- Build: xcodebuild -scheme CodexHeadless -configuration Debug
- CLI Status: codex-headless status
- CLI On: codex-headless on
- CLI Off: codex-headless off
- Set Resolution: codex-headless config set resolution 2560x1440

## Safety Rules
- Before changing display topology, save a state snapshot.
- When entering Headless Mode, start a 30-second rollback guard.
- Never destroy a virtual display before restoring the built-in display.
- If an operation fails, fallback to brightness dimming instead of force-disconnect.
- Validate custom resolution before creating a virtual display.
```

## 17. 版本规划

## 17.1 v0.1：菜单栏基础版

目标：先做出可运行的菜单栏 App 和 CLI。

功能：

1. 菜单栏常驻。
2. 显示状态：Normal / Error。
3. Keep Awake 开关。
4. 使用 caffeinate 防睡眠。
5. 使用 pmset 设置 sleep/displaysleep/disksleep。
6. CLI 支持 status/on/off。
7. 写日志。
8. 配置文件结构初始化。
9. 不处理虚拟显示器。
10. 不断开内建屏幕。

验收标准：

1. App 能在菜单栏运行。
2. 点击 Keep Awake 后，系统不会自动睡眠。
3. CLI 可以查看状态。
4. 日志正常写入。
5. 配置文件可以创建。
6. 不会影响正常显示器使用。

## 17.2 v0.2：显示器识别版

目标：让工具能够识别当前显示器情况。

功能：

1. 使用 CoreGraphics 枚举显示器。
2. 识别内建屏幕。
3. 识别主显示器。
4. 显示分辨率、active、online 状态。
5. CLI status 输出显示器列表。
6. 菜单栏 Status 展示显示器摘要。
7. 预留虚拟显示器分辨率菜单。

验收标准：

1. 能正确识别 MacBook 内建屏幕。
2. 能识别外接显示器或 HDMI Dummy。
3. 能输出主显示器信息。
4. 能显示当前配置的虚拟显示器分辨率。
5. 不修改显示器布局。

## 17.3 v0.3：HDMI Dummy Headless 版

目标：在插入 HDMI Dummy Plug 的情况下，实现稳定 Headless Mode。

功能：

1. 检测外接 / Dummy 显示器。
2. 将外接 / Dummy 显示器设为主屏。
3. 将内建屏幕亮度降到 0。
4. 设置 displaysleep 1。
5. 开启 Keep Awake。
6. 增加 30 秒 rollback guard。
7. 支持 confirm。
8. 支持恢复 Normal Mode。
9. 保留虚拟显示器分辨率配置，但不一定创建软件虚拟显示器。

验收标准：

1. 插入 HDMI Dummy 后，点击 Enable Headless Mode，可以进入远程开发状态。
2. 主显示器切换到 Dummy。
3. 内建屏幕亮度降到 0。
4. 系统不睡眠。
5. 远程桌面分辨率稳定。
6. 30 秒不确认时自动恢复。
7. 确认后不自动恢复。
8. SSH 中执行 `codex-headless off` 可以恢复。

## 17.4 v0.4：内建屏幕 soft-disconnect 探索版

目标：尝试在已有外接 / Dummy 显示器时，软件断开内建屏幕。

功能：

1. 增加 BuiltInDisplayManager。
2. 尝试 soft-disconnect 内建屏幕。
3. 失败时 fallback 到亮度 0。
4. 增加更多日志。
5. 增加恢复内建屏幕逻辑。

验收标准：

1. 有替代显示器时才允许断开内建屏幕。
2. 如果断开成功，窗口不再出现在内建屏幕。
3. 如果断开失败，自动 fallback。
4. Restore Normal Mode 可以恢复内建屏幕。
5. 不出现无法恢复的黑屏。

## 17.5 v0.5：软件虚拟显示器探索版

目标：尝试不依赖 HDMI Dummy Plug，直接创建虚拟显示器，并支持自定义分辨率。

功能：

1. 增加 VirtualDisplayManager。
2. 默认创建 1920×1080 60Hz 虚拟显示器。
3. 支持菜单栏选择预设分辨率。
4. 支持 CLI 指定 `--resolution`。
5. 支持配置文件保存默认分辨率。
6. 支持基础自定义分辨率输入。
7. 支持分辨率校验。
8. 将虚拟显示器设为主屏。
9. 在虚拟显示器创建成功后，再处理内建屏幕。
10. Restore Normal Mode 时销毁虚拟显示器。
11. 创建失败时不影响基础 Headless Mode。

验收标准：

1. 没有 HDMI Dummy 时，可以尝试创建虚拟显示器。
2. 虚拟显示器能被系统识别。
3. 虚拟显示器能成为主屏。
4. 远程桌面可以连接到虚拟显示器。
5. 恢复时可以销毁虚拟显示器。
6. 创建失败时不会影响系统正常使用。
7. 分辨率配置可以通过菜单栏和 CLI 生效。

## 17.6 v1.0：自用稳定版

目标：形成用户日常可用版本。

功能：

1. 菜单栏 UI。
2. CLI 后门。
3. Keep Awake。
4. HDMI Dummy Headless。
5. 内建屏幕降亮度 fallback。
6. 可选 soft-disconnect。
7. 可选软件虚拟显示器。
8. 虚拟显示器默认分辨率配置。
9. 至少支持 1920×1080 和 2560×1440。
10. CLI 可查看当前虚拟显示器分辨率。
11. CLI 可设置默认分辨率。
12. 菜单栏可选择常用预设分辨率。
13. 自动回滚。
14. 日志。
15. 开机自启。
16. 基础 README。
17. 安装和卸载脚本。

验收标准：

1. 用户可以长期远程使用 MBP。
2. 系统不会自动睡眠。
3. 内建屏幕不会常亮。
4. 远程桌面分辨率稳定。
5. 虚拟显示器分辨率可配置。
6. 遇到异常可以通过 SSH 恢复。
7. 日常操作只需要菜单栏点击。

## 18. 验收测试

## 18.1 v0.1 测试

1. App 能启动并出现在菜单栏。
2. 点击 Keep Awake 后，`caffeinate` 运行。
3. 再次点击 Keep Awake 后，`caffeinate` 停止。
4. `pmset` 设置生效。
5. 日志写入正常。
6. CLI status 正常输出。
7. 配置文件正常创建。

## 18.2 v0.2 测试

1. 能识别内建屏幕。
2. 能识别外接显示器。
3. 能识别 HDMI Dummy。
4. 能输出主显示器。
5. 能输出当前显示器分辨率。
6. 不修改显示布局。

## 18.3 v0.3 测试

前提：插入 HDMI Dummy。

测试项：

1. 点击 Enable Headless Mode。
2. Dummy 成为主显示器。
3. 内建屏幕亮度降到 0。
4. 系统不睡眠。
5. 远程桌面分辨率稳定。
6. 30 秒不确认时自动恢复。
7. 确认后不自动恢复。
8. SSH 执行 `codex-headless off` 可以恢复。

## 18.4 v0.4 测试

1. 有替代显示器时，尝试 soft-disconnect。
2. 无替代显示器时，禁止 soft-disconnect。
3. soft-disconnect 失败时 fallback 到亮度 0。
4. Restore Normal Mode 可以恢复。
5. 不出现无法恢复黑屏。

## 18.5 v0.5 预设分辨率测试

需要测试以下分辨率：

```text
1280x720
1600x900
1920x1080
2560x1440
3008x1692
3840x2160
```

测试项：

1. 菜单栏可以选择该分辨率。
2. CLI 可以指定该分辨率。
3. 配置文件可以保存该分辨率。
4. Headless Mode 会按该分辨率创建虚拟显示器。
5. status 可以正确显示该分辨率。
6. Restore Normal Mode 后可以恢复。

## 18.6 自定义分辨率测试

测试有效输入：

```text
1366x768
1440x900
1920x1200
2560x1600
```

测试无效输入：

```text
800x600
9999x9999
1920x0
abcx1080
1920xabc
1921x1080
```

无效输入应：

1. 不创建虚拟显示器。
2. 不修改当前显示布局。
3. 给出错误提示。
4. 写入日志。
5. 不影响 Restore Normal Mode。

## 18.7 CLI 优先级测试

配置文件中保存：

```text
1920x1080
```

执行：

```bash
codex-headless on --resolution 2560x1440
```

预期：

```text
本次创建 2560x1440 虚拟显示器
配置文件仍保持 1920x1080
```

执行：

```bash
codex-headless config set resolution 2560x1440
codex-headless on
```

预期：

```text
创建 2560x1440 虚拟显示器
```

## 19. 风险与应对

## 19.1 风险：黑屏

原因：

1. 断开了唯一显示器。
2. 虚拟显示器创建失败。
3. 主屏切换失败。
4. 恢复顺序错误。

应对：

1. 不断开唯一显示器。
2. 自动回滚。
3. CLI 恢复。
4. 先恢复内建屏幕，再销毁虚拟屏幕。

## 19.2 风险：远程连接中断

原因：

1. 系统睡眠。
2. 网络断开。
3. 合盖触发睡眠。
4. pmset 未生效。

应对：

1. 使用 caffeinate。
2. 设置 pmset。
3. 开盖或半开盖使用。
4. 使用 Tailscale + SSH。
5. 不依赖磁铁模拟合盖。

## 19.3 风险：私有 API 失效

原因：

1. macOS 更新。
2. Intel / Apple Silicon 差异。
3. CoreDisplay 符号变化。

应对：

1. 私有 API 仅作为 v0.4/v0.5 探索功能。
2. 保留 HDMI Dummy 方案。
3. 保留亮度 0 fallback。
4. 日志记录错误。
5. 不影响 v0.1-v0.3 基础功能。

## 19.4 风险：权限问题

原因：

1. pmset 需要 sudo。
2. 登录项需要授权。
3. 未来可能需要辅助功能权限。

应对：

1. 第一版尽量减少权限。
2. 提供清晰错误提示。
3. CLI 输出需要执行的授权命令。
4. 不强依赖 GUI 自动化。

## 19.5 风险：分辨率异常

原因：

1. 用户输入过高分辨率。
2. 用户输入无效宽高。
3. 私有 API 对某些分辨率支持不好。
4. 远程桌面工具无法识别特殊比例。

应对：

1. 限制第一版分辨率范围。
2. 默认使用 1920×1080。
3. 对异常分辨率进行校验。
4. 创建失败时自动 fallback。
5. 日志记录分辨率和失败原因。

## 20. 推荐实施路线

建议实际开发顺序：

```text
第一阶段：v0.1
菜单栏 App + CLI + Keep Awake + 日志 + 配置文件

第二阶段：v0.2
显示器枚举 + 状态展示 + 分辨率配置占位

第三阶段：v0.3
HDMI Dummy Headless Mode + 亮度降到 0 + 自动回滚

第四阶段：v0.4
尝试 soft-disconnect 内建屏幕

第五阶段：v0.5
尝试软件虚拟显示器 + 自定义分辨率

第六阶段：v1.0
整理成自用稳定版本
```

## 21. 最小可用版本定义

对于用户当前场景，最小可用版本不是完整虚拟显示器版本，而是：

1. 菜单栏 App。
2. CLI 后门。
3. Keep Awake。
4. HDMI Dummy 支持。
5. 内建屏幕降亮度。
6. 主显示器切换。
7. 自动回滚。
8. CLI 恢复。
9. 虚拟显示器分辨率配置预留。

注意：在 HDMI Dummy 阶段，不一定能真正创建软件虚拟显示器，但配置结构和 UI 应提前预留分辨率选项，避免后续重构。

## 22. 最终推荐方案

CodexHeadless 最终应支持两种 Headless 路径。

### 路径 A：HDMI Dummy 模式

```text
HDMI Dummy Plug
→ 设置 Dummy 为主屏
→ 内建屏幕降亮度或断开
→ 保持系统不休眠
```

该模式稳定性最高。

### 路径 B：软件虚拟显示器模式

```text
读取用户配置分辨率
→ 创建指定分辨率虚拟显示器
→ 设置虚拟显示器为主屏
→ 内建屏幕降亮度或断开
→ 保持系统不休眠
```

该模式体验最好，但依赖私有 API，稳定性需要实机验证。

默认推荐：

```text
1920x1080 @ 60Hz
```

用户主力远程开发推荐：

```text
2560x1440 @ 60Hz
```

低带宽远程推荐：

```text
1600x900 @ 60Hz
```

最终目标不是把 MacBook 改成真正无头服务器，而是把它改造成一台稳定、可恢复、适合远程 Codex 开发的 macOS 工作节点。
