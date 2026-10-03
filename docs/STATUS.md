# 性能优化状态与交接

更新时间：2026-10-04（Asia/Taipei）

## 当前结论

P0–P3 优化已完成。2026-10-04 用户反馈 P3 实机正常运行，并据此确认 P1/P2 状态正常；三阶段验收关闭，未获得量化实机 CPU/FPS 数据。P0–P2 已提交 `00b44da`；P3 源码、测试和验收文档列入本次收尾提交并同步 origin/main。保留三份已验收 ZIP、回归所需 Lua 与测量证据，清理冗余构建变体和重复日志。目标见 [PERFORMANCE_PLAN.md](PERFORMANCE_PLAN.md)，P0 口径见 [PERFORMANCE_P0.md](PERFORMANCE_P0.md)，第一步说明见 [PERFORMANCE_P1_P2.md](PERFORMANCE_P1_P2.md)，P3 策略与数据见 [PERFORMANCE_P3.md](PERFORMANCE_P3.md)。

## 授权与范围

- 用户确认：性能优化止于 P3，分为 P0–P2 与 P3 两步。
- 使用 tactical 输入构建，保持原有规则与功能，不加入 Fire Guard。
- 用户已确认实施首步 P0 方案，允许找不到现有 LuaJIT 时使用项目本地工具；未改系统 PATH。
- 后续授权持续推进到 P2，保留 P1 与 P1+P2 两份默认开启统计的包供实机比较。
- 用户已授权本次收尾清理、提交并推送 GitHub；目标为自己的 fork origin/main，不向 upstream 推送，不创建发行版或自动部署游戏。
- P4–P6 不在范围内。P1 必要缓存有效性检查不能被误解为可删掉完整 guards。

## 仓库基线

- 本地：`D:/Coding_Projects/hd2-mods/auto-reload`
- 分支：`main`，开始本轮时工作区干净。
- HEAD：`f4c809380ca72ed5150b08a945774647e96aa2de`
- origin：`https://github.com/EvanH624/HD2-Auto-Reload.git`
- upstream：`https://github.com/1264600905/HD2-Auto-Reload.git`
- 源码版本：`0.7.0`；README 声明布局支持 builds `25327279/25480438`，本轮未对本机游戏版本作验证。
- 未发现仓库内 AGENTS.md；遵循本聊天用户提供的全局 AGENTS.md。

## 已完成工作

1. 上一轮已创建 fork、直接 clone 到当前目录并配置 upstream。
2. 本轮重新读取引用对话的最后一轮，提取 P0–P3 方向及“不改功能”的约束。
3. 核对 README、build.py、完整 context_reader、静态组件验证、snapshot/update、发送前复核、输入与控制器关键路径，以及现有测试入口。
4. 创建并更新计划与交接文档。
5. 只读搜索未找到已有 LuaJIT；在忽略的 tools/luajit-source 内下载官方源码并用已有 MSVC x64 编译，版本 2.1.1788856981，源码提交 c6ffc141a8762b41703f9287d63d93622a13dd8f。
6. 加入 --perf 开关、runtime 统计及 map/guard 计数；保留初始化、日常、普通和续装完整复核，另列 other 读取。
7. 添加完整 update 的模拟内存/输入夹具、统计开关行为对照、失败/身份/map/汇总测试，以及 scripts/benchmark.lua。README 补充入口，PERFORMANCE_P0.md 记录口径与实测摘要。
8. P1 收集完整依赖，缓存解析结果并合并同页读取；所有静态 map/config 内容与 guards 仍验证，失效最多一次完整回退。两条发送前完整复核保留。
9. P2 用 QPC 累计期限调度日常读取；输入、松键、原回调仍每 update。完整复核发现弹药变化时有界重跑原策略，保留最后一发优先级。
10. 新增 --optimization-stage p0/p1/p2；P1/P2 要求 tactical 输入模式并自动启用 PERF，保留独立 ZIP。新增缓存/调度回归，生成三个阶段同轨迹 CSV。
11. 提交 P0–P2：`00b44da00a000f599b3c995ace3b261682461f5b`。提交作者采用核验的 GitHub 登录身份与 noreply 邮箱，仅命令级设置，未改全局配置。
12. P3 稳定空闲 30/60 Hz，活动及不确定状态 120 Hz，边沿立即观察且保留 P2 高频相位；最大观察扣弹裕量、无输入扣弹保护、稳定期/重置和各档实际采样统计已实现。
13. P3 回归包含三类弹药/五帧率、零/总弹阈值、未知/attack-only、自动/快速点击/抖动、多发骤降、失败/恢复/焦点/时钟和统计开关。Python 优化产物测试改用临时源码副本，保护已交付 P1/P2。

## 阶段状态

| 项目 | 实施 | 自动验证/测量 | 实机验收 |
|---|---|---|---|
| 目标与计划 | 已完成 | 文档检查 | 不适用 |
| P0 基线/统计 | 已完成 | 已通过，离线测量已生成 | 未测量/未验收 |
| P1 快速上下文缓存 | 已完成 | 已通过，离线测量已生成 | 用户确认正常（依据 P3 验收） |
| P2 固定 120 Hz | 已完成 | 已通过，离线测量已生成 | 用户确认正常（依据 P3 验收） |
| 第一步 P0–P2 交付 | 已完成 | P1/P1+P2 两份包保留 | 用户确认通过 |
| P3 自适应采样 | 已完成 | 已通过，四场景 P2/P3 测量已生成 | 用户实机测试通过，正常运行 |

已有同夹具 P0/P1/P2 读取量与批量耗时，无游戏内 CPU/FPS 改善数据。240 FPS 下 P1 调用量下降约 30%，P1+P2 下降约 63%–64%；仅为模拟结果。

## 下一步执行顺序

1. 本轮至 P3 收尾，不继续 P4–P6。
2. 后续仅根据新反馈处理问题；保留的三个包一次只装一个。用户验收不代表已量化实机性能，也不代表原生实验版或 MG-43 历史问题得到专项验收。

## 交接时不能遗漏的风险

- P1 缓存依赖来自完整读取第一遍，全部静态字节及原 guard 第二遍保留；不要删除这些检查来提高收益。
- 配置 override 和 map 原地变化也会失效；批量读取可能多请求少量 gap 字节，失败安全回退。
- 固定频率会引入检测延迟；朴素 now+interval 会降低实际频率，高射速短暂 count==1 可能漏采。
- 不采样时 latest_at 不更新；输入边沿和 R 释放仍每 update 处理。
- P3 不以“已发 R”当作“正在换弹”，未知状态保持高频，attack-only 和续装不能因降频丢重试。
- 新增完整 update 的模拟验证已通过；夹具覆盖不能替代游戏中的对象生命周期和输入验收。
- 离线 fixture/包检查不等于实机接受；MG-43 原有稳定性限制仍在。

## 本轮验证与提交

修改前默认构建成功、Python 7 项通过；四个 Lua 文件通过，其中控制器 62 项通过。最终 Python 11 项通过，检查全部 8 种 tactical/debug/perf 组合、P1/P2 的隐式统计与独立产物、GUID/ZIP/payload，以及 native 校验不能被 perf 绕过。

四个既有 Lua 文件继续通过，Windows API 初始化 existing-declaration、perf/QPC 和 p2/poll_now 场景通过。test_perf.lua 的 15 组弹药/FPS 对照及失败/guard/map/汇总检查通过；P0 关闭统计无性能时钟调用。test_optimization.lua 的 P1 行/请求对照、13 类失效、中途变化、P2 调度/焦点/长帧/每帧输入回调、10 秒接受请求原因/次数及延迟上限检查通过。P2 使用独立采样时钟，即使离线关闭统计仍需调度计时。

已运行的主要入口（仓库根目录，工具用绝对路径调用）：

```powershell
python scripts/build.py
python scripts/build.py --enable-tactical-reload --perf
python -m unittest discover -s tests -p 'test_*.py'
luajit tests/test_auto_reload.lua
luajit tests/test_auto_reload_maps.lua
luajit tests/test_context.lua
luajit tests/test_read_api.lua
luajit tests/test_read_api.lua existing-declaration
luajit tests/test_read_api.lua perf
luajit tests/test_read_api.lua p2
luajit tests/test_perf.lua
luajit tests/test_optimization.lua
python scripts/build.py --enable-tactical-reload --optimization-stage p1
python scripts/build.py --enable-tactical-reload --optimization-stage p2
luajit scripts/benchmark.lua 10 3 p0
luajit scripts/benchmark.lua 10 3 p1
luajit scripts/benchmark.lua 10 3 p2
git diff --check
```

Python 实际路径：%LOCALAPPDATA%/Programs/Python/Python313/python.exe，版本 3.13.14。LuaJIT 实际路径：tools/luajit-source/src/luajit.exe。benchmark-p0.csv、benchmark-p1.csv、benchmark-p2.csv 保存在忽略的 build/；复现及测量限制见 PERFORMANCE_P1_P2.md。

本次交付：build/Auto-Reload-v0.7.0-tactical-p1-perf.zip 与 build/Auto-Reload-v0.7.0-tactical-p2-perf.zip，两个文件同时保留。模拟 10 秒、240 FPS 的 Magazine/Rounds/Heat：P0 读取 224143/212636/206699 次，P1 154738/147711/146284 次，P2 83196/76240/74698 次；含初始化与发送复核。三类日常采样 P0/P1 为 2287 次，P2 为 1153 次，含失焦。

UTF-8/空白格式和 Git 差异检查在交付前完成。P0–P2 已提交；P3 纳入本次收尾提交。2026-10-04 用户确认正常，未自动部署游戏。

保留的安装包位于 Git 忽略的 build/，不将生成二进制加入源码提交。P1 SHA256：`BEBAD72071D893414C8650260876F3F86037CDC7518EC43A1F5C7EDC5EFECB8A`；P2 SHA256：`3162AA3B8E29252AF4DBD7416B1B7A60C4C9CC71375C0BA5C46B9E922C57888D`。P3 使用独立文件名，不覆盖这两份实机对照包。

## P3 最终验证与产物

Python 11 项通过（含隔离构建 P1/P2/P3、隐式统计、模式限制、ZIP/payload）。原控制器 62 项及 map/context/read_api 检查通过，existing-declaration/perf/p2/p3 Windows API 初始化通过。test_perf.lua、test_optimization.lua 和新增 test_adaptive.lua 全部通过。最后运行已包含多发裕量与跨失败风险记录的最终源码。

命令：`python -m unittest discover -s tests -p 'test_*.py'`；默认及 tactical-perf 构建；`luajit tests/test_adaptive.lua`；全部上列既有 Lua 入口；`luajit tests/test_read_api.lua p3`；`git diff --check`。实际工具仍为上述 Python 与项目本地 LuaJIT，未修改 PATH。

日志：build/validation-p3-python.log、build/validation-p3-test_*.log。四场景测量：`luajit scripts/benchmark.lua 10 3 p2|p3 trajectory|idle_far|idle_near|held_fire`；各 stage/scenario 单独执行，不将竖线作为实际命令。CSV 为 build/benchmark-p2-*.csv 与 build/benchmark-p3-*.csv，各 30 条行。

240 FPS 的稳定远离/邻近 Magazine：P2 1200 次采样、76942 次读取；P3 分别 354/636 次采样、22798/40846 次读取。持续按住时均 1200 次采样、76942 次读取。混合轨迹 P3 1157 次采样，比 P2 1153 多 4 次；此轨迹频繁变化，未降频，额外边沿采样稍增加成本。全部为离线模拟，无实机 CPU/FPS 改善结论。

交付：build/Auto-Reload-v0.7.0-tactical-p3-perf.zip；entry 为 build/auto_reload_entry_tactical_p3_perf.lua。SHA256：`92EB9062AD98E66DAAAAF72D34D60BD3696C38AE3E8B4F49A7AFA60008540168`。P1/P2 两包 SHA256 仍与本次提交记录一致。

## 2026-10-04 收尾

用户实机反馈：P3 可正常运行；用户同时确认 P1/P2 正常。记录为功能验收通过，未推断游戏版本、武器专项覆盖或 CPU/FPS 改善比例。

清理 build/ 内 23 个冗余文件：非阶段安装包、多余 debug/普通生成 Lua、旧的重复 P0/P2 测试日志。保留 P1/P2/P3 三份 ZIP、五份回归必需 Lua、全部 CSV 和最终 validation-p3 日志。三份 ZIP 的 SHA256 均与交付记录一致。tools/ 下本地 LuaJIT 与源码保留，未修改系统 PATH。

本次仅将源码、测试与验收文档提交并同步 GitHub fork 的 main；build/ 仍保持 Git 忽略，安装包本地保留。无新代码修改，因此沿用已完成的 Python/Lua 和用户实机验收证据，收尾只检查差异、编码及保留产物。

后续每步更新本文件的阶段表和此节，附真实命令、结果及必要数据摘要；长期目标与验收口径写在计划文档，当前进度写在这里。
