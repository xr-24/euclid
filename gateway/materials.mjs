import { createSketchfabTextureSource, sketchfabTextureId } from './sketchfab-textures.mjs';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readdir, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';

const ID = /^[a-z0-9_]{1,64}$/;
const RESERVED = new Set(['earth', 'sand', 'rock']);
const validId = id => typeof id === 'string' && ID.test(id) && !RESERVED.has(id);
const MAPS = { albedo: 'Diffuse', normal: 'nor_gl', orm: 'arm' };
const LIMIT = 5 * 1024 * 1024;
const HEADERS = { 'User-Agent': 'Euclid/0.1 (local 3D workspace)' };
const API = 'https://api.polyhaven.com';

async function download(url, limit, fetcher, signal) {
  const response = await fetcher(url, { headers: HEADERS, redirect: 'error', signal });
  if (!response.ok) throw new Error(`Poly Haven returned HTTP ${response.status}.`);
  const chunks = [];
  let bytes = 0;
  for await (const chunk of response.body) {
    bytes += chunk.length;
    if (bytes > limit) throw new Error('A Poly Haven file exceeds the import limit.');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export function createMaterialService(directory, fetcher = fetch, sketchfab = createSketchfabTextureSource()) {
  return createImportService(directory, {
    kind: 'material', catalog: 'textures', type: 1, validId, extension: 'jpg', limit: LIMIT,
    prefix: '/file/ph-assets/Textures/', files: files => Object.fromEntries(
      Object.entries(MAPS).map(([key, map]) => [key, files[map]?.['1k']?.jpg])),
  }, fetcher, sketchfab);
}

export function createSkyService(directory, fetcher = fetch, sketchfab = createSketchfabTextureSource()) {
  return createImportService(directory, {
    kind: 'sky', catalog: 'hdris', type: 0, validId: id => typeof id === 'string' && ID.test(id),
    extension: 'hdr', limit: 12 * 1024 * 1024, prefix: '/file/ph-assets/HDRIs/hdr/2k/',
    files: files => ({ panorama: files.hdri?.['2k']?.hdr }),
  }, fetcher, sketchfab);
}

function createImportService(directory, config, fetcher, sketchfab) {
  const { kind, type, validId, extension, limit, prefix } = config;
  const pending = new Map();
  let catalog;

  async function provider(route, limit = LIMIT, signal = AbortSignal.timeout(10000)) {
    return JSON.parse(await download(API + route, limit, fetcher, signal));
  }

  function assets() {
    catalog ??= provider('/assets?t=' + config.catalog).catch(error => {
      catalog = undefined;
      throw error;
    });
    return catalog;
  }

  function describe(id, item) {
    return { id, name: item.name, author: Object.keys(item.authors ?? {}).join(', '),
      page: `https://polyhaven.com/a/${id}`, license: 'CC0', provider: 'Poly Haven' };
  }

  async function search(query, provider = 'polyhaven') {
    if (typeof query !== 'string' || query.length > (provider === 'sketchfab' ? 240 : 120) || !query.trim()) throw new Error(`Enter a ${kind} name.`);
    if (!['all', 'polyhaven', 'sketchfab'].includes(provider)) throw new Error('Choose a supported texture provider.');
    if (provider === 'sketchfab') return sketchfab.search(query.trim());
    if (provider === 'all') {
      const results = await Promise.allSettled(['polyhaven', 'sketchfab'].map(source => search(query, source)));
      if (results.every(result => result.status === 'rejected')) throw results[0].reason;
      return results.flatMap(result => result.status === 'fulfilled' ? result.value.slice(0, 6) : []);
    }
    const words = query.toLowerCase().trim().split(/\s+/);
    return Object.entries(await assets())
      .filter(([id, item]) => validId(id) && item.type === type && typeof item.name === 'string')
      .map(([id, item]) => {
        const name = item.name.toLowerCase();
        const terms = [...(item.tags ?? []), ...(item.categories ?? [])].join(' ').toLowerCase();
        const score = words.reduce((sum, word) => sum + (name.includes(word) ? 3 : terms.includes(word) ? 1 : 0), 0);
        return { id, item, score: id === words.join('_') ? score + 20 : score };
      })
      .filter(row => row.score > 0)
      .sort((a, b) => b.score - a.score || a.item.name.localeCompare(b.item.name))
      .slice(0, 12).map(({ id, item }) => describe(id, item));
  }

  async function read(id) {
    if (!validId(id)) throw new Error(`Invalid ${kind} ID.`);
    try {
      const folder = path.join(directory, id);
      const info = JSON.parse(await readFile(path.join(folder, kind + '.json'), 'utf8'));
      for (const key of Object.keys(config.files({}))) await stat(path.join(folder, key + '.' + extension));
      return info;
    } catch (error) {
      if (error.code === 'ENOENT') return null;
      throw error;
    }
  }

  async function prepare(id) {
    if (sketchfabTextureId.test(id)) {
      return publish(id, await makeStage(), stage => sketchfab.prepare(id, kind, stage));
    }
    const signal = AbortSignal.timeout(23000);
    const item = (await assets())[id];
    if (!item || item.type !== type) throw new Error(`Poly Haven ${kind} not found.`);
    const files = await provider('/files/' + id, 1024 * 1024, signal);
    return publish(id, await makeStage(), async stage => {
      const downloads = await Promise.allSettled(Object.entries(config.files(files)).map(async ([key, file]) => {
        if (!file?.url || !/^[a-f0-9]{32}$/i.test(file.md5 ?? '') || !Number.isInteger(file.size) || file.size < 1 || file.size > limit) {
          throw new Error(`This ${kind} is missing a supported download.`);
        }
        const url = new URL(file.url);
        if (url.origin !== 'https://dl.polyhaven.org' || !url.pathname.startsWith(prefix)) {
          throw new Error('Unexpected Poly Haven download host.');
        }
        const bytes = await download(url, file.size, fetcher, signal);
        if (bytes.length !== file.size || createHash('md5').update(bytes).digest('hex') !== file.md5.toLowerCase()) {
          throw new Error('A file failed its download checksum. Retry the import.');
        }
        await writeFile(path.join(stage, key + '.' + extension), bytes);
      }));
      const failed = downloads.find(result => result.status === 'rejected');
      if (failed) throw failed.reason;
      return describe(id, item);
    });
  }

  async function makeStage() {
    await mkdir(directory, { recursive: true });
    return mkdtemp(path.join(directory, '.import-'));
  }

  async function publish(id, stage, prepareFiles) {
    try {
      const info = await prepareFiles(stage);
      for (const name of await readdir(stage)) {
        if (name === 'input.json' || name.startsWith('input-')) await rm(path.join(stage, name));
      }
      for (const key of Object.keys(config.files({}))) {
        const file = await stat(path.join(stage, key + '.' + extension));
        if (!file.isFile() || file.size < 1 || file.size > limit) throw new Error('A prepared texture exceeds the import limit.');
      }
      await writeFile(path.join(stage, kind + '.json'), JSON.stringify(info));
      try {
        await rename(stage, path.join(directory, id));
      } catch (error) {
        const cached = await read(id);
        if (cached) return cached;
        throw error;
      }
      return info;
    } finally {
      await rm(stage, { recursive: true, force: true });
    }
  }

  async function importMaterial(id) {
    const cached = await read(id);
    if (cached) return cached;
    if (pending.has(id)) return pending.get(id);
    if (pending.size >= 2) throw new Error(`Two ${kind} imports are running. Try again when one finishes.`);
    const job = prepare(id).finally(() => pending.delete(id));
    pending.set(id, job);
    return job;
  }

  async function map(id, key) {
    if (!Object.hasOwn(config.files({}), key) || !await read(id)) throw new Error(`The ${kind} file is unavailable.`);
    return path.join(directory, id, key + '.' + extension);
  }

  return { search, importMaterial, map };
}
