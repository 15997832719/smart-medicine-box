# 慧药管家后端

FastAPI + SQLite 后端，提供药品管理、用药提醒、服药记录、库存/过期告警、药物冲突检测，以及基于智谱视觉模型的药品图片识别。

## 启动

```powershell
cd D:\smart-medicine-box\backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

浏览器打开：

- API 文档：http://127.0.0.1:8000/docs
- 健康检查：http://127.0.0.1:8000/api/v1/health

生产默认不会写入演示账号或药品数据。只有明确设置 `SMB_SEED_DEMO_DATA=true` 才会生成演示数据；正式环境保持 `false`。

数据库初始化会记录 `schema_migrations` 版本表并自动执行兼容迁移。升级或维护前可备份/恢复 SQLite：

```bash
python backup_database.py backup backups/smart-medicine-box-$(date +%F).db
python backup_database.py restore backups/smart-medicine-box-2026-01-01.db
```

## 主要接口

- `GET /api/v1/medicines`：药品列表
- `POST /api/v1/medicines`：新增药品
- `PATCH /api/v1/medicines/{id}`：更新药品
- `DELETE /api/v1/medicines/{id}`：删除药品
- `GET /api/v1/reminders`：提醒列表
- `POST /api/v1/reminders`：新增提醒
- `POST /api/v1/intake-logs`：记录一次服药，并自动扣减库存
- `GET /api/v1/alerts`：库存不足和临期/过期提醒
- `POST /api/v1/conflicts/check`：药物冲突检测
- `POST /api/v1/ai/recognize-medicine`：上传药盒图片并识别药品信息（需要配置智谱视觉模型）
- `POST /api/v1/ai/parse-instruction`：使用智谱文本模型提取说明书用法和注意事项
- `GET /api/v1/ai/status`：查看当前账号是否已配置智谱模型（不会返回 API Key）

## 语音意图接口

`POST /api/v1/logs/voice-intent` 支持以下中文意图：

- 今日用药：例如“我今天该吃什么药”
- 库存查询：例如“我的库存还剩多少”
- 有效期查询：例如“哪些药快过期了”
- 确认服药：例如“确认服用阿司匹林”

确认服药优先使用请求中的 `schedule_id`；没有该字段时会按药品名称匹配。若存在多个计划且无法唯一匹配，接口不会写入服药记录，而会要求用户说清药品名称，避免误记。移动端语音识别由手机系统能力提供，系统没有中文识别引擎时可在语音助手页面改用文字输入。

## 本地语音识别（最省费用）

鸿蒙设备无法把 Android `SpeechRecognizer` 转交给本地系统服务时，手机改为录音并上传到 `POST /voice/transcribe`，后端使用本地 `faster-whisper` 转写，不产生按次云服务费用。

推荐模型：

- 2 GB 内存：`tiny` 或 `base` 的 `int8` 模型
- 4 GB 内存及以上：`small` 的 `int8` 模型，中文短句准确率更好

部署示例：

```bash
cd /root/smart-medicine-box-backend
source .venv/bin/activate
pip install -r requirements.txt
export HF_ENDPOINT=https://hf-mirror.com
python - <<'PY'
from faster_whisper import WhisperModel
WhisperModel("base", device="cpu", compute_type="int8", download_root="./models/whisper")
PY
```

环境变量：

```env
SMB_ASR_MODEL=base
SMB_ASR_DEVICE=cpu
SMB_ASR_COMPUTE_TYPE=int8
SMB_ASR_LANGUAGE=zh
SMB_ASR_MODEL_DIR=./models/whisper
SMB_ASR_MAX_UPLOAD_MB=15
```

模型首次下载后可以离线运行；录音文件在转写结束后由后端自动删除。

## 环境变量


## 医学安全与生产安全

- AI 识别结果必须人工核对；置信度低于 0.65 时前端禁止直接保存。系统不能替代医生诊断，处方和剂量以药品说明书及医生指导为准。
- 药品支持记录 `information_source` 和 `source_type`（如包装、说明书、AI 识别），便于追溯。
- 新增药品会写入 `audit_logs` 操作审计表；生产环境应限制审计表访问并定期导出留存。
- API 内置单进程基础限流（每 IP 每分钟 120 次）；多实例部署还应在 Nginx/API 网关配置限流。
- 生产环境必须使用 HTTPS，密钥只放在服务器环境变量或密钥管理服务中，不要提交 `.env`。请设置强随机 `SMB_JWT_SECRET` 和智谱 API Key。
- `SMB_CORS_ORIGINS` 应配置为实际前端域名列表，禁止使用 `*`；数据库应通过定时任务执行备份脚本并将备份复制到独立存储。

可以新建 `.env` 覆盖配置：

```env
SMB_DATABASE_URL=sqlite:///./smart_medicine_box.db
SMB_CORS_ORIGINS=["*"]
SMB_JWT_SECRET=请替换为随机长字符串
SMB_JWT_EXPIRE_MINUTES=43200
SMB_SEED_DEMO_DATA=false
SMB_DUEROS_USER_ID=小度对应的老人账号ID
SMB_ZHIPU_API_KEY=你的智谱 API Key
SMB_ZHIPU_VISION_MODEL=glm-4.6v-flash
SMB_ZHIPU_TEXT_MODEL=glm-4-flash
```

## 用户与家庭账号

- `POST /api/v1/auth/register`：注册老人或家属账号
- `POST /api/v1/auth/login`：登录并获取 Bearer JWT
- `POST /api/v1/auth/generate-bind-code`：老人账号生成 24 小时有效的邀请码
- `POST /api/v1/auth/bind-family`：家属账号绑定老人
- `GET /api/v1/auth/my-family`：查看已绑定的家庭成员

除 `/health`、DuerOS 技能入口外，药品、提醒、服药记录和告警接口都需要：

```text
Authorization: Bearer <access_token>
```

老人只能访问自己的数据；家属只能访问已经绑定的老人数据。旧版本数据库启动时会自动添加所属用户字段，并将旧演示数据归属到演示老人账号。生产环境请设置 `SMB_SEED_DEMO_DATA=false` 并更换 `SMB_JWT_SECRET`。

图片识别会将药盒图片发送给智谱视觉模型；说明书解析会将文本发送给智谱文本模型。模型无法确认时接口会返回 422，不会伪造药品名称或用法。请人工核对结果，并以说明书和医生指导为准。

## 适老化开通与设备管理

- `POST /api/v1/auth/activation/start`：老人端生成 6 位开通码。
- `POST /api/v1/auth/activation/claim`：家属端使用开通码代办开通。
- `POST /api/v1/auth/activation/exchange`：老人设备用设备密钥换取访问令牌。
- `GET /api/v1/auth/devices`：查看当前账号的绑定设备。
- `DELETE /api/v1/auth/devices/{id}`：撤销单台设备。
- `DELETE /api/v1/auth/devices`：撤销全部设备。

## 说明书资料库

导入 JSON 示例：

```powershell
cd D:\smart-medicine-box\backend
.\.venv\Scripts\python.exe import_drug_instructions.py .\examples\drug_instructions.example.json
```

导入官方纯文本或可提取文本的 PDF，必须先完成人工复核，再决定是否使用 `--approve`：

```powershell
.\.venv\Scripts\python.exe import_drug_instructions.py .\official-instructions.txt --source-url "官方页面链接" --source-type nmpa
```

已审核说明书可以通过 `GET /api/v1/instructions/search?q=药品名称` 查询。

## 智能药箱摄像头素材

设备代理使用独立的 `X-Agent-Token` 上传抓拍图和服药录像，家庭 App 使用登录 JWT 访问。相关环境变量：

```env
SMB_DEVICE_AGENT_TOKEN=replace-with-a-random-device-agent-token
SMB_DEVICE_CAMERA_DIR=./data/camera_assets
SMB_DEVICE_CAMERA_MAX_UPLOAD_MB=200
```

家庭账号接口：

- `GET /api/v1/hardware-devices/{device_id}/camera/assets`
- `GET /api/v1/hardware-devices/{device_id}/camera/assets/{asset_id}/file`
- `GET /api/v1/hardware-devices/{device_id}/camera/assets/{asset_id}/thumbnail`
- `PATCH /api/v1/hardware-devices/{device_id}/camera/assets/{asset_id}/review`

设备代理接口：

- `POST /api/v1/device-agent/camera-assets`
- 命令类型新增 `camera_snapshot`，并复用 `intake_record`

素材不会公开静态暴露。视频只是“疑似服药”的辅助证据，App 确认后只更新素材审核状态，不会自动写入真实服药记录。完整部署步骤见 `docs/摄像头服务部署与验证.md`。
## 联网设备事件与播报

设备注册、人脸注册任务、识别事件、近实时摄像头预览、雷达事件、小智状态、SYN6288 播报和 WebSocket 设备通道的接口与验证流程见：

`docs/联网设备与播报联动.md`