# dsh-longlongchat 生产机更新安装流程（RC2 版）

> 供执行 agent 使用。**目标**：生产 `dsh-web.service`（DSH 0.1.0-rc.8，:3081）升级到 **DSH 0.1.1-rc.2 核心 + 本包 `patches/rc2` 补丁**（与 `/tmp/dsh-rc2-runtime` :25922 验证运行同源）。
> **原则**：不修改生产数据（`DSH_HOME=/www/dsh`、profiles、sessions 原样保留）；只替换"核心运行根"，服务启动切换；全流程可回滚。

## 0. 前置条件（执行前逐项核对）

| 项 | 期望值 |
|---|---|
| 生产服务 | `dsh-web.service`（active，:3081） |
| 生产 DSH_HOME | `/www/dsh`（目录存在，内含 profiles/sessions/home） |
| 生产当前核心 | `/usr/local/node/lib/node_modules/@deepseek-ai/dsh` = `0.1.0-rc.8` |
| rc2 验证源 | `/tmp/dsh-rc2-runtime/node_modules`（pnpm 布局，**已打 rc2 补丁**，:25922 验证 200） |
| 代理/网络 | 不涉及（本机文件操作） |
| 磁盘 | `/opt` 至少 2GB（rc2 source ≈ 275MB + 备份） |

> ⚠️ **执行 agent 必须先用只读命令确认以上**，任何一项不符 → 停止并汇报，不要继续。

## 1. 使用脚本（推荐路径）

```bash
# 脚本位置（发布仓库 dsh-longlongchat/scripts/）
cd dsh-longlongchat/scripts
chmod +x production-install.sh

# ① 只读状态概览（先看是否符合预期）
./production-install.sh status

# ② 备份生产（核心 + 服务 unit + profile 清单）
./production-install.sh backup

# ③ 部署 rc2 核心到新根（/opt/dsh-rc2-core，cp -a 保留 pnpm symlink）
./production-install.sh deploy

# ④ verify：语法 + 补丁功能标记（VirtualChatFlow/OutlinePanel/outlineOf/untilSeq）
./production-install.sh verify

# ⑤ 切换服务启动到新核心并重启
./production-install.sh start
```

## 2. 验证点（start 后）

1. `systemctl status dsh-web.service` → active
2. `curl -o /dev/null -w '%{http_code}' http://127.0.0.1:3081/` → `200`
3. 浏览器打开 `http://110.42.47.93:3080/`（或 3081）→ 登录、开一个长会话
4. 功能验收：首帧贴底无闪烁；大纲面板可拖拽；点击大纲跳转到较早消息**单次渲染完成**（不再逐页慢）；向上滚动贴底稳定
5. host 侧：会话历史返回包含 `outline` 分组（可查 `/var/log/dsh-longlongchat-install.log`）
6. 服务器日志无 `[web-runtime] history page discontinuous` 等异常

## 3. 回滚（任何时候可执行）

```bash
./production-install.sh rollback   # 恢复服务 unit 指向原 /usr/local/bin/dsh + 原核心，重启
```
- 原生产核心 `/usr/local/node/.../dsh` **从未被修改**（部署只写新根 `/opt/dsh-rc2-core`），回滚即恢复服务启动路径
- 备份齐全：`/opt/dsh-prod-backup/<timestamp>/`（dsh-main-rc8、dsh-web.service.unit、profile 清单）

## 4. 风险与注意事项

- **生产数据零改动**：脚本只操作 `/opt/dsh-rc2-core`（新根）与 `/etc/systemd/system/dsh-web.service` 的 ExecStart；`/www/dsh`（profiles/sessions/home）只读备份，不写。
- **业务插件兼容性**：生产 profile（dsh-deepmemory 0.5.0、dsh-task-board 等）在升级后仍由 profile 的 cordis.yml 加载；0.1.1-rc.2 与 0.1.0-rc.8 插件 API 差异风险存在——升级后**必须先确认插件面板正常**（记忆面板/任务板可打开），异常则 `rollback`。
- **pnpm symlink**：rc2 源是 pnpm 布局（`@deepseek-ai/dsh` → `.pnpm/...`），脚本用 `cp -a` 保留；**不要**用 rsync 默认（会解引用）或 tar 后不保链。
- **服务启动命令变更**：升级后 `ExecStart=/usr/local/bin/node /opt/dsh-rc2-core/@deepseek-ai/dsh/lib/bin.js web ...`（不再用 `/usr/local/bin/dsh`）。`/usr/local/bin/dsh` 原样保留（回滚用）。
- **内存/依赖**：rc2 全套依赖已随 `.pnpm` 复制，Node 版本用 `/usr/local/bin/node`（生产既有）；若 rc2 需要更高 Node，脚本 start 前需确认。
- **不可同时执行**：升级窗口内禁止其他 agent 操作生产；先 `systemctl stop dsh-web.service`（可选，脚本 start 会 restart）。

## 5. 其他 agent 执行注意

- 执行时**逐条打印命令输出**到日志（脚本已写 `/var/log/dsh-longlongchat-install.log`）。
- 任何 `FATAL` / verify 失败 / HTTP 非 200 → **执行 `rollback`**，然后汇报，不要继续。
- 完成后把 `status` 输出 + HTTP 验证 + 服务状态三样作为验收附件。

## 6. 快速成功判定表

| 检查 | 成功 |
|---|---|
| deploy 后 `.deployed-version` | `0.1.1-rc.2` |
| verify VirtualChatFlow/OutlinePanel/untilSeq | 均为 ≥1 |
| start 后服务 | active |
| start 后 HTTP | 200 |
