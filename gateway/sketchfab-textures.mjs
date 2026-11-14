import { execFile } from 'node:child_process';
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { createSketchfabSource } from './assets.mjs';

const run = promisify(execFile);
const project = fileURLToPath(new URL('../world', import.meta.url));
const bundled = process.platform === 'win32' ? 'Godot_v4.7.2-stable_win64_console.exe' : 'Godot_v4.7.2-stable_linux.x86_64';
const LIMIT = 24 * 1024 * 1024;
const MAX_TEXTURE_INPUTS = 16;
export const sketchfabTextureId = /^sf_([a-f0-9]{32})$/;

function readGLB(glb) {
  if (glb.length < 28 || glb.toString('ascii', 0, 4) !== 'glTF' || glb.readUInt32LE(4) !== 2 ||
      glb.readUInt32LE(8) !== glb.length || glb.toString('ascii', 16, 20) !== 'JSON') {
    throw new Error('Sketchfab returned an invalid GLB.');
  }
  const end = 20 + glb.readUInt32LE(12);
  if (end + 8 > glb.length || glb.toString('ascii', end + 4, end + 8) !== 'BIN\0' ||
      glb.readUInt32LE(end) !== glb.length - end - 8) {
    throw new Error('The GLB is missing its embedded texture data.');
  }
  return { doc: JSON.parse(glb.toString('utf8', 20, end)), binary: glb.subarray(end + 8) };
}

function embeddedImage(doc, binary, field) {
  const image = doc.images?.[doc.textures?.[field?.index]?.source];
  const view = doc.bufferViews?.[image?.bufferView];
  const start = view?.byteOffset ?? 0;
  const size = view?.byteLength;
  if (!view || view.buffer !== 0 || !Number.isSafeInteger(start) || start < 0 ||
      !Number.isSafeInteger(size) || size < 1 || size > LIMIT || size > binary.length - start) return null;
  const extension = { 'image/jpeg': 'jpg', 'image/png': 'png' }[image.mimeType];
  return extension ? { bytes: binary.subarray(start, start + size), extension } : null;
}

function numericFactor(value, fallback) {
  return Number.isFinite(value) ? value : fallback;
}

function mapsForMaterial(doc, binary, material) {
  const pbr = material.pbrMetallicRoughness ?? {};
  const legacy = material.extensions?.KHR_materials_pbrSpecularGlossiness ?? {};
  const color = pbr.baseColorFactor ?? legacy.diffuseFactor;
  const maps = {
    albedo: embeddedImage(doc, binary, pbr.baseColorTexture ?? legacy.diffuseTexture),
    normal: embeddedImage(doc, binary, material.normalTexture),
    rough_metal: embeddedImage(doc, binary, pbr.metallicRoughnessTexture),
    occlusion: embeddedImage(doc, binary, material.occlusionTexture),
  };
  return {
    maps,
    factors: {
      albedo: [0, 1, 2].map(channel => numericFactor(color?.[channel], 1)),
      roughness: numericFactor(pbr.roughnessFactor, 1 - numericFactor(legacy.glossinessFactor, 0)),
      metallic: numericFactor(pbr.metallicFactor, pbr.metallicRoughnessTexture ? 1 : 0),
      occlusion: numericFactor(material.occlusionTexture?.strength, 1),
      normal: numericFactor(material.normalTexture?.scale, 1),
    },
  };
}

export async function convertSketchfabMaps(glb, kind, directory, projectRoot = project) {
  directory = path.resolve(directory);
  const { doc, binary } = readGLB(glb);
  let candidates;
  if (kind === 'sky') {
    // The conversion validates 2:1 dimensions. Try every unique background/base image in order.
    const options = (doc.materials ?? []).flatMap(material => [material.emissiveTexture,
      material.pbrMetallicRoughness?.baseColorTexture, material.extensions?.KHR_materials_pbrSpecularGlossiness?.diffuseTexture]);
    const textureIndices = [...new Set(options.filter(Boolean).map(option => option.index))].slice(0, MAX_TEXTURE_INPUTS);
    candidates = textureIndices.map(index => ({ maps: { panorama: embeddedImage(doc, binary, { index }) } }))
      .filter(item => item.maps.panorama);
  } else {
    candidates = (doc.materials ?? []).map(material => mapsForMaterial(doc, binary, material))
      .filter(item => item.maps.albedo)
      .sort((a, b) => Object.values(b.maps).filter(Boolean).length - Object.values(a.maps).filter(Boolean).length);
  }
  if (!candidates.length) throw new Error('This Sketchfab asset has no supported embedded texture.');
  if (kind === 'material') candidates = candidates.slice(0, 1);
  const inputs = [];
  for (const [index, candidate] of candidates.entries()) {
    const maps = {};
    for (const [name, image] of Object.entries(candidate.maps)) {
      if (!image) continue;
      const filename = `input-${index}-${name}.${image.extension}`;
      await writeFile(path.join(directory, filename), image.bytes);
      maps[name] = filename;
    }
    inputs.push({ maps, factors: candidate.factors });
  }
  await writeFile(path.join(directory, 'input.json'), JSON.stringify(inputs));
  const binaryPath = process.env.GODOT_BIN ?? path.join(projectRoot, '..', '.tools', 'godot', bundled);
  try {
    const result = await run(binaryPath, ['--headless', '--path', projectRoot, '--script',
      'res://scripts/assets/prepare_texture_maps.gd', '--quit-after', '600', '--', kind, directory],
    { windowsHide: true, timeout: 25000, maxBuffer: 128 * 1024 });
    if (!result.stdout.includes('EUCLID_TEXTURE_MAPS_OK') || /^(?:SCRIPT ERROR|ERROR):/m.test(result.stderr)) {
      throw new Error('Texture conversion did not finish successfully.');
    }
  } catch {
    if (kind === 'sky') throw new Error('Choose a Sketchfab skybox with an embedded 2:1 panoramic image.');
    throw new Error('Godot could not convert the embedded material maps. Choose a textured material sample.');
  }
}

export function createSketchfabTextureSource(source = createSketchfabSource(), convert = convertSketchfabMaps) {
  function metadata(item) {
    return { id: `sf_${item.source_id}`, name: item.title, author: item.author, page: item.page,
      license: item.license_label ?? item.license, license_url: item.license_url, provider: 'Sketchfab' };
  }

  return {
    async search(query) { return (await source.search(query)).map(metadata); },
    async prepare(id, kind, stage) {
      const uid = sketchfabTextureId.exec(id)?.[1];
      if (!uid) throw new Error('Invalid Sketchfab texture ID.');
      const info = metadata(await source.info(uid));
      await convert(await source.glb(uid), kind, stage);
      return info;
    },
  };
}
