#!/usr/bin/env node
// LongLongChat core-file patch installer.
//
// DSH rc.6 has no plugin-only seam for replacing the official ChatView
// renderers, so this package patches the installed core bundles when the
// profile is provisioned. `verify` is non-destructive; `apply` backs up each
// file before replacing it; `restore` reverts from those backups.
//
// Usage:
//   node scripts/install-patch.mjs apply   [--root <dsh-install-root>]
//   node scripts/install-patch.mjs verify  [--root <dsh-install-root>]
//   node scripts/install-patch.mjs restore [--root <dsh-install-root>]
//
// Without `--root`, the root comes from INIT_CWD (npm/pnpm postinstall) or the
// nearest ancestor of this package that has node_modules/@deepseek-ai.

import { createHash } from 'node:crypto'
import { copyFile, mkdir, readFile, stat, writeFile } from 'node:fs/promises'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const pkgRoot = resolve(__dirname, '..')

const SUPPORTED_RELEASES = new Set(['0.1.0-rc.6'])

const TARGETS = [
  {
    key: 'host-apiproxy',
    pkgName: 'dsh-host-apiproxy',
    rel: ['@deepseek-ai', 'dsh-host-apiproxy', 'lib', 'index.js'],
    patchFile: ['patches', 'rc6', 'dsh-host-apiproxy.index.js'],
  },
  {
    key: 'client-runtime',
    pkgName: 'dsh-client-runtime',
    rel: ['@deepseek-ai', 'dsh-client-runtime', 'lib', 'client.js'],
    patchFile: ['patches', 'rc6', 'dsh-client-runtime.client.js'],
  },
  {
    key: 'ui-conversation',
    pkgName: 'dsh-client-ui-conversation',
    rel: ['@deepseek-ai', 'dsh-client-ui-conversation', 'lib', 'client.js'],
    patchFile: ['patches', 'rc6', 'dsh-client-ui-conversation.client.js'],
  },
]

function hashOf(text) {
  return createHash('sha256').update(text).digest('hex')
}

function log(label, message) {
  process.stdout.write(`[dsh-longlongchat] ${label}: ${message}\n`)
}

function readJsonIfExists(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch {
    return null
  }
}

async function readRelease(root) {
  const versions = []
  for (const target of TARGETS) {
    const pkgFile = join(root, 'node_modules', '@deepseek-ai', target.pkgName, 'package.json')
    const pkg = readJsonIfExists(pkgFile)
    if (pkg?.version) versions.push(pkg.version)
  }
  if (versions.length === 0) return null
  return versions.every((version) => version === versions[0]) ? versions[0] : versions[0] + '+mixed'
}

function resolveDshRoot(explicitRoot) {
  if (explicitRoot) return resolve(explicitRoot)
  const initCwd = process.env.INIT_CWD
  if (initCwd && existsSync(join(initCwd, 'package.json'))) return resolve(initCwd)
  let parent = resolve(pkgRoot, '..')
  while (parent !== dirname(parent)) {
    if (existsSync(join(parent, 'node_modules', '@deepseek-ai'))) return parent
    parent = dirname(parent)
  }
  return resolve(pkgRoot, '..')
}

function targetPath(root, target) {
  return join(root, 'node_modules', ...target.rel)
}

function stateFile(root) {
  return join(root, 'dsh-longlongchat-patch-state.json')
}

async function verifyTarget(root, target) {
  const file = targetPath(root, target)
  const current = await readFile(file, 'utf8').catch(() => null)
  if (current === null) return { status: 'missing' }
  const expected = await readFile(resolve(pkgRoot, ...target.patchFile), 'utf8')
  const patched = hashOf(current) === hashOf(expected)
  return { status: patched ? 'patched' : 'unpatched' }
}

async function backupTarget(root, target) {
  const dest = targetPath(root, target)
  const backup = `${dest}.longlongchat.bak`
  if (!existsSync(backup)) await copyFile(dest, backup)
  return backup
}

async function main() {
  const args = process.argv.slice(2)
  const mode = args.find((arg) => !arg.startsWith('--')) ?? 'verify'
  const rootArg = args.find((arg) => arg.startsWith('--root='))?.split('=')[1]
    ?? (args.includes('--root') ? args[args.indexOf('--root') + 1] : undefined)
  const root = resolveDshRoot(rootArg)
  const release = await readRelease(root)
  log('mode', `${mode} root=${root} release=${release ?? 'unresolved'}`)

  if (mode === 'verify') {
    let all = true
    for (const target of TARGETS) {
      const status = await verifyTarget(root, target)
      log(target.key, status.status)
      if (status.status !== 'patched') all = false
    }
    process.exitCode = all ? 0 : 1
    return
  }

  if (mode === 'restore') {
    for (const target of TARGETS) {
      const backup = `${targetPath(root, target)}.longlongchat.bak`
      if (existsSync(backup)) {
        await copyFile(backup, targetPath(root, target))
        log(target.key, 'restored')
      } else {
        log(target.key, 'no backup found')
      }
    }
    return
  }

  if (mode !== 'apply') throw new Error(`unknown mode: ${mode}`)
  if (!release) {
    log('apply', 'DSH core packages not found at this install root; skip patching here.')
    log('apply', 'Run `pnpm patch:apply --root <dsh-install-root>` against the DSH core installation.')
    return
  }
  if (!SUPPORTED_RELEASES.has(release)) {
    log('apply', `unsupported release ${release}; supported: ${[...SUPPORTED_RELEASES].join(', ')}`)
    process.exitCode = 1
    return
  }

  for (const target of TARGETS) {
    const dest = targetPath(root, target)
    await mkdir(dirname(dest), { recursive: true })
    const status = await verifyTarget(root, target)
    if (status.status === 'patched') {
      log(target.key, 'already patched')
      continue
    }
    await backupTarget(root, target)
    await copyFile(resolve(pkgRoot, ...target.patchFile), dest)
    log(target.key, `patched (${relative(pkgRoot, resolve(pkgRoot, ...target.patchFile))})`)
  }
  await writeFile(stateFile(root), JSON.stringify({
    release,
    appliedAt: new Date().toISOString(),
    targets: TARGETS.map((target) => target.key),
  }, null, 2) + '\n')
  log('done', `LongLongChat patches applied for ${release}`)
}

main().catch((error) => {
  process.stderr.write(`[dsh-longlongchat] fatal: ${String(error)}\n`)
  process.exitCode = 1
})
