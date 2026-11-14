import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { access, cp, lstat, mkdir, open, statfs, writeFile, readFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { assertSeparateBase, linkBase, syncBase } from './preview-base.mjs';
import { fingerprint, isGatewayPath } from './workbench-source.mjs';

const previewLogPath = draft => path.join(draft.directory, `preview-${fingerprint(draft.diff)}.log`);
const isDocPath = name => name === 'README.md' || /^docs\/[\w.-]+\.md$/.test(name);
export const validCheckView = name => typeof name === 'string' && /^[a-z0-9_-]{1,64}$/.test(name);

// What a draft's checks must cover. Documentation runs nothing. Gateway code skips the
// Godot core and smoke tests, whose code it cannot change, but keeps the import so the
// command contract test can compare the gateway with Godot. Anything else gets every check.
export function checkScope(names) {
  if (!Array.isArray(names) || !names.length || !names.every(name => typeof name === 'string')) return 'full';
  if (names.every(isDocPath)) return 'docs';
  if (names.every(name => isDocPath(name) || isGatewayPath(name))) return 'gateway';
  return 'full';
}

function childEnvironment(godot) {
  const env = { ...process.env, GODOT_BIN: godot };
  for (const name of Object.keys(env)) {
    if (/^(?:CONSTRUCT_|EUCLID_|SKETCHFAB_|OPENAI_|CODEX_|ELEVENLABS_)/i.test(name)) delete env[name];
  }
  return env;
}

function run(file, args, { cwd, env, timeout, phase, onOutput, signal }) {
  signal.throwIfAborted();
  return new Promise((resolve, reject) => {
    const child = spawn(file, args, { cwd, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    for (const stream of [child.stdout, child.stderr]) {
      stream.setEncoding('utf8');
      stream.on('data', onOutput);
    }
    let failure;
    function stopChild(error) {
      if (failure) return;
      failure = error;
      if (process.platform === 'win32' && child.pid) {
        const stop = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
        stop.on('error', () => child.kill());
      } else child.kill();
    }
    const abort = () => stopChild(signal.reason);
    const timer = setTimeout(() => stopChild(new Error(`${phase} timed out after ${timeout / 1000} seconds.`)), timeout);
    signal.addEventListener('abort', abort, { once: true });
    child.on('error', reject);
    child.on('close', code => {
      clearTimeout(timer);
      signal.removeEventListener('abort', abort);
      if (failure) reject(failure);
      else resolve(code);
    });
  });
}

export function createPreviewRunner(root, { benchmarkWindowId = 0, base = path.join(root, '.local/preview-base'), powershell = 'powershell.exe' } = {}) {
  const godot = process.env.GODOT_BIN || path.join(root, '.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
  const env = childEnvironment(godot);
  assertSeparateBase(root, base);
  let preview = null;
  let baseTurn = Promise.resolve();
  // One preview at a time updates the shared base and links from it.
  function fillFromBase(tree, onOutput, signal) {
    const turn = baseTurn.then(async () => {
      const names = await syncBase(root, base, { signal, onOutput });
      const { linked, copied } = await linkBase(base, tree, names, { signal });
      onOutput(`Linked ${linked} art and import files${copied ? `, copied ${copied}` : ''}.\n`);
    });
    baseTurn = turn.catch(() => {});
    return turn;
  }
  async function prepare({ directory, worktree, id }, onOutput, signal) {
    const tree = path.join(directory, 'preview');
    await rm(tree, { recursive: true, force: true });
    const disk = await statfs(directory);
    if (disk.bavail * disk.bsize < 512 * 1024 ** 2) throw new Error('Free at least 0.5 GiB for the disposable preview project.');
    await mkdir(tree);
    onOutput('Preparing a preview from the reviewed Git worktree.\n');
    const copyFilter = async source => {
      signal.throwIfAborted();
      if ((await lstat(source)).isSymbolicLink()) throw new Error('The preview project contains a symbolic link.');
      return true;
    };
    // The relay is copied too, because the gateway tests exercise its core. Older drafts may not have it.
    for (const entry of ['world', 'gateway', 'scripts', 'relay', 'package.json']) {
      if (!existsSync(path.join(worktree, entry))) continue;
      await cp(path.join(worktree, entry), path.join(tree, entry), { recursive: true, filter: async source => {
        const parts = path.relative(worktree, source).split(path.sep);
        if (parts.some(part => ['.local', '.tools', '.godot', 'override.cfg', 'node_modules', '__pycache__'].includes(part))) return false;
        return copyFilter(source);
      } });
    }
    onOutput('Linking the local art pack and import cache.\n');
    await fillFromBase(tree, onOutput, signal);
    const project = path.join(tree, 'world/project.godot');
    const config = await readFile(project, 'utf8');
    const settings = config.replace(/^config\/custom_user_dir_name=.*$/m, `config/custom_user_dir_name="Godot/app_userdata/Euclid-workbench-${id}"`);
    if (settings === config || !/^config\/use_custom_user_dir=true\s*$/m.test(config)) throw new Error('The preview could not isolate its user data.');
    await writeFile(project, settings.replace(/^config\/name=.*$/m, 'config/name="Euclid | Preview"'));
    onOutput('Importing the isolated Godot project.\n');
    let importFailed = false;
    const importCode = await run(godot, ['--headless', '--path', path.join(tree, 'world'), '--editor', '--import'], {
      cwd: tree, env, timeout: 180000, phase: 'Godot import', signal, onOutput: chunk => {
        if (/^(?:SCRIPT ERROR|ERROR):/m.test(chunk)) importFailed = true;
        onOutput(chunk);
      },
    });
    if (importCode !== 0 || importFailed) throw new Error('Godot could not import the preview.');
    return tree;
  }

  return {
    async check(draft, onOutput, signal) {
      const scope = checkScope(draft.names);
      if (scope === 'docs') {
        onOutput('This draft changes only documentation, so there is nothing to run.\n');
        return { scope };
      }
      const tree = await prepare(draft, onOutput, signal);
      onOutput(scope === 'gateway'
        ? 'This draft changes only the gateway and docs. Running the gateway tests and command contract without the Godot core and smoke tests.\n'
        : 'Running Euclid project checks.\n');
      const code = await run(powershell, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(tree, 'scripts/check.ps1')],
        { cwd: tree, env: scope === 'gateway' ? { ...env, EUCLID_CHECK_SCOPE: 'gateway' } : env,
          timeout: 300000, phase: scope === 'gateway' ? 'Gateway checks' : 'Project checks', onOutput, signal });
      if (code !== 0) throw new Error('The preview failed its project checks.');
      const captures = [];
      if (scope === 'full' && process.platform === 'win32' && existsSync(path.join(tree, 'scripts/background-render.py'))) {
        const output = path.join(draft.directory, `check-images-${fingerprint(draft.diff)}`);
        try {
          await rm(output, { recursive: true, force: true });
          const binary = godot.replace(/_console\.exe$/i, '.exe');
          const captureCode = await run(process.env.EUCLID_PYTHON || 'python',
            [path.join(tree, 'scripts/background-render.py'), '--draft-view', '--output', output, '--timeout', '90'],
            { cwd: tree, env: { ...env, GODOT_BIN: binary }, timeout: 105000, phase: 'Draft screenshots', onOutput, signal });
          if (captureCode !== 0) throw new Error('The background renderer failed.');
          const { zones } = JSON.parse(await readFile(path.join(tree, 'world/data/world.json'), 'utf8'));
          for (const { id } of zones.slice(0, 12)) {
            if (!validCheckView(id)) throw new Error('A capture has an invalid environment ID.');
            await access(path.join(output, `${id}.jpg`));
            captures.push(id);
          }
        } catch (error) {
          signal.throwIfAborted();
          onOutput(`Draft screenshots unavailable: ${error.message}\n`);
        }
      }
      return { scope, captures };
    },

    async benchmark(source, output, settings, onOutput, signal) {
      const tree = await prepare(source, onOutput, signal);
      const code = await run(powershell, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        path.join(root, 'scripts/benchmark.ps1'), '-ProjectPath', path.join(tree, 'world'),
        '-OutputDirectory', output, '-Zone', settings.zone, '-Quality', settings.profile,
        '-Width', String(settings.width), '-Height', String(settings.height), '-WindowId', String(benchmarkWindowId)],
      { cwd: root, env, timeout: 150000, phase: 'Environment benchmark', onOutput, signal });
      if (code !== 0) throw new Error('The environment benchmark failed. See the run output.');
      for (const view of settings.views) await access(path.join(output, `${settings.zone}_${view}.png`));
      const result = JSON.parse(await readFile(path.join(output, 'results.json'), 'utf8'));
      return { ...result, mode: benchmarkWindowId ? 'embedded' : 'desktop' };
    },

    async play(draft) {
      if (preview) throw new Error('A preview is already running.');
      const world = path.join(draft.directory, 'preview/world');
      const application = godot.replace(/_console\.exe$/i, '.exe');
      const binary = existsSync(application) ? application : godot;
      const log = previewLogPath(draft);
      await rm(log, { force: true });
      const child = spawn(binary, ['--path', world, '--windowed', '--resolution', '1280x720', '--log-file', log,
        '--', '--workbench-preview'],
        { cwd: world, env, stdio: 'ignore' });
      preview = child;
      child.on('exit', () => { if (preview === child) preview = null; });
      child.on('error', () => { if (preview === child) preview = null; });
      await new Promise((resolve, reject) => { child.once('spawn', resolve); child.once('error', reject); });
    },

    async previewLog(draft) {
      const file = await open(previewLogPath(draft), 'r').catch(error => {
        if (error.code !== 'ENOENT') throw error;
      });
      if (!file) return '';
      try {
        const { size } = await file.stat();
        const bytes = Buffer.alloc(Math.min(size, 12000));
        const { bytesRead } = await file.read(bytes, 0, bytes.length, size - bytes.length);
        return bytes.toString('utf8', 0, bytesRead);
      } finally { await file.close(); }
    },

    async stop() {
      const child = preview;
      if (!child) return;
      const stopped = new Promise(resolve => child.once('close', resolve));
      child.kill();
      await stopped;
    },

    playing: () => preview !== null,
  };
}
