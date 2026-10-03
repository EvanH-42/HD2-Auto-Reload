# P0 性能统计与离线基线

日期：2026-10-03。P0 只增加可关闭的统计和测量入口，不改变缓存、采样调度或换弹策略。

## 构建与日志

```powershell
python scripts/build.py --enable-tactical-reload --perf
# 可选组合；大量 debug 日志会影响测量，常规测量不加 --debug
python scripts/build.py --enable-tactical-reload --debug --perf
```

普通构建仍默认关闭统计。统计版 `START` 行增加 `perf=true`，安装包以 `-perf` 结尾；GUID 不变，不能与其他 Auto Reload 包同时启用。统计关闭时不创建 state.perf、不调用性能时钟、不做汇总；保留少量开关分支及读取调用封装。

每 10 秒输出一组 5 行 `PERF scope=cumulative`；长帧不补发历史汇总。数字从脚本启动累计，不在汇总后清零。elapsed 从首次 update 计时，updates 为收到的 update 数；这不是游戏渲染 FPS 测量器。日志位于 README 中原有 AutoReloadRounds.log。

类别：

| category | 包含的成本 |
|---|---|
| initialization | setup 的内存读取及首次 snapshot；reader 耗时仅涵盖首次 context_reader |
| periodic | 日常 snapshot 的完整 context_reader |
| reload_refresh | reload_request 发送前完整复核；即使复核拒绝或最终没发送也计入 |
| continuous_refresh | 逐发续装发送前完整复核 |
| other | 上述范围外的 api.read，例如原生实验路径发送时的附加检查；输入版通常为 0 |

计数定义：

- `read_attempts`：实际尝试调用 api.read 的次数；预算拒绝而未调用 api.read 不计入。`requested_bytes` 为请求字节数，包含失败请求，不是成功返回字节数。
- `read_successes` / `read_failures`：完整字符串读取 / nil、短读或抛错。保持原返回值和错误传播。
- `guard_rereads`：已开始的 guard 复读次数；首个不一致即停止，未执行的后续 guards 不计。
- `map_checks`、`map_reads`、`map_bytes`：已开始的完整静态 map 验证、其中块读取次数及请求字节数；它们是总读取的子集，不能再次累加。配置/记录读取包含在总读取中。
- `reader_attempts` / `reader_successes` / `reader_failures`：完整读取器尝试、返回 row、抛错或返回 nil。等待玩家等非可行动 row 也属于 reader_successes。
- `observed_contexts`：返回 context_status=context_observed 的次数；不代表已验证可行动、请求获准或完成换弹，map 不匹配也可能返回该状态。
- `reader_seconds`：Windows QueryPerformanceCounter 测得的累计读取器墙钟秒数，包含启用统计后读取封装的成本；不包含输入、日志输出和完整 update 的所有成本。

运行时数据可从 `LiuAutoReloadRounds.perf.categories` 查看；此字段仅在统计构建存在，是诊断状态，不是游戏行为接口。

## 工具来源与复现命令

未找到现有 LuaJIT；已用本机 Visual Studio 2022 Build Tools 开发环境编译官方源码，未改系统 PATH。

- 来源：[LuaJIT 官方仓库](https://github.com/LuaJIT/LuaJIT)，提交 `c6ffc141a8762b41703f9287d63d93622a13dd8f`。
- 版本：`LuaJIT 2.1.1788856981`，Windows/x64 默认 release 构建。
- 构建方式：Developer PowerShell x64 中运行 `src/msvcbuild.bat`，遵循 [官方安装说明](https://luajit.org/install.html)。
- 实际工具：`D:/Coding_Projects/hd2-mods/auto-reload/tools/luajit-source/src/luajit.exe`；源码、二进制、编译产物位于已忽略的 tools/，未提交。
- Python：`%LOCALAPPDATA%/Programs/Python/Python313/python.exe`，本轮实际版本 `3.13.14`。工具路径和版本仅为本轮记录，后续须重新确认。

在仓库根目录 PowerShell 运行：

```powershell
$pythonTool = Join-Path $env:LOCALAPPDATA 'Programs/Python/Python313/python.exe'
$luaTool = Join-Path (Get-Location) 'tools/luajit-source/src/luajit.exe'
& $pythonTool scripts/build.py
& $pythonTool scripts/build.py --enable-tactical-reload --perf
& $pythonTool -m unittest discover -s tests -p 'test_*.py'
& $luaTool tests/test_auto_reload.lua
& $luaTool tests/test_auto_reload_maps.lua
& $luaTool tests/test_context.lua
& $luaTool tests/test_read_api.lua
& $luaTool tests/test_read_api.lua existing-declaration
& $luaTool tests/test_read_api.lua perf
& $luaTool tests/test_perf.lua
& $luaTool scripts/benchmark.lua 10 3 > build/benchmark-p0.csv
```

运行脚本时检查每条原生命令的 `$LASTEXITCODE`，失败即停止。benchmark 的两个参数是模拟秒数（2–120）与重复次数（1–20，整数）。结果第一行描述环境，第二行为 CSV 表头，其余是数据行；默认 30 行（三类弹药 × 五档 FPS × 统计开关）。

夹具仅替换真实内存/输入后端，运行生成 Lua 的 setup、读取器、snapshot、输入探测、控制器和 update。使用模拟页面与完整静态 map；不打开游戏、不调用 SendInput。内存页面的模拟性能与 ReadProcessMemory 不等价。

每轮同一条两秒重复轨迹包含阈值下降、最后一发、空仓、装填恢复、点击/手动 R、发送失败、松键延后、切槽、失焦/恢复和短读。Rounds 使用 SG-8 的续装规则；Magazine 使用 AR-23；Heat 使用已知 map 中非 attack-only 资源并模拟烧毁。每个实例先预热，重新建立夹具后测量完整轨迹批量耗时，报告多次重复的中位数。计数含初始化，periodic_samples 不含初始化和发送复核。

开启/关闭统计用相同夹具、相同轨迹。批量时间包含夹具更新和日志收集，不是纯 reader 时间；零星快慢和一次耗时差不能作为优化收益结论。

## 2026-10-03 自动结果

- 修改前：Python 7 项通过；四个 Lua 文件通过，其中控制器 62 项通过；Windows API 额外 existing-declaration 场景通过。
- 修改后：Python 9 项通过，覆盖 tactical/debug/perf 全部 8 种组合的开关、GUID、ZIP 与嵌入 Lua payload，以及 perf 不绕过 native 游戏校验。
- 原有四个 Lua 文件继续通过；新增 15 组开关对照的请求日志及模拟输入事件时刻完全一致，关闭统计时性能时钟调用数为 0。
- 失败/短读/抛错、读取中身份变化、静态 map 不匹配的统计检查通过。完整返回的非可行动 row 不被错误标为读取异常。

原始离线输出：`build/benchmark-p0.csv`（忽略的本地文件，10 模拟秒 × 3 次重复）。下表取 perf=true、240 FPS 的一轮计数及批量中位时间；结果含轨迹中的后台时段，故实际日常采样小于 240 Hz。

| 路径 | update | 日常采样 | api.read 尝试 | 请求字节 | map 请求字节 | 普通/续装复核 | 批量中位秒 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Magazine | 2400 | 2287 | 224143 | 24146479 | 20381760 | 93 / 0 | 0.408838 |
| Rounds | 2400 | 2287 | 212636 | 5378786 | 1828800 | 10 / 10 | 0.184559 |
| Heat | 2400 | 2287 | 206699 | 7580441 | 2107488 | 5 / 0 | 0.129667 |

三类路径的读取量随 FPS 明显增长；Magazine 的静态 map 验证占较多请求字节。统计自身有成本，启用版与关闭版计数/行为一致，但模拟耗时不同；本轮尚无游戏内基线或实际 CPU/FPS 收益。

## 人工待办与下一阶段

P0 实机待办：只启用一份 tactical-perf 包、重启游戏；确认 START perf=true 和约每 10 秒的累计统计，按相同武器/场景/FPS 对照无 perf 版，核验原有换弹、续装、点击重试、切槽和焦点行为。没有部署或实机结果时不得宣称完成验收。

P1/P2 尚未实施。它们应沿用本统计口径和夹具，并以本轮 disabled/perf 数据为对照；真正游戏收益仍需实机数据。不得为了提速移除完整复核或越界开展 P4–P6。
