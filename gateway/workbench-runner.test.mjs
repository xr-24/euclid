import assert from 'node:assert/strict';
import { chmod, mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { checkScope, createPreviewRunner, visualChange } from './workbench-runner.mjs';

test('a draft is checked for what it can change', () => {
  assert.equal(checkScope(['README.md', 'docs/agents.md']), 'docs');
  assert.equal(checkScope(['gateway/server.mjs', 'docs/agents.md']), 'gateway');
  assert.equal(checkScope(['gateway/agents/claude.mjs', 'gateway/grid-plan.schema.json']), 'gateway');
  assert.equal(checkScope(['gateway/server.mjs', 'world/scripts/world.gd']), 'full');
  assert.equal(checkScope(['world/data/commands/scene.json']), 'full');
  assert.equal(checkScope(['docs/nested/guide.md']), 'full');
  assert.equal(checkScope(['scripts/check.ps1']), 'full');
  // Godot scripts, shaders and scenes skip the gateway tests; data the gateway reads does not.
  assert.equal(checkScope(['world/scripts/agents/activity_view.gd', 'world/shaders/sky.gdshader', 'docs/agents.md']), 'world');
  assert.equal(checkScope(['world/scripts/world.gd', 'world/data/zones/villa/zone.json']), 'full');
  assert.equal(checkScope(['world/assets/library/catalog.json']), 'full');
  assert.equal(visualChange(['world/scripts/agents/activity_view.gd', 'docs/a.md']), false);
  for (const name of ['world/shaders/sky.gdshader', 'world/scripts/world_art.gd', 'world/scripts/rendering/atmosphere.gd',
    'world/data/zones/villa/zone.json', 'world/main.tscn']) assert.equal(visualChange([name]), true, name);
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

test('a check links the base into a preview of the reviewed worktree', async t => {
  const setup = await fixture(t);
  if (!setup) return;
  const { area, root, base, runner, calls, draft } = setup;
  assert.throws(() => createPreviewRunner(root, { base: path.join(root, 'world/base') }), /outside the project world/);
  const { result, log } = await check(runner, draft(['world/scripts/world.gd']));
  // A script alone is world scope: every Godot check, no gateway tests.
  assert.deepEqual(result, { scope: 'world', captures: [] });
  assert.match(log, /Linked 2 art and import files\./);
  assert.match(log, /Running the Godot checks without the gateway tests/);
  assert.match(log, /Skipping the environment screenshots/);
  const [importCall, checkCall] = await calls();
  assert.match(importCall, /^godot --headless --path .*--editor --import$/);
  assert.equal(checkCall, 'check scope=world gateway=none', 'the check gets the Godot tests and no gateway credential');

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
  assert.deepEqual(result, { scope: 'gateway', captures: [] });
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

test('runTargeted runs a node test file inside the draft worktree and rejects invalid paths', async t => {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-targeted-'));
  t.after(() => rm(area, { recursive: true, force: true }));
  const root = path.join(area, 'project');
  const worktree = path.join(area, 'draft/worktree');
  await mkdir(path.join(root, 'world'), { recursive: true });
  await mkdir(path.join(worktree, 'gateway/terminal'), { recursive: true });
  await writeFile(path.join(worktree, 'gateway/sample.test.mjs'), [
    "import assert from 'node:assert/strict';",
    "import test from 'node:test';",
    "test('alpha passes', () => { assert.equal(1 + 1, 2); });",
    "test('beta passes', () => { assert.equal(2 + 2, 4); });",
    '',
  ].join('\n'));
  await writeFile(path.join(worktree, 'gateway/terminal/failing.test.mjs'), [
    "import assert from 'node:assert/strict';",
    "import test from 'node:test';",
    "test('always fails', () => { assert.equal(1, 2); });",
    '',
  ].join('\n'));
  await writeFile(path.join(worktree, 'gateway/server.mjs'), 'export {};\n');

  const runner = createPreviewRunner(root, { base: path.join(area, 'storage/preview-base') });
  const draft = { directory: path.join(area, 'draft'), worktree, id: 't1', names: ['gateway/sample.test.mjs'] };

  const passed = await runner.runTargeted(draft, { kind: 'node', target: 'gateway/sample.test.mjs' });
  assert.equal(passed.ok, true);
  assert.equal(passed.kind, 'node');
  assert.equal(passed.target, 'gateway/sample.test.mjs');
  assert.match(passed.output, /alpha passes/);
  assert.match(passed.output, /beta passes/);

  const filtered = await runner.runTargeted(draft, { kind: 'node', target: 'gateway/sample.test.mjs', filter: 'alpha' });
  assert.equal(filtered.ok, true);
  assert.equal(filtered.filter, 'alpha');
  assert.match(filtered.output, /alpha passes/);
  assert.doesNotMatch(filtered.output, /not ok/);

  const failed = await runner.runTargeted(draft, { kind: 'node', target: 'gateway/terminal/failing.test.mjs' });
  assert.equal(failed.ok, false);
  assert.match(failed.output, /always fails/);

  for (const bad of ['../x.test.mjs', 'gateway/server.mjs', 'world/test.test.mjs', 'gateway/missing.test.mjs']) {
    await assert.rejects(runner.runTargeted(draft, { kind: 'node', target: bad }));
  }
  await assert.rejects(runner.runTargeted(draft, { kind: 'unknown' }), /Unknown targeted test kind/);
  await assert.rejects(runner.runTargeted(draft, { kind: 'godot_core', filter: 'bad filter!' }), /Filter/);
});
