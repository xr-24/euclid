import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createMaterialService } from './materials.mjs';

test('material imports verify map integrity, share downloads and reopen offline', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'euclid-materials-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const bytes = Buffer.from('fixture JPEG bytes');
  const md5 = createHash('md5').update(bytes).digest('hex');
  const routes = ['Diffuse', 'nor_gl', 'arm'];
  const files = Object.fromEntries(routes.map(key => [key, { '1k': { jpg: {
    url: 'https://dl.polyhaven.org/file/ph-assets/Textures/' + key + '.jpg', size: bytes.length, md5,
  } } }]));
  let corrupt = true;
  let downloads = 0;
  const provider = async (address, options) => {
    const url = String(address);
    assert.match(options.headers['User-Agent'], /Euclid/);
    assert.equal(options.redirect, 'error');
    if (url.endsWith('/assets?t=textures')) return Response.json({
      gravel_test: { name: 'Gravel Test', type: 1, authors: { Artist: '' } },
      model_test: { name: 'Gravel Model', type: 2 },
    });
    if (url.endsWith('/files/gravel_test')) return Response.json(files);
    downloads++;
    return new Response(corrupt && url.endsWith('/arm.jpg') ? Buffer.alloc(bytes.length) : bytes);
  };
  const service = createMaterialService(directory, provider);
  assert.deepEqual((await service.search('gravel')).map(item => item.id), ['gravel_test']);
  await assert.rejects(service.importMaterial('../bad'), /Invalid material ID/);
  await assert.rejects(service.importMaterial('gravel_test'), /checksum/);
  assert.deepEqual(await readdir(directory), []);
  corrupt = false;
  const results = await Promise.all([service.importMaterial('gravel_test'), service.importMaterial('gravel_test')]);
  assert.deepEqual(results[0], results[1]);
  assert.equal(downloads, 6);
  const offline = createMaterialService(directory, () => { throw new Error('Expected cached data'); });
  assert.equal((await offline.importMaterial('gravel_test')).license, 'CC0');
  assert.deepEqual(await readFile(await offline.map('gravel_test', 'normal')), bytes);
});
