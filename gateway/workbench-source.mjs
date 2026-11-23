import { createHash } from 'node:crypto';
import { lstat, readFile, readdir, realpath } from 'node:fs/promises';
import path from 'node:path';

export const sourceLimit = 64 * 1024;
const editable = /^world\/(?:scripts\/(?!diagnostics\/)(?:[\w-]+\/)*[\w.-]+\.gd|shaders\/(?:[\w-]+\/)*[\w.-]+\.gdshader(?:inc)?|data\/(?:[\w-]+\/)*[\w.-]+\.json|main\.tscn)$/;
const decode = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
export const fingerprint = text => createHash('sha256').update(text).digest('hex');
export const isSourcePath = name => typeof name === 'string' && editable.test(name) && !isKernelPath(name);
const agentSource = /^world\/(?:scripts\/(?:[\w-]+\/)*[\w.-]+\.gd(?:\.uid)?|scenes\/(?:[\w-]+\/)*[\w.-]+\.tscn|surfaces\/(?:[\w-]+\/)*[\w.-]+\.(?:html|css|js|svg))$/;
// The kernel decides what a draft may change, verifies and commits it, isolates its
// checks, and replaces the running gateway. No draft may change it. The launcher,
// check and recovery scripts under scripts/ and the files in the project root are
// outside every draft as well, so a bad change can always be reviewed and undone.
export const kernel = Object.freeze(['gateway/handoff.mjs', 'gateway/preview-base.mjs', 'gateway/workbench-git.mjs',
  'gateway/workbench-runner.mjs', 'gateway/workbench-source.mjs',
  'world/scripts/extensions/hot_load.gd', 'world/scripts/extensions/soft_restart.gd']);
export const isKernelPath = name => kernel.includes(name);
export const isGatewayPath = name => typeof name === 'string' && name.startsWith('gateway/');
const harness = /^(?:gateway\/(?:[\w-]+\/)*[\w.-]+\.(?:mjs|json)|gateway\/generators\/(?:[\w-]+\/)*[\w.-]+\.py|docs\/[\w.-]+\.md|README\.md)$/;
export const isAgentSourcePath = name => isSourcePath(name) ||
  (typeof name === 'string' && !isKernelPath(name) && (agentSource.test(name) || harness.test(name)));

export async function listSources(root) {
  const files = ['world/main.tscn'];
  async function scan(directory) {
    for (const item of await readdir(path.join(root, directory), { withFileTypes: true })) {
      const name = `${directory}/${item.name}`;
      if (item.isDirectory()) await scan(name);
      else if (item.isFile() && isSourcePath(name) && (await lstat(path.join(root, name))).size <= sourceLimit) files.push(name);
    }
  }
  for (const directory of ['world/scripts', 'world/shaders', 'world/data']) await scan(directory);
  return files.sort();
}

export async function readSource(root, name) {
  if (!isSourcePath(name)) throw new Error('Choose a source file from the workbench.');
  const base = await realpath(root);
  const file = path.join(base, name);
  const info = await lstat(file);
  if (!info.isFile() || info.size > sourceLimit || await realpath(file) !== file) throw new Error('This source file cannot be edited in the workbench.');
  const text = decode.decode(await readFile(file));
  if (text.includes('\0')) throw new Error('Choose a UTF-8 text file.');
  return { file, text, hash: fingerprint(text) };
}

export function normalizeEdit(original, text, limit = sourceLimit) {
  if (typeof text !== 'string' || text.includes('\0')) throw new Error('An edit must be UTF-8 text.');
  const normalized = text.replace(/\r\n/g, '\n');
  const formatted = original.includes('\r\n') ? normalized.replace(/\n/g, '\r\n') : normalized;
  if (Buffer.byteLength(formatted) > limit) throw new Error(`An edit must fit within ${limit / 1024} KiB.`);
  return formatted;
}

// What a connected agent may read: everything a source draft may change, plus the kernel,
// the project guides and the launcher scripts.
export const agentFileLimit = 256 * 1024;
const reference = /^(?:AGENTS\.md|package\.json|scripts\/[\w.-]+\.(?:ps1|mjs|py|sh))$/;
const isAgentReadable = name => isAgentSourcePath(name) || isKernelPath(name) || (typeof name === 'string' && reference.test(name));

export async function listAgentSources(root) {
  const files = [];
  async function scan(directory) {
    let items;
    try { items = await readdir(path.join(root, directory), { withFileTypes: true }); }
    catch (error) { if (error.code === 'ENOENT') return; throw error; }
    for (const item of items) {
      const name = `${directory}/${item.name}`;
      if (item.isDirectory()) await scan(name);
      else if (item.isFile() && !name.endsWith('.uid') && isAgentReadable(name) &&
        (await lstat(path.join(root, name))).size <= agentFileLimit) files.push(name);
    }
  }
  for (const directory of ['docs', 'gateway', 'scripts', 'world/scripts', 'world/shaders', 'world/data', 'world/scenes', 'world/surfaces']) await scan(directory);
  for (const name of ['README.md', 'AGENTS.md', 'package.json', 'world/main.tscn']) {
    const info = await lstat(path.join(root, name)).catch(error => { if (error.code !== 'ENOENT') throw error; });
    if (info?.isFile() && info.size <= agentFileLimit) files.push(name);
  }
  return files.sort();
}

export async function readAgentSource(root, name) {
  if (!isAgentReadable(name)) throw new Error('Choose a file from list_source.');
  const base = await realpath(root);
  const file = path.join(base, name);
  const info = await lstat(file).catch(error => { if (error.code !== 'ENOENT') throw error; });
  if (!info) throw new Error(`${name} does not exist.`);
  if (!info.isFile() || info.size > agentFileLimit || await realpath(file) !== file) throw new Error('This file cannot be read through the workbench.');
  const text = decode.decode(await readFile(file));
  if (text.includes('\0')) throw new Error('Choose a UTF-8 text file.');
  return { text, hash: fingerprint(text) };
}

const nestedQuantifier = /\([^)]*[+*][^)]*\)[+*{]/;

export async function searchAgentSources(root, { query, pathPrefix = '', regex = false, maxResults = 60 } = {}) {
  if (typeof query !== 'string' || query.length === 0 || query.length > 200) {
    throw new Error('query must be a string between 1 and 200 characters.');
  }
  const limit = Number.isInteger(maxResults) ? Math.min(100, Math.max(1, maxResults)) : 60;
  const prefix = typeof pathPrefix === 'string' ? pathPrefix.replace(/\\/g, '/').replace(/^\.\//, '') : '';
  let matcher = null;
  if (regex === true) {
    if (nestedQuantifier.test(query)) throw new Error('Regex pattern cannot contain nested quantifiers.');
    try { matcher = new RegExp(query, 'i'); }
    catch (error) { throw new Error(`Invalid regex: ${error.message}`); }
  }
  const needle = matcher ? '' : query.toLowerCase();
  const files = (await listAgentSources(root)).filter(name => prefix ? name.startsWith(prefix) : true);
  const matches = [];
  let truncated = false;
  let searched = 0;
  outer: for (const name of files) {
    let text;
    try { ({ text } = await readAgentSource(root, name)); }
    catch { continue; }
    searched++;
    const lines = text.replace(/\r\n?/g, '\n').split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const hit = matcher ? matcher.test(line) : line.toLowerCase().includes(needle);
      if (!hit) continue;
      if (matches.length >= limit) {
        truncated = true;
        break outer;
      }
      matches.push({ path: name, line: i + 1, text: line.slice(0, 200) });
    }
  }
  return { matches, truncated, searched };
}

const removedAssertion = /\b(?:test|_check)\s*\(|\bassert\.[a-z]+|\bMinimumFps\b|\bMaximumP95Ms\b/;

export function inspectCheckRisk(names = [], diff = '') {
  const files = Array.isArray(names) ? names : [];
  const reasons = new Set();
  for (const name of files) {
    if (typeof name !== 'string') continue;
    if (/\.test\.mjs$/.test(name)) reasons.add('edits gateway tests');
    if (name.startsWith('world/scripts/diagnostics/')) reasons.add('edits Godot diagnostics/tests');
    if (name === 'world/data/hot_reload.json') reasons.add('edits hot-reload tier rules');
  }
  if (typeof diff === 'string' && diff) {
    for (const line of diff.split(/\r?\n/)) {
      if (/^-(?!--)/.test(line) && removedAssertion.test(line)) {
        reasons.add('removes or alters existing assertions/budgets');
        break;
      }
    }
  }
  const list = [...reasons];
  return {
    touchesChecks: list.length > 0,
    reasons: list,
    warning: list.length ? 'Modifies checks: ' + list.join(', ') : '',
  };
}
