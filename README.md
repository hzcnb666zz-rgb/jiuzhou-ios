# 九州书剑录 iOS 个人测试工程

状态：原生 SwiftUI/TCP 移植初版。尚未经过 Xcode 编译或 iPhone 实机验证；此目录不是安装包。

## 已实现范围

- 连接可编辑的服务器地址和端口，默认 172.20.10.5:6666。
- 登录、创建角色、场景描述、人物物品、九宫格方向、服务器按钮。
- 弹出菜单、输入框、确认对话、状态条、消息记录和手动重连。
- TCP 分包、UTF-8、Telnet 协商处理，协议测试放在 Tests。
- 最低 iOS 16。UI 按安卓源码的区域结构移植，还没有达到逐像素一致。

暂未移植完整语音、第三方充值、账号中心、所有扩展私有协议和安卓个性化设置。
当前服务器只用于可信局域网测试，沿用本地 APK 的简化登录，不能作为公网生产账号系统。

## 有 Mac：免费个人真机测试

1. 安装 Xcode，登录你自己的 Apple ID；不用把密码发给任何人。
2. 安装 Homebrew 和 XcodeGen，然后在本目录运行 `xcodegen generate`。
3. 打开 `Jiuzhou.xcodeproj`。在 Signing & Capabilities 选择自己的 Personal Team。
4. 如包名冲突，修改 Bundle Identifier 为自己的唯一标识。
5. 连接并信任 iPhone，按 Xcode/手机提示开启开发者模式，选手机并 Run。
6. 免费个人签名一般约 7 天有效，届时需要重新安装/续签，以苹果实际限制为准。

## Windows + GitHub Mac 构建机

1. 把本目录作为单独仓库的根目录，包括 `.github/workflows/ios-build.yml`。
2. 先查看自己的 GitHub Actions 免费额度。私有仓库的 macOS 构建会消耗额度；没有额度就不要启动付费构建。
   不要为了免费额度公开上传不适合公开的游戏资源。
3. Actions -> Build Personal iOS Test Package -> Run workflow。
4. 工作流先运行 Swift 协议测试，再编译模拟器和 iPhone 版本。失败时不会交付 IPA。
5. 成功后下载 `Jiuzhou-unsigned-IPA` 工件，解压得到 `Jiuzhou-unsigned.ipa`。
6. 此 IPA 没有签名，微信点开不能直接安装。用适用的免费个人侧载工具，在你自己电脑上登录 Apple ID，
   给该 IPA 签名并装入自己 iPhone。工具兼容性、设备数、续签周期以当前工具和苹果规定为准。

本工程没有上传到任何远程仓库，也没有启动云端构建或产生云端费用。

## 在本地 Mac 生成未签名 IPA

运行 `bash build-unsigned.sh`，成功后产物为 `build/Jiuzhou-unsigned.ipa`。
生成未签名包不需要付费开发者账号，但生成后必须个人签名才能安装。

## 连接游戏

电脑运行已有的 `outputs/start-android-server.cmd`，手机和电脑处于同一个可互通的局域网。
允许 iOS 的局域网访问权限；如果电脑 IP 改变，在 App 登录页修改地址。
账号沿用安卓版账号会进入同一角色，请避免安卓和苹果同时登录该角色。
游戏逻辑和存档在电脑端，电脑关闭后手机不能继续玩。

## 验证记录

- Windows 上只能检查工程文件与实际服务器通信，不能声称通过了 Xcode 编译。
- `swift test` 与两种 iOS 构建已经加入脚本，需在 Mac 环境实际运行。
- 真机安装、显示效果、触摸交互、后台重连仍需 iPhone 验证。
