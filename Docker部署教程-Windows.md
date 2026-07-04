# Docker 部署教程 —— Windows + NVIDIA GPU 全栈 AI 平台

## 简介

本教程是一套**开箱即用的全栈 AI 平台部署方案**，使用 Docker Compose 在 Windows 上一键拉起 9 个容器服务，涵盖从数据存储、推理引擎到前端对话界面、再到生产级监控的完整链路。所有镜像均为离线 `.tar` 包，无需联网拉取，适合内网、研发环境或快速复现。

**你将在 15 分钟内获得：**

- 🔧 **基础设施层**：PostgreSQL + Redis + Qdrant 向量数据库
- 🧠 **AI 推理层**：Ollama（通用 LLM）+ vLLM（高性能推理，支持 NVIDIA GPU）
- 🖥️ **前端交互**：Open WebUI（类 ChatGPT 对话面板）
- 📊 **生产监控**：Prometheus 指标采集 + Alertmanager 告警 + Grafana 可视化面板

**适用人群**：Windows 用户、AI 应用开发者、需要本地离线部署大模型服务的团队。

**前置知识**：熟悉基本命令行操作、了解 Docker/Compose 基本用法。

> **容器总数**：9 个（基础设施 3 + AI 服务 3 + 监控 3）
> **镜像**：`*.tar` 离线包，`docker load` 直接导入，无需联网拉取
> 💡 如果你使用纯 Linux 服务器 → 请查看 `Docker部署教程-Linux.md`

---

## 〇、部署平台选择（二选一）

| 方案 | 适用场景 | 性能 | GPU 支持 | 复杂度 |
|---|---|---|---|---|
| **WSL2**（推荐） | 追求性能、愿意用命令行 | 中等（9P 文件系统有损耗） | ✅ 需装 nvidia-toolkit | 中 |
| **Docker Desktop** | 要 GUI 管理，不想碰 WSL 命令行 | 中等（WSL2/Hyper-V 后端） | ✅ 内置 GPU 支持 | 低 |

### 方案对比速查

| 对比维度 | WSL2 | Docker Desktop |
|---|---|---|
| Docker 安装方式 | `apt install docker.io` | 下载 exe 安装包 |
| daemon 管理 | 手动 `sudo dockerd &` | 自动（系统服务） |
| 路径访问宿主机 | `/mnt/c/` `/mnt/d/` | `D:\` 或 WSL 路径 |
| daemon.json 位置 | `/etc/docker/daemon.json` | 在 Docker Desktop GUI 中编辑 |
| GPU 配置 | 手动安装 nvidia-container-toolkit | Settings → Enable GPU ✅ |
| vLLM UVA | ❌ 需 patch | ❌ 需 patch（WSL2 后端同样） |
| 文件系统 | ext4（推荐） | NTFS（默认） |
| 进入方式 | `wsl -d Ubuntu-24.04` | 直接打开 PowerShell/CMD |

> 💡 **推荐 WSL2**：性能更好，文件系统更稳定，本文主要以此为主线。Docker Desktop 用户请跳到 [附录 B：Docker Desktop 部署](#附录-bdocker-desktop-部署)。

---

## 一、环境与前置条件（WSL2）

| 项 | 详情 |
|---|---|
| 宿主机 | Windows + WSL2（Ubuntu-24.04） |
| Docker | 29+，data-root `/var/lib/docker`（WSL ext4） |
| GPU | NVIDIA GPU + CUDA 13.x |
| nvidia-toolkit | 1.19+ |
| 默认 Runtime | `runc`，GPU 容器显式指定 `runtime: nvidia` |

### 1.1 安装 Docker（WSL 内）

```bash
# 进入 WSL
wsl -d Ubuntu-24.04

# 安装 Docker
sudo apt update && sudo apt install -y docker.io docker-compose-v2
sudo usermod -aG docker $USER
```

### 1.2 安装 NVIDIA Container Toolkit

```bash
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update && sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker

# 验证
nvidia-smi                      # 能看到 GPU
sudo nvidia-ctk --version       # 1.19.x
```

### 1.3 daemon.json（关键配置）

> ⚠️ **不要设 `"default-runtime": "nvidia"`** — 会让 postgres/redis 等非 GPU 容器也走 nvidia runtime 导致崩溃。

```json
{
  "data-root": "/var/lib/docker",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
```

保存到 `/etc/docker/daemon.json`，然后：

```bash
# 启动 dockerd
sudo dockerd &> /tmp/dockerd.log &

# 如果报 exit code 1（旧 PID 残留）
sudo kill $(pgrep dockerd) 2>/dev/null
sudo rm -f /var/run/docker.pid
sudo dockerd &> /tmp/dockerd.log &
```

---

## 二、架构概览

```
┌────────────────────────────────────────────────────────┐
│                     Windows 宿主机                       │
│  :3090(WebUI) :11434(Ollama) :3080(vLLM)               │
│  :5432(PG) :6379(Redis) :6333(Qdrant) :9091(Grafana)  │
│                                                        │
│  ┌─────── llm-net ───────┐  ┌─────── backend ────────┐ │
│  │ ollama :11434         │  │ postgres :5432         │ │
│  │ vllm   :3080          │  │ redis    :6379         │ │
│  │ open-webui :8080      │  │ qdrant   :6333/4       │ │
│  └───────────────────────┘  │ prometheus :9090       │ │
│                              │ alertmanager :9093     │ │
│                              │ grafana :3000          │ │
│                              └────────────────────────┘ │
└────────────────────────────────────────────────────────┘
```

**网络设计**：`llm-net`（AI 推理互访）+ `backend`（基础设施 + 监控），两层隔离。

---

## 三、全部容器清单

### 基础设施（`backend` 网络）

| 服务 | 镜像 | 端口 | 默认凭证 | 用途 |
|---|---|---|---|---|
| PostgreSQL 16 | `postgres:16-alpine` | 5432 | admin/admin123/studio | 关系数据库 |
| Redis 7 | `redis:7-alpine` | 6379 | 无密码 | 缓存/队列 |
| Qdrant | `qdrant/qdrant:latest` | 6333/6334 | — | 向量数据库(RAG) |

### AI 服务（`llm-net` 网络）

| 服务 | 镜像 | 端口 | GPU | 用途 |
|---|---|---|---|---|
| **Ollama** ⭐ | `ollama/ollama:latest` | 11434 | ✅ | **主力**：多模型管理，API 热切换 |
| vLLM | `vllm/vllm-openai:latest` | 3080 | ✅ | 可选：单模型高并发 |
| Open WebUI | `ghcr.io/open-webui/open-webui:main` | 3090 | ❌ | AI 对话界面 |

> ⭐ **Ollama 是主力后端**：多模型并存，API 按名称随时切换，无需重启。vLLM 仅用于单模型高性能场景，非必须。

### 监控（`backend` 网络）

| 服务 | 镜像 | 端口 | 凭证 | 用途 |
|---|---|---|---|---|
| Prometheus | `prom/prometheus:latest` | 9090 | — | 指标采集 |
| Alertmanager | `prom/alertmanager:latest` | 9093 | — | 告警路由 |
| Grafana | `grafana/grafana:latest` | 9091 | admin/admin | 仪表盘 |

### 地址速查

```
Open WebUI     → http://localhost:3090
Ollama API     → http://localhost:11434
vLLM API       → http://localhost:3080/v1
Grafana        → http://localhost:9091    (admin/admin)
PostgreSQL     → localhost:5432           (admin/admin123/studio)
Redis          → localhost:6379
Qdrant HTTP    → http://localhost:6334
Prometheus     → http://localhost:9090
```

---

## 四、快速部署

### WSL2 部署流程

```bash
# 1. 进入 WSL
wsl -d Ubuntu-24.04

# 2. 启动 Docker（WSL2 每次重启后都需要）
sudo dockerd &> /tmp/dockerd.log &

# 3. 进入项目目录
cd /mnt/d/docker-images

# 4. 加载镜像
docker load -i infra-images-latest.tar          # PG + Redis + Qdrant
docker load -i monitoring-images-latest.tar     # Prometheus + Alertmanager + Grafana
docker load -i ollama-latest.tar
docker load -i vllm-openai-latest.tar           # 可选
docker load -i open-webui-main.tar

# 5. 创建网络 + 启动
docker network create backend 2>/dev/null
docker network create llm-net 2>/dev/null
docker compose up -d

# 6. 验证
docker ps
```

### Docker Desktop 部署流程

```powershell
# 1. 确保 Docker Desktop 正在运行（右下角鲸鱼图标绿色）

# 2. 进入项目目录（PowerShell）
cd D:\docker-images

# 3. 加载镜像
docker load -i infra-images-latest.tar
docker load -i monitoring-images-latest.tar
docker load -i ollama-latest.tar
docker load -i vllm-openai-latest.tar          # 可选
docker load -i open-webui-main.tar

# 4. 创建网络 + 启动
docker network create backend 2>$null
docker network create llm-net 2>$null
docker compose up -d

# 5. 验证
docker ps
```

> 💡 PowerShell 中 `2>/dev/null` 需改为 `2>$null`。
> 部署成功后如何对外提供 API？→ 参见 [第九章 对外映射](#九对外映射)。

---

## 五、基础设施部署

> 💡 **网络隔离说明**：基础设施和监控放在 `backend` 网络，与 AI 推理的 `llm-net` 隔离。这样 AI 服务不直接访问数据库/缓存，监控也不暴露给前端调用链。若需要 Grafana 监控 Ollama/vLLM，可给 grafana 容器同时加入两个网络。

### 5.1 PostgreSQL 16

```yaml
postgres:
  image: postgres:16-alpine
  container_name: postgres
  restart: unless-stopped
  environment:
    POSTGRES_USER: admin
    POSTGRES_PASSWORD: admin123
    POSTGRES_DB: studio
  ports:
    - "5432:5432"
  volumes:
    - pgdata:/var/lib/postgresql/data
  networks:
    - backend
```

**验证**：`docker exec -it postgres psql -U admin -d studio`

**常用操作**：

```bash
docker exec postgres pg_dump -U admin studio > backup.sql     # 备份
docker exec -i postgres psql -U admin -d studio < backup.sql  # 恢复
```

> ⚠️ **生产必改密码**：`docker exec -it postgres psql -U admin -c "ALTER USER admin WITH PASSWORD '强密码';"`
> ⚠️ **数据安全**：数据在 Docker volume `pgdata` 中，删容器不丢数据。

### 5.2 Redis 7

```yaml
redis:
  image: redis:7-alpine
  container_name: redis
  restart: unless-stopped
  ports:
    - "6379:6379"
  volumes:
    - redisdata:/data
  networks:
    - backend
```

**验证**：`docker exec redis redis-cli ping` → PONG

> ⚠️ **默认无密码**，公网暴露前加 `command: redis-server --requirepass 密码`。
> 💡 Redis 7 默认 RDB 持久化，重启不丢数据。

### 5.3 Qdrant 向量数据库

```yaml
qdrant:
  image: qdrant/qdrant:latest
  container_name: qdrant
  restart: unless-stopped
  ports:
    - "6333:6333"    # gRPC
    - "6334:6334"    # HTTP REST
  volumes:
    - qdrantdata:/qdrant/storage
  networks:
    - backend
```

**验证**：`curl http://localhost:6334/collections`

> 💡 gRPC(6333) 性能更好适合高频写入，HTTP(6334) 方便调试。

### 5.4 卷（Volume）声明

以上服务引用的命名卷需在 compose 文件底部声明：

```yaml
volumes:
  pgdata:
  redisdata:
  qdrantdata:
  ollamadata:
  webuidata:
  promdata:
  amdata:
  grafanadata:
```

> 💡 Docker 自动管理这些卷的存储路径，删容器不会丢数据。如需绑定到宿主机目录（跨系统共享时有用），改为 `- /mnt/d/data/pg:/var/lib/postgresql/data` 即可。

---

## 六、监控部署

### 6.1 Prometheus

```yaml
prometheus:
  image: prom/prometheus:latest
  container_name: prometheus
  restart: unless-stopped
  ports:
    - "9090:9090"
  volumes:
    - promdata:/prometheus
  networks:
    - backend
```

**验证**：`curl http://localhost:9090`

**最小可用配置**（挂载到 `/etc/prometheus/prometheus.yml`）：

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
```

> 💡 接其他 exporter 时在此文件追加 `scrape_configs` 即可。
> 💡 推荐 Grafana Dashboard：**3662**（Prometheus 自监控）、**1860**（Node Exporter），在 Grafana → Dashboards → Import 里输入 ID 一键导入。

### 6.2 Alertmanager

```yaml
alertmanager:
  image: prom/alertmanager:latest
  container_name: alertmanager
  restart: unless-stopped
  ports:
    - "9093:9093"
  volumes:
    - amdata:/alertmanager
  networks:
    - backend
```

> 💡 告警规则 + 通知渠道（邮件/钉钉/企微）需另配 `alert_rules.yml` 和 `alertmanager.yml`，建议先跑 Grafana 看指标，告警通路按需搭建。

### 6.3 Grafana

```yaml
grafana:
  image: grafana/grafana:latest
  container_name: grafana
  restart: unless-stopped
  depends_on:
    - prometheus
  ports:
    - "9091:3000"
  volumes:
    - grafanadata:/var/lib/grafana
  environment:
    GF_SECURITY_ADMIN_USER: admin
    GF_SECURITY_ADMIN_PASSWORD: admin
  networks:
    - backend
```

**首次配置**：打开 `http://localhost:9091`，admin/admin 登录 → Data Sources → Prometheus → URL 填 `http://prometheus:9090`。

> ⚠️ **生产必改密码**，端口映射 `9091:3000`。

---

## 七、AI 服务部署

### 7.1 Ollama ⭐（主力后端）

**核心优势**：多模型并存，API 调用时按模型名切换，无需重启，自动管理显存。

```yaml
ollama:
  image: ollama/ollama:latest
  container_name: ollama
  restart: unless-stopped
  ports:
    - "11434:11434"
  volumes:
    - ollamadata:/root/.ollama
  networks:
    - llm-net
  runtime: nvidia
  environment:
    - NVIDIA_VISIBLE_DEVICES=all
```

**拉模型**：

```bash
docker exec ollama ollama pull qwen2.5-coder:7b   # 代码 ~4.7GB
docker exec ollama ollama pull qwen2.5:7b          # 中文 ~4.7GB
docker exec ollama ollama pull llama3.1:8b         # 通用 ~4.9GB
docker exec ollama ollama pull qwen2.5:3b          # 轻量 ~2.0GB
docker exec ollama ollama list                      # 查看已安装
```

**API 调用（同一端口，换模型只改 model 字段）**：

```bash
# 代码生成
curl http://localhost:11434/api/generate -d '{"model":"qwen2.5-coder:7b","prompt":"写快速排序","stream":false}'

# 中文对话 — 只改了 model 名，不需要重启任何东西
curl http://localhost:11434/api/generate -d '{"model":"qwen2.5:7b","prompt":"解释量子计算","stream":false}'

# OpenAI 兼容
curl http://localhost:11434/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"model":"qwen2.5-coder:7b","messages":[{"role":"user","content":"你好"}]}'
```

**本地模型导入**：

```bash
cat > /tmp/Modelfile << 'EOF'
FROM /mnt/d/app/LLM/models/huggingface/models/qwen2
EOF
docker cp /tmp/Modelfile ollama:/tmp/Modelfile
docker exec ollama ollama create qwen2-local:1.5b -f /tmp/Modelfile
```

**显存管理**：Ollama 空闲 5 分钟后自动卸载模型释放显存。`docker exec ollama ollama ps` 查看当前加载。

> ⚠️ **国内下载慢** → 配 `HTTPS_PROXY` 代理或用上方本地导入。
> ⚠️ **显存不够** → 不会崩溃，自动卸载旧模型加载新的，仅短暂等待。

### 7.2 vLLM（可选）

> 💡 仅高并发(100+ QPS)场景需要。日常用 Ollama 即可。
> ⚠️ **WSL2 需 UVA 补丁**（Windows 宿主机不支持 UVA），使用 `vllm_entrypoint.sh` 自动 patch。

```yaml
vllm:
  image: vllm/vllm-openai:latest
  container_name: vllm
  restart: unless-stopped
  runtime: nvidia
  ports:
    - "3080:3080"
  networks:
    - llm-net
  entrypoint: ["/vllm_entrypoint.sh"]       # WSL2 必需！
  environment:
    - NVIDIA_VISIBLE_DEVICES=all
    - HF_HUB_OFFLINE=1
    - TRANSFORMERS_OFFLINE=1
  volumes:
    - /mnt/d/app/LLM/models/huggingface:/root/.cache/huggingface:ro
    - /mnt/d/docker-images/vllm_entrypoint.sh:/vllm_entrypoint.sh:ro
  command:
    - "--model"
    - "/root/.cache/huggingface/models/qwen2"
    - "--port"
    - "3080"
    - "--host"
    - "0.0.0.0"
```

> 💡 `vllm_entrypoint.sh` 详见项目根目录，核心功能：启动前 patch `is_uva_available()` 返回 True，绕过 WSL2 限制。

**验证**：

```bash
curl http://localhost:3080/health          # 200 OK
curl http://localhost:3080/v1/models       # 模型列表
```

**更换模型**：修改 compose 中 vllm 的 `--model` 路径 → `docker compose up -d --force-recreate vllm`。

**可用模型路径**：

```
D:\app\LLM\models\huggingface\models\       ← Windows 侧视角
/mnt/d/app/LLM/models/huggingface/models/  ← WSL2 侧视角
├── qwen2/                  ← ✅ 当前使用 (1.5B, 2.88GB)
├── qwen/                   ← ✅ 同上
├── Qwen3-0.6B/             ← ✅ (0.6B, 1.5GB)
├── models--...1.5B-Instruct/  ← ❌ 符号链接失效
└── models--...7B-Instruct/    ← ❌ 缺 shard
```

> ⚠️ WSL2 9P 文件系统不兼容 NTFS 符号链接，只认实体文件目录。

### 7.3 Open WebUI

```yaml
open-webui:
  image: ghcr.io/open-webui/open-webui:main
  container_name: open-webui
  restart: unless-stopped
  depends_on:
    - ollama
  ports:
    - "3090:8080"
  volumes:
    - webuidata:/app/backend/data
  environment:
    OLLAMA_BASE_URL: http://ollama:11434
    OPENAI_API_BASE_URLS: http://vllm:3080/v1
  networks:
    - llm-net
```

**多后端**：`OPENAI_API_BASE_URLS` 多个地址用 `;` 分隔。添加新模型后需 `docker compose restart open-webui` 刷新列表。

> ⚠️ 容器可能显示 "unhealthy"（jq 脚本误判），**不影响使用**。

---

## 八、vLLM vs Ollama 选型

| 维度 | Ollama ⭐ | vLLM |
|---|---|---|
| 模型管理 | 多模型热切换 | 单模型，换则重启 |
| 上手 | 简单 | 需处理 UVA/网络/路径 |
| 性能 | 中等 | 高(PagedAttention) |
| 显存 | 按需加载 | 常驻 |
| 场景 | 日常开发/对外API | 高并发单模型 |
| WSL2 UVA | ✅ 无影响 | ❌ 需 `vllm_entrypoint.sh` patch |

**本项目的策略**：日常用 Ollama(11434)，高并发场景另开 vLLM(3080)，Open WebUI(3090) 统一界面。

---

## 九、对外映射

| 方案 | 适用 | 要点 |
|---|---|---|
| 路由器转发 | 有公网IP | ⚠️ Ollama/WebUI 无认证，暴露前加保护 |
| Nginx 反向代理 | 有公网IP+域名 | SSL + HTTP Basic Auth，推荐 |
| Cloudflare Tunnel | 无公网IP | 免费，需域名 |

客户端调用示例：

```python
from openai import OpenAI
client = OpenAI(base_url="https://你的地址/v1", api_key="not-needed")
response = client.chat.completions.create(
    model="qwen2.5-coder:7b",
    messages=[{"role":"user","content":"写冒泡排序"}]
)
```

详细 Nginx/Tunnel 配置 → 参见附录 A。

---

## 十、常用操作

### WSL2（在 WSL 终端中执行）

```bash
docker ps                                    # 查看状态
docker logs -f ollama                        # 实时日志
docker compose restart open-webui            # 重启单个服务
docker compose down && docker compose up -d  # 全部重建
docker exec -it postgres psql -U admin       # 进数据库
docker exec ollama ollama list               # 已安装模型
docker exec ollama ollama pull 模型名         # 下载新模型
nvidia-smi                                   # GPU 占用
sudo pkill dockerd                           # 停止 Docker
```

### Docker Desktop（PowerShell）

```powershell
docker ps
docker logs -f ollama
docker compose restart open-webui
docker compose down; docker compose up -d
docker exec -it postgres psql -U admin
docker exec ollama ollama list
nvidia-smi
```

---

## 十一、踩坑索引

### 🅰 Docker 通用

| 现象 | 原因 | 解决 |
|---|---|---|
| `executable file not found` | data-root 在 Windows FS | 用 `/var/lib/docker` |
| postgres/redis 启动崩溃 | `default-runtime: nvidia` | 去掉，只在 compose 指定 `runtime: nvidia` |
| dockerd exit code 1 | 旧 PID 残留 | `kill dockerd && rm /var/run/docker.pid` |
| `deploy.resources...devices` 不生效 | Swarm 语法，compose 不认 | 改用 `runtime: nvidia` |
| 3090 无响应 | 容器名冲突 | `docker compose down --remove-orphans` |

### 🅱 AI 服务

| 服务 | 现象 | 原因 | 解决 |
|---|---|---|---|
| **vLLM** | `is_uva_available() Check failed` | WSL2 不支持 UVA | `vllm_entrypoint.sh` patch |
| **vLLM** | 无法下载模型 | 容器内 HTTPS 被墙 | `HF_HUB_OFFLINE=1` |
| **vLLM** | 模型加载失败 | 9P 符号链接失效 | 用实体文件目录 |
| **vLLM** | `Loading safetensors` 卡住 | 9P 读大文件慢 | 正常，约20秒 |
| **vLLM** | `Not enough SMs` | A5000 SM 限制 | 不影响 |
| **vLLM** | pin_memory 禁用 | WSL 自动检测 | 轻微性能损失 |
| **Ollama** | 模型下载慢 | 国内网络 | 配代理或本地导入 |
| **Ollama** | 显存不足 | 同时加载太多模型 | 用 `keepalive` 缩短 |
| **WebUI** | 看不到新模型 | 未刷新 | `docker compose restart open-webui` |
| **WebUI** | unhealthy 状态 | jq 误判 | 不影响使用 |

### 🅲 基础设施

| 服务 | 现象 | 解决 |
|---|---|---|
| PostgreSQL | 密码忘记 | 进容器 `psql -U admin` 执行 ALTER |
| Redis | 外部连不上 | `bind 0.0.0.0`，默认只监听 localhost |
| Qdrant | gRPC 不通 | 确认用 6333 端口，HTTP 用 6334 |
| Grafana | 登录失败 | 默认 admin/admin |
| Prometheus | 无数据 | 检查 `prometheus.yml` 中 targets |

### 🅳 Windows 特有

| 现象 | 原因 | 解决 |
|---|---|---|
| WSL 中无法访问 GPU | nvidia-toolkit 未装 | 按第一章重装 |
| `docker load` 很慢 | 9P 跨文件系统读大文件 | 正常，耐心等待 |
| Windows 防火墙弹窗 | 端口首次监听 | 点击"允许访问" |
| VS Code 编辑 `.sh` 后容器启动异常 | CRLF 换行符 | VS Code 右下角选择 LF，或 `sed -i 's/\r$//' *.sh` |
| Docker Desktop 启动失败 | 内存不足 | Settings → Resources → Memory ≥ 8GB |
| 端口被占用 | IIS/WSL 占用 80/443 | `netstat -ano \| findstr :3090` 查看，改映射端口 |

---

## 九、集成 AI 全栈平台 (ai-fullstack-platform)

本教程部署的 **docker-images** 是整个 AI 平台的**基础设施层**（数据库、缓存、AI 推理、监控）。如果你还需要完整的业务应用（后端 API + 多个前端 + 异步任务），可以搭配 [ai-fullstack-platform](https://github.com/yuanxiufei/ai-dev-platform) 项目——这是一套基于 FastAPI + Vue 3 / React 19 的全栈 AI 开发平台。

### 架构总览

```
┌─────────────────────────────────────────────────────┐
│           docker-images (基础设施层)                  │
│                                                       │
│  ┌──────────┐  ┌───────┐  ┌────────┐                │
│  │PostgreSQL│  │ Redis │  │ Qdrant │  ← 数据存储     │
│  └────┬─────┘  └───┬───┘  └───┬────┘                │
│  ┌────┴─────┐  ┌───┴───┐  ┌───┴────┐                │
│  │  Ollama  │  │ vLLM  │  │OpenWebUI│  ← AI 推理     │
│  │ (for Win)│  │(Linux)│  │         │                │
│  └──────────┘  └───────┘  └────────┘                │
│  ┌──────────┐  ┌───────────┐  ┌────────┐            │
│  │Prometheus│  │Alertmgr   │  │Grafana │  ← 监控    │
│  └──────────┘  └───────────┘  └────────┘            │
│         docker compose up -d (9容器)                 │
└──────────────────────┬──────────────────────────────┘
                       │ 共享网络 ai-platform-net
                       ↓
┌─────────────────────────────────────────────────────┐
│         ai-fullstack-platform (应用层)                │
│                                                       │
│  ┌────────────┐  ┌───────────┐  ┌───────────┐       │
│  │  backend   │  │  celery   │  │  4 个前端  │       │
│  │ FastAPI    │  │  worker   │  │ Vue3/React │       │
│  │ :18000     │  │ (异步任务) │  │ :5173-5176 │       │
│  └─────┬──────┘  └─────┬─────┘  └─────┬─────┘       │
│        └───────────────┴───────────────┘             │
│         docker compose up (应用服务)                   │
└─────────────────────────────────────────────────────┘
```

### 两者关系

| 服务 | docker-images 提供 | ai-fullstack-platform 提供 |
|---|---|---|
| PostgreSQL | ✅ `container_name: postgres` | 连接 → `POSTGRES_SERVER=db` |
| Redis | ✅ `container_name: redis` | 连接 → `REDIS_URL=redis://redis:6379/0` |
| Qdrant | ✅ `container_name: qdrant` | 连接 → `QDRANT_HOST=qdrant` |
| Ollama | ✅ Windows 原生 / Docker | 通过 API 调用 |
| vLLM | ⚠️ 仅 Linux/WSL2 | 通过 API 调用 |
| FastAPI 后端 | — | ✅ 108 个 API 端点 |
| 前端 (4 个) | — | ✅ Vue 3 / React 19 |
| Celery Worker | — | ✅ 异步任务（Windows 需 `--pool=solo`） |
| 监控 | ✅ Prometheus + Grafana | — |
| Open WebUI | ✅ 对话面板 | — |

**关键凭证**（两者一致，无需修改）：

| 变量 | 值 | 说明 |
|---|---|---|
| `POSTGRES_USER` | `admin` | 数据库用户 |
| `POSTGRES_PASSWORD` | `admin123` | 数据库密码 |
| `POSTGRES_DB` | `studio` | 数据库名 |
| POSTGRES 端口 | 5432 | 对外映射 |
| Redis 端口 | 6379 | 对外映射 |
| Qdrant HTTP | 6333 | 对外映射 |

### 部署方式一：统一编排（推荐）

使用 `compose.unified.yml` 一键拉起基础设施 + 应用层：

**WSL2 方案：**

```bash
# 1. 创建共享网络（首次）
docker network create ai-platform-net

# 2. 设置平台项目路径（WSL2 中访问 Windows 路径）
export PLATFORM_DIR=/mnt/d/code/ai-fullstack-platform

# 3. 启动全部服务
cd /mnt/d/docker-images
docker compose -f compose.unified.yml up -d --build
```

**Docker Desktop 方案（PowerShell）：**

```powershell
# 1. 创建共享网络
docker network create ai-platform-net

# 2. 设置环境变量
$env:PLATFORM_DIR = "D:\code\ai-fullstack-platform"

# 3. 启动全部服务
cd D:\docker-images
docker compose -f compose.unified.yml up -d --build
```

> **Windows 注意事项**：
> - vLLM 在 Windows 上**不可用**（需 Linux + CUDA），Ollama 可替代作为推理后端
> - 如果 vLLM 启动失败，在 `compose.unified.yml` 中注释掉 vLLM 服务定义
> - Celery Worker 在 Windows 容器中需加 `--pool=solo`（`compose.unified.yml` 中已预留注释行，取消注释即可）
> - 首次 `--build` 前端需 5-10 分钟（pnpm install + Vite build）

### 部署方式二：分步部署

分别启动两个项目，通过共享网络互连：

**WSL2：**

```bash
# ─── 第一步：启动基础设施 ───
cd /mnt/d/docker-images
docker network create ai-platform-net  # 首次
docker compose up -d

# ─── 第二步：启动应用层 ───
cd /mnt/d/code/ai-fullstack-platform
# 参见下方 "compose.app.yml" 方案
```

**Docker Desktop（PowerShell）：**

```powershell
# ─── 第一步：启动基础设施 ───
cd D:\docker-images
docker compose up -d

# ─── 第二步：创建 compose.app.yml（不含 PG/Redis/Qdrant）
```

创建 `D:\code\ai-fullstack-platform\compose.app.yml`：

```yaml
services:
  prestart:
    build:
      context: .
      dockerfile: backend/Dockerfile
    image: ai-platform-backend:latest
    depends_on:
      postgres:
        condition: service_healthy
        restart: true
    command: bash scripts/prestart.sh
    environment:
      - POSTGRES_SERVER=db
      - POSTGRES_PORT=5432
      - POSTGRES_DB=${POSTGRES_DB:-studio}
      - POSTGRES_USER=${POSTGRES_USER:-admin}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-admin123}
      - SECRET_KEY=${SECRET_KEY:-changethis}
      - FIRST_SUPERUSER=${FIRST_SUPERUSER:-admin@example.com}
      - FIRST_SUPERUSER_PASSWORD=${FIRST_SUPERUSER_PASSWORD:-changethis}
    extra_hosts:
      - "db:host-gateway"
      - "redis:host-gateway"
      - "qdrant:host-gateway"

  backend:
    build:
      context: .
      dockerfile: backend/Dockerfile
    image: ai-platform-backend:latest
    restart: unless-stopped
    depends_on:
      prestart:
        condition: service_completed_successfully
    ports:
      - "18000:8000"
    environment:
      - POSTGRES_SERVER=host.docker.internal
      - POSTGRES_PORT=5432
      - POSTGRES_DB=${POSTGRES_DB:-studio}
      - POSTGRES_USER=${POSTGRES_USER:-admin}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-admin123}
      - REDIS_HOST=host.docker.internal
      - REDIS_URL=redis://host.docker.internal:6379/0
      - QDRANT_HOST=host.docker.internal
      - QDRANT_PORT=6333
      - SECRET_KEY=${SECRET_KEY:-changethis}

  celery-worker:
    build:
      context: .
      dockerfile: backend/Dockerfile
    image: ai-platform-backend:latest
    restart: unless-stopped
    environment:
      - REDIS_HOST=host.docker.internal
      - POSTGRES_SERVER=host.docker.internal
      - POSTGRES_DB=${POSTGRES_DB:-studio}
      - POSTGRES_USER=${POSTGRES_USER:-admin}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-admin123}
    command: celery -A task_queue.celery_app worker --loglevel=info --pool=solo
```

```powershell
# 启动应用服务
cd D:\code\ai-fullstack-platform
docker compose -f compose.app.yml up -d --build
```

> **Docker Desktop 特有**：分步部署时使用 `host.docker.internal` 代替服务名，因为两个 compose 不在同一网络。WSL2 用 `compose.unified.yml` 统一网络更简单。

### 端口与服务总览

| 分类 | 服务 | 地址 |
|---|---|---|
| 基础设施 | PostgreSQL | `localhost:5432` |
| 基础设施 | Redis | `localhost:6379` |
| 基础设施 | Qdrant Web | `http://localhost:6333` |
| AI 模型 | Ollama API | `http://localhost:11434` |
| AI 模型 | vLLM API（仅 WSL2） | `http://localhost:3080/v1` |
| AI 模型 | Open WebUI | `http://localhost:3090` |
| 业务 | 后端 API | `http://localhost:18000` |
| 业务 | API 文档 (Swagger) | `http://localhost:18000/docs` |
| 业务 | Studio 前端 | `http://localhost:5173` |
| 业务 | Video 前端 | `http://localhost:5174` |
| 业务 | Studio 管理端 | `http://localhost:5175` |
| 业务 | Video 管理端 | `http://localhost:5176` |
| 管理 | Adminer 数据库 | `http://localhost:18080` |
| 监控 | Prometheus | `http://localhost:9090` |
| 监控 | Alertmanager | `http://localhost:9093` |
| 监控 | Grafana (admin/admin) | `http://localhost:9091` |

### 开发模式：基础设施全跑，应用层跑本地

最推荐的日常开发方式——Docker 跑数据库/Redis/模型，本地跑前后端（热重载）：

```bash
# ─── 保持基础设施运行 ───
cd /mnt/d/docker-images     # WSL2
docker compose up -d

# ─── 在 ai-fullstack-platform 本地开发 ───
cd /mnt/d/code/ai-fullstack-platform

# 终端 1：后端热重载
cd backend && uv run fastapi dev app/main.py --port 8000

# 终端 2：前端（任选，自动热更新）
pnpm dev:studio-client      # http://localhost:5173
pnpm dev:video-client       # http://localhost:5174
pnpm dev:studio-admin       # http://localhost:5175
pnpm dev:video-admin        # http://localhost:5176
```

> 本地运行的后端通过 `POSTGRES_SERVER=localhost`、`REDIS_URL=redis://localhost:6379` 连接 Docker 基础设施。后端 `fastapi dev` 模式文件修改自动重载。

> ⚠️ **凭证不兼容提醒**：`backend/.env`（本地开发用）的数据库凭证为 `postgres/changethis/app`，而 docker-images 的 PostgreSQL 使用 `admin/admin123/studio`。本地运行时必须覆盖这三个环境变量：
>
> ```bash
> # WSL2 / PowerShell：命令行临时导出（推荐）
> export POSTGRES_USER=admin POSTGRES_PASSWORD=admin123 POSTGRES_DB=studio
> cd backend && uv run fastapi dev app/main.py --port 8000
>
> # 或直接修改 backend/.env
> # POSTGRES_USER=admin
> # POSTGRES_PASSWORD=admin123
> # POSTGRES_DB=studio
> ```
>
> 如果不覆盖，prestart 数据库迁移会因找不到数据库 `app` 而失败。

### Windows 开发注意事项

1. **Celery on Windows**：必须加 `--pool=solo`，不支持 prefork 模式。在 `compose.unified.yml` 中 celery-worker 的 command 行取消 `--pool=solo` 注释即可
2. **vLLM 不可用**：Windows/WSL2 上 vLLM 的 UVA 大页内存不可用，请用 Ollama 替代。ai-fullstack-platform 的模型路由会自动回退
3. **换行符**：`vllm_entrypoint.sh` 和 `prestart.sh` 必须是 LF，右键 VS Code 底部状态栏切换
4. **防火墙弹窗**：首次监听端口时 Windows 防火墙会弹窗，点"允许访问"

---

## 附录 A：对外映射完整配置

### Nginx 反向代理（推荐）

```nginx
server {
    listen 443 ssl;
    server_name ai.yourdomain.com;
    ssl_certificate     /etc/ssl/certs/cert.pem;
    ssl_certificate_key /etc/ssl/private/key.pem;
    auth_basic "AI API";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location /ollama/     { proxy_pass http://127.0.0.1:11434/; proxy_read_timeout 300s; }
    location /vllm/       { proxy_pass http://127.0.0.1:3080/; proxy_read_timeout 300s; }
    location /grafana/    { proxy_pass http://127.0.0.1:9091/; }
    location /            { proxy_pass http://127.0.0.1:3090; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }
}
```

### Cloudflare Tunnel

```yaml
# ~/.cloudflared/config.yml
tunnel: <tunnel-id>
credentials-file: /root/.cloudflared/<tunnel-id>.json
ingress:
  - hostname: ai.yourdomain.com
    service: http://localhost:3090
  - hostname: api.yourdomain.com
    service: http://localhost:11434
  - service: http_status:404
```

---

## 附录 B：Docker Desktop 部署

> 适用于不想安装 WSL2、偏好图形化管理的 Windows 用户。

### B.1 安装 Docker Desktop

1. 下载 [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/)
2. 运行安装程序，推荐选择 **"Use WSL 2 instead of Hyper-V"**（性能更好）
3. 安装完成后重启电脑
4. 打开 Docker Desktop，等待右下角鲸鱼图标变绿（Engine running）

```powershell
# 验证安装
docker --version
docker ps
```

### B.2 GPU 支持配置

Docker Desktop 4.30+ **内置** NVIDIA Container Toolkit，无需手动安装。

**配置步骤**：
1. Docker Desktop → Settings（⚙️ 齿轮图标）
2. → Resources → Advanced → **Enable GPU** ✅ 勾选
3. 点击 "Apply & Restart"

```powershell
# 验证 GPU 可用
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

> ⚠️ 如果报错 `could not select device driver "nvidia"`，在 Settings → Docker Engine 中确认 daemon.json 包含：
>
> ```json
> {
>   "runtimes": {
>     "nvidia": {
>       "path": "nvidia-container-runtime",
>       "runtimeArgs": []
>     }
>   }
> }
> ```

### B.3 daemon.json 配置

在 Docker Desktop → Settings → Docker Engine 中直接编辑：

```json
{
  "data-root": "D:\\docker-data",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
```

> ⚠️ Windows 用反斜杠 `\`，JSON 中需转义为 `\\`。建议 data-root 指向 SSD 分区。

### B.4 Windows 下 Compose 文件的路径写法

```yaml
# ❌ WSL2 写法（Docker Desktop 原生模式下不生效）
volumes:
  - /mnt/d/app/LLM/models:/root/.cache/huggingface:ro

# ✅ Windows 写法（两种均可）
volumes:
  # 方式一：Windows 绝对路径
  - D:\app\LLM\models\huggingface:/root/.cache/huggingface:ro

  # 方式二：相对路径（推荐，跨平台兼容）
  - ./models/huggingface:/root/.cache/huggingface:ro
```

> 💡 **相对路径 `./` 是跨 WSL2 / Docker Desktop / Linux 的最好选择**，把模型放到项目的 `models/` 目录下即可。

### B.5 Windows 特有注意事项

1. **换行符问题**：`.sh` 脚本文件（如 `vllm_entrypoint.sh`）必须用 **LF** 换行，不可用 CRLF。
   ```powershell
   # VS Code 右下角点击 CRLF → 选择 LF
   git config --global core.autocrlf input
   ```

2. **文件权限**：Windows NTFS 没有 Linux 权限概念，Docker 容器内看到的文件默认 `777`。如有安全需求，在 compose 中加 `:ro` 只读挂载。

3. **端口占用**：Windows 上 80/443 端口可能被 IIS 或 WSL 占用。
   ```powershell
   netstat -ano | findstr :3090
   # 如被占用，改 compose 映射端口
   ```

4. **防火墙**：首次启动时 Windows 防火墙可能弹窗，选择"允许访问"。

5. **Docker Desktop 内存**：Settings → Resources → Advanced，建议 Memory 至少 **8GB**（跑 7B 模型需 16GB+）。

---

## 附录 C：WSL2 vs Docker Desktop 快速对比

| 对比维度 | WSL2 | Docker Desktop |
|---|---|---|
| Docker 安装方式 | `apt install docker.io` | 下载 exe 安装包 |
| daemon 管理 | 手动 `sudo dockerd &` | 自动（系统服务） |
| 路径访问宿主机 | `/mnt/c/` `/mnt/d/` | `D:\` 或 WSL 路径 |
| GPU 配置 | 手动安装 nvidia-container-toolkit | GUI 勾选 Enable GPU |
| vLLM UVA | ❌ 需 patch | ❌ 需 patch（WSL2 后端同样） |
| 文件系统 | ext4（推荐） | NTFS（默认） |
| 文件性能 | ext4 上最优，NTFS 挂载较慢 | 良好 |
| 模型加载速度 | ~20s（9P 跨文件系统） | ~20s（WSL2 后端同样） |
| 进入方式 | `wsl -d Ubuntu-24.04` | 直接打开 PowerShell/CMD |
| Docker Compose | 需安装 `docker-compose-v2` | 内置 `docker compose`（插件） |
