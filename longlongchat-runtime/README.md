# LongLongChat

DeepSeek Harness long-conversation plugin: virtualized chat flow, grouped outline navigation, stable paging/follow, and the LongLongChat memory panel.

## Layout

- `dsh-longlongchat/` - web/UI plugin (virtual flow patch, outline host/runtime patches, memory panel).
- `dsh-longlongchat-agent/` - global agent-plane memory plugin (recall, extraction, `/memory`).
- `patches/` - applyable patch files for DSH rc.6 bundles.

## Deploy

Add both packages as profile bundles:

```json
{
  "dependencies": {
    "dsh-longlongchat": "file:...",
    "dsh-longlongchat-agent": "file:..."
  }
}
```

Then restart DSH Web. Memory panel requires the LongLongChat memory server on port 6230 and an API token at `$DSH_HOME/.dsh-memory-api-token`.
