# P3 自适应采样交付

实现日期：2026-10-03；验收更新：2026-10-04。基于 P2，只调整日常采样；战术规则、api.read 安全路径、完整 guard/map 验证和两条发送前完整复核保留，不加入 Fire Guard。用户反馈 P3 实机正常运行，并据此确认 P1/P2 正常。本轮至 P3 收尾；未获得量化实机 CPU/FPS 数据。

## 安装包与构建

`build/Auto-Reload-v0.7.0-tactical-p3-perf.zip`：P0 统计 + P1 缓存 + P2 高频调度 + P3 自适应空闲调度。

```powershell
python scripts/build.py --enable-tactical-reload --optimization-stage p3
```

默认启用 PERF，START 应包含 `optimization_stage=3 perf=true tactical_reload=true no_native_calls=true`。GUID 与原包相同，替换安装且重启，一次只运行一份。未自动部署；用户已授权本次源码收尾提交并推送 origin/main。P1/P2 的原 ZIP 和回归所需 entry 文件保留，构建组合测试在临时副本中生成优化包，避免覆盖实机对照版本。

P0–P2 进度已提交：`00b44da00a000f599b3c995ace3b261682461f5b`。仓库没有 Git 作者身份，提交时使用经 gh api user 核验的登录账号 EvanH624 公开姓名和 GitHub noreply 邮箱，仅设置命令级身份，未改全局配置。P3 源码、测试和本次验收更新纳入收尾提交。

## 实际调度

没有可靠的武器射速上限，持续射击不能按平均消耗降频。P3 仅为稳定空闲状态减少读取：

| 状态 | 采样 |
|---|---|
| 后台 | 20 Hz，焦点变化立即重置 |
| LMB/RMB/R 按下、请求后未恢复、战术窗口、最后一发、未知/Heat/attack-only、失效/恢复后未稳定 | 120 Hz |
| 已验证 Magazine/Rounds，已配置且无输入活动/弹药变化至少 0.6 秒，有足够裕量 | 30 Hz |
| 相同空闲条件，较小但足够的裕量 | 60 Hz |
| 近期无观测输入却仍扣弹 | 该武器保持 120 Hz，至身份变化 |

计数沿用 rule.basis，包含 SG-97/GL-15 的膛内总弹。`window=max(limit,1)`、`headroom=count-window`；非正裕量保持 120 Hz。对同武器保存最大观察扣弹量 D，30 Hz 需 `headroom >= max(window,4D)`，60 Hz 需 `headroom >= 2D`。4/2 来自相对于 120 Hz 的采样间隔。D 是保守附加裕量，不是已知射速上限；它只帮助选择无输入活动时的档位。多发突降重置稳定期并扩大裕量，同身份的风险记录跨失败/缓存重建保留。

新 LMB/RMB/R 按下边沿在当前 update 立即采样，持续按下保持高频；高频期限持续沿用 P2 的相位，即使处于低频也维护该期限，额外边沿观察不移动它。档位提升及时生效，降频必须经过稳定期。每 update 最多一次日常采样，长帧不补采；输入探测、松键、控制器和原回调仍每 update 执行，不采样时不更新 latest_at。

身份/槽位、配置/cache 重建、读失败、恢复、焦点与时钟变化均重新建立稳定条件。发送成功不视为换弹动画开始；普通重试与逐发续装仍使用原间隔和完整复核。

## 统计与模拟测量

五类累计 PERF 仍每 10 秒汇总。periodic 新增 `poll_20_samples/poll_30_samples/poll_60_samples/poll_120_samples`，总和为实际日常采样次数；`poll_immediate_samples` 是其中由输入边沿触发的子集，可能与正常到期重叠，不可另加到总数上。完整失败回退和发送复核分别记账。关闭统计时不测量性能耗时；P3 调度仍须使用 QPC。

同夹具、10 秒、三次批量计时取中位数、60/120/144/240/360 FPS、统计开/关。四场景为：混合操作轨迹、稳定远离阈值、稳定邻近阈值、持续按住射击键。后者保持弹药不变，主要检查输入是否阻止降频；真实快速扣弹另由回归轨迹覆盖。

240 FPS、统计启用，读取调用包含初始化与复核：

| 场景/类型 | P2 采样 | P3 采样 | P2 读取 | P3 读取 |
|---|---:|---:|---:|---:|
| 稳定远离 / Magazine | 1200 | 354 | 76942 | 22798 |
| 稳定远离 / Rounds | 1200 | 354 | 76938 | 22794 |
| 稳定邻近 / Magazine | 1200 | 636 | 76942 | 40846 |
| 稳定邻近 / Rounds | 1200 | 636 | 76938 | 40842 |
| 持续按住 / Magazine | 1200 | 1200 | 76942 | 76942 |
| 稳定或按住 / Heat | 1200 | 1200 | 76934 | 76934 |
| 混合轨迹 / Magazine | 1153 | 1157 | 83196 | 83452 |
| 混合轨迹 / Rounds | 1153 | 1157 | 76240 | 76496 |
| 混合轨迹 / Heat | 1153 | 1157 | 74698 | 74954 |

远离/邻近空闲场景相对 P2 调用下降约 70%/47%，含最初 0.6 秒的 120 Hz 稳定期。混合轨迹频繁改变弹药、输入、身份，未达到降频条件；额外边沿采样略增加调用，因此不能声称所有场景都有收益。P3 自适应判断增加开销，读取量下降不保证批量耗时或游戏 CPU 同比下降。全部数据为模拟，实机 CPU/FPS 收益未测。

本次 Magazine 批量秒数（P2 → P3）：稳定远离 `0.020844 → 0.012850`；稳定邻近 `0.024383 → 0.024573`；持续按住 `0.022934 → 0.037675`。Rounds 邻近为 `0.022336 → 0.047249`。可见部分场景模拟耗时反而上升；模拟内存不能反映真实 ReadProcessMemory 成本，不能用这些耗时替代实机验收。

原始 CSV 位于忽略的 build/：`benchmark-p2-{trajectory,idle_far,idle_near,held_fire}.csv` 与对应 `benchmark-p3-*.csv`，各 30 条测量行，保留 QPC 耗时与档位计数。复现不需要重建保留的 P2 包：

```powershell
foreach ($stage in @('p2','p3')) {
    foreach ($scenario in @('trajectory','idle_far','idle_near','held_fire')) {
        & .\tools\luajit-source\src\luajit.exe scripts/benchmark.lua 10 3 $stage $scenario |
            Set-Content -LiteralPath "build/benchmark-$stage-$scenario.csv" -Encoding utf8
    }
}
```

## 验证与实机交接

新增 `tests/test_adaptive.lua` 使用真实 reader/controller/update 与模拟后端：三种弹药、五种 FPS 的 P2/P3 请求次数/原因及触发延迟对照；实际空闲档位；高频相位不移动；立即观察短暂一发；多发扣弹与无输入扣弹回退；总弹口径、零阈值、attack-only、未知规则；自动/快速点击/抖动帧和发送/松键失败；重建、焦点、长帧、时钟倒退；每 update 输入/松键/回调及统计开关一致。Python 构建测试验证 P3 开关、GUID、ZIP payload 和模式限制。原检查继续执行，最终结果与日志入口见 STATUS。

请先用保留的 P2 作对照，再替换 P3 并重启。相同武器与帧率下分别测试：空闲 30 秒、开始射击/快速连点、最后一发与空仓、逐发续装、手动 R、切枪/重生和失焦恢复。按 F8 标记场景，保存 START、PERF、RELOAD_REQUEST 和恢复日志；使用累计计数差值比较每秒成本。

日志：`%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/AutoReloadRounds.log`。检查空闲时出现 30/60 档位、输入后回到 120 Hz、续装未停顿，Heat/attack-only 不降频。

无观测输入的变化可等待最多约 33.33 ms（30 Hz）或 16.67 ms（60 Hz）再被发现，另加 update 帧量化；新点击被探测后立即采样。更改射击绑定或未反映为 LMB 的输入需要实机重点验证。即使 120 Hz 也不保证捕获不足 8.33 ms 的一发状态，不保护最后一发。MG-43 原有稳定性限制仍未解决。自动测试通过不等于实机验收。
