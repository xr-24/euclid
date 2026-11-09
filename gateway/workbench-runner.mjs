import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { cp, lstat, mkdir, statfs, writeFile, readFile, rm } from 'node:fs/promises';
import path from 'node:path';

function childEnvironment(godot) {
  const env = { ...process.env, GODOT_BIN: godot };
  for (const name of Object.keys(env)) {
    if (/^(?:CONSTRUCT_|EUCLID_|SKETCHFAB_|OPENAI_|CODEX_)/i.test(name)) delete env[name];
  }
  return env;
}

function run(file, args, { cwd, env, timeout, onOutput, signal }) {
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
    const timer = setTimeout(() => stopChild(new Error('Preview checks timed out.')), timeout);
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

export function createPreviewRunner(root) {
  const godot = process.env.GODOT_BIN || path.join(root, '.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
  const env = childEnvironment(godot);
  let preview = null;
  return {
    async check(draft, onOutput, signal) {
      const { directory, name, after, id } = draft;
      const tree = path.join(directory, 'preview');
      await rm(tree, { recursive: true, force: true });
      const disk = await statfs(directory);
      if (disk.bavail * disk.bsize < 2.5 * 1024 ** 3) throw new Error('Free at least 2.5 GiB for the disposable preview project.');
      await mkdir(tree);
      onOutput('Copying the preview project and assets.\n');
      for (const entry of ['world', 'gateway', 'scripts', 'package.json']) {
        await cp(path.join(root, entry), path.join(tree, entry), { recursive: true, filter: async source => {
          signal.throwIfAborted();
          const parts = path.relative(root, source).split(path.sep);
          if (parts.some(part => ['.local', '.tools', 'node_modules', '__pycache__'].includes(part))) return false;
          const cache = parts.indexOf('.godot');
          const allowed = cache === -1 || parts.length === cache + 1 || ['imported', 'uid_cache.bin'].includes(parts[cache + 1]);
          if (allowed && (await lstat(source)).isSymbolicLink()) throw new Error('The preview project contains a symbolic link.');
          return allowed;
        } });
      }
      await writeFile(path.join(tree, name), after);
      const project = path.join(tree, 'world/project.godot');
      const config = await readFile(project, 'utf8');
      const settings = config.replace(/^config\/custom_user_dir_name=.*$/m, `config/custom_user_dir_name="Godot/app_userdata/Euclid-workbench-${id}"`);
      if (settings === config || !/^config\/use_custom_user_dir=true\s*$/m.test(config)) throw new Error('The preview could not isolate its user data.');
      await writeFile(project, settings.replace(/^config\/name=.*$/m, 'config/name="Euclid | Preview"'));
      onOutput('Importing the isolated Godot project.\n');
      let importFailed = false;
      const importCode = await run(godot, ['--headless', '--path', path.join(tree, 'world'), '--editor', '--import'], {
        cwd: tree, env, timeout: 180000, signal, onOutput: chunk => {
          if (/^(?:SCRIPT ERROR|ERROR):/m.test(chunk)) importFailed = true;
          onOutput(chunk);
        },
      });
      if (importCode !== 0 || importFailed) throw new Error('Godot could not import the preview.');
      onOutput('Running Euclid project checks.\n');
      const code = await run('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(tree, 'scripts/check.ps1')],
        { cwd: tree, env, timeout: 180000, onOutput, signal });
      if (code !== 0) throw new Error('The preview failed its project checks.');
    },

    async play(draft) {
      if (preview) throw new Error('A preview is already running.');
      const world = path.join(draft.directory, 'preview/world');
      const application = godot.replace(/_console\.exe$/i, '.exe');
      const binary = existsSync(application) ? application : godot;
      const child = spawn(binary, ['--path', world, '--windowed', '--resolution', '1280x720', '--', '--workbench-preview'],
        { cwd: world, env, stdio: 'ignore' });
      preview = child;
      child.on('exit', () => { if (preview === child) preview = null; });
      child.on('error', () => { if (preview === child) preview = null; });
      await new Promise((resolve, reject) => { child.once('spawn', resolve); child.once('error', reject); });
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
