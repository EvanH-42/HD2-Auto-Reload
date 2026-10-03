# P1 / P1+P2 对照交付

日期：2026-10-03。仅 tactical 输入版；不加入 Fire Guard。未提交、推送或部署；实机验收待完成。

## 两份安装包

| 包（build/ 下） | 内容 | START 标识 |
|---|---|---|
| Auto-Reload-v0.7.0-tactical-p1-perf.zip | P0 统计 + P1 缓存，前台仍每 update 采样 | optimization_stage=1 perf=true |
| Auto-Reload-v0.7.0-tactical-p2-perf.zip | P0 统计 + P1 缓存 + P2 固定采样 | optimization_stage=2 perf=true |

两份包沿用原 GUID，只能替换安装其中一份，替换后需重启游戏。普通构建的统计仍默认关闭；P1/P2 构建自动开启统计，无需额外 --perf。未更改系统 PATH。

```powershell
python scripts/build.py --enable-tactical-reload --optimization-stage p1
python scripts/build.py --enable-tactical-reload --optimization-stage p2
```

## 实现与统计口径

P1 从成功的完整读取收集依赖，缓存已解析的组件与配置。快速路径通过 api.read 合并同页、间隙不超过 32 字节的依赖读取；保留全部静态依赖内容比较、完整 map 内容验证和原 guard 第二遍复读。变化、短读、异常或无效动态值使缓存失效，每次采样最多一次完整回退。完整读取器及普通/续装两条发送前完整复核保留。批量读取可能增加请求字节数；读取次数下降不意味着字节数同比下降。

P2 仅调度日常采样：QPC 累计期限实现前台 120 Hz、后台 20 Hz；每 update 最多一次，长帧不补采。输入探测、松键、策略和原回调仍每 update 执行，控制器仍用原毫秒时钟。失焦/恢复重建上下文，未采样不刷新 latest_at。发送前完整复核发现弹药变化时，重新执行原优先级一次，避免旧的“两发”续装压过新的一发请求；此处理有界，不新增策略规则。

PERF 每 10 秒累计汇总 initialization、periodic、reload_refresh、continuous_refresh、other 五类。新增 full_readers、fast_readers、cache_hits、cache_invalidations、cache_builds；最后失效原因保存在 state.last_cache_invalidation，不逐帧写日志。read_attempts/requested_bytes 统计实际 API 请求，包含失败及回退。guard_rereads 与 map_reads/map_bytes 为逻辑依赖块，合并后不能当作物理 API 调用数；reader_attempts 包含失效的快速读取和完整回退，所以不等于采样次数。

## 离线测量

同一模拟内存/输入轨迹，10 秒，三次批量耗时取中位数，覆盖 Magazine/Rounds/Heat、60/120/144/240/360 FPS 和统计开/关。轨迹包含失焦、读取失败与换弹复核。所有数据是模拟结果，无游戏内 CPU/FPS 数据。

240 FPS、统计启用时：

| 类型 | P0 读取调用 | P1 读取调用 | P1+P2 读取调用 | P0 / P1 / P2 批量秒数 |
|---|---:|---:|---:|---|
| Magazine | 224143 | 154738 | 83196 | 0.363989 / 0.120784 / 0.081044 |
| Rounds | 212636 | 147711 | 76240 | 0.192744 / 0.097006 / 0.076850 |
| Heat | 206699 | 146284 | 74698 | 0.137721 / 0.101662 / 0.047141 |

P1 总调用下降约 30%；P1+P2 相对 P0 下降约 63%–64%。P1 每类仍采样 2287 次，P2 为 1153 次。P1 Magazine 请求字节由 24146479 增至 24205149；P2 为 12729300。离线耗时受 JIT、夹具和调度噪声影响，不能直接推算实机收益。

| FPS | P0/P1 日常采样次数 | P2 日常采样次数 |
|---:|---:|---:|
| 60 | 578 | 582 |
| 120 | 1147 | 1152 |
| 144 | 1375 | 1150 |
| 240 | 2287 | 1153 |
| 360 | 3428 | 1153 |

上表含失焦，不能除以总时长后要求始终 120 Hz。独立全前台调度测试验证高帧率 10 秒约 1200 次、低帧率受 update 限制；后台 20 Hz，无长帧补采。发送复核不受 120 Hz 限制，因此总读取成本仍可能随输入/重试次数变化。P2 的失败/被松键抑制的复核次数可以变化；相同轨迹中接受请求的次数和原因通过对照。

原始 CSV（Git 忽略目录）：build/benchmark-p0.csv、benchmark-p1.csv、benchmark-p2.csv。在仓库根目录复现：

```powershell
foreach ($stage in @('p0','p1','p2')) {
    python scripts/build.py --enable-tactical-reload --perf --optimization-stage $stage
    & .\tools\luajit-source\src\luajit.exe scripts/benchmark.lua 10 3 $stage |
        Set-Content -LiteralPath "build/benchmark-$stage.csv" -Encoding utf8
}
```

## 检查与实机待办

Python 11 项通过；原控制器 62 项及 map/context/read_api 检查通过，Windows 初始化的 existing-declaration、perf、p2 模式通过。P0 统计开关的 15 组弹药/FPS 行为对照通过。新增 test_optimization.lua 验证完整/快速 row 与请求一致、13 类失效及中途切槽、120 Hz/20 Hz、长帧、焦点与 row 新鲜度、每 update 输入/松键/原回调，以及 10 秒高帧率接受请求次数/原因和延迟上限。两份 ZIP 的 GUID、开关、payload 与独立保留检查通过。

120 Hz 会增加最多一个采样间隔约 8.33 ms 的发现等待，加上 update 帧量化；不保证捕获不足一个间隔的 count==1。未声称高射速实机完全等价或最后一发受保护。

实机对照步骤：

1. 先安装 P1，重启游戏；确认 START 的 stage=1、perf=true、tactical_reload=true、no_native_calls=true。使用固定游戏版本、场景、武器与帧率，运行至少 30 秒，保存 START、PERF、请求/恢复日志。
2. 替换为 P1+P2，重启；确认 stage=2，其余开关相同，重复同一场景。日志位置为 `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/AutoReloadRounds.log`；每次测试后单独保存，避免混用累计计数。
3. 对累计 PERF 作区间差值，比较每秒读取量、日常 full/fast、缓存失效、普通/续装复核与请求/恢复。核验自动及半自动、逐发续装、attack-only、Heat、切枪、重生、手动 R、失焦/恢复；特别观察高速射击与快速连点是否漏触发。
4. 记录游戏版本、实际 FPS、武器、测试时长及异常。包发送输入成功不等于游戏完成换弹；MG-43 原有稳定性限制尚未解决。实机状态明确后再进行独立 P3。
