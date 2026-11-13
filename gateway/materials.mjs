import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, readdir, rename, rm, stat, writeFile } from 'node:fs/promises';
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

export function createMaterialService(directory, fetcher = fetch) {
  const pending = new Map();
  let catalog;

  async function provider(route, limit = LIMIT, signal = AbortSignal.timeout(10000)) {
    return JSON.parse(await download(API + route, limit, fetcher, signal));
  }

  function assets() {
    catalog ??= provider('/assets?t=textures').catch(error => {
      catalog = undefined;
      throw error;
    });
    return catalog;
  }

  function describe(id, item) {
    return { id, name: item.name, author: Object.keys(item.authors ?? {}).join(', '),
      page: `https://polyhaven.com/a/${id}`, license: 'CC0', provider: 'Poly Haven', tile: 3 };
  }

  async function search(query) {
    if (typeof query !== 'string' || query.length > 120 || !query.trim()) throw new Error('Enter a material name.');
    const words = query.toLowerCase().trim().split(/\s+/);
    return Object.entries(await assets())
      .filter(([id, item]) => validId(id) && item.type === 1 && typeof item.name === 'string')
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
    if (!validId(id)) throw new Error('Invalid material ID.');
    try {
      const folder = path.join(directory, id);
      const info = JSON.parse(await readFile(path.join(folder, 'material.json'), 'utf8'));
      for (const key of Object.keys(MAPS)) await stat(path.join(folder, key + '.jpg'));
      return info;
    } catch (error) {
      if (error.code === 'ENOENT') return null;
      throw error;
    }
  }

  async function prepare(id) {
    const signal = AbortSignal.timeout(23000);
    const item = (await assets())[id];
    if (!item || item.type !== 1) throw new Error('Poly Haven material not found.');
    const files = await provider('/files/' + id, 1024 * 1024, signal);
    await mkdir(directory, { recursive: true });
    const stage = await mkdtemp(path.join(directory, '.import-'));
    try {
      const downloads = await Promise.allSettled(Object.entries(MAPS).map(async ([key, map]) => {
        const file = files[map]?.['1k']?.jpg;
        if (!file?.url || !/^[a-f0-9]{32}$/i.test(file.md5 ?? '') || !Number.isInteger(file.size) || file.size < 1 || file.size > LIMIT) {
          throw new Error('This material needs a 1K color, OpenGL normal and packed ARM map.');
        }
        const url = new URL(file.url);
        if (url.origin !== 'https://dl.polyhaven.org' || !url.pathname.startsWith('/file/ph-assets/Textures/')) {
          throw new Error('Unexpected Poly Haven download host.');
        }
        const bytes = await download(url, file.size, fetcher, signal);
        if (bytes.length !== file.size || createHash('md5').update(bytes).digest('hex') !== file.md5.toLowerCase()) {
          throw new Error('A material map failed its download checksum. Retry the import.');
        }
        await writeFile(path.join(stage, key + '.jpg'), bytes);
      }));
      const failed = downloads.find(result => result.status === 'rejected');
      if (failed) throw failed.reason;
      const info = describe(id, item);
      await writeFile(path.join(stage, 'material.json'), JSON.stringify(info));
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
    if (pending.size >= 2) throw new Error('Two materials are importing. Try again when one finishes.');
    const job = prepare(id).finally(() => pending.delete(id));
    pending.set(id, job);
    return job;
  }

  async function map(id, key) {
    if (!Object.hasOwn(MAPS, key) || !await read(id)) throw new Error('Material map unavailable.');
    return path.join(directory, id, key + '.jpg');
  }

  return { search, importMaterial, map };
}
