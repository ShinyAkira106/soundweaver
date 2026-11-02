<p align="center">
  <img src="Design/AppIcon-1024.png" width="160" alt="Soundweaver icon">
</p>

<h1 align="center">Soundweaver</h1>

<p align="center">
  把外接显示器和 MacBook 的声音织在一起<br>
  Weave your monitor's sound and your MacBook's speakers into one
</p>

<p align="center">v0.1.0 · macOS 13+ · Apple silicon · MIT License</p>

---

## 简介 / Overview

Soundweaver 是一个 macOS 菜单栏小工具。当声音通过 USB-C、DisplayPort 或 HDMI 送到外接显示器时，macOS 无法调节它的音量，系统的音量键和音量提示框都会变灰；如果再把显示器和 MacBook 扬声器组合成“多输出设备”，整个组合也同样没有音量。Soundweaver 解决的就是这个问题：它让键盘音量键同时控制显示器的硬件音量和 MacBook 扬声器，两边的音量比例可以分别调整，并在按键时显示音量提示框。

Soundweaver is a macOS menu bar utility. When audio goes to an external monitor over USB-C, DisplayPort or HDMI, macOS cannot change its volume, so the volume keys and the volume HUD turn grey; combining the monitor and the MacBook speakers into a Multi Output Device has the same problem. Soundweaver fixes this: the keyboard volume keys control the monitor's hardware volume and the MacBook speakers together, the balance between the two is adjustable, and a volume HUD appears as you press the keys.

接在显示器 3.5mm 耳机口上的音箱会跟着显示器的硬件音量变化，所以同样可以被音量键控制。

Speakers plugged into the monitor's 3.5mm headphone jack follow the monitor's hardware volume, so they are controlled by the volume keys as well.

## 工作原理 / How it works

启动后，Soundweaver 会创建一个名为 Soundweaver 的多输出设备，以 MacBook 扬声器为时钟源，对显示器开启漂移校正，并把它设为系统输出。由于多输出设备没有音量，程序通过事件监听接管键盘的音量加、减和静音键：显示器那一路通过 DDC/CI 写入 VCP 0x62 来改变显示器的硬件音量，MacBook 那一路直接设置扬声器的系统音量，每一路的实际音量等于总音量乘以该设备的比例。DDC 写入在后台串行执行并合并连续的请求，按住按键或拖动滑块都不会卡顿。

On launch Soundweaver creates a Multi Output Device called Soundweaver, with the MacBook speakers as the clock source and drift correction on the monitor, and makes it the system output. Because a Multi Output Device has no volume, the app takes over the volume up, volume down and mute keys with an event tap: the monitor's hardware volume is set by writing VCP 0x62 over DDC/CI, the MacBook speakers get their own system volume, and each output's level is the master volume times that device's share. DDC writes run serially in the background and rapid requests are merged, so holding a key or dragging a slider never stutters.

当你在控制中心把输出切换到 AirPods 等其他设备时，Soundweaver 会自动把音量键交还给系统；退出时会恢复之前的输出设备，并删除它创建的多输出设备。

When you switch output to AirPods or any other device in Control Center, Soundweaver hands the volume keys back to the system; on quit it restores the previous output and removes the Multi Output Device it created.

## 功能 / Features

菜单栏面板采用分组卡片和胶囊滑块的设计。最上面是 Soundweaver 总开关和总音量；下面是显示器卡片，它的开关只静音显示器，滑块调整显示器所占的比例，展开后可以设置显示器音量上限并查看 DDC 状态；再下面是 MacBook 卡片，它的开关决定 MacBook 扬声器是否加入组合输出，展开后可以调整两路声音之间的同步补偿。右下角的齿轮打开设置窗口，省略号菜单里有重新检测设备、预览提示框、关于和退出。

The menu bar panel uses grouped cards and pill sliders. At the top are the Soundweaver master switch and master volume. Below is the monitor card, whose switch mutes only the monitor and whose slider sets the monitor's share; expanded, it offers a monitor volume cap and the DDC status. Then comes the MacBook card, whose switch decides whether the MacBook speakers join the combined output; expanded, it offers a sync offset between the two outputs. The gear opens the settings window, and the ellipsis menu holds rescan, HUD preview, about and quit.

设置窗口采用左右两栏布局，左边是应用图标和“重新检测设备”按钮，右边是八个设置主题，点进去可以做细节调整。输出设备页可以手动指定显示器和 MacBook 使用的音频设备，并切换“显示器 + MacBook”与“仅显示器”两种模式。音量调节页可以设置每次按键的步进（16、32 或 64 格）、音量曲线以及显示器的最大硬件音量。显示器 DDC 页可以查看连接状态、读取显示器当前音量、重新检测，以及选择启动时是否以显示器当前音量作为总音量。同步与校正页可以调整同步补偿、选择时钟源和开关漂移校正。提示框页可以在系统原生提示框和自绘提示框之间切换，并设置位置、显示的屏幕和停留时间。键盘页可以开关音量键接管、按住时连续调节，以及 Option 加音量键打开声音设置。启动与退出页可以设置登录时自动启动和退出时恢复原来的输出设备。

The settings window has two panes: the app icon and a Rescan button on the left, and eight topics on the right that open detail pages. The output devices page picks the audio devices for the monitor and the MacBook and switches between monitor plus MacBook and monitor only. The volume page sets the step per key press (16, 32 or 64 steps), the volume curve and the monitor's maximum hardware volume. The DDC page shows the connection status, reads the monitor's current volume, rescans, and can take the monitor's current volume as the master volume at launch. The sync page adjusts the sync offset, the clock source and drift correction. The HUD page switches between the native system HUD and the app's own HUD and sets its position, screen and duration. The keyboard page toggles key takeover, hold to repeat, and Option plus a volume key opening Sound settings. The startup page sets launch at login and restoring the previous output on quit.

按住 Option 和 Shift 再按音量键，可以用四分之一格的精细步进调节，和 macOS 的习惯一致。

Holding Option and Shift while pressing a volume key adjusts in quarter steps, just like macOS.

## 图标 / Icon

图标叫“编织声波”：两条声波在深靛紫色底上像经纬线一样一上一下地交织，背后淡淡的竖线代表织机的经线。暖色的一条代表显示器，冷色的一条代表 MacBook。源文件在 `Design/AppIcon.svg`。

The icon is a woven waveform: two sound waves interlace over and under each other on a deep indigo base, with faint vertical lines behind them like the warp of a loom. The warm thread stands for the monitor and the cool one for the MacBook. The source is `Design/AppIcon.svg`.

## 系统要求 / Requirements

需要搭载 Apple 芯片的 Mac，运行 macOS 13 Ventura 或更新版本，并安装 Xcode 或命令行工具（`xcode-select --install`）。显示器需要支持 DDC/CI 并通过 USB-C 或 DisplayPort 连接；部分 Mac 自带的 HDMI 接口不支持 DDC。

An Apple silicon Mac running macOS 13 Ventura or later, with Xcode or the Command Line Tools installed (`xcode-select --install`). The monitor must support DDC/CI and be connected over USB-C or DisplayPort; the built in HDMI port on some Macs does not pass DDC.

## 编译与安装 / Build and install

```bash
git clone https://github.com/ShinyAkira106/Soundweaver.git
cd Soundweaver
chmod +x build.sh
./build.sh install
```

`./build.sh` 只编译到 `build/Soundweaver.app`，加上 `install` 会复制到“应用程序”文件夹并启动。

`./build.sh` alone builds `build/Soundweaver.app`; adding `install` copies it to Applications and launches it.

首次启动时 macOS 会请求“辅助功能”权限，请在“系统设置 > 隐私与安全性 > 辅助功能”里打开 Soundweaver，否则无法接管音量键。

On first launch macOS asks for Accessibility permission; turn on Soundweaver under System Settings > Privacy & Security > Accessibility, otherwise it cannot take over the volume keys.

## 已知问题 / Known issues

这个版本使用临时签名，每次重新编译后签名都会改变，macOS 会把它当作新应用，需要在辅助功能列表里删除 Soundweaver 再重新添加。在 macOS 26 Tahoe 上，系统原生提示框可能无法显示正确的音量格数，这时可以在设置的“提示框”页面改用自绘提示框。DDC 控制目前只支持 Apple 芯片的 Mac。

This version is ad hoc signed, so its signature changes with every rebuild and macOS treats it as a new app; remove Soundweaver from the Accessibility list and add it again. On macOS 26 Tahoe the native system HUD may not show the correct level; switch to the app's own HUD on the HUD page in settings. DDC control currently supports Apple silicon Macs only.

## 项目结构 / Project layout

`Sources/` 是全部 Swift 源代码：`AudioSystem.swift` 负责 Core Audio 设备和多输出设备，`DDC.swift` 负责显示器 DDC 通信，`MediaKeyTap.swift` 负责拦截音量键，`HUD.swift` 是音量提示框，`Controller.swift` 是应用状态和逻辑，`App.swift`、`Components.swift` 和 `SettingsWindow.swift` 是界面。`Design/` 是图标源文件，`Resources/` 是编译用的图标集，`build.sh` 是编译脚本。

`Sources/` holds all the Swift code: `AudioSystem.swift` handles Core Audio devices and the Multi Output Device, `DDC.swift` talks DDC to the monitor, `MediaKeyTap.swift` intercepts the volume keys, `HUD.swift` draws the volume HUD, `Controller.swift` holds app state and logic, and `App.swift`, `Components.swift` and `SettingsWindow.swift` make up the interface. `Design/` contains the icon source, `Resources/` the icon set used by the build, and `build.sh` is the build script.

## 致谢 / Acknowledgements

DDC 通信和原生提示框的实现思路参考了 [MonitorControl](https://github.com/MonitorControl/MonitorControl)（MIT 许可）和 [m1ddc](https://github.com/waydabber/m1ddc)。

The DDC and native HUD approach follows [MonitorControl](https://github.com/MonitorControl/MonitorControl) (MIT licensed) and [m1ddc](https://github.com/waydabber/m1ddc).

## 许可 / License

MIT License. Copyright © 2026 ShinyAkira.
