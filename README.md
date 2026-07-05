# docker-images

本目录原为离线镜像仓库，所有部署配置和文档已迁移至主项目。

## 镜像存储

```
NTFS 共享分区 app/Docker/docker-volumes.img (70GB ext4)
  └── /data/docker-volumes/docker/  ← Docker data-root
```

全部镜像通过 `docker compose` 从 Docker Hub 拉取，存储在 ext4 卷内。
**Linux 和 WSL2 共享同一份文件**，包含镜像层、数据库、缓存、监控等全部数据。

## 部署

```bash
cd ai-fullstack-platform && bash setup.sh
```

## 详细文档

→ [ai-fullstack-platform/docs/DEPLOY.md](../code/ai-fullstack-platform/docs/DEPLOY.md)
