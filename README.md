# docker-images — AI 全栈平台基础设施层

本仓库是 [ai-fullstack-platform](https://github.com/yuanxiufei/ai-dev-platform) 的**基础设施配置仓库**，提供 PostgreSQL 16、Redis 7、Qdrant、Ollama、vLLM、Open WebUI、Prometheus、Alertmanager、Grafana 共 9 个服务的 Docker 编排与多系统环境变量。

---

## 双系统共享架构

```
┌────────────────────────────────────────────────────┐
│            NTFS 共享分区 (Software/D:)              │
│                                                    │
│  ┌── Docker 存储 ──┐  ┌─── AI 模型 ────┐          │
│  │ docker-volumes.  │  │ app/LLM/models/ │          │
│  │ img (70GB ext4)  │  │  ├── ollama/    │          │
│  │  ├── docker/     │  │  └── huggingface│          │
│  │  ├── postgres/   │  └────────────────┘          │
│  │  ├── redis/      │                              │
│  │  ├── qdrant/     │  ┌── 项目代码 ────┐          │
│  │  ├── open-webui/ │  │ code/           │          │
│  │  ├── prometheus/ │  │  ai-fullstack-  │          │
│  │  ├── grafana/    │  │  platform/      │          │
│  │  └── alertmgr/   │  └────────────────┘          │
│  └──────────────────┘                              │
└────────────────────┬───────────────────────────────┘
                     │ 同一份文件，两个系统共享
          ┌──────────┴──────────┐
          ▼                     ▼
   ┌─────────────┐      ┌─────────────┐
   │   Linux     │      │    WSL2     │
   │ /run/media/ │      │  /mnt/d/    │
   │ reginyuan/  │      │             │
   │ Software/   │      │             │
   └─────────────┘      └─────────────┘
```

**核心设计**：Docker 全部数据（镜像层、数据库、缓存、监控）存储在 NTFS 分区上的 ext4 卷中。Linux 和 WSL2 共享同一份文件，切换系统后数据完全一致，无需重新拉取镜像或导入。

---

## 环境变量配置

根据当前运行的系统，选择对应的 `.env` 文件复制为 `.env`：

### Linux（主系统）

```bash
cp .env.linux .env
```

| 变量 | 值 |
|------|-----|
| `SHARED_DATA` | `/run/media/reginyuan/Software/app/Docker/SharedData` |
| `MODELS_DIR` | `/run/media/reginyuan/Software/app/LLM/models` |
| `PLATFORM_DIR` | `/run/media/reginyuan/Software/code/ai-fullstack-platform` |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | `admin` / `admin123` / `studio` |

### WSL2（Windows 子系统）

```bash
cp .env.wsl2 .env
```

| 变量 | 值 |
|------|-----|
| `SHARED_DATA` | `/mnt/d/app/Docker/SharedData` |
| `MODELS_DIR` | `/mnt/d/app/LLM/models` |
| `PLATFORM_DIR` | `/mnt/d/code/ai-fullstack-platform` |
| `CELERY_POOL` | `solo`（Windows 不支持 prefork） |

> ⚠️ WSL2 路径前缀取决于 D 盘的挂载名称（通常为 `/mnt/d/`，也可能为 `/mnt/软件/` 等），请根据实际情况修改。

---

## 系统差异速查

| 配置项 | Linux | WSL2 |
|--------|-------|------|
| Docker 启动 | `systemctl start docker` | `sudo dockerd &` |
| `daemon.json`: default-runtime | `nvidia` | 不设（仅 runc） |
| GPU 容器 | 默认 `runtime: nvidia` 可用 | 需 compose 显式指定 `runtime: nvidia` |
| celery pool | `prefork` | `--pool=solo` |
| vLLM UVA | ✅ 原生支持 | ❌ 需 `vllm_entrypoint.sh` 补丁 |
| NTFS 路径前缀 | `/run/media/reginyuan/Software` | `/mnt/d` |
| 换行符要求 | LF（默认） | LF（CRLF 会导致脚本失败） |

---

## 快速启动

```bash
# 1. 配置当前系统的 .env
cp .env.linux .env    # Linux
# cp .env.wsl2 .env   # WSL2

# 2. 进入主项目，执行一键部署脚本
cd $PLATFORM_DIR
bash setup.sh
```

`setup.sh` 会自动完成：
1. 检测 Linux / WSL2 环境
2. 挂载 ext4 卷（如未挂载）
3. 配置 Docker daemon.json（适配当前系统）
4. 启动全部 16 个服务（9 基础 + 7 应用）

---

## 切换系统

双系统共享同一份 ext4 数据。从 Windows 切换到 Linux（或反过来）时：

```bash
# 1. 切换到目标系统
# 2. 更新 .env（如果当前 .env 还是另一系统的）
cp .env.linux .env    # 切到 Linux
# cp .env.wsl2 .env   # 切到 WSL2

# 3. 一键恢复
cd $PLATFORM_DIR && bash setup.sh
```

> 切换后数据库、缓存、模型、监控历史完全一致，无感知。

---

## 从零部署（首次）

### Linux

```bash
# 1. 安装 Docker
sudo apt update && sudo apt install -y docker.io docker-compose-v2
sudo systemctl enable docker --now

# 2. 安装 NVIDIA Container Toolkit
# 详见: ai-fullstack-platform/docs/deployment/Linux部署.md

# 3. 创建 ext4 卷（仅首次，后续两个系统共享）
sudo dd if=/dev/zero of=/run/media/reginyuan/Software/app/Docker/docker-volumes.img bs=1M count=71680
sudo mkfs.ext4 -F /run/media/reginyuan/Software/app/Docker/docker-volumes.img
sudo mkdir -p /data/docker-volumes
echo "/run/media/reginyuan/Software/app/Docker/docker-volumes.img /data/docker-volumes ext4 loop,defaults 0 0" | sudo tee -a /etc/fstab
sudo mount /data/docker-volumes

# 4. 配置 .env 并启动
cp .env.linux .env
cd $PLATFORM_DIR && bash setup.sh
```

### WSL2

> 前提：ext4 卷已在 Linux 端创建（只需一次）。

```bash
# 1. 安装 WSL2 + Docker + nvidia-container-toolkit
# 详见: ai-fullstack-platform/docs/deployment/Windows部署.md

# 2. 配置 .env 并启动
cp .env.wsl2 .env
cd /mnt/d/code/ai-fullstack-platform
bash setup.sh
```

---

## 服务端口速查

| 服务 | 端口 | 凭证 |
|------|------|------|
| PostgreSQL 16 | 5432 | `admin` / `admin123` / `studio` |
| Redis 7 | 6379 | 无 |
| Qdrant HTTP | 6334 | — |
| Qdrant gRPC | 6333 | — |
| Ollama API | 11434 | — |
| vLLM API | 3080 | — |
| Open WebUI | 3090 | — |
| Prometheus | 9090 | — |
| Alertmanager | 9093 | — |
| Grafana | 9091 | `admin` / `admin` |

---

## 详细文档

| 文档 | 位置 |
|------|------|
| 📄 **部署总览**（双系统架构 + 全部服务配置） | [docs/DEPLOY.md](../code/ai-fullstack-platform/docs/DEPLOY.md) |
| 📘 **Windows 部署**（WSL2 / Docker Desktop） | [docs/deployment/Windows部署.md](../code/ai-fullstack-platform/docs/deployment/Windows部署.md) |
| 📗 **Linux 部署**（原生 Linux + GPU 直通） | [docs/deployment/Linux部署.md](../code/ai-fullstack-platform/docs/deployment/Linux部署.md) |
| 📙 **部署基础篇**（镜像清单 + Traefik + CI/CD） | [docs/deployment/部署概览.md](../code/ai-fullstack-platform/docs/deployment/部署概览.md) |
| 🔧 **开发指南**（本地开发 + 模型管理） | [docs/development/开发指南.md](../code/ai-fullstack-platform/docs/development/开发指南.md) |
