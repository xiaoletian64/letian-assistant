# 每日综合早报

用户确认：北京时间每天09:30，接收渠道为乐天助手通知。与旧微信/邮件额度速览分开，不改动旧任务。

`morning preview`只生成JSON，不入库、不推送。`morning run`生成当天报告，写入现有owner 1收件箱，再调用现有投递器。同一天以稳定ID去重；关闭daily设置则不创建早报。持久化收件箱可在之后阅读，远程推送仍沿用5分钟有效期、泛化锁屏正文和设备权限。定时器不补发错过的旧早报。

124读取已有额度缓存，通过固定SSH别名`monitor-primary`向106调用`morning sources`。106只读订单SQLite、固定owner 1，只返回汇总和采集覆盖，不传商品、订单号、凭据。未查询114，也未调用模型、官方按量推理端点或新账单API。

额度不跨账户求和。push块优先于聚合镜像；Cursor只有核对相同account_id后才采用结构化聚合字段。保留真实采集时间，超过90分钟、失败、未来异常均不当作当前数据。Codex按返回的window_seconds解释窗口，不按fh字段名猜5小时。MiMo现有缓存的套餐键名与credits文案不能证明单位，显示单位待核验。百分比展示至1位小数，金额保留币种，整数计量保留精确值。

昨日消费按北京时间00:00至次日00:00的paid_at统计；不把created_at当支付时间。父子层级存在歧义时排除并报告数量。金额、币种、支付时间缺失均不能推算为零。只报告已核验时间的局部实付，不声称全平台完整消费；退款未核验则不算净支出。

服务器账单使用可选的私有只读文件`/var/lib/letian-notifications/server-billing.json`，由未来核验过的账单采集器写入。当前未配置该来源。契约为`{"entries":[{"server_id":"106","day":"YYYY-MM-DD","basis":"official_daily_bill","coverage_complete":true,"amount_minor":125,"currency":"CNY","evidence_ref":"private-bill-reference","observed_at":"ISO-8601"}]}`。仅当服务器/日期匹配、唯一完整官方日账单、有私有证据引用、金额为非负整数分、币种明确且观测时间在48小时内，才称实际费用；估算、套餐摊销、余额、部分账单、冲突或缺失均不当作实际费用。各服务器各币种独立列出。证据引用留在私有环境，不传客户端。

客户端共用Flutter正文、每日开关，Android增加daily类型过滤；iOS沿用现有APNs流程。通知正文采用可选择文字，普通列表滚动、返回，不增加模态操作。GET响应有大小预算，避免历史早报超过Android256KiB接收上限；未读总数仍涵盖未返回的旧记录。

验收：Python通知测试、Flutter通知测试、Dart分析、Android单元测试、公开导出扫描。真机推送、iOS构建、正式签名发布分别验证，不能用服务启动或APNs配置冒充手机收到。

部署：将模块及quota_history的collector/history依赖放入既有私有服务目录；先在线备份通知库、备份service/delivery源码，确认当前文件未被其他工作修改，再部署。systemd文件在同目录systemd内。停用：`systemctl disable --now letian-morning.timer`；勿删除历史通知。修改service.py后重启宿主API，避免进程保留旧模块。
