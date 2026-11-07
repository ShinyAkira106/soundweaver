<p align="center"><img src="Design/AppIcon-1024.png" width="96" alt="Soundweaver"></p>

# Soundweaver

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-6b52e0"></a>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-6b52e0?logo=apple">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple-silicon-6b52e0">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-6b52e0?logo=swift&logoColor=white">
  <a href="https://github.com/ShinyAkira106/Soundweaver/releases"><img alt="Version" src="https://img.shields.io/badge/version-1.4.0-6b52e0"></a>
  <a href="https://github.com/ShinyAkira106"><img alt="Author: ShinyAkira" src="https://img.shields.io/badge/author-ShinyAkira-6b52e0?logo=github"></a>
</p>

简体中文 · English · 日本語（界面为简体中文 / interface in Simplified Chinese / インターフェースは簡体字中国語）

一个 macOS 菜单栏小工具：让键盘音量键同时控制外接显示器和 MacBook 扬声器。声音通过 USB-C、DisplayPort 或 HDMI 送到显示器时，macOS 调不了它的音量，音量键和提示框都会变灰。Soundweaver 通过 DDC/CI 直接调显示器的硬件音量（接在显示器耳机口上的音箱也会跟着变），同时把显示器和 MacBook 扬声器组合成一路输出，两边的音量比例可以分别调整，按键时照样有音量提示框。

A macOS menu bar app that lets the volume keys control an external monitor and the MacBook speakers together. When audio goes to a monitor over USB-C, DisplayPort or HDMI, macOS cannot change its volume, so the keys and the HUD go grey. Soundweaver sets the monitor's hardware volume over DDC/CI (speakers plugged into the monitor's headphone jack follow along), combines the monitor and the MacBook speakers into one output with a separate share for each, and still shows a volume HUD as you press the keys.

外部モニターと MacBook のスピーカーを、キーボードの音量キーでまとめて操作できる macOS のメニューバーアプリです。USB-C、DisplayPort、HDMI でモニターに音声を送ると macOS では音量を変えられず、音量キーも HUD もグレーになります。Soundweaver は DDC/CI でモニター本体の音量を直接変え（モニターのイヤホン端子につないだスピーカーも連動します）、モニターと MacBook のスピーカーを 1 つの出力にまとめ、それぞれの割合を個別に調整できます。キーを押すと音量 HUD も表示されます。

<p align="center">
  <img src="docs/images/panel.png" width="300" alt="菜单栏里的 Soundweaver 面板 / The Soundweaver panel in the menu bar">
</p>

菜单栏里的 Soundweaver 面板。

The Soundweaver panel in the menu bar.

## 安装 / Install

从 [Releases](https://github.com/ShinyAkira106/Soundweaver/releases) 下载 `Soundweaver-1.4.0.dmg`，打开后把 Soundweaver 拖进“应用程序”文件夹。需要搭载 Apple 芯片的 Mac 和 macOS 13 或更新版本。由于应用没有经过苹果公证，第一次打开时如果被系统拦下，请到“系统设置 > 隐私与安全性”最下面点“仍要打开”。首次启动会请求“辅助功能”权限，打开后 Soundweaver 才能接管音量键。

Download `Soundweaver-1.4.0.dmg` from [Releases](https://github.com/ShinyAkira106/Soundweaver/releases), open it and drag Soundweaver into Applications. An Apple silicon Mac with macOS 13 or later is required. The app is not notarized by Apple, so if macOS stops it on first launch, click Open Anyway at the bottom of System Settings > Privacy & Security. On first launch it asks for Accessibility permission, which it needs to take over the volume keys.

菜单栏右上角会多一个声波图标。点开是一个和控制中心风格一致的面板：最上面是 Soundweaver 总开关和总音量；下面是显示器卡片，开关只静音显示器，滑块调整显示器的比例，展开后可以设置显示器音量上限；再下面是 MacBook 卡片，开关决定 MacBook 扬声器是否加入组合输出，展开后可以调整两边的同步补偿。右下角的齿轮打开完整设置，省略号菜单里有重新检测设备、预览提示框、检查更新和退出。

A waveform icon appears in the menu bar. It opens a panel styled like Control Center: the Soundweaver master switch and master volume on top; then the monitor card, whose switch mutes only the monitor and whose slider sets its share, with a monitor volume cap when expanded; then the MacBook card, whose switch decides whether the MacBook speakers join the combined output, with a sync offset when expanded. The gear opens the full settings, and the ellipsis menu holds rescan, HUD preview, update check and quit.

## 界面一览 / Screenshots / スクリーンショット

<p align="center">
  <img src="docs/images/settings.png" width="720" alt="设置窗口 / Settings window">
</p>

设置窗口：左边是图标和“重新检测设备”按钮，右边是八个设置主题，点进去可以做细节调整。

The settings window: the icon and a Rescan button on the left, and eight topics on the right that open detail pages.

設定ウィンドウ：左側にアイコンと「デバイスを再検出」ボタン、右側に 8 つの設定項目があり、クリックすると詳細を調整できます。

## 功能 / Features / 機能

### 显示器硬件音量 / Monitor hardware volume / モニター本体の音量

通过 DDC/CI 写入 VCP 0x62 改变显示器自己的音量，所以接在显示器 3.5mm 耳机口上的音箱也会跟着变。写入在后台串行执行，连续按键或拖动滑块时只发送最新的值，不会卡顿。可以设置显示器的音量上限，避免音箱突然过响。

The monitor's own volume is set by writing VCP 0x62 over DDC/CI, so speakers on the monitor's 3.5mm jack follow it. Writes run serially in the background and only the latest value is sent while you hold a key or drag a slider, so nothing stutters. A volume cap keeps the speakers from getting suddenly loud.

DDC/CI で VCP 0x62 を書き込み、モニター本体の音量を変えるので、3.5mm 端子につないだスピーカーも連動します。書き込みはバックグラウンドで順番に行い、キーを押し続けたりスライダーを動かしたりしても最新の値だけを送るため、引っかかりません。音量の上限を決めて、急に大きな音が出るのを防げます。

### 组合输出 / Combined output / 出力をまとめる

Soundweaver 会创建一个名为 Soundweaver 的多输出设备，把显示器和 MacBook 扬声器组合在一起，并开启漂移校正。总音量乘以各自的比例就是两边的实际音量。两路声音如果有回声感，可以用同步补偿让其中一边晚一点出声。切换到 AirPods 等其他设备时，音量键会自动交还给系统；退出时会恢复原来的输出设备。

Soundweaver creates a Multi Output Device named Soundweaver that combines the monitor and the MacBook speakers, with drift correction on. Each side's level is the master volume times its share. If the two outputs sound slightly echoed, the sync offset delays one of them. Switching to AirPods or any other device hands the volume keys back to macOS, and quitting restores the previous output.

モニターと MacBook のスピーカーをまとめた「Soundweaver」という複数出力装置を作り、ドリフト補正を有効にします。実際の音量はマスター音量にそれぞれの割合を掛けたものです。2 つの音がずれて聞こえるときは、同期補正でどちらかを少し遅らせられます。AirPods などに切り替えると音量キーは macOS に戻り、終了時には元の出力に戻ります。

### 音量提示框 / Volume HUD / 音量 HUD

默认使用 macOS 自己的音量提示框。在 macOS 26 Tahoe 上，Soundweaver 通过 XPC 直接请求系统的 OSDUIHelper 画出带正确音量格数的提示框，这和 MonitorControl 4.4 的做法相同。也可以改用 Soundweaver 自己的液态玻璃提示框，它会显示正在发声的设备名称，位置、显示的屏幕和停留时间都可以调整。

The HUD is macOS's own by default. On macOS 26 Tahoe, Soundweaver asks the system's OSDUIHelper over XPC to draw it with the correct level, the same approach MonitorControl 4.4 takes. You can switch to Soundweaver's own liquid glass HUD instead, which names the outputs that are playing; its position, screen and duration are adjustable.

既定では macOS 自身の音量 HUD を使います。macOS 26 Tahoe では MonitorControl 4.4 と同じ方法で、XPC 経由でシステムの OSDUIHelper に正しい音量の HUD を描かせます。Soundweaver 独自の Liquid Glass 風 HUD に切り替えることもでき、再生中の出力の名前を表示します。位置、表示する画面、表示時間を調整できます。

### 细节设置 / Fine tuning / 細かな設定

完整设置里可以手动指定显示器和 MacBook 使用的音频设备，并给它们起自定义名称；选择每次按键的步进（16、32 或 64 格）和音量曲线；读取显示器当前音量；选择时钟源和漂移校正；设置 Option 加音量键是否打开声音设置；以及登录时自动启动和退出时恢复原来的输出。按住 Option 和 Shift 再按音量键，可以用四分之一格精细调节。

The full settings let you pick the audio devices for the monitor and the MacBook and give them custom names; choose the step per key press (16, 32 or 64 steps) and the volume curve; read the monitor's current volume; pick the clock source and drift correction; decide whether Option plus a volume key opens Sound settings; and set launch at login and restoring the previous output on quit. Holding Option and Shift adjusts in quarter steps.

設定では、モニターと MacBook に使うオーディオデバイスを選んで名前を付けたり、キー 1 回あたりの段数（16、32、64 段）と音量カーブ、モニターの現在の音量の読み取り、クロックソースとドリフト補正、Option と音量キーでサウンド設定を開くかどうか、ログイン時の自動起動と終了時に元の出力へ戻すかどうかを設定できます。Option と Shift を押しながら音量キーを押すと 1/4 段ずつ調整できます。

### 新版本提醒 / Update notices / 更新のお知らせ

Soundweaver 每天最多检查一次 GitHub Releases，有新版本时面板里会出现一条提示，点一下就能打开下载页。也可以在“关于”页面或省略号菜单里手动检查。

Soundweaver checks GitHub Releases at most once a day and shows a notice in the panel when a newer version exists; one click opens the download page. You can also check by hand on the About page or from the ellipsis menu.

Soundweaver は 1 日に 1 回まで GitHub Releases を確認し、新しいバージョンがあればパネルにお知らせを表示します。クリックするとダウンロードページが開きます。「情報」ページや省略記号メニューから手動でも確認できます。

## 工作原理 / How it works

<p align="center">
  <a href="https://github.com/ShinyAkira106/Soundweaver/releases"><img src="docs/images/how-it-works.png" width="900" alt="How it works: install once, just press the keys, one HUD for both / 工作原理 / 仕組み"></a>
</p>

音量键：Soundweaver 用 CGEventTap 监听系统定义事件里的音量加、减和静音键。只有当系统输出是 Soundweaver 的多输出设备或显示器时才会接管，其他时候按键原样交给 macOS。按键改变的是总音量，显示器那一路按“总音量 × 显示器比例 × 音量上限”换算成 DDC 的数值写入显示器，MacBook 那一路按“总音量 × MacBook 比例”设置扬声器的系统音量。

Volume keys: Soundweaver listens for volume up, volume down and mute in system defined events with a CGEventTap. It only takes them over while the system output is its Multi Output Device or the monitor; otherwise the keys go to macOS untouched. A key press changes the master volume; the monitor gets master × monitor share × cap, converted to a DDC value, and the MacBook speakers get master × MacBook share as their system volume.

DDC：在 Apple 芯片上，Soundweaver 通过 IOKit 找到外接显示器的 `DCPAVServiceProxy`，再用 `IOAVServiceWriteI2C` 向地址 0x37 发送 DDC/CI 命令。启动时会先读出显示器音量的最大值，按它换算。

DDC: on Apple silicon, Soundweaver finds the external display's `DCPAVServiceProxy` through IOKit and sends DDC/CI commands to address 0x37 with `IOAVServiceWriteI2C`. At launch it reads the monitor's maximum volume and scales to it.

仕組み：音量キーは CGEventTap で受け取り、システムの出力が Soundweaver の複数出力装置かモニターのときだけ処理します。それ以外は macOS にそのまま渡します。モニターにはマスター音量 × モニターの割合 × 上限を DDC の値に換算して書き込み、MacBook のスピーカーにはマスター音量 × MacBook の割合をシステム音量として設定します。Apple シリコンでは IOKit で外部ディスプレイの `DCPAVServiceProxy` を見つけ、`IOAVServiceWriteI2C` でアドレス 0x37 に DDC/CI コマンドを送ります。

## 已知问题 / Known issues

有些显示器的耳机口不跟随 DDC 设置的音量，这时 Soundweaver 只能控制 MacBook 那一路。部分 Mac 自带的 HDMI 接口不支持 DDC，建议用 USB-C 或 DisplayPort 连接。DDC 控制目前只支持 Apple 芯片的 Mac。

Some monitors' headphone jacks ignore the volume set over DDC, in which case Soundweaver can only control the MacBook side. The built in HDMI port on some Macs does not pass DDC, so USB-C or DisplayPort is recommended. DDC control currently supports Apple silicon Macs only.

## 开发 / Development

需要 Xcode 或命令行工具（`xcode-select --install`），项目不依赖任何第三方库。

Xcode or the Command Line Tools are required (`xcode-select --install`); the project has no third party dependencies.

```bash
git clone https://github.com/ShinyAkira106/Soundweaver.git
cd Soundweaver
./build.sh install   # 编译、安装并启动 / build, install and launch
./make_dmg.sh        # 生成 build/Soundweaver-版本号.dmg / produce the disk image
```

第一次编译时 `build.sh` 会运行 `setup_signing.sh`，在登录钥匙串里创建一个名为 Soundweaver Local Signing 的自签名证书，之后每次编译都用它签名。macOS 按签名记住辅助功能权限，签名不变，更新后就不用重新授权。README 里的工作原理图由 `node scripts/how-it-works.js` 生成（需要 Playwright），图中的菜单栏、面板和提示框是示意图，数值是示例。

On the first build, `build.sh` runs `setup_signing.sh`, which creates a self signed certificate called Soundweaver Local Signing in your login keychain, and every later build is signed with it. macOS remembers the Accessibility permission by signature, so it survives updates. The How it works image comes from `node scripts/how-it-works.js` (Playwright required); the menu bar, panel and HUD in it are drawn mocks and the numbers are examples.

```text
Sources/AudioSystem.swift    Core Audio 设备和多输出设备 / devices and the Multi Output Device
Sources/DDC.swift            显示器 DDC 通信 / DDC to the monitor
Sources/MediaKeyTap.swift    接管音量键 / volume key takeover
Sources/HUD.swift            系统提示框和玻璃提示框 / system and glass HUD
Sources/Controller.swift     状态和逻辑 / state and logic
Sources/Updater.swift        检查 GitHub 上的新版本 / update check
Sources/App.swift            菜单栏面板 / menu bar panel
Sources/Components.swift     玻璃控件 / glass controls
Sources/SettingsWindow.swift 设置窗口 / settings window
Design/                      图标源文件 / icon source
Resources/                   图标集和安装盘背景 / icon set and disk image background
scripts/how-it-works.js      生成工作原理图 / renders the How it works image
docs/images/                 README 截图和示意图 / README screenshots and diagram
```

## 致谢 / Acknowledgements

DDC 通信和系统提示框的实现思路参考了 [MonitorControl](https://github.com/MonitorControl/MonitorControl)（MIT 许可）和 [m1ddc](https://github.com/waydabber/m1ddc)。Soundweaver 是独立编写的代码。

The DDC and system HUD approach follows [MonitorControl](https://github.com/MonitorControl/MonitorControl) (MIT licensed) and [m1ddc](https://github.com/waydabber/m1ddc). Soundweaver is independently written.

## 作者 / Author / 作者

Soundweaver 由 [ShinyAkira](https://github.com/ShinyAkira106) 开发和维护。欢迎在 [Issues](https://github.com/ShinyAkira106/Soundweaver/issues/new) 里提出问题和建议。

Soundweaver is made and maintained by [ShinyAkira](https://github.com/ShinyAkira106). Issues and suggestions are welcome in [Issues](https://github.com/ShinyAkira106/Soundweaver/issues/new).

Soundweaver は [ShinyAkira](https://github.com/ShinyAkira106) が開発・メンテナンスしています。不具合の報告や提案は [Issues](https://github.com/ShinyAkira106/Soundweaver/issues/new) へどうぞ。

## 许可 / License / ライセンス

版权所有 © 2026 ShinyAkira。基于 [MIT 许可证](LICENSE) 开源。

Copyright © 2026 ShinyAkira. Released under the [MIT License](LICENSE).

Copyright © 2026 ShinyAkira。[MIT ライセンス](LICENSE)のもとで公開しています。
