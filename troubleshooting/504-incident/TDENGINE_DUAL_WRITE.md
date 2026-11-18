# 时序数据双写迁移策略（TDengine）

对应简历：「针对时序数据设计双写策略迁移至 TDengine，慢查询减少 99%」。

## 背景

`device_reports` 是典型时序数据：高写入（设备并发上报）、按时间范围查询、极少更新。
MySQL 的 B+ 树索引在大时间范围聚合上成本高、磁盘占用大。TDengine 针对时序场景做了
按设备分表、时间分区、列式存储，查询同类问题快一个数量级。

## 双写迁移三阶段（不停机）

```
阶段 1  影子写入          阶段 2  双写 + 校验           阶段 3  切读 + 下线
─────────────────      ───────────────────        ───────────────────
MySQL  ← 主写            MySQL  ← 写               MySQL  ← 停止写
                        TDengine ← 同步写          TDengine ← 唯一写
读走 MySQL              读仍走 MySQL               读切到 TDengine
                        + 定时对账 job
```

**阶段 1 — 影子写入**：应用先只写 MySQL，但把写请求异步镜像到 TDengine（不读），
观察 TDengine 写入延迟和成功率，确认链路稳定。

**阶段 2 — 双写 + 对账**：
- 同步写 MySQL（保底），异步写 TDengine（削峰，失败进重试队列）
- 每小时跑一次对账 job：按 device_id + 时间窗口对比两边条数和聚合值
- 连续 7 天对账无差异，进入阶段 3

**阶段 3 — 切读 + 下线**：
- 大屏查询切到 TDengine，MySQL 保留只读兜底 2 周
- 确认无回归后，TDengine 成为唯一写入目标，MySQL 侧归档

## 关键设计点（面试可讲）

1. **异步解耦**：TDengine 写入走消息队列，避免拖慢主链路；失败可重放。
2. **对账 job**：双写期间数据一致性靠对账证明，而不是"写完就切"。
3. **可回滚**：任何阶段发现问题，把读切回 MySQL 即可，零数据丢失。
4. **为什么先修索引再迁移**：加联合索引（见 fix_indexes.sql）几小时内止血，
   迁移是治本的长期方案——**先止血、再治本**，体现故障处理的优先级判断。

## TDengine 建表示意

```sql
CREATE DATABASE iot KEEP 365 DURATION 10;
USE iot;
CREATE STABLE device_reports (
    ts TIMESTAMP,
    metric_value FLOAT
) TAGS (device_id BINARY(64), metric_name BINARY(64));

-- 查询某设备某时间窗（自动按设备分表，无需手写索引）
SELECT AVG(metric_value) FROM device_reports
WHERE device_id = 'device-0500' AND ts >= '2026-04-01 00:00:00'
INTERVAL(1m);
```
