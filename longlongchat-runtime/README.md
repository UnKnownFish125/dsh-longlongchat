# LongLongChat

DeepSeek Harness long-conversation plugin: virtualized chat flow, grouped outline navigation, stable paging/follow, and the LongLongChat memory panel.

## Layout

- `dsh-longlongchat/` - single distributable plugin package:
  - `index.js` / `client.js` - web plugin (memory panel + `/mem-api` proxy).
  - `agent/index.js` - agent-plane memory plugin (recall, extraction, `/memory`).
  - `patches/rc6/` - DSH rc.6 core bundle patches (virtual flow, outline, anchor, `loadOlder(options)`).
  - `scripts/install-patch.mjs` - `apply` / `verify` / `restore` installer.
- `patches/` - rc.6 patch copies used for the running test machine.

## Deploy

Add the single package as a profile bundle:

```json
{
  "dependencies": {
    "dsh-longlongchat": "file:.../dsh-longlongchat"
  }
}
```

Then restart DSH Web. The postinstall script patches DSH rc.6 core bundles and backs up the originals. If DSH core is not under the profile install root, run:

```sh
node scripts/install-patch.mjs apply --root /path/to/dsh-install
node scripts/install-patch.mjs verify --root /path/to/dsh-install
node scripts/install-patch.mjs restore --root /path/to/dsh-install
```

The agent memory plugin is mounted from an agent preset row, for example `./node_modules/dsh-longlongchat/agent/index.js`. Memory panel requires the LongLongChat memory server on port 6230 and an API token at `$DSH_HOME/.dsh-memory-api-token`.
