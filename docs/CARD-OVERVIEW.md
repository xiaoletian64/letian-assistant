# 卡片摘要与折叠 PRD / 实现记录

目标：不展开任何业务卡，即可知道需要关注的额度、消费金额或未知原因、已知待发货与运输中数量。折叠明细，不隐藏重点。

首页AI额度、消费、快递三个业务组默认收起。AI摘要最多展示两个来源，保留平台、多账号身份、周期、剩余额度/余额，异常优先，另显示平台数、需关注数量与最早来源时间。Cursor直接来源存在时，其推送来源只留详情，不将其作为另一个余额累计。未知、失败、过期的旧读数不冒充当前值。

消费摘要由鉴权后的既有purchases内容接口overview.expense字段提供，分别标明昨日/近30天、净消费或实付、币种、退款未知、缺少支付时间及覆盖范围。不得从长正文截断或猜测合计。快递来自overview.delivery，已知缓存状态与真实签收/预计到货区别显示；未知不是零。服务端未提供摘要时，旧协议仍能打开完整详情，但首页显示未知，不用正则猜金额。

展开后直接显示账号周期简表、平台消费简表或订单简表，不再嵌套平台折叠。完整记录通过独立按钮进入既有详情页。该详情页仍保留完整数据、图片、退款口径及原文入口。通用内容卡支持summary作为收起摘要，原subtitle/body在展开区完整保留。金额、单位、周期和异常不省略，窄屏和大字体允许换行。

首次进入收起；同一身份的数据刷新保留展开状态；身份切换重建卡片，旧身份响应不会覆盖新身份数据。请求进行中与失败状态保持可见。使用平台ExpansionTile提供按钮、键盘焦点和展开语义，maintainState=false确保收起的明细不参与导航。使用现有Flutter动效及系统减少动画设置。

验证覆盖：多账号不加总；异常旧读数隐藏；消费摘要缺失时为未知；三业务组首次折叠；收起仍看得见金额/周期/状态；刷新保留展开；再次收起隐藏详情；320宽及两倍字号无溢出；首页按授权目录请求消费数据；完整回归及合成截图。Android/iOS实际发布验证另由统一发布记录提供，不能将widget通过当作真机验收。

## Card recovery and notification access

A feature-level 403 clears only that feature's cached data and keeps its error
and retry visible. Other catalog-authorized cards remain available. Retrying a
card requests only its endpoint; a catalog-level denial still clears protected
content, and 401 still signs out. Account switches continue to invalidate late
responses. Missing values remain unknown and summaries stay collapsed.

The home header opens notification permissions, monitoring and the existing
inbox directly. Monitoring remains an explicit user action with a visible stop
control. Android foreground monitoring and iOS APNs require separate acceptance.
The update checker's version must match the packaged pubspec version to avoid
repeatedly offering the currently installed release.

Collapsed quota summaries prioritize available values (low quota first), keeping
up to two account/window values visible. Unavailable sources remain in the
attention count with an explicit unknown-value count, and keep their individual
failure details when expanded. Failed sources cannot crowd all confirmed
remaining values out of the collapsed summary.


Android 9 update compatibility: archive parsing requires both
GET_SIGNING_CERTIFICATES and GET_SIGNATURES to populate signingInfo. Use both
flags while retaining strict package, higher-version and current-signer checks.
An already-installed older client with this parsing defect needs a same-signer
manual covering upgrade to the bridge release; do not uninstall it or describe
that covering install as an in-app OTA success.

## Refresh isolation

Home refresh awaits identity, the authorized catalog and visible business data.
External QR/platform authorization checks load on the account page and do not
hold the home refresh lock. Entering the account page still checks its current
state. A new refresh generation clears obsolete pending indicators; late prior
responses cannot overwrite newer results or a different account. Retrying home
while an authorization source is slow must issue fresh business requests.

## Donut pie and period reset time on the AI quota card (2.13.6)

收起的 AI 额度卡新增两个信息层：环形饼图与最近周期到时间。饼图为各平台"最紧窗口"剩余百分比的归一化对比展示（不同平台配额不同，仅作视觉对比，绝不合计为总配额）；图例逐平台给出剩余百分比与各自的下一次重置时间。认证失败、过期或无剩余百分比的来源不进入饼图，只在"N 个来源无有效剩余百分比"中计数，未确认值不冒充当前值。

周期到时间取结构化 resetAt（epoch 秒或带时区 ISO），来源为 GLM/OpenCode 的窗口重置、Cursor 的 cycle_end、MiMo 的 reset_at；无未来时间时回退最近一次过去重置并保持可见。最近一条以"最近周期到：时间 · 平台 窗口"展示在收起摘要与平台卡副标题，全部为北京时间口径。320 宽与两倍字号不溢出；饼图为 CustomPainter 实现，不新增依赖。
