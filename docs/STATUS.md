# 性能优化状态与交接

更新时间：2026-10-03（Asia/Taipei）

## 当前结论

P0–P2 已实现并完成自动验证和离线测量。交付 P1 与 P1+P2 两份独立 tactical 输入包，均默认启用 P0 统计；P1 保留前台每 update 采样，P2 前台限为 120 Hz。P1/P2 实机状态为测试中，尚未验收；已授权继续 P3。目标见 [PERFORMANCE_PLAN.md](PERFORMANCE_PLAN.md)，P0 口径见 [PERFORMANCE_P0.md](PERFORMANCE_P0.md)，两包对照与人工步骤见 [PERFORMANCE_P1_P2.md](PERFORMANCE_P1_P2.md)。

## 授权与范围

- 用户确认：性能优化止于 P3，分为 P0–P2 与 P3 两步。
- 使用 tactical 输入构建，保持原有规则与功能，不加入 Fire Guard。
- 用户已确认实施首步 P0 方案，允许找不到现有 LuaJIT 时使用项目本地工具；未改系统 PATH。
- 后续授权持续推进到 P2，保留 P1 与 P1+P2 两份默认开启统计的包供实机比较。
- 用户已授权提交当前 P0–P2 进度，并继续 P3 构建和自动验证；未授权推送、发布或游戏部署。
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

## 阶段状态

| 项目 | 实施 | 自动验证/测量 | 实机验收 |
|---|---|---|---|
| 目标与计划 | 已完成 | 文档检查 | 不适用 |
| P0 基线/统计 | 已完成 | 已通过，离线测量已生成 | 未测量/未验收 |
| P1 快速上下文缓存 | 已完成 | 已通过，离线测量已生成 | 测试中，未验收 |
| P2 固定 120 Hz | 已完成 | 已通过，离线测量已生成 | 测试中，未验收 |
| 第一步 P0–P2 交付 | 已完成 | P1/P1+P2 两份包已生成 | 未验收 |
| P3 自适应采样 | 未开始 | 未运行 | 未验收 |

已有同夹具 P0/P1/P2 读取量与批量耗时，无游戏内 CPU/FPS 改善数据。240 FPS 下 P1 调用量下降约 30%，P1+P2 下降约 63%–64%；仅为模拟结果。

## 下一步执行顺序

1. 用户用 P1 和 P1+P2 替换测试，分别重启游戏并保存 START/PERF/请求与恢复日志；一次只装一包。
2. 检查高速射击、快速点击、逐发续装、Heat、切枪、重生和焦点恢复；实机异常先定位。
3. 根据第一步实机状态细化并实施独立 P3；范围仍止于 P3。复用当前本地工具，不重复安装，不自动部署。

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

UTF-8/空白格式和 Git 差异检查在交付前完成。本次授权提交 P0–P2 进度；未推送、未部署，实机仍未验收。

保留的安装包位于 Git 忽略的 build/，不将生成二进制加入源码提交。P1 SHA256：`BEBAD72071D893414C8650260876F3F86037CDC7518EC43A1F5C7EDC5EFECB8A`；P2 SHA256：`3162AA3B8E29252AF4DBD7416B1B7A60C4C9CC71375C0BA5C46B9E922C57888D`。P3 使用独立文件名，不覆盖这两份实机对照包。

后续每步更新本文件的阶段表和此节，附真实命令、结果及必要数据摘要；长期目标与验收口径写在计划文档，当前进度写在这里。
