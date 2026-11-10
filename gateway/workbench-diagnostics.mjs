import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

const settings = { profile: 'balanced', width: 1920, height: 1080 };
const views = ['arrival', 'pool', 'portico'];
const metrics = ['fps', 'p95_ms', 'p99_ms', 'gpu_ms', 'cpu_process_ms', 'draw_calls', 'primitives'];
const runId = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;

function validate(result) {
  if (result?.schema_version !== 1 || result.profile !== settings.profile || result.vsync !== false ||
      result.resolution?.[0] !== settings.width || result.resolution?.[1] !== settings.height ||
      typeof result.renderer !== 'string' || !result.renderer || typeof result.device !== 'string' || !result.device ||
      !['desktop', 'embedded'].includes(result.mode) || !Array.isArray(result.samples) || result.samples.length !== views.length) {
    throw new Error('The benchmark did not use the expected display settings.');
  }
  const samples = views.map(view => {
    const sample = result.samples.find(item => item.zone === 'villa' && item.variant === 'default' && item.view === view);
    if (!sample || !Number.isInteger(sample.frames) || sample.frames < 3 ||
        !metrics.every(key => Number.isFinite(sample[key]) && sample[key] >= 0)) {
      throw new Error('The benchmark did not measure every fixed villa view.');
    }
    return { view, frames: sample.frames, ...Object.fromEntries(metrics.map(key => [key, sample[key]])) };
  });
  return { renderer: result.renderer, device: result.device, mode: result.mode, samples };
}

export function createWorkbenchDiagnostics(storage, git, runner) {
  const directory = path.resolve(storage, 'diagnostics');
  const runs = path.join(directory, 'runs');
  const scope = (draft, version) => draft ? draft.id + '-' + version : 'baseline';
  const index = key => path.join(directory, key + '.json');

  async function read(key) {
    let report;
    try { report = JSON.parse(await readFile(index(key), 'utf8')); }
    catch (error) { if (error.code === 'ENOENT' || error instanceof SyntaxError) return null; throw error; }
    return runId.test(report?.id) ? { ...report, directory: path.join(runs, report.id) } : null;
  }

  async function save(key, report) {
    const prior = await read(key);
    const file = index(key);
    await writeFile(file + '.next', JSON.stringify(report));
    await rename(file + '.next', file);
    if (prior && prior.id !== report.id) await rm(path.join(runs, prior.id), { recursive: true, force: true }).catch(() => {});
  }

  return {
    async state(draft, version) {
      return read(scope(draft, version));
    },

    async run(job, draft, version, base, signal, verify) {
      const folder = path.join(runs, job.id);
      const worktree = path.join(folder, 'worktree');
      const snapshot = path.join(folder, 'snapshot');
      const report = { id: job.id, status: 'failed', name: 'Villa frame times', ...settings, base,
        version: version || '', completed_at: '', before: null, after: null, error: '', log: '' };
      const update = chunk => { job.log = (job.log + chunk).slice(-12000); };
      try {
        await mkdir(snapshot, { recursive: true });
        await git.add(worktree, base);
        update('Measuring the pinned Git baseline.\n');
        report.before = validate(await runner.benchmark({ directory: snapshot, worktree, id: job.id },
          path.join(folder, 'before'), settings, update, signal));
        if (draft) {
          await verify(draft);
          update('Measuring the reviewed draft.\n');
          report.after = validate(await runner.benchmark({ directory: snapshot, worktree: draft.worktree, id: job.id },
            path.join(folder, 'after'), settings, update, signal));
          await verify(draft);
          if (['device', 'renderer', 'mode'].some(key => report.before[key] !== report.after[key])) {
            throw new Error('The baseline and draft used different rendering devices or modes.');
          }
        }
        signal.throwIfAborted();
        report.status = 'complete';
      } catch (error) {
        report.error = error.message;
      } finally {
        await git.remove(worktree).catch(() => {});
        await rm(snapshot, { recursive: true, force: true }).catch(() => {});
      }
      if (signal.aborted) {
        await rm(folder, { recursive: true, force: true }).catch(() => {});
        return;
      }
      report.log = job.log;
      report.completed_at = new Date().toISOString();
      await save(scope(draft, version), report);
    },
  };
}
