import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { createAssetService, validAssetId } from './assets.mjs';
import { createGateway } from './server.mjs';

const id = 'sf-' + 'a'.repeat(32);

test('asset cache retains provenance and rejects arbitrary paths', async t => {
  const folder = await mkdtemp(path.join(os.tmpdir(), 'euclid-assets-'));
  t.after(() => rm(folder, { recursive: true, force: true }));
  const service = createAssetService(folder);
  assert.equal(validAssetId('../secrets'), false);
  assert.equal(validAssetId('https://example.com/model.glb'), false);
  await assert.rejects(service.importAsset('../secret'), /Invalid asset ID/);
  await assert.rejects(service.search('', 'all'), /Search with/);
  await assert.rejects(service.search('pizza', 'shell'), /supported provider/);
  assert.equal((await service.status(id)).status, 'missing');
  await mkdir(path.join(folder, id));
  const record = { asset_id: id, title: 'Test model', author: 'Test artist', license: 'by', page: 'https://sketchfab.com/example' };
  await writeFile(path.join(folder, id, 'asset.json'), JSON.stringify(record));
  assert.equal((await service.status(id)).status, 'missing');
  await writeFile(path.join(folder, id, 'model.glb'), 'fixture');
  assert.deepEqual((await service.importAsset(id)).asset, record);
  assert.deepEqual((await service.list()).assets, [record]);
  assert.equal((await service.model(id)).file, path.join(folder, id, 'model.glb'));
});

test('authenticated asset download and MCP spawn wait for the world result', async t => {
  const folder = await mkdtemp(path.join(os.tmpdir(), 'euclid-asset-gateway-'));
  const cached = path.join(folder, 'runtime-assets', id);
  await mkdir(cached, { recursive: true });
  await writeFile(path.join(cached, 'asset.json'), JSON.stringify({ asset_id: id, title: 'Fixture', license: 'cc0' }));
  await writeFile(path.join(cached, 'model.glb'), 'cached-model');
  const { server } = await createGateway({ dataDir: folder, token: 'asset-test-secret' });
  t.after(async () => {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    await rm(folder, { recursive: true, force: true });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(base + '/v1/assets')).status, 401);
  const headers = { Authorization: 'Bearer asset-test-secret', 'Content-Type': 'application/json' };
  const model = await fetch(base + `/v1/assets/${id}/model.glb`, { headers });
  assert.equal(model.status, 200);
  assert.equal(await model.text(), 'cached-model');
  const post = (route, body) => fetch(base + route, { method: 'POST', headers, body: JSON.stringify(body) });
  assert.equal((await post('/v1/assets/import', { asset_id: '../../private' })).status, 400);
  const session = 'b'.repeat(32);
  const context = { current: 'construct', environments: [{ id: 'construct', name: 'The Grid', description: 'Workspace' }] };
  const sync = result => post('/v1/companion/sync', { session, context, result }).then(response => response.json());
  await sync();
  const waiting = post('/mcp/' + session, { jsonrpc: '2.0', id: 1, method: 'tools/call',
    params: { name: 'spawn_entity', arguments: { asset_id: id, scale: 0.35 } } });
  let command;
  for (let i = 0; !command && i < 10; i++) ({ command } = await sync());
  assert.equal(command?.tool, 'spawn_asset');
  assert.equal(command.target, id);
  assert.equal(command.scale, 0.35);
  const outcome = { ok: true, id: 'spawned-entity' };
  await sync({ id: command.id, value: outcome });
  const answer = await (await waiting).json();
  assert.deepEqual(JSON.parse(answer.result.content[0].text), outcome);
});
