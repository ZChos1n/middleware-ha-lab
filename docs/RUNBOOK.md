# Runbook — 中间件日常运维与故障处理

面向值班工程师，照着做即可。对应简历「编写 5 份运维操作手册及故障排查文档，团队故障定位时间缩短约 50%」。

## 启动整套环境

```bash
docker compose up -d
docker compose ps                 # 确认 16 个服务健康
docker compose logs -f mysql-master
```

## 日常巡检

```bash
bash scripts/inspect.sh                    # 输出主机/CPU/内存/磁盘/端口/容器快照
bash scripts/health_check.sh --url http://127.0.0.1/healthz --retries 3
```

## 一键发布 / 回滚

```bash
bash scripts/deploy.sh v1.2.0              # 原子 symlink 切换 + 健康检查，失败自动回滚
```

## 日志切割（cron 每天 02:00）

```bash
LOG_DIR=/var/log/app bash scripts/logrotate.sh
# crontab: 0 2 * * * LOG_DIR=/var/log/app /opt/scripts/logrotate.sh >> /var/log/logrotate.log 2>&1
```

---

## 故障处理卡片

### 大屏 504（最经典）
1. `python troubleshooting/504-incident/analyze_nginx_log.py --log <access.log>` 找高频 5xx 接口
2. 慢查询日志 + `EXPLAIN` 看是否 `type=ALL` 全表扫描
3. 止血：加联合索引（见 `fix_indexes.sql`）；治本：时序数据迁 TDengine（见 `TDENGINE_DUAL_WRITE.md`）
4. 完整证据链见 [`troubleshooting/504-incident/POSTMORTEM.md`](../troubleshooting/504-incident/POSTMORTEM.md)

### MySQL 主从延迟 > 30s
1. `SHOW SLAVE STATUS\G` 看 `Seconds_Behind_Master`、SQL/IO 线程状态
2. 常见原因：大事务、无主键表、从库性能不足
3. 临时：读流量切主库；长期：拆分大事务、从库加索引

### Redis 内存 > 90%
1. `redis-cli INFO memory` 看 used_memory 与 maxmemory
2. 检查 `maxmemory-policy`（本仓库用 allkeys-lru）
3. 排查 bigkey：`redis-cli --bigkeys`；必要时扩容或清理

### RabbitMQ 消息积压
1. 管理界面 `http://localhost:15672` 看队列 ready 数
2. 检查消费者是否挂掉、是否 ACK 卡住
3. 临时扩容消费者；长期加限流和死信队列

### VIP 漂移失败
1. `ip addr show | grep <VIP>` 确认 VIP 在哪个节点
2. 查 keepalived 日志 `journalctl -u keepalived -f`，看 VRRP 选举
3. 跑 `bash scripts/failover_test.sh` 做主备切换演练

---

## 告警对应表

| 告警 | 含义 | 首要动作 |
|------|------|---------|
| MiddlewareDown | exporter 不可达 | 查容器状态 `docker compose ps` |
| MySQLSlowQueries | 慢查询上升 | 查索引（见 504 案例）|
| MySQLReplicationLag | 主从延迟 | 查 SHOW SLAVE STATUS |
| RedisHighMemory | 内存吃紧 | 查 bigkey / 淘汰策略 |
| RabbitMQQueueBacklog | 消息积压 | 查消费者健康 |
