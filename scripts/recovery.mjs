import { spawn, execFileSync } from 'node:child_process';
import { cp, lstat, mkdir, mkdtemp, readFile, statfs, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

const lastGood = 'refs/euclid/last-good';
const script = fileURLToPath(import.meta.url);

function git(root, ...args) {
  return execFileSync('git', ['-c', 'core.longpaths=true', '-C', root, ...args],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true }).trim();
}

function cleanRevision(root) {
  try {
    if (!git(root, 'status', '--porcelain')) return git(root, 'rev-parse', 'HEAD');
  } catch {}
  return '';
}

export async function launch({ root, binary, args, directory, timeout = 90_000, track = true, env = process.env }) {
  const ready = path.join(directory, 'ready');
  const log = path.join(directory, 'godot.log');
  const childEnv = { ...env, EUCLID_BOOT_READY: ready, EUCLID_BOOT_NODE: track ? process.execPath : '' };
  const revision = track ? cleanRevision(root) : '';
  const child = spawn(binary, ['--log-file', log, ...args],
    { cwd: root, env: childEnv, stdio: 'ignore', detached: true });
  const exited = new Promise(resolve => {
    child.once('error', error => resolve({ error: error.message }));
    child.once('exit', (code, signal) => resolve({ code, signal }));
  });
  const started = Date.now();
  try {
    while (Date.now() - started < timeout) {
      const outcome = await Promise.race([exited, delay(150)]);
      if (outcome) throw new Error(outcome.error ?? `Godot exited before startup completed (${outcome.code ?? outcome.signal}).`);
      const marker = await readFile(ready, 'utf8').catch(error => {
        if (error.code !== 'ENOENT') throw error;
      });
      if (marker !== String(child.pid)) continue;
      const startupLog = await readFile(log, 'utf8');
      if (/^(?:SCRIPT ERROR|ERROR):/m.test(startupLog)) throw new Error('Godot reported an error during startup.');
      if (revision && cleanRevision(root) === revision) git(root, 'update-ref', lastGood, revision);
      return { child, exited };
    }
    throw new Error('Godot did not report startup ready before the timeout.');
  } catch (error) {
    if (child.pid && child.exitCode === null && child.signalCode === null) {
      child.kill();
      await exited;
    }
    throw new Error(`${error.message}\nStartup log: ${log}`);
  }
}

export async function recover({ root, binary, directory, env = process.env, extraArgs = [] }) {
  let revision;
  try {
    revision = git(root, 'rev-parse', '--verify', `${lastGood}^{commit}`);
  } catch {
    throw new Error('No recovery build is recorded. Launch a clean committed build successfully first.');
  }
  const tree = path.join(directory, 'checkout');
  const disk = await statfs(directory);
  if (disk.bavail * disk.bsize < 2.25 * 1024 ** 3) {
    throw new Error('Free at least 2.25 GiB to open the isolated recovery build.');
  }
  git(root, 'worktree', 'add', '--detach', tree, revision);
  try {
    const world = path.join(tree, 'world');
    const filter = async source => !(await lstat(source)).isSymbolicLink();
    for (const entry of ['assets', '.godot/imported', '.godot/uid_cache.bin']) {
      const source = path.join(root, 'world', entry);
      const exists = await lstat(source).catch(error => { if (error.code !== 'ENOENT') throw error; });
      if (exists) await cp(source, path.join(world, entry), { recursive: true, force: false, filter });
    }
    const project = path.join(world, 'project.godot');
    const config = await readFile(project, 'utf8');
    if (!/^config\/use_custom_user_dir=true\s*$/m.test(config) || !/^config\/custom_user_dir_name=.+$/m.test(config)) {
      throw new Error('Could not isolate the recovery build’s saves.');
    }
    await writeFile(project, config
      .replace(/^config\/custom_user_dir_name=.*$/m, 'config/custom_user_dir_name="Godot/app_userdata/Euclid-recovery"')
      .replace(/^config\/name=.*$/m, 'config/name="Euclid | Recovery"'));
    const recoveryEnv = { ...env };
    for (const key of ['CONSTRUCT_GATEWAY_URL', 'CONSTRUCT_GATEWAY_TOKEN', 'EUCLID_WORKBENCH_TOKEN']) delete recoveryEnv[key];
    const { exited } = await launch({
      root: tree, binary, directory, track: false, env: recoveryEnv,
      args: ['--path', world, '--windowed', '--resolution', '1920x1080', ...extraArgs, '--', '--workbench-preview']
    });
    const result = await exited;
    if (result.code !== 0) throw new Error(`Recovery exited with ${result.code ?? result.signal}. See ${path.join(directory, 'godot.log')}.`);
  } finally {
    git(root, 'worktree', 'remove', '--force', tree);
  }
}

async function main([mode, binary, ...args]) {
  if (!['start', 'restart', 'recovery'].includes(mode) || !binary) throw new Error('Choose start, restart, or recovery and a Godot executable.');
  const root = path.dirname(path.dirname(script));
  const parent = path.join(root, '.local', 'recovery');
  await mkdir(parent, { recursive: true });
  const directory = await mkdtemp(path.join(parent, 'boot-'));
  if (mode === 'recovery') {
    console.log('Opening the last successful build in a separate checkout and save profile.');
    await recover({ root, binary, directory });
  } else {
    if (mode === 'restart') {
      const pid = Number(args.shift());
      if (!Number.isSafeInteger(pid) || pid <= 0) throw new Error('Invalid process to restart.');
      const deadline = Date.now() + 15_000;
      while (true) {
        try { process.kill(pid, 0); } catch (error) {
          if (error.code === 'ESRCH') break;
          throw error;
        }
        if (Date.now() >= deadline) throw new Error('The previous Euclid process did not exit.');
        await delay(150);
      }
    }
    const { child } = await launch({ root, binary, args, directory });
    child.unref();
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === script) {
  main(process.argv.slice(2)).catch(error => {
    console.error(error.message);
    console.error('Open Start Euclid Recovery.cmd to try the last successful build.');
    process.exitCode = 1;
  });
}
