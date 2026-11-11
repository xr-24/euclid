import assert from 'node:assert/strict';
import { chmod, mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { checkScope, createPreviewRunner } from './workbench-runner.mjs';

test('a draft is checked for what it can change', () => {
  assert.equal(checkScope(['README.md', 'docs/agents.md']), 'docs');
  assert.equal(checkScope(['gateway/server.mjs', 'docs/agents.md']), 'gateway');
  assert.equal(checkScope(['gateway/agents/claude.mjs', 'gateway/grid-plan.schema.json']), 'gateway');
  assert.equal(checkScope(['gateway/server.mjs', 'world/scripts/world.gd']), 'full');
  assert.equal(checkScope(['world/data/commands/scene.json']), 'full');
  assert.equal(checkScope(['docs/nested/guide.md']), 'full');
  assert.equal(checkScope(['scripts/check.ps1']), 'full');
  for (const unknown of [[], undefined, null, 'README.md', [7]]) assert.equal(checkScope(unknown), 'full');
});

// Stand-ins for Godot and PowerShell record how the runner called them.
async function fixture(t) {
  if (process.platform === 'win32') return t.skip('Uses shell scripts in place of Godot and PowerShell.');
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-runner-'));
  t.after(() => rm(area, { recursive: true, force: true }));
  const root = path.join(area, 'project');
  const live = {
    'world/assets/villa/statue.glb': 'statue mesh',
    'world/assets/villa/statue.glb.import': 'live import settings',
    'world/.godot/imported/statue.glb-1.scn': 'imported statue',
  };
  const worktree = path.join(area, 'draft/worktree');
  const reviewed = {
    'world/project.godot': 'config/name="Euclid"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="Godot/app_userdata/Euclid"\n',
    'world/scripts/world.gd': 'reviewed script',
    'world/assets/villa/statue.glb.import': 'reviewed import settings',
    'gateway/server.mjs': '', 'scripts/check.ps1': '', 'package.json': '{}',
  };
  for (const [folder, files] of [[root, live], [worktree, reviewed]]) {
    for (const [name, text] of Object.entries(files)) {
      await mkdir(path.dirname(path.join(folder, name)), { recursive: true });
      await writeFile(path.join(folder, name), text);
    }
  }
  const record = path.join(area, 'calls.log');
  const godot = path.join(area, 'godot.sh');
  const powershell = path.join(area, 'powershell.sh');
  await writeFile(godot, `#!/bin/sh\necho "godot $*" >> "${record}"\n`);
  await writeFile(powershell, `#!/bin/sh\necho "check scope=\${EUCLID_CHECK_SCOPE:-full} gateway=\${CONSTRUCT_GATEWAY_TOKEN:-none}" >> "${record}"\n`);
  await Promise.all([chmod(godot, 0o755), chmod(powershell, 0o755)]);
  const previous = { GODOT_BIN: process.env.GODOT_BIN, CONSTRUCT_GATEWAY_TOKEN: process.env.CONSTRUCT_GATEWAY_TOKEN };
  Object.assign(process.env, { GODOT_BIN: godot, CONSTRUCT_GATEWAY_TOKEN: 'secret' });
  t.after(() => {
    for (const [name, value] of Object.entries(previous)) if (value === undefined) delete process.env[name]; else process.env[name] = value;
  });
  const base = path.join(area, 'storage/preview-base');
  const runner = createPreviewRunner(root, { base, powershell });
  const calls = async () => (await readFile(record, 'utf8').catch(() => '')).trim().split('\n').filter(Boolean);
  const draft = names => ({ directory: path.join(area, 'draft'), worktree, id: 'abc', names });
  return { area, root, base, runner, calls, draft };
}

const check = async (runner, draft) => {
  let log = '';
  const result = await runner.check(draft, chunk => { log += chunk; }, new AbortController().signal);
  return { result, log };
};

test('a full check links the base into a preview of the reviewed worktree', async t => {
  const setup = await fixture(t);
  if (!setup) return;
  const { area, root, base, runner, calls, draft } = setup;
  assert.throws(() => createPreviewRunner(root, { base: path.join(root, 'world/base') }), /outside the project world/);
  const { result, log } = await check(runner, draft(['world/scripts/world.gd']));
  assert.deepEqual(result, { scope: 'full' });
  assert.match(log, /Linked 2 art and import files\./);
  assert.match(log, /Running Euclid project checks/);
  const [importCall, checkCall] = await calls();
  assert.match(importCall, /^godot --headless --path .*--editor --import$/);
  assert.equal(checkCall, 'check scope=full gateway=none', 'the check gets every test and no gateway credential');

  const tree = path.join(area, 'draft/preview');
  assert.equal(await readFile(path.join(tree, 'world/scripts/world.gd'), 'utf8'), 'reviewed script');
  assert.equal(await readFile(path.join(tree, 'world/assets/villa/statue.glb.import'), 'utf8'), 'reviewed import settings');
  const statue = 'world/assets/villa/statue.glb';
  assert.equal((await stat(path.join(tree, statue))).ino, (await stat(path.join(base, statue))).ino);
  assert.notEqual((await stat(path.join(tree, statue))).ino, (await stat(path.join(root, statue))).ino);
  assert.match(await readFile(path.join(tree, 'world/project.godot'), 'utf8'), /Euclid-workbench-abc/);
});

test('a gateway draft skips the Godot core and smoke tests', async t => {
  const setup = await fixture(t);
  if (!setup) return;
  const { result, log } = await check(setup.runner, setup.draft(['gateway/server.mjs', 'docs/agents.md']));
  assert.deepEqual(result, { scope: 'gateway' });
  assert.match(log, /without the Godot core and smoke tests/);
  const [importCall, checkCall] = await setup.calls();
  assert.match(importCall, /--import$/, 'the command contract still needs an imported project');
  assert.equal(checkCall, 'check scope=gateway gateway=none');
});

test('a documentation draft runs nothing', async t => {
  const setup = await fixture(t);
  if (!setup) return;
  const { result, log } = await check(setup.runner, setup.draft(['README.md', 'docs/water.md']));
  assert.deepEqual(result, { scope: 'docs' });
  assert.match(log, /only documentation/);
  assert.deepEqual(await setup.calls(), []);
  await assert.rejects(stat(path.join(setup.area, 'draft/preview')), { code: 'ENOENT' });
});
