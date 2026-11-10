import { execFile } from 'node:child_process';
import path from 'node:path';
import { promisify } from 'node:util';

const execute = promisify(execFile);
const diffOptions = ['--no-ext-diff', '--no-textconv', '--no-color', '--no-renames', '--full-index'];

async function git(cwd, ...args) {
  const env = { ...process.env, GIT_TERMINAL_PROMPT: '0', GIT_EDITOR: 'true' };
  for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR']) delete env[key];
  try {
    const { stdout } = await execute('git', ['-c', 'core.longpaths=true', '-c', 'core.hooksPath=.git/euclid-disabled-hooks', '-c', 'commit.gpgSign=false', ...args],
      { cwd, env, windowsHide: true, timeout: 30000, maxBuffer: 768 * 1024 });
    return stdout;
  } catch (error) {
    throw new Error(error.stderr?.trim().slice(0, 600) || `Git could not run ${args[0]}.`);
  }
}

export function createWorkbenchGit(root) {
  const stageAll = worktree => git(worktree, 'add', '--all', '--', '.');

  async function primary() {
    try {
      const [head, branch, status] = await Promise.all([git(root, 'rev-parse', 'HEAD'),
        git(root, 'symbolic-ref', 'HEAD'), git(root, 'status', '--porcelain', '--untracked-files=all')]);
      return { head: head.trim(), branch: branch.trim(), clean: !status };
    } catch {
      throw new Error('Open a Git branch with a local baseline commit to use the workbench.');
    }
  }

  async function assertPrimary(base, branch) {
    const current = await primary();
    if (current.head !== base || current.branch !== branch) throw new Error('The main branch moved. The draft is still available for review.');
    if (!current.clean) throw new Error('The main checkout has local changes. Commit or set them aside before continuing.');
  }

  async function review(worktree, base, expected) {
    const [names, unknown, diff] = await Promise.all([
      git(worktree, 'diff', '--name-only', '--no-renames', '-z', base, '--'),
      git(worktree, 'ls-files', '--others', '--exclude-standard', '-z'),
      git(worktree, 'diff', ...diffOptions, base, '--'),
    ]);
    const changed = names.split('\0').filter(Boolean).sort();
    if (unknown || changed.length !== expected.length || changed.some((name, index) => name !== expected[index])) {
      throw new Error('The Git worktree has changes outside the reviewed file list.');
    }
    if (!diff) throw new Error('There are no Git changes to review.');
    return diff;
  }

  return {
    primary,
    assertPrimary,
    review,
    add: (worktree, base) => git(root, 'worktree', 'add', '--detach', worktree, base),
    apply: (worktree, file) => git(worktree, 'apply', '--whitespace=nowarn', '--', file),
    async changedPaths(worktree, base) {
      const changed = await git(worktree, 'diff', '--name-only', '--no-renames', '-z', base, '--');
      const added = await git(worktree, 'ls-files', '--others', '--exclude-standard', '-z');
      return [...new Set((changed + added).split('\0').filter(Boolean))].sort();
    },
    async snapshot(worktree) {
      await stageAll(worktree);
      return (await git(worktree, 'write-tree')).trim();
    },
    diffTrees: (before, after) => git(root, 'diff', ...diffOptions, before, after, '--'),
    intent: (worktree, names) => git(worktree, 'add', '--intent-to-add', '--', ...names),
    remove: (worktree) => git(root, 'worktree', 'remove', '--force', worktree),
    async headRevision() {
      try {
        const body = await git(root, 'log', '-1', '--format=%H%n%B');
        return /^Euclid-Workbench-Draft: [a-f0-9-]{36}$/m.test(body) ? body.split('\n', 1)[0] : '';
      } catch { return ''; }
    },
    async commit(draft, message) {
      const { worktree, base, branch, diff, id } = draft;
      await assertPrimary(base, branch);
      const head = (await git(worktree, 'rev-parse', 'HEAD')).trim();
      if (head === base) {
        await stageAll(worktree);
        if (await git(worktree, 'diff', '--cached', ...diffOptions, base, '--') !== diff) throw new Error('The Git index differs from the reviewed draft.');
        await git(worktree, 'commit', '-m', message, '-m', `Euclid-Workbench-Draft: ${id}`);
      }
      const [commit, parent, committed, status, body] = await Promise.all([
        git(worktree, 'rev-parse', 'HEAD'), git(worktree, 'rev-list', '--parents', '-1', 'HEAD'),
        git(worktree, 'diff', ...diffOptions, base, 'HEAD', '--'),
        git(worktree, 'status', '--porcelain', '--untracked-files=all'), git(worktree, 'log', '-1', '--format=%B'),
      ]);
      if (parent.trim() !== `${commit.trim()} ${base}` || committed !== diff || status || !body.trimEnd().endsWith(`Euclid-Workbench-Draft: ${id}`)) {
        throw new Error('The draft commit differs from the reviewed changes.');
      }
      await assertPrimary(base, branch);
      await git(root, 'merge', '--ff-only', '--no-edit', commit.trim());
      return commit.trim();
    },
    async revert(revision) {
      const current = await primary();
      await assertPrimary(revision, current.branch);
      if (!current.clean) throw new Error('The main checkout has local changes.');
      await git(root, 'revert', '--no-edit', revision);
      return (await primary()).head;
    },
    async touched(revision) {
      const names = await git(root, 'diff', '--name-only', '--no-renames', '-z', `${revision}~1`, revision, '--');
      return names.split('\0').filter(Boolean);
    },
    worktreePath: directory => path.join(directory, 'worktree'),
  };
}
