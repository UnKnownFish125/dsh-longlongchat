# LongLongChat

DeepSeek Harness 长对话插件：虚拟滚动、分级大纲导航、加载更早时的滚动锚定，以及长期记忆 UI 与 Agent 记忆能力。一个 `dsh-longlongchat` 包交付全部能力。

## 包含内容

- `index.js` / `client.js`：Web 插件。注册 `/mem-api` 同源代理与记忆控制面板（会话状态卡、检索、图谱、归档、维护）。
- `agent/index.js`：Agent 侧记忆插件。语义召回注入、低成本 LLM 抽取、`/memory` 命令、`memory_recall` / `memory_save` / `memory_briefing` 工具。
- `patches/rc6/`：DSH `0.1.0-rc.6` 核心包完整补丁。
  - `dsh-client-runtime.client.js`：会话 `outline` 状态、`loadOlder(options)`、`prefetch()` 与 live outline 合并。
  - `dsh-client-ui-conversation.client.js`：`VirtualChatFlow` 虚拟滚动、`OutlinePanel` 大纲弹窗、分页锚定与像素校正。
  - `dsh-host-apiproxy.index.js`：`session.history` 返回按用户消息分组的 `outline`。
- `patches/rc2/`：DSH `0.1.1-rc.2` 核心包平行补丁，同构能力：`VirtualChatFlow`/`OutlinePanel`、`outline` 状态与 `loadOlder(options)` 批量（`untilSeq` 直达目标区、单次渲染）、host `outlineOf` 分组大纲。
- `scripts/install-patch.mjs`：安装、校验、恢复工具。

## 兼容性

当前同时支持 DSH `0.1.0-rc.6` 与 `0.1.1-rc.2`：安装器读取目标安装根的三个核心包版本，按 `0.1.0-rc.6 → patches/rc6/`、`0.1.1-rc.2 → patches/rc2/` 选择补丁；其他版本拒绝写入，避免破坏未验证的 DSH 发行版。同一 `apply / verify / restore` 接口覆盖全部受支持版本。

## 安装

在 DSH Web profile 中把本包加入 `package.json` 依赖，并让 profile 应用它的 bundle patch：

```json
{
  "dependencies": {
    "dsh-longlongchat": "file:../dsh-longlongchat"
  }
}
```

安装/重启后，核心补丁由 postinstall 自动执行；若 DSH 核心不在当前 `INIT_CWD`，手动指定安装根：

```sh
node scripts/install-patch.mjs apply --root /path/to/dsh-install
node scripts/install-patch.mjs verify --root /path/to/dsh-install
node scripts/install-patch.mjs restore --root /path/to/dsh-install
```

安装器会先备份每个核心文件为 `lib/<file>.longlongchat.bak`，`restore` 用备份还原。`verify` 只做只读检查，退出码 0 表示三个目标文件均与补丁完全一致。

Web 面板依赖 LongLongChat memory server：默认 `http://localhost:6230`，可用 `MEMORY_SERVER_PORT` 覆盖；token 从 `$DSH_HOME/.dsh-memory-api-token`（或 `$HOME/.dsh-memory-api-token`）读取。

Agent 侧插件由同一个 bundle patch 自动注册（`dsh-longlongchat/agent` 行），无需单独安装。若希望只在特定 preset 中挂载，可改为在 `agent.cordis.yml` 中引用：

```yaml
- id: longlongchat
  name: './node_modules/dsh-longlongchat/agent/index.js'
  config:
    preset_mode: task
    extraction_model: deepseek-official/deepseek-chat
```

`extraction_model` 支持 `provider/model` 或仅模型名；不配置时按 `deepseek-official` 的可用模型自动选择非 reasoner 模型。

## 已知限制

DSH 没有插件级 ChatView 替换缝，因此虚拟滚动和大纲必须修补核心包文件。核心升级后需要重新执行 `apply`；`verify` 会在升级后报告 `unpatched`，避免静默降级。恢复原始核心后，本插件 UI 的虚拟滚动和大纲能力会消失，记忆面板与 Agent 记忆工具仍可用。
