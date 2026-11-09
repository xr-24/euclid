import { readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

async function isFile(file) {
  try { return (await stat(file)).isFile(); }
  catch (error) {
    if (['ENOENT', 'ENOTDIR', 'EACCES'].includes(error.code)) return false;
    throw error;
  }
}

export async function resolveCodexBinary(env = process.env) {
  if (env.EUCLID_CODEX_BIN) return env.EUCLID_CODEX_BIN;
  if (process.platform !== 'win32') return 'codex';
  const searchPath = Object.entries(env).find(([key]) => key.toLowerCase() === 'path')?.[1] ?? '';
  const directories = searchPath.split(path.delimiter).map(item => item.replace(/^"|"$/g, '')).filter(Boolean);
  for (const directory of directories) {
    const native = path.join(directory, 'codex.exe');
    if (await isFile(native)) return native;
  }
  // Node's execFile cannot launch npm's .cmd shim. Resolve its native package
  // payload directly, including when Explorer supplied an older PATH.
  const npmDirectories = env.APPDATA ? [path.join(env.APPDATA, 'npm'), ...directories] : directories;
  const triple = process.arch === 'arm64' ? 'aarch64-pc-windows-msvc' : 'x86_64-pc-windows-msvc';
  for (const directory of new Set(npmDirectories)) {
    const root = path.join(directory, 'node_modules', '@openai', 'codex');
    const packages = [path.join(root, 'node_modules', '@openai', `codex-win32-${process.arch}`), root];
    for (const pkg of packages) {
      for (const folder of ['bin', 'codex']) {
        const native = path.join(pkg, 'vendor', triple, folder, 'codex.exe');
        if (await isFile(native)) return native;
      }
    }
  }
  if (env.LOCALAPPDATA) {
    const bin = path.join(env.LOCALAPPDATA, 'OpenAI', 'Codex', 'bin');
    let entries = [];
    try { entries = await readdir(bin, { withFileTypes: true }); }
    catch (error) { if (!['ENOENT', 'ENOTDIR'].includes(error.code)) throw error; }
    const candidates = [];
    for (const entry of entries.filter(item => item.isDirectory())) {
      const native = path.join(bin, entry.name, 'codex.exe');
      if (await isFile(native)) candidates.push({ file: native, modified: (await stat(native)).mtimeMs });
    }
    candidates.sort((a, b) => b.modified - a.modified);
    if (candidates.length) return candidates[0].file;
  }
  throw new Error('Install the Codex CLI or set EUCLID_CODEX_BIN to its executable.');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(await resolveCodexBinary()); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
