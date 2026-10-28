# DuerOS 控制台配置清单

## 一、配置前确认

1. 后端服务必须能通过公网 HTTPS 访问。
2. Webhook 地址：

```text
https://smart-medicine-box.124.156.137.131.nip.io/api/v1/dueros/skill
```

3. 该方法必须是 `POST`，请求体和响应体都使用 JSON。
4. 该接口不应要求登录令牌，DuerOS 平台请求不会携带 App 的 JWT。

## 二、绑定 Webhook

1. 登录 DuerOS 技能开放平台。
2. 进入“智能药箱”技能配置页。
3. 找到“服务配置”“后端服务”或“Webhook”页面。
4. 服务类型选择自定义服务或 HTTP 服务。
5. 请求地址填写上面的 Webhook URL。
6. 请求方法选择 `POST`。
7. 保存后使用平台自带的接口测试，确认返回 `version=2.0` 的 JSON。

## 三、创建意图和口语样本

在“交互模型”“意图”或“对话模型”页面创建以下意图。名称必须保持一致：

- `TodayMedicineIntent`
- `StockCheckIntent`
- `ExpiryCheckIntent`
- `ConfirmTakenIntent`
- `MedicineInfoIntent`
- `FallbackIntent`

批量导入文件：

```text
D:\smart-medicine-box\backend\examples\dueros_intents.csv
```

如果平台不支持 CSV 导入，就按照 CSV 中的 `intent` 和 `utterance` 两列逐条粘贴。

不要让平台把药品名词槽位作为唯一原文来源。当前后端会同时读取 `query`、`text`、`utterance`、原始文本和槽位值。若平台允许，保留原始语句最稳定。

## 四、配置兜底意图

这是解决“今天吃什么药”被官方闲聊接走的关键步骤。

1. 创建或启用 `FallbackIntent`。
2. 在平台中查找以下同义配置：
   - 系统兜底意图
   - 未匹配意图
   - 未知意图
   - 默认意图
   - 闲聊兜底
   - 未识别语句处理
3. 将这些入口全部指向同一个智能药箱 Webhook。
4. 不要映射到“小度系统闲聊”“系统搜索”或其他官方技能。
5. 如果平台提供“允许系统闲聊”开关，关闭该技能范围内的系统闲聊。
6. 如果平台支持技能优先级，将智能药箱技能优先级调到系统闲聊之前。

## 五、必须完成的音箱验收

在平台调试页和真实音箱上分别执行：

1. 连续说 20 次：

```text
小度小度，打开智能药箱，今天吃什么药
```

2. 每次都应进入自有技能，不允许出现“蒸羊羔、蒸熊掌”等无关回答。
3. 再说：

```text
小度小度，打开智能药箱，今天天气怎么样
```

预期回复应说明只能处理家庭用药问题，而不是进入系统闲聊。

4. 再说：

```text
小度小度，打开智能药箱，库存还剩多少
小度小度，打开智能药箱，哪些药快过期了
小度小度，打开智能药箱，确认服药
```

5. 检查后端日志中的 `dueros_skill_request`，每条日志应包含：

- `request_id`
- `raw_text`
- `platform_intent`
- `final_intent`
- `reply_source`
- `elapsed_ms`

## 六、如何判断问题在哪一层

### 平台没有转发请求

后端没有 `dueros_skill_request` 日志，且音箱出现官方闲聊。

处理：继续检查平台兜底意图和闲聊开关，后端无法拦截未到达 Webhook 的语句。

### 请求到达了后端，但意图错误

后端有日志，`platform_intent` 或 `raw_text` 不正确。

处理：补充口语样本，检查槽位配置和 ASR 错别字样本。

### 请求到达，`final_intent=FallbackIntent`

后端认为该句话不属于药品、库存、有效期、确认服药或说明书范围。

处理：增加对应意图样本，或调整后端意图规则。

### 请求到达但仍出现官方回答

说明该请求没有进入当前技能，或平台在自有技能回复前插入了系统回答。只能通过控制台兜底映射、关闭闲聊和调整技能优先级解决。

## 七、平台不支持兜底时

如果平台不允许把未知语句接入自定义 Webhook，也无法关闭系统闲聊：

- 后端无法单方面修复该问题。
- 只能继续扩充自定义意图覆盖更多语句。
- 或者改用自控设备端对话链路：设备负责唤醒、录音和 TTS，后端负责 ASR、意图和数据查询，绕开平台 NLU。

## 扩充语料包

当前已经整理 300 条自定义口语样本：

- `TodayMedicineIntent`：60 条
- `StockCheckIntent`：50 条
- `ExpiryCheckIntent`：50 条
- `ConfirmTakenIntent`：45 条
- `MedicineInfoIntent`：55 条
- `FallbackIntent`：40 条

文件位置：

```text
D:\smart-medicine-box\backend\examples\dueros_intents.csv
D:\smart-medicine-box\backend\examples\dueros_intents.example.json
D:\smart-medicine-box\backend\examples\dueros_utterances\
```

如果控制台不支持批量导入，请打开 `dueros_utterances` 目录，把每个 TXT 文件中的内容逐行粘贴到对应意图。

注意：新增语料只能提高命中率，不能替代平台兜底映射。只有当平台把未匹配语句转发给 Webhook 时，后端才能拦截官方闲聊。
