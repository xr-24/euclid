import { readFile, writeFile, mkdir, mkdtemp, rename, readdir, stat } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const exec = promisify(execFile);
const root = fileURLToPath(new URL('../', import.meta.url));
const allowed = new Set(['cc0', 'by', 'by-sa', 'by-nc', 'by-nc-sa']);
const headers = { 'User-Agent': 'Euclid/0.1 (local 3D workspace)' };
const LIMIT = 64 * 1024 * 1024;
export const validAssetId = id => typeof id === 'string' && /^(rig-)?(sf-[a-f0-9]{32}|ph-[A-Za-z0-9_-]{1,80})$/.test(id);

async function token() {
  if (process.env.SKETCHFAB_API_TOKEN) return process.env.SKETCHFAB_API_TOKEN.trim();
  for (const name of ['sketchfab-key.txt', 'sketchfab_token.txt']) {
    try { return (await readFile(path.join(root, '.local', name), 'utf8')).replace(/^\uFEFF/, '').trim(); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  throw new Error('Add your Sketchfab API key to .local/sketchfab-key.txt.');
}

async function bytes(url, auth = '') {
  const parsed = new URL(url);
  if (parsed.protocol !== 'https:') throw new Error('The provider supplied an unsupported download URL.');
  if (auth && parsed.hostname !== 'api.sketchfab.com') throw new Error('Sketchfab authentication requires its API host.');
  const response = await fetch(url, { headers: { ...headers, ...(auth ? { Authorization: `Token ${auth}` } : {}) },
    redirect: auth ? 'error' : 'follow', signal: AbortSignal.timeout(60000) });
  if (!response.ok) throw new Error(`Asset provider returned HTTP ${response.status}.`);
  if (Number(response.headers.get('content-length')) > LIMIT) throw new Error('The asset exceeds the 64 MB download limit.');
  const parts = [];
  let size = 0;
  for await (const chunk of response.body) {
    size += chunk.length;
    if (size > LIMIT) throw new Error('The asset exceeds the 64 MB download limit.');
    parts.push(chunk);
  }
  return Buffer.concat(parts);
}
const json = async (url, auth = '') => JSON.parse((await bytes(url, auth)).toString('utf8'));

async function sketchfab(uid) {
  const item = await json(`https://api.sketchfab.com/v3/models/${uid}`);
  if (!item.isDownloadable || !allowed.has(item.license?.slug)) throw new Error('This model has no supported download license.');
  return { asset_id: `sf-${uid}`, provider: 'sketchfab', source_id: uid, title: item.name.slice(0, 160),
    author: item.user?.displayName ?? item.user?.username ?? 'Unknown', page: item.viewerUrl,
    license: item.license.slug, license_label: item.license.label, license_url: item.license.url,
    triangles: item.faceCount ?? 0, animations: item.animationCount ?? 0 };
}

async function blender() {
  if (process.env.BLENDER_BIN) return process.env.BLENDER_BIN;
  const base = path.join(process.env.ProgramFiles ?? 'C:/Program Files', 'Blender Foundation');
  const folders = (await readdir(base, { withFileTypes: true })).filter(item => item.isDirectory()).map(item => item.name).sort().reverse();
  for (const folder of folders) {
    const file = path.join(base, folder, 'blender.exe');
    try { if ((await stat(file)).isFile()) return file; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  throw new Error('Set BLENDER_BIN to the Blender executable to prepare downloaded models.');
}

export function createAssetService(directory = path.join(root, '.local/runtime-assets')) {
  const jobs = new Map();
  let preparing = Promise.resolve();
  let catalog;
  async function polyhavenCatalog() {
    catalog ??= json('https://api.polyhaven.com/assets?t=models').catch(error => { catalog = null; throw error; });
    return catalog;
  }
  async function metadata(id) {
    if (!validAssetId(id)) throw new Error('Invalid asset ID.');
    if (id.startsWith('sf-')) return sketchfab(id.slice(3));
    const item = (await polyhavenCatalog())[id.slice(3)];
    if (!item || item.type !== 2) throw new Error('Unknown Poly Haven model.');
    return { asset_id: id, provider: 'polyhaven', source_id: id.slice(3), title: item.name,
      author: Object.keys(item.authors ?? {}).join(', '), page: `https://polyhaven.com/a/${id.slice(3)}`,
      license: 'cc0', license_label: 'CC0', license_url: 'https://creativecommons.org/publicdomain/zero/1.0/',
      credit: 'Powered by Poly Haven', triangles: item.polycount ?? 0 };
  }
  async function search(query, provider = 'all') {
    if (typeof query !== 'string' || !query.trim() || query.length > 120 || !['all', 'sketchfab', 'polyhaven'].includes(provider)) {
      throw new Error('Search with 1–120 characters and a supported provider.');
    }
    const results = [];
    const errors = [];
    if (provider !== 'polyhaven') {
      try {
        const data = await json(`https://api.sketchfab.com/v3/search?type=models&downloadable=true&count=6&q=${encodeURIComponent(query)}`, await token());
        const details = await Promise.allSettled(data.results.map(item => sketchfab(item.uid)));
        for (const detail of details) if (detail.status === 'fulfilled') results.push(detail.value);
      } catch (error) { errors.push(error.message); }
    }
    if (provider !== 'sketchfab') {
      try {
        const words = query.toLowerCase().split(/\s+/).filter(Boolean);
        const matches = Object.entries(await polyhavenCatalog()).filter(([, item]) => item.type === 2)
          .map(([id, item]) => ({ id, score: words.filter(word => `${item.name} ${(item.tags ?? []).join(' ')}`.toLowerCase().includes(word)).length }))
          .filter(item => item.score > 0).sort((a, b) => b.score - a.score).slice(0, 6);
        for (const item of matches) results.push(await metadata(`ph-${item.id}`));
      } catch (error) { errors.push(error.message); }
    }
    return { ok: true, assets: results, notices: errors };
  }
  async function status(id) {
    if (!validAssetId(id)) throw new Error('Invalid asset ID.');
    try {
      const record = JSON.parse(await readFile(path.join(directory, id, 'asset.json'), 'utf8'));
      await stat(path.join(directory, id, 'model.glb'));
      return { ok: true, status: 'ready', asset: record };
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    return jobs.get(id)?.state ?? { ok: false, status: 'missing', message: 'Import this asset first.' };
  }
  async function prepare(id, job) {
    const rigged = id.startsWith('rig-');
    const info = await metadata(rigged ? id.slice(4) : id);
    info.asset_id = id;
    await mkdir(directory, { recursive: true });
    const stage = await mkdtemp(path.join(directory, '.preparing-'));
    job.state = { ok: true, status: 'downloading', asset_id: id };
    let source;
    if (info.provider === 'sketchfab') {
      const links = await json(`https://api.sketchfab.com/v3/models/${info.source_id}/download`, await token());
      if (!links.glb?.url) throw new Error('Sketchfab does not offer this model as GLB.');
      source = path.join(stage, 'source.glb');
      await writeFile(source, await bytes(links.glb.url));
    } else {
      const files = await json(`https://api.polyhaven.com/files/${info.source_id}`);
      const formats = files.gltf?.['1k'] ?? files.gltf?.['2k'];
      const gltf = formats?.gltf;
      if (!gltf?.url) throw new Error('Poly Haven does not offer this model as glTF.');
      source = path.join(stage, path.basename(new URL(gltf.url).pathname));
      await writeFile(source, await bytes(gltf.url));
      let total = (await stat(source)).size;
      for (const [name, file] of Object.entries(gltf.include ?? {})) {
        const target = path.resolve(stage, name);
        if (!target.startsWith(stage + path.sep)) throw new Error('Invalid model dependency path.');
        const data = await bytes(file.url);
        total += data.length;
        if (total > LIMIT) throw new Error('The model and textures exceed 64 MB.');
        await mkdir(path.dirname(target), { recursive: true });
        await writeFile(target, data);
      }
    }
    job.state = { ok: true, status: 'preparing', asset_id: id };
    const output = path.join(stage, 'model.glb');
    const run = () => exec(blenderPath, ['--background', '--factory-startup', '--disable-autoexec', '--python-exit-code', '1',
      '--python', path.join(root, 'scripts/blender/prepare_runtime_asset.py'), '--', source, output,
      ...(rigged ? ['--preserve-rig'] : [])],
      { windowsHide: true, timeout: 120000, maxBuffer: 512 * 1024 });
    const blenderPath = await blender();
    const operation = preparing.then(run);
    preparing = operation.catch(() => {});
    try {
      const result = await operation;
      await writeFile(path.join(stage, 'prepare.log'), result.stdout + result.stderr);
    } catch (error) {
      const log = (error.stdout ?? '') + (error.stderr ?? '');
      await writeFile(path.join(stage, 'prepare.log'), log);
      if (log.includes('EUCLID_RIG_REQUIRED')) throw new Error('Choose a model with one skinned skeleton for joint animation.');
      if (log.includes('EUCLID_RIG_BUDGET')) throw new Error('Choose a rigged model under 100,000 triangles and 256 joints.');
      throw new Error('Blender could not prepare this model within the import budget.');
    }
    const size = (await stat(output)).size;
    if (size > LIMIT) throw new Error('The prepared model exceeds 64 MB.');
    const report = JSON.parse(await readFile(output + '.json', 'utf8'));
    const record = { ...info, ...report, bytes: size };
    await writeFile(path.join(stage, 'asset.json'), JSON.stringify(record));
    await rename(stage, path.join(directory, id));
    job.state = { ok: true, status: 'ready', asset: record };
  }
  async function importAsset(id, preserveRig = false) {
    if (!validAssetId(id)) throw new Error('Invalid asset ID.');
    if (typeof preserveRig !== 'boolean') throw new Error('Invalid asset import options.');
    if (preserveRig && !id.startsWith('rig-')) id = `rig-${id}`;
    const current = await status(id);
    if (current.status === 'ready' || (current.ok && jobs.has(id))) return current;
    const active = [...jobs.values()].filter(job => job.state.ok && job.state.status !== 'ready');
    if (active.length >= 2) return { ok: false, status: 'busy', message: 'Two models are already importing. Retry when one finishes.' };
    const job = { state: { ok: true, status: 'queued', asset_id: id } };
    jobs.set(id, job);
    prepare(id, job).catch(error => { job.state = { ok: false, status: 'failed', message: error.message, asset_id: id }; });
    return job.state;
  }
  async function list() {
    await mkdir(directory, { recursive: true });
    const assets = [];
    for (const name of await readdir(directory)) {
      if (validAssetId(name)) {
        const item = await status(name);
        if (item.status === 'ready') assets.push(item.asset);
      }
    }
    return { ok: true, assets };
  }
  async function model(id) {
    if ((await status(id)).status !== 'ready') throw new Error('The model is not ready.');
    return { file: path.join(directory, id, 'model.glb') };
  }
  return { search, importAsset, status, list, model };
}
