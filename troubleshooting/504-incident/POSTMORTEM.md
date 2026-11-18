# 故障复盘：设备并发上报导致数据大屏频繁 504

> 来源：AIRIOT 物联网智慧能源管理平台（简历项目一）
> 严重级别：SEV-2 · 影响：数据大屏部分实时曲线加载失败 · 状态：已解决

## 摘要

工业物联网平台，设备高频并发上报数据。运营侧反馈"数据大屏实时曲线频繁转圈、偶发 504"。
根因是大屏实时接口的数据库查询缺少支撑索引，在设备并发上报时发生全表扫描 + 文件排序，
响应从正常的百毫秒级恶化到 3.5s，超过 Nginx 60s 读超时后返回 504。
通过 Nginx access log 定位接口 → 慢查询日志 + EXPLAIN 定位失效索引 →
上线联合索引止血 → TDengine 时序双写治本。接口响应 3.5s→800ms，504 恢复时间 2h→20min，慢查询 -99%。

## 排查时间线（证据链）

| 步骤 | 动作 | 证据 / 工具 | 发现 |
|------|------|-------------|------|
| 1 | 确认现象范围 | Grafana + Nginx 监控 | 仅 `/api/dashboard/realtime` 异常，其它接口正常 |
| 2 | 定位高频慢接口 | `analyze_nginx_log.py` 分析 access log | 该接口 5xx 占比 38.6%，p95 upstream 4.3s |
| 3 | 定位慢 SQL | MySQL slow query log | 同一条聚合查询反复出现，Rows_examined 极高 |
| 4 | 分析执行计划 | `EXPLAIN`（fix_indexes.sql 步骤 1） | `type=ALL` 全表扫描 + `Using filesort` |
| 5 | 根因确认 | 表结构核对 | `device_id + reported_at` 无联合索引 |
| 6 | 止血 | `ADD INDEX idx_device_time` | 查询计划变 `type=range`，响应降至 800ms |
| 7 | 治本 | TDengine 双写迁移 | 时序查询慢查询减少 99% |

## 根因（5 Why）

1. 为什么 504？→ 上游接口响应超过 Nginx `proxy_read_timeout`。
2. 为什么响应慢？→ 大屏聚合查询扫全表 + 临时表排序。
3. 为什么全表扫描？→ `device_id + reported_at` 查询没有支撑索引。
4. 为什么没索引？→ 早期数据量小，问题未暴露；上线后设备规模增长未同步做索引评审。
5. **根本原因**：缺少「数据量增长 → 查询模式变化 → 索引/存储选型评审」的机制。索引修复是止血，
   把时序数据迁到 TDengine 才是治本。

## 修复

- **止血（分钟级）**：`ALTER TABLE ... ADD INDEX idx_device_time (device_id, reported_at)`；
  联合索引列顺序遵循最左前缀——等值列 device_id 在前，范围列 reported_at 在后。
- **治本（周级）**：TDengine 时序双写迁移，见 [`TDENGINE_DUAL_WRITE.md`](TDENGINE_DUAL_WRITE.md)。
- **配置兜底**：Nginx `proxy_read_timeout` 从默认调到 60s，并加 keepalive 连接池
  （见 `middleware/nginx/nginx.conf`），避免偶发慢请求直接 504。

## 效果

| 指标 | 修复前 | 修复后 |
|------|--------|--------|
| 接口响应 | 3.5s | 800ms |
| 504 恢复时间 | 2 小时 | 20 分钟 |
| 慢查询数量 | 基线 | -99% |
| 大屏可用性 | 波动 | 99.9% |

## 在本仓库中复现

```bash
cd troubleshooting/504-incident

# 步骤 2：分析 access log 定位高频 504 接口
python analyze_nginx_log.py --log sample_access.log

# 步骤 4/6：用 SQLite 复现 全表扫描 vs 联合索引 的真实性能差异
python setup_db.py --out reports.db --rows 300000
python benchmark.py --db reports.db --runs 5
# 预期：SCAN ~47ms -> SEARCH USING INDEX ~6ms（约 8x）
```

> **面试讲解提示**：这条案例的价值在于完整证据链——从日志到 SQL 到执行计划到索引，
> 每一步都有据可查；并且区分了「止血（加索引）」和「治本（换存储）」，体现故障处理的优先级判断。
