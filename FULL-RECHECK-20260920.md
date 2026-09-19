# 构建 11 全面复查记录

结论：不通过完整一比一验收。已有测试通过，但仍有确定的源码差异和未验证场景。

本轮是对当前源码、安卓参考源码、测试内容、构建结果和交付文件身份的复查，没有重新进行真机游戏测试，也没有生成新 IPA。下列问题尚未修复，不得标记已关闭。

## 对象与范围

- 当前仓库提交：9ff91257ab3986f312a395ed31c2175f07236655。
- 交付应用代码：bef9953fa7f5ebb377ee377e012bbc80d94f4cde；后续提交只更新记录。
- 构建任务 35456748885 当前查询仍为 success。
- 交付文件：Jiuzhou-unsigned-build11-20260920.ipa。
- 本轮重新核对 SHA-256：a054b31ec490432bdf8cd29c4ba743eab288b1c8d4ff3d2b80779baeba1fca9f。
- 对照目录：../MudZJutf8-src/MudZJutf8/app/src/main；该安卓工程包含本地服务器适配，不能把原远程服务和本地模式混为一谈。
- 审查模块：登录/角色创建、游戏状态、协议解析、Socket 生命周期、富文本、主界面/交互/背包/地图/分页/奖励/菜单、网页面板、打包配置和测试覆盖。

## 确定的差异

| 编号 | 问题与触发条件 | 当前 iOS 证据 | 安卓证据 | 状态 |
|---|---|---|---|---|
| F01 | 相同命令的不同按钮会丢失。例如 `查看:look$zj#刷新:look` 只留下一个按钮，后续行数和排列随之变化。房间对象也按命令合并。 | Core/MudProtocol.swift:151 的 seen 去重；GameModel.swift:281 合并对象 | mudmaind.java:394 的 takeobacts 逐项创建；489 的 takeobj 逐项添加 | 未修复，影响协议和布局 |
| F02 | 标题旁动作仍固定 12pt 字号和 28pt 高度；特殊出口也使用同一固定 12pt 字号，缺少安卓出口边距/专用背景。屏幕越宽差异越明显。 | AndroidWorldView.swift:113、215、362 | mudmaind.java:279 的 take_tt 使用 scrw/30；takeexit 使用 scrw/35、scrw/7 宽、scrw/11 高以及 3dp/1dp 上下边距 | 未修复，尺寸差异 |
| F03 | 注册页只校验密码后进入与登录相同的分区流程，不执行安卓注册流程，且缺少手机号/邮箱。 | AndroidEntryView.swift:85、90；GameModel.login | logind.java:509 的 checkreg 校验这些字段并调用注册接口 | 未完整移植；本轮未调用原注册服务 |
| F04 | voice: 链接被丢弃；“发送语音”动作没有安卓录音入口的特殊处理。 | MudRichText.swift:27 只允许 mudcmd 或 HTTP(S)；GameModel.act 无录音分支 | main/myUSpan.java:25；mudmaind.java:442 附近的录音面板逻辑 | 未移植 |
| F05 | ESC024 战斗浮动文字变成普通通知，缺少原有位置、放大、位移和渐隐。 | GameModel.swift:326 将其写入 notice；AndroidWorldView 的通知面板 | mudmaind.java:792 创建 text3d 并配置动画 | 未移植 |
| F06 | 属性条最后一行不足列数时，iOS 留空格；安卓实际行内控件按权重占满。另外 iOS 有 16pt 最小高度，安卓使用服务器给出的 scrw/高度参数。 | AndroidWorldView.swift:340 的 LazyVGrid 和 max(16,...) | mudmaind.java:650 后 ESC012 逐行创建 LinearLayout、按实际条目分配 weight | 未修复；现有测试只测整行数据 |
| F07 | 普通方向和上/下方向更新到同一方向位置时，旧项可能继续显示。例：先 north 后 northup，iOS 保存两个 slot，视图 first 取旧项。 | GameModel.swift:279；AndroidWorldView.swift:267 附近的 first 查找 | mudmaind.java 的 takeexit 对 north/northup/northdown 更新同一个 n_exit | 未修复，依赖服务器更新序列 |
| F08 | 富文本状态范围不同：iOS 每段文本重新初始化颜色/链接/字号；安卓静态 span 状态保留到重置，跨消息或片段可能呈现不同。 | MudRichText.swift:43 开始的局部状态 | mudmaind.java:66-86 静态 span 状态和 takespan 的重置分支 | 源码差异已确认；真实会话影响需专项回放 |

## 条件性差异和不能贸然修改的部分

- 奖励图：iOS 始终显示 icon.jpeg，安卓尝试 assets/item/<image>.png，失败后才回退图标。当前参考源码目录没有 assets，不能据此断言现用 APK 一定显示了其他物品图；需确认实际 APK 资源覆盖再移植。
- 三段血条：安卓有 A/B/C 层，当前 iOS 只有一个比例；但参考 attrbarx.xml 的 B/C 初始透明，longitemd/attrbar 中还存在占位实现。不能仅凭层数断言当前 APK 肉眼显示不同，也不能随意添加颜色。
- 同名属性条和同命令弹出项使用内容充当 SwiftUI identity，存在冲突风险；尚无专门的运行测试。
- 原安卓分区请求已被改成本地列表，不能把“未调用原远程分区 API”本身认定为本地 APK 缺陷；列表布局与所有交互仍未完整验收。

## 已有验证证明什么

- 构建 11 的 19 项逻辑测试、iPhone 和 iPad 各 7 项 UI 测试通过。
- 上轮留存 30 张 iOS 截图及安卓手机/平板常用、背包、物品、人物、NPC 对照截图。
- 这些验证覆盖共享样例及特定尺寸断言，不能证明所有服务器生成的页面都一致。
- Tests/GameModelTests.swift 使用 RecordingTransport；其中“登录成功/失败重试”是状态机模拟，并非本轮真实 TCP 认证。
- Tests/MudProtocolTests.swift 的历史会话和分包测试证明特定输入的解码行为，不等于当前服务器端到端可用。
- 本轮没有修改应用代码，因此未重复触发收费风险或消耗新的云端编译额度；上轮运行结果不可改称本轮新测试结果。

## 仍缺的验收

- iPhone/iPad 实际签名安装、当前服务器登录、创建角色、断线/重连/切服后的持续游戏。
- 横屏和旋转、长描述/长按钮文字、所有昼夜模式、按下状态、字体行高/换行/安全区的逐项运行对照。
- 重复命令/同名条目、不同方向更新顺序、属性条不完整末行、超长列表和协议边界数据。
- 完整语音流程、注册服务、战斗动画以及有效物品资源的运行对照。

以上缺口关闭前，构建 11 只能称为已修正部分主要界面的测试版，不能称为全部无问题或完整一比一复刻版。
