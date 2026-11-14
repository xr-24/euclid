import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { convertSketchfabMaps, createSketchfabTextureSource } from './sketchfab-textures.mjs';
import { createHash } from 'node:crypto';
import { access, mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createMaterialService, createSkyService } from './materials.mjs';

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

function textureGLB() {
  // An embedded 8×4 JPEG is enough for both a real panorama and a non-square material rejection.
  const image = Buffer.from('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAAEAAgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwCKiiivDPHP/9k=', 'base64');
  const doc = {
    materials: [{ emissiveTexture: { index: 0 }, pbrMetallicRoughness: { baseColorTexture: { index: 0 } } }],
    textures: [{ source: 0 }],
    images: [{ bufferView: 0, mimeType: 'image/jpeg' }],
    bufferViews: [{ buffer: 0, byteLength: image.length }],
  };
  const text = Buffer.from(JSON.stringify(doc));
  const json = Buffer.concat([text, Buffer.alloc((4 - text.length % 4) % 4, 32)]);
  const binary = Buffer.concat([image, Buffer.alloc((4 - image.length % 4) % 4)]);
  const file = Buffer.alloc(28 + json.length + binary.length);
  file.write('glTF', 0);
  file.writeUInt32LE(2, 4);
  file.writeUInt32LE(file.length, 8);
  file.writeUInt32LE(json.length, 12);
  file.write('JSON', 16);
  json.copy(file, 20);
  const end = 20 + json.length;
  file.writeUInt32LE(binary.length, end);
  file.write('BIN', end + 4);
  binary.copy(file, end + 8);
  return file;
}

test('Sketchfab routes store panorama attribution, and failed material conversion leaves the cache clear', async t => {
  const executable = process.platform === 'win32' ? 'Godot_v4.7.2-stable_win64_console.exe' : 'Godot_v4.7.2-stable_linux.x86_64';
  const godot = process.env.GODOT_BIN ?? fileURLToPath(new URL(`../.tools/godot/${executable}`, import.meta.url));
  try { await access(godot); } catch { t.skip('Godot is not installed.'); return; }
  const directory = await mkdtemp(path.join(os.tmpdir(), 'euclid-sketchfab-textures-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const uid = 'a'.repeat(32);
  const id = `sf_${uid}`;
  const item = { source_id: uid, title: 'Night sky', author: 'Artist', license: 'by', license_label: 'CC Attribution',
    page: 'https://sketchfab.com/3d-models/mock-' + uid };
  const source = createSketchfabTextureSource({
    search: async () => [item], info: async () => item, glb: async () => textureGLB(),
  }, convertSketchfabMaps);
  const offline = () => { throw new Error('Unexpected Poly Haven request'); };
  const skies = createSkyService(path.join(directory, 'skies'), offline, source);
  assert.equal((await skies.search('night', 'sketchfab'))[0].id, id);
  const result = await skies.importMaterial(id);
  assert.equal(result.author, 'Artist');
  assert.equal(result.license, 'CC Attribution');
  assert.match((await readFile(await skies.map(id, 'panorama'))).toString('ascii', 0, 64), /-Y 4 \+X 8/);
  assert.deepEqual(await readdir(path.join(directory, 'skies', id)), ['panorama.hdr', 'sky.json']);
  const materials = createMaterialService(path.join(directory, 'materials'), offline, source);
  await assert.rejects(materials.importMaterial(id), /textured material sample/);
  assert.deepEqual(await readdir(path.join(directory, 'materials')), []);
});

test('the sky catalog lists every Pure Sky and skips panoramas with scenery', async () => {
  const catalog = {
    bright_afternoon: { name: 'Bright Afternoon', type: 0, category: 'Pure Skies' },
    quiet_morning: { name: 'A Quiet Morning', type: 0, categories: ['pure skies'] },
    park: { name: 'Park', type: 0, categories: ['outdoor', 'skies'] },
    bad_type: { name: 'Wrong type', type: 1, category: 'Pure Skies' },
  };
  for (let index = 0; index < 15; index++) {
    catalog[`test_sky_${index}`] = { name: `Sky ${index}`, type: 0, category: 'Pure Skies' };
  }
  const skies = createSkyService('', async () => Response.json(catalog));
  const list = await skies.catalog();
  assert.equal(list.length, 17);
  assert.deepEqual(list.slice(0, 2).map(item => item.id), ['quiet_morning', 'bright_afternoon']);
  assert.equal(list[0].page, 'https://polyhaven.com/a/quiet_morning');
});
