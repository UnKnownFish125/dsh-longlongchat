#!/usr/bin/env bash
# dsh-longlongchat production upgrade installer (RC2 版)
#
# 目标: 生产 dsh-web.service (0.1.0-rc.8, :3081) 升级到 DSH 0.1.1-rc.2 核心
#       + 本包 patches/rc2 补丁 (已验证: /tmp/dsh-rc2-runtime, :25922)。
# 原则: 不修改生产数据 (DSH_HOME=/www/dsh、profiles、sessions 原样保留);
#       只替换"核心运行根"，服务启动切换到新根; 全程可回滚。
#
# 用法:
#   production-install.sh backup      # 备份生产核心/服务(供回滚)
#   production-install.sh deploy      # 部署 rc2 核心到目标根(带备份)
#   production-install.sh verify      # verify 新核心 + 补丁完整性
#   production-install.sh start       # 切换服务启动到新根并重启
#   production-install.sh rollback    # 恢复核心/服务到升级前状态
#   production-install.sh status      # 只读状态概览
#
# 每次 deploy 前会自动 backup。

set -euo pipefail

# ------- 配置(按生产实际调整; 执行 agent 需先核对) -------
PROD_HOME=/www/dsh                      # 生产 DSH_HOME
PROD_SERVICE=dsh-web.service            # 生产服务
PROD_PORT=3081
PROD_LAUNCHER=/usr/local/bin/dsh        # 生产启动命令(升级后改指向新根)
PROD_CORE_SRC=/tmp/dsh-rc2-runtime/node_modules   # rc2 已验证核心源(pnpm 布局, 已打补丁)
RC2_CORE_DIR=/opt/dsh-rc2-core           # 生产新核心根(部署目标)
BACKUP_DIR=/opt/dsh-prod-backup          # 备份目录
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG=/var/log/dsh-longlongchat-install.log
FAILED_BACKUP_MSG=""

mkdir -p "$BACKUP_DIR" "$RC2_CORE_DIR"

log() { echo "[dsh-longlongchat] $(date +%H:%M:%S) $*" | tee -a "$LOG"; }
die() { log "FATAL: $*"; exit 1; }

# 只读状态
status() {
  log "--- 状态概览 ---"
  log "生产 DSH_HOME: $PROD_HOME"
  log "生产服务: $PROD_SERVICE ($(systemctl is-active "$PROD_SERVICE" 2>/dev/null || echo 'unknown'))"
  log "生产端口: $PROD_PORT ($(ss -tlnp 2>/dev/null | grep -c ":$PROD_PORT\b") 监听)"
  log "生产当前版本: $(node -e "try{console.log(require('$PROD_LAUNCHER'.replace(/\/bin\/dsh$/, '/lib/bin.js')))}catch(e){console.log('n/a')}" 2>/dev/null || echo 'n/a')"
  log "rc2 源可用: $([ -d "$PROD_CORE_SRC/@deepseek-ai/dsh" ] && echo yes || echo NO)"
  log "新核心根已部署: $([ -d "$RC2_CORE_DIR/node_modules/@deepseek-ai/dsh" ] && echo yes || echo NO)"
  log "备份存在: $([ -d "$BACKUP_DIR" ] && echo yes || echo no)"
}

# 备份生产核心 + 服务配置 + 关键清单
backup() {
  log "--- backup 开始 ($TIMESTAMP) ---"
  local dest="$BACKUP_DIR/$TIMESTAMP"
  mkdir -p "$dest"
  # 1) 生产全局 dsh 主包(含嵌套核心) — 若存在
  if [ -d /usr/local/node/lib/node_modules/@deepseek-ai/dsh ]; then
    cp -a /usr/local/node/lib/node_modules/@deepseek-ai/dsh "$dest/dsh-main-rc8.global" 2>/dev/null \
      || log "WARN: dsh 主包备份失败(跳过)" 
  fi
  # 2) 生产启动器/服务单元
  cp /usr/local/bin/dsh "$dest/dsh-launcher" 2>/dev/null || true
  systemctl cat "$PROD_SERVICE" > "$dest/dsh-web.service.unit" 2>/dev/null || true
  # 3) 生产 .longlongchat.bak / 补丁状态(若有)
  find /usr/local/node/lib/node_modules/@deepseek-ai -name '*.longlongchat.bak' -exec cp -a {} "$dest/" \; 2>/dev/null || true
  # 4) 生产 profile 清单(只读快照, 不动数据)
    cp /www/dsh/home/profiles/web/cordis.yml "$dest/cordis.yml" 2>/dev/null || true
    cp /www/dsh/home/profiles/web/package.json "$dest/profile.package.json" 2>/dev/null || true
    if [ -f /www/dsh/home/profiles/web/node_modules/@deepseek-ai/dsh/package.json ]; then
      cp /www/dsh/home/profiles/web/node_modules/@deepseek-ai/dsh/package.json "$dest/prod-core-version.json" 2>/dev/null || true
    fi
  # 5) 若上次部署过新核心, 备份它以便回滚更精确
  if [ -d "$RC2_CORE_DIR" ] && [ "$(ls -A "$RC2_CORE_DIR" 2>/dev/null | wc -l)" -gt 0 ]; then
    cp -a "$RC2_CORE_DIR" "$dest/rc2-core.deployed" 2>/dev/null || log "WARN: 已部署核心备份失败"
  fi
  echo "$TIMESTAMP" > "$BACKUP_DIR/last-backup"
  log "--- backup 完成: $dest ---"
}

# 部署 rc2 核心到目标根 (cp -a 保留 pnpm symlink)
deploy() {
  log "--- deploy 开始 ---"
  [ -d "$PROD_CORE_SRC/@deepseek-ai/dsh" ] || die "rc2 核心源不存在: $PROD_CORE_SRC"
  # 先备份现有(幂等: 若已部署过则备份当前再覆盖)
  backup
  # 清空并复制 (cp -a 保留 symlink, .pnpm 完整)
  rm -rf "${RC2_CORE_DIR:?}"/*
  cp -a "$PROD_CORE_SRC/." "$RC2_CORE_DIR/" 2>/dev/null \
    || die "复制 rc2 核心失败"
  # 完整性: 主包 + .pnpm
  [ -d "$RC2_CORE_DIR/@deepseek-ai/dsh" ] || die "部署后缺主包 @deepseek-ai/dsh"
  [ -d "$RC2_CORE_DIR/.pnpm" ] || die "部署后缺 .pnpm store"
  log "核心部署完成: $RC2_CORE_DIR"
  # 记录版本
  node -e "console.log(require('$RC2_CORE_DIR/@deepseek-ai/dsh/package.json').version)" > "$RC2_CORE_DIR/.deployed-version" 2>/dev/null || true
  log "deployed version: $(cat "$RC2_CORE_DIR/.deployed-version" 2>/dev/null || echo 'unknown')"
}

# verify: 语法 + 补丁功能标记 + 版本
verify() {
  log "--- verify 开始 ---"
  local binjs="$RC2_CORE_DIR/@deepseek-ai/dsh/lib/bin.js"
  [ -f "$binjs" ] || die "新核心 bin.js 缺失"
  node --check "$binjs" || die "新核心 bin.js 语法失败"
  # 找到补丁后核心(rc2 core 在 .pnpm 内, 通过主包解析; 直接搜文件)
  local ui
  ui=$(find "$RC2_CORE_DIR/.pnpm" -path '*dsh-client-ui-conversation@0.1.1-rc.2*/lib/client.js' 2>/dev/null | head -1)
  if [ -z "$ui" ]; then
    ui=$(find "$RC2_CORE_DIR" -path '*dsh-client-ui-conversation/lib/client.js' 2>/dev/null | head -1)
  fi
  [ -n "$ui" ] || die "未找到 ui-conversation core"
  echo -n "VirtualChatFlow: "; grep -c 'function VirtualChatFlow' "$ui" || echo 0
  echo -n "OutlinePanel: "; grep -c 'function OutlinePanel' "$ui" || echo 0
  echo -n "untilSeq: "; grep -c 'untilSeq' "$ui" || echo 0
  # host outlineOf
  local host
  host=$(find "$RC2_CORE_DIR/.pnpm" -path '*dsh-host-apiproxy@0.1.1-rc.2*/lib/index.js' 2>/dev/null | head -1)
  [ -n "$host" ] && echo -n "outlineOf: " && grep -c 'function outlineOf' "$host" || echo "outlineOf: 未找到host"
  log "--- verify 完成 ---"
}

# 切换服务: 修改 dsh-web.service 启动命令指向新核心根并重启
start() {
  log "--- start: 切换服务启动路径 ---"
  # 备份当前 unit (已由 backup 做; 再记录一份)
  cp /etc/systemd/system/$PROD_SERVICE "$BACKUP_DIR/last/$PROD_SERVICE.unit.bak" 2>/dev/null \
    || mkdir -p "$BACKUP_DIR/last" && cp /etc/systemd/system/$PROD_SERVICE "$BACKUP_DIR/last/$PROD_SERVICE.unit.bak"
  local newbin="$RC2_CORE_DIR/@deepseek-ai/dsh/lib/bin.js"
  [ -f "$newbin" ] || die "新 bin.js 不存在"
  # 生成新 unit (ExecStart 改为直接 node 新根 bin.js; 保留原 环境/参数)
  cat > /etc/systemd/system/$PROD_SERVICE <<UNIT
# auto-generated by dsh-longlongchat production-install.sh (RC2 upgrade)
[Unit]
Description=DSH production Web client (RC2 0.1.1-rc.2 + longlongchat patches)
After=network.target dsh-memory-server.service

[Service]
Type=simple
WorkingDirectory=$PROD_HOME
Environment=DSH_HOME=$PROD_HOME/home
ExecStart=/usr/local/bin/node $newbin web --port $PROD_PORT --trusted-host 110.42.47.93:3080 --no-open
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl restart "$PROD_SERVICE"
  sleep 6
  if systemctl is-active --quiet "$PROD_SERVICE"; then
    log "服务已重启为 RC2 核心"
  else
    log "WARN: 服务未 active, 检查 journalctl -u $PROD_SERVICE"
  fi
  curl -sS -o /dev/null -w "HTTP %{http_code}\n" --max-time 8 "http://127.0.0.1:$PROD_PORT/" 2>&1 || echo "HTTP 无响应"
}

# 回滚: 恢复服务 unit(备份) 并重启(核心无需动, 因原核心未改)
rollback() {
  log "--- rollback ---"
  local unitbak="$BACKUP_DIR/last/$PROD_SERVICE.unit.bak"
  if [ -f "$unitbak" ]; then
    cp "$unitbak" /etc/systemd/system/$PROD_SERVICE
    systemctl daemon-reload
    systemctl restart "$PROD_SERVICE"
    sleep 6
    log "服务已回滚(核心=原 /usr/local/node ...)"
    curl -sS -o /dev/null -w "HTTP %{http_code}\n" --max-time 8 "http://127.0.0.1:$PROD_PORT/" 2>&1 || echo "无响应"
  elif [ -f "$BACKUP_DIR/$(cat "$BACKUP_DIR/last-backup" 2>/dev/null || echo x)/dsh-web.service.unit" ]; then
    cp "$BACKUP_DIR/$(cat "$BACKUP_DIR/last-backup" 2>/dev/null || echo x)/dsh-web.service.unit" /etc/systemd/system/$PROD_SERVICE
    systemctl daemon-reload
    systemctl restart "$PROD_SERVICE"
    sleep 6
    log "服务已回滚(从 backup 目录)"
    curl -sS -o /dev/null -w "HTTP %{http_code}\n" --max-time 8 "http://127.0.0.1:$PROD_PORT/" 2>&1 || echo "无响应"
  else
    die "无备份 unit 可回滚; 手动执行: systemctl cat $PROD_SERVICE 还原 ExecStart"
  fi
}

case "${1:-status}" in
  backup)  backup ;;
  deploy)  deploy ;;
  verify)  verify ;;
  start)   start ;;
  rollback) rollback ;;
  status)  status ;;
  *) echo "usage: $0 {backup|deploy|verify|start|rollback|status}"; exit 1 ;;
esac
