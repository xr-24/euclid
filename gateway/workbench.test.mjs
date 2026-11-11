import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { setTimeout as sleep } from 'node:timers/promises';
import os from 'node:os';
import path from 'node:path';
import { createGateway } from './server.mjs';
import { createWorkbench } from './workbench.mjs';
import { fingerprint } from './workbench-source.mjs';
import { createPreviewRunner } from './workbench-runner.mjs';
import { shorelinePath } from './workbench-shoreline.mjs';
import { gridAppearance } from './workbench-grid.mjs';

test('checked palette-only revisions expose the exact source for live preview', async t => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'euclid-palette-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const file = 'world/scripts/ui/grid_palette.gd';
  const base = 'extends VBoxContainer\n';
  const changed = base + '# Reset rotation\n';
  await mkdir(path.join(root, 'world/scripts/ui'), { recursive: true });
  await writeFile(path.join(root, '.gitignore'), '.local/\n');
  await writeFile(path.join(root, file), base);
  const git = (...args) => execFileSync('git', args, { cwd: root, windowsHide: true });
  git('init', '-q');
  git('config', 'core.autocrlf', 'false');
  git('add', '.');
  git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Palette base');
  const workbench = createWorkbench(root, path.join(root, '.local'), {
    runner: { async check() {}, playing: () => false, async stop() {} },
    async editSource({ workspace, context }) {
      if (context) {
        assert.match(context.preview_output, /Fixture palette error/);
        await writeFile(path.join(workspace, 'world/scripts/ui/other.gd'), 'extends Control\n');
      } else {
        await writeFile(path.join(workspace, file), changed);
      }
    },
  });
  const call = (action, body = {}) => workbench(action, body, new AbortController().signal);
  async function until(status) {
    for (let attempt = 0; attempt < 100; attempt++) {
      const { draft } = await call('state');
      if (draft?.status === status) return draft;
      await sleep(20);
    }
    assert.fail('Expected palette status ' + status);
  }
  await call('source', { prompt: 'Add a Reset rotation button' });
  const reviewed = await until('staged');
  const identity = { id: reviewed.id, version: reviewed.version };
  assert.equal(reviewed.activation, 'reload_palette');
  assert.equal(reviewed.checked_preview, true);
  await assert.rejects(call('live', identity), /pass checks/);
  await call('check', identity);
  await until('passed');
  await assert.rejects(call('live', { id: reviewed.id }), /palette revision/);
  const { live } = await call('live', identity);
  assert.deepEqual(live, { draft: identity.id, version: identity.version,
    grid_palette: { source: changed, digest: fingerprint(changed) } });
  await call('revise', { ...identity, prompt: 'Fix the palette error', live_preview_output: 'Fixture palette error' });
  const broader = await until('staged');
  assert.equal(broader.activation, 'restart');
  assert.equal(broader.live, false);
  await assert.rejects(call('live', identity), /current source draft version/);
  await call('discard', { id: broader.id, version: broader.version });
});

test('workbench checks and commits an isolated two-file Git draft, and reverts it', async t => {
  const folder = await mkdtemp(path.join(os.tmpdir(), 'euclid-workbench-test-'));
  const root = path.join(folder, 'project');
  const dataDir = path.join(folder, 'gateway');
  const name = 'world/scripts/example.gd';
  const other = 'world/scripts/other.gd';
  const plugin = 'world/scripts/plugins/proximity_pulse.gd';
  const plate = '1'.repeat(32);
  const door = '2'.repeat(32);
  const original = 'extends Node\nconst VALUE := 1\n';
  const proposedPackage = {
    supported: true, id: 'door_plate', name: 'Door plate', entity_type: 'pressure_plate', output: 'door_open',
    settings: [{ key: 'radius', label: 'Radius', minimum: 0.4, maximum: 3, default: 0.65 },
      { key: 'speed', label: 'Speed', minimum: 0.2, maximum: 8, default: 2 }],
    source_entity: plate, target_entity: door, source: original, summary: 'Create a door plate.',
  };
  const file = path.join(root, name);
  const otherOriginal = 'extends Node\nconst LABEL := "Old"\n';
  const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', windowsHide: true }).trim();
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, original);
  await writeFile(path.join(root, other), otherOriginal);
  await mkdir(path.join(root, 'world/scripts/plugins'));
  await mkdir(path.join(root, 'world/data'));
  await writeFile(path.join(root, plugin), original);
  await writeFile(path.join(root, 'world/data/behavior_plugins.json'), JSON.stringify({ schema_version: 1, plugins: [{ id: 'proximity_pulse' }] }));
  const shoreOriginal = { schema_version: 1, foam_strength: 1, foam_softness: 1 };
  await writeFile(path.join(root, shorelinePath), JSON.stringify(shoreOriginal));
  const gridOriginal = { schema_version: 1, floor_spacing: 2, wall_height: 1 };
  await writeFile(path.join(root, gridAppearance.file), JSON.stringify(gridOriginal));
  git('init', '-q');
  git('config', 'user.name', 'Euclid Test');
  git('config', 'user.email', 'test@example.invalid');
  git('config', 'core.autocrlf', 'false');
  git('add', '.');
  git('commit', '-qm', 'Baseline');
  const base = git('rev-parse', 'HEAD');
  let server;
  let fail = true;
  let playing = false;
  let finishShoreChecks;
  const shoreChecks = new Promise(resolve => { finishShoreChecks = resolve; });
  let finishBehaviorChecks;
  const behaviorChecks = new Promise(resolve => { finishBehaviorChecks = resolve; });
  let finishToolChecks;
  const toolChecks = new Promise(resolve => { finishToolChecks = resolve; });
  const runner = {
    async check(draft, output) {
      if (draft.names[0] === shorelinePath) {
        assert.deepEqual(JSON.parse(await readFile(path.join(root, shorelinePath), 'utf8')), shoreOriginal);
        await shoreChecks;
        return;
      }
      if (draft.names[0] === gridAppearance.file) {
        assert.deepEqual(JSON.parse(await readFile(path.join(root, gridAppearance.file), 'utf8')), gridOriginal);
        return;
      }
      if (draft.names[0].startsWith('world/data/workshop_tools/')) return toolChecks;
      if (draft.binding) return behaviorChecks;
      assert.equal(await readFile(file, 'utf8'), original);
      assert.match(await readFile(path.join(draft.worktree, name), 'utf8'), /VALUE := 2/);
      assert.match(await readFile(path.join(draft.worktree, other), 'utf8'), /"New"/);
      output('Checked a staged copy.');
      if (fail) throw new Error('Test failure');
    },
    playing: () => playing,
    play: async () => { playing = true; },
    stop: async () => { playing = false; },
  };
  t.after(async () => {
    server.closeAllConnections();
    if (server.listening) await new Promise(resolve => server.close(resolve));
    await rm(folder, { recursive: true, force: true });
  });
  async function start() {
    const gateway = await createGateway({ dataDir, workbenchRoot: root, workbenchOptions: {
      runner, author: async () => proposedPackage, designShoreline: async ({ request }) => ({
        supported: true, summary: 'Soften the foam.', foam_strength: 1, foam_softness: request === 'Unsafe' ? 3 : 1.5,
      }), designGrid: async ({ request }) => ({
        supported: true, summary: 'Space the lines apart.', floor_spacing: request === 'Unsafe' ? 9 : 4, wall_height: 1,
      }), designTool: async ({ request }) => ({
        supported: true, id: 'reset_demo', label: 'Reset demo', description: 'Restore the test door.', summary: 'Capture the door state.',
        targets: [{ id: request === 'Invalid' ? 'f'.repeat(32) : door, fields: ['yaw', 'position'], close_door: true }],
      }), propose: async () => ({ summary: 'Raise the value and update the label.', edits: [
        { file: name, original: 'VALUE := 1', replacement: 'VALUE := 2' },
        { file: other, original: '"Old"', replacement: '"New"' },
      ] }),
    } });
    server = gateway.server;
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const base = `http://127.0.0.1:${server.address().port}/v1/workbench/`;
    return async (action, args = {}, trusted = true) => {
      const headers = { Authorization: `Bearer ${gateway.token}`, 'Content-Type': 'application/json' };
      if (trusted) headers['X-Euclid-Workbench'] = gateway.workbenchToken;
      const result = await fetch(base + action, { method: 'POST', headers, body: JSON.stringify(args) });
      return { code: result.status, body: await result.json() };
    };
  }
  let call = await start();
  assert.equal((await call('state', {}, false)).code, 403);
  assert.equal((await call('read', { name: '../secrets.txt' })).code, 400);
  assert.equal((await call('read', { name: 'world/project.godot' })).code, 400);
  const originals = await Promise.all([name, other].map(async name => ({ name, ...(await call('read', { name })).body })));
  const suggested = await call('propose', { files: originals, prompt: 'Raise the value and update the label' });
  const files = suggested.body.files.map(file => ({ ...file, hash: originals.find(item => item.name === file.name).hash }));
  assert.equal(files[0].text, original.replace(':= 1', ':= 2'));
  const staged = await call('stage', { files });
  assert.equal(staged.code, 200, JSON.stringify(staged.body));
  const id = staged.body.draft.id;
  assert.match(staged.body.draft.diff, /\+const VALUE := 2/);
  assert.match(staged.body.draft.diff, /\+const LABEL := "New"/);
  assert.equal(await readFile(file, 'utf8'), original);
  await new Promise(resolve => server.close(resolve));
  call = await start();
  const recovered = (await call('state')).body.draft;
  assert.equal(recovered.id, id);
  assert.equal(recovered.status, 'staged');
  assert.equal(recovered.diff, staged.body.draft.diff);
  const accept = { id, message: 'Update value and label' };
  assert.equal((await call('apply', accept)).code, 400);
  assert.equal((await call('play', { id })).code, 400);
  assert.equal((await call('live', { id })).code, 400);
  async function checks() {
    await call('check', { id });
    for (let tries = 0; tries < 30; tries++) {
      const { body } = await call('state');
      if (body.draft.status !== 'checking') return body.draft;
      await sleep(20);
    }
    throw new Error('Check did not finish');
  }
  assert.equal((await checks()).status, 'failed');
  assert.equal((await call('apply', accept)).code, 400);
  fail = false;
  assert.equal((await checks()).status, 'passed');
  assert.equal((await call('play', { id })).body.playing, true);
  await writeFile(file, original.replace(':= 1', ':= 3'));
  const blocked = await call('apply', accept);
  assert.equal(blocked.code, 400);
  assert.match(blocked.body.error, /local changes/);
  assert.equal((await call('state')).body.draft.id, id);
  await writeFile(file, original);
  git('commit', '--allow-empty', '-qm', 'Concurrent change');
  assert.match((await call('apply', accept)).body.error, /main branch moved/);
  assert.equal((await call('state')).body.draft.id, id);
  git('reset', '--soft', base);
  const applied = await call('apply', accept);
  assert.equal(applied.code, 200, JSON.stringify(applied.body));
  assert.equal(applied.body.draft, null);
  assert.equal(applied.body.playing, false);
  assert.equal(await readFile(file, 'utf8'), files[0].text);
  assert.equal(await readFile(path.join(root, other), 'utf8'), files[1].text);
  assert.equal(git('rev-parse', 'HEAD^'), base);
  assert.equal(git('log', '-1', '--format=%s'), accept.message);
  assert.equal(git('status', '--porcelain'), '');
  assert.equal(git('worktree', 'list', '--porcelain').split('\n').filter(line => line.startsWith('worktree ')).length, 1);
  await new Promise(resolve => server.close(resolve));
  call = await start();
  const revision = (await call('state')).body.revision;
  assert.equal(revision, applied.body.commit);
  assert.equal((await call('restore', { revision })).code, 200);
  assert.equal(await readFile(file, 'utf8'), original);
  assert.equal(await readFile(path.join(root, other), 'utf8'), otherOriginal);
  assert.equal(git('rev-parse', 'HEAD^'), revision);
  assert.equal((await call('state')).body.revision, '');
  // The journal outlives the gateway restart and records the commit and its revert.
  const [reverted, committed] = (await call('history', { limit: 2 })).body.entries;
  assert.deepEqual([reverted.event, reverted.reverted, reverted.commit], ['reverted', revision, git('rev-parse', 'HEAD')]);
  assert.deepEqual(reverted.files.toSorted(), [path.relative(root, file).replaceAll(path.sep, '/'), other].toSorted());
  assert.deepEqual([committed.event, committed.draft, committed.commit, committed.message], ['committed', id, revision, accept.message]);
  assert.ok((await call('history', { draft: id })).body.entries.some(item => item.event === 'checked' && item.status === 'passed'));

  const before = (await call('read', { name: plugin })).body;
  const liveDraft = (await call('stage', { files: [{ name: plugin, hash: before.hash, text: files[0].text }] })).body.draft;
  assert.equal(liveDraft.live, true);
  assert.equal((await call('live', { id: liveDraft.id }, false)).code, 403);
  const live = (await call('live', { id: liveDraft.id })).body.live;
  assert.deepEqual(live, { draft: liveDraft.id, plugin: 'proximity_pulse', source: files[0].text, digest: fingerprint(files[0].text) });
  assert.equal(await readFile(path.join(root, plugin), 'utf8'), original);
  assert.equal((await call('discard', { id: liveDraft.id })).body.draft, null);

  const context = { zone: 'construct', entities: [{ id: plate, type: 'pressure_plate' }, { id: door, type: 'sliding_door' }] };
  assert.equal((await call('author', { prompt: 'Make the plate open the door', context: { ...context, entities: context.entities.slice(0, 1) } })).code, 400);
  const authored = await call('author', { prompt: 'Make the plate open the door', context });
  assert.equal(authored.code, 200, JSON.stringify(authored.body));
  assert.deepEqual(authored.body.draft.files, ['world/data/behavior_plugins/door_plate.json', 'world/scripts/plugins/door_plate.gd']);
  assert.equal(authored.body.draft.live, true);
  assert.match(authored.body.draft.diff, /new file mode/);
  const packageDraft = (await call('live', { id: authored.body.draft.id })).body.live;
  assert.equal(packageDraft.definition.output, 'door_open');
  assert.deepEqual(packageDraft.binding, { zone: 'construct', source: plate, target: door });
  assert.equal((await call('discard', { id: authored.body.draft.id })).body.draft, null);

  assert.equal((await call('shoreline', { prompt: 'Unsafe' })).code, 400);
  const shore = await call('shoreline', { prompt: 'Soften the foam' });
  assert.equal(shore.code, 200, JSON.stringify(shore.body));
  const shoreId = shore.body.draft.id;
  assert.equal(shore.body.operation, 'checking');
  assert.equal(shore.body.draft.status, 'checking');
  assert.deepEqual(shore.body.draft.files, [shorelinePath]);
  assert.equal((await call('live', { id: shoreId })).code, 400);
  finishShoreChecks();
  for (let tries = 0; tries < 30; tries++) {
    if ((await call('state')).body.draft.status !== 'checking') break;
    await sleep(20);
  }
  const preview = await call('live', { id: shoreId });
  assert.deepEqual(preview.body.live, { draft: shoreId, shoreline: { ...shoreOriginal, foam_softness: 1.5 } });
  const accepted = await call('apply', { id: shoreId, message: 'Soften shore foam' });
  assert.equal(accepted.code, 200, JSON.stringify(accepted.body));
  assert.deepEqual(JSON.parse(await readFile(path.join(root, shorelinePath), 'utf8')), preview.body.live.shoreline);

  assert.equal((await call('grid', { prompt: 'Widen the floor lines' }, false)).code, 403);
  assert.equal((await call('grid', { prompt: 'Unsafe' })).code, 400);
  const grid = await call('grid', { prompt: 'Spread out the Grid floor lines' });
  assert.equal(grid.code, 200, JSON.stringify(grid.body));
  assert.equal(grid.body.draft.activation, 'reload_grid');
  assert.equal(grid.body.draft.from_world, true);
  const gridId = grid.body.draft.id;
  for (let tries = 0; tries < 30 && (await call('state')).body.draft.status === 'checking'; tries++) await sleep(20);
  assert.deepEqual((await call('live', { id: gridId })).body.live, { draft: gridId, grid: { ...gridOriginal, floor_spacing: 4 } });
  assert.equal((await call('discard', { id: gridId })).body.draft, null);
  assert.deepEqual(JSON.parse(await readFile(path.join(root, gridAppearance.file), 'utf8')), gridOriginal);

  const inWorld = await call('author', { prompt: 'Create a door plate', from_world: true, context: {
    zone: 'construct', entities: [{ id: plate, type: 'pressure_plate' }, { id: door, type: 'sliding_door' }],
  } });
  assert.equal(inWorld.code, 200, JSON.stringify(inWorld.body));
  const behaviorId = inWorld.body.draft.id;
  assert.equal(inWorld.body.draft.activation, 'live');
  assert.equal(inWorld.body.draft.status, 'checking');
  assert.equal((await call('live', { id: behaviorId })).code, 400);
  finishBehaviorChecks();
  for (let tries = 0; tries < 30 && (await call('state')).body.draft.status === 'checking'; tries++) await sleep(20);
  assert.deepEqual((await call('live', { id: behaviorId })).body.live.binding, packageDraft.binding);
  assert.equal((await call('discard', { id: behaviorId })).body.draft, null);

  const toolContext = { zone: 'construct', entities: [{ id: door, type: 'sliding_door', position: [1, 0, 2], yaw: 15, scale: 1, color: '112233' }] };
  assert.equal((await call('tool', { prompt: 'Reset demo', context: toolContext }, false)).code, 403);
  assert.equal((await call('tool', { prompt: 'Invalid', context: toolContext })).code, 400);
  const tool = await call('tool', { prompt: 'Reset demo', context: toolContext });
  assert.equal(tool.code, 200, JSON.stringify(tool.body));
  assert.equal(tool.body.draft.subject, 'workshop_tool');
  assert.equal(tool.body.draft.preview_zone, 'construct');
  const toolId = tool.body.draft.id;
  assert.equal((await call('live', { id: toolId })).code, 400);
  finishToolChecks();
  for (let tries = 0; tries < 30 && (await call('state')).body.draft.status === 'checking'; tries++) await sleep(20);
  const toolPreview = (await call('live', { id: toolId })).body.live.workshop_tool;
  assert.deepEqual(toolPreview.targets, [{ id: door, changes: { yaw: 15, position: [1, 0, 2] }, close_door: true }]);
  const toolCommit = await call('apply', { id: toolId, message: 'Add demo reset' });
  assert.equal(toolCommit.code, 200, JSON.stringify(toolCommit.body));
  assert.deepEqual(JSON.parse(await readFile(path.join(root, 'world/data/workshop_tools/reset_demo.json'), 'utf8')), toolPreview);
});

test('source drafts isolate authoring, revise from failed checks, and restore reviewed versions', async t => {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-source-test-'));
  t.after(() => rm(area, { recursive: true, force: true }));
  const root = path.join(area, 'project');
  const storage = path.join(area, 'workbench');
  const script = 'world/scripts/example.gd';
  const removed = 'world/scripts/old.gd';
  const testFile = 'world/scripts/diagnostics/example_test.gd';
  const original = 'extends Node\n' + '# Fixture source padding.\n'.repeat(2800);
  await mkdir(path.join(root, 'world/scripts'), { recursive: true });
  await writeFile(path.join(root, script), original);
  await writeFile(path.join(root, removed), 'extends Node\n');
  await writeFile(path.join(root, '.gitignore'), '.local/\n');
  await mkdir(path.join(root, '.local'));
  await writeFile(path.join(root, '.local/fixture'), 'Ignored local data.');
  const git = (...args) => execFileSync('git', args, { cwd: root, windowsHide: true, encoding: 'utf8' }).trim();
  git('init', '-q');
  git('config', 'user.name', 'Euclid Test');
  git('config', 'user.email', 'test@example.invalid');
  git('config', 'core.autocrlf', 'false');
  git('add', '.');
  git('commit', '-qm', 'Fixture');
  const base = git('rev-parse', 'HEAD');
  let checked = 0;
  let benchmarks = 0;
  let holdBenchmark = false;
  let played = false;
  const previewLog = createPreviewRunner(root).previewLog;
  const runner = {
    async check(draft, log) {
      checked++;
      assert.match(await readFile(path.join(draft.worktree, testFile), 'utf8'), /FIXTURE/);
      await assert.rejects(readFile(path.join(draft.worktree, removed)), { code: 'ENOENT' });
      if (!(await readFile(path.join(draft.worktree, script), 'utf8')).includes('const NEW := true')) {
        log('FIXTURE expected NEW to be true.\n');
        throw new Error('The fixture failed.');
      }
    },
    async benchmark(source, output, settings, log, signal) {
      if (holdBenchmark) await sleep(10000, undefined, { signal });
      benchmarks++;
      const after = output.endsWith(path.sep + 'after');
      const text = await readFile(path.join(source.worktree, script), 'utf8');
      assert.equal(text, after ? original + 'const NEW := true\n' : original);
      log('Rendered fixed views.\n');
      return { schema_version: 1, profile: settings.profile, resolution: [settings.width, settings.height], vsync: false,
        device: 'Fixture GPU', renderer: 'forward_plus', mode: 'desktop',
        samples: ['arrival', 'pool', 'portico'].map(view => ({ view, zone: 'villa', variant: 'default', frames: 420,
          fps: after ? 70 : 55, p95_ms: after ? 15 : 20, p99_ms: 22, gpu_ms: 10, cpu_process_ms: 2,
          draw_calls: 80, primitives: 10000 })) };
    },
    playing: () => played,
    previewLog,
    async play(draft) {
      await writeFile(path.join(draft.directory, `preview-${fingerprint(draft.diff)}.log`),
        'old output\n'.repeat(2000) + 'SCRIPT ERROR: Fixture preview error\n');
      played = true;
    },
    async stop() { played = false; },
  };
  const editSource = async ({ workspace, request, context, evidence, signal, onProgress }) => {
    await assert.rejects(readFile(path.join(workspace, '.git')), { code: 'ENOENT' });
    await assert.rejects(readFile(path.join(workspace, '.local/fixture')), { code: 'ENOENT' });
    if (context) {
      assert.equal(context.request, 'Update the script');
      assert.deepEqual(context.files, [testFile, script, removed]);
      assert.equal(context.check_status, 'failed');
      assert.match(context.check_output, /expected NEW/);
      assert.equal(await readFile(path.join(workspace, script), 'utf8'), original + 'const NEW := false\n');
      assert.match(await readFile(path.join(workspace, testFile), 'utf8'), /FIXTURE/);
      await assert.rejects(readFile(path.join(workspace, removed)), { code: 'ENOENT' });
      if (request === 'Cancel') await sleep(10000, undefined, { signal });
      if (request === 'Outside scope') return writeFile(path.join(workspace, 'world/project.godot'), 'Bad change');
      await writeFile(path.join(workspace, script), original + 'const NEW := true\n');
      return 'Fixed the failing check.';
    }
    assert.equal(await readFile(path.join(workspace, script), 'utf8'), original);
    if (request === 'Cancel') await sleep(10000, undefined, { signal });
    if (request === 'Outside scope') return writeFile(path.join(workspace, 'world/project.godot'), 'Bad change');
    assert.equal(evidence.before.samples[1].fps, 55);
    onProgress('Reading source and adding a test.\n');
    await mkdir(path.dirname(path.join(workspace, testFile)), { recursive: true });
    await writeFile(path.join(workspace, testFile), 'extends SceneTree\nconst FIXTURE := true\n');
    await writeFile(path.join(workspace, script), original + 'const NEW := false\n');
    await rm(path.join(workspace, removed));
    return 'Updated the script and test.';
  };
  const connect = () => createWorkbench(root, storage, { runner, editSource });
  let workbench = connect();
  const call = (action, args = {}) => workbench(action, args, new AbortController().signal);
  async function until(status) {
    for (let attempt = 0; attempt < 100; attempt++) {
      const result = await call('state');
      if (result.draft?.status === status) return result.draft;
      await sleep(20);
    }
    assert.fail('Draft did not reach ' + status);
  }
  async function finishedBenchmark() {
    for (let attempt = 0; attempt < 100; attempt++) {
      const result = await call('state');
      if (!result.diagnostic_job) return result;
      await sleep(20);
    }
    assert.fail('The villa benchmark did not finish.');
  }
  async function benchmark(args) {
    const started = await call('benchmark', args);
    assert.equal(started.operation, 'diagnosing');
    const { diagnostic } = await finishedBenchmark();
    assert.equal(diagnostic.status, 'complete', diagnostic.error);
    return diagnostic;
  }
  const baseline = await benchmark({});
  assert.equal(baseline.base, base);
  assert.equal(baseline.after, null);
  holdBenchmark = true;
  const activeBenchmark = await call('benchmark');
  await call('cancelbenchmark', { id: activeBenchmark.diagnostic_job.id });
  const afterCancel = await finishedBenchmark();
  assert.equal(afterCancel.diagnostic.id, baseline.id);
  assert.equal(afterCancel.diagnostic_notice, 'Benchmark cancelled.');
  holdBenchmark = false;
  const rejected = await call('source', { prompt: 'Outside scope' });
  assert.equal(rejected.draft.status, 'authoring');
  assert.match((await until('failed')).error, /outside the draft scope/);
  assert.equal((await call('discard', { id: rejected.draft.id })).draft, null);

  const cancelled = await call('source', { prompt: 'Cancel' });
  assert.equal((await call('discard', { id: cancelled.draft.id })).draft, null);
  const started = await call('source', { prompt: 'Update the script' });
  assert.equal(started.draft.status, 'authoring');
  const reviewed = await until('staged');
  assert.equal(reviewed.agent_source, true);
  assert.deepEqual(reviewed.files, [testFile, script, removed]);
  assert.match(reviewed.diff, /new file mode/);
  assert.match(reviewed.diff, /deleted file mode/);
  assert.equal(checked, 0);
  assert.equal(git('rev-parse', 'HEAD'), base);
  assert.equal(git('status', '--porcelain'), '');
  await assert.rejects(call('play', { id: reviewed.id }), /pass the project checks/);
  await assert.rejects(call('benchmark', { id: reviewed.id, version: reviewed.version }), /pass checks before benchmarking/);

  workbench = connect();
  assert.equal((await call('state')).draft.diff, reviewed.diff);
  await call('check', { id: reviewed.id });
  const failed = await until('failed');
  assert.equal(checked, 1);
  workbench = connect();
  const resumed = (await call('state')).draft;
  assert.equal(resumed.status, 'failed');
  assert.equal(resumed.version, failed.version);
  assert.equal(resumed.check_status, 'failed');
  assert.equal(resumed.log, failed.log);
  assert.equal(resumed.error, failed.error);
  const first = { id: failed.id, version: failed.version };
  const revising = await call('revise', { ...first, prompt: 'Cancel' });
  assert.equal(revising.draft.status, 'revising');
  assert.equal(revising.draft.diff, reviewed.diff);
  await assert.rejects(call('discard', first), /Cancel the revision before discarding/);
  const preserved = (await call('discard', { ...first, cancel_revision: true })).draft;
  assert.equal(preserved.status, 'failed');
  assert.match(preserved.revision_notice, /Revision cancelled/);
  await assert.rejects(call('discard', { ...first, cancel_revision: true }), /no revision running/);
  await call('revise', { ...first, prompt: 'Outside scope' });
  const rejectedRevision = await until('failed');
  assert.equal(rejectedRevision.diff, failed.diff);
  assert.match(rejectedRevision.revision_notice, /outside the draft scope/);
  assert.equal(rejectedRevision.log, failed.log);

  await call('revise', { ...first, prompt: 'Fix the failing check' });
  const revised = await until('staged');
  assert.equal(revised.id, reviewed.id);
  assert.notEqual(revised.version, reviewed.version);
  assert.equal(revised.has_previous, true);
  assert.match(revised.revision_diff, /-const NEW := false\n\+const NEW := true/);
  assert.doesNotMatch(revised.revision_diff, /example_test\.gd|old\.gd/);
  assert.deepEqual(revised.files, reviewed.files);
  const second = { id: revised.id, version: revised.version };
  await assert.rejects(call('check', first), /current source draft version/);
  await assert.rejects(call('play', second), /pass the project checks/);
  await assert.rejects(call('apply', { ...second, message: 'Unchecked version' }), /pass the project checks/);

  workbench = connect();
  assert.equal((await call('state')).draft.revision_diff, revised.revision_diff);
  await call('check', second);
  await until('passed');
  const comparison = await benchmark(second);
  assert.equal(comparison.base, base);
  assert.equal(comparison.version, second.version);
  assert.equal(comparison.before.samples[1].p95_ms, 20);
  assert.equal(comparison.after.samples[1].p95_ms, 15);
  assert.equal(benchmarks, 3);
  workbench = connect();
  assert.equal((await call('state')).diagnostic.id, comparison.id);
  const previousPass = (await call('state')).draft;
  assert.equal(previousPass.status, 'staged');
  assert.equal(previousPass.check_status, 'passed');
  await assert.rejects(call('play', second), /pass the project checks/);
  await call('check', second);
  await until('passed');
  const preview = await call('play', second);
  assert.equal(preview.playing, true);
  assert.match(preview.preview_log, /SCRIPT ERROR: Fixture preview error/);
  assert.equal(Buffer.byteLength(preview.preview_log), 12000);
  const restored = await call('previous', second);
  assert.equal(restored.playing, false);
  assert.equal(restored.diagnostic, null);
  assert.equal(restored.preview_log, '');
  assert.equal(restored.draft.status, 'staged');
  assert.equal(restored.draft.check_status, '');
  assert.equal(restored.draft.version, first.version);
  assert.match(restored.draft.revision_diff, /-const NEW := true\n\+const NEW := false/);
  assert.equal((await call('previous', first)).diagnostic.id, comparison.id);
  await assert.rejects(call('play', second), /pass the project checks/);
  await call('check', second);
  await until('passed');
  assert.equal((await call('play', second)).playing, true);
  await call('apply', { ...second, message: 'Apply checked agent changes' });
  assert.notEqual(git('rev-parse', 'HEAD'), base);
  assert.equal(await readFile(path.join(root, testFile), 'utf8'), 'extends SceneTree\nconst FIXTURE := true\n');
  assert.equal(git('status', '--porcelain'), '');
});
