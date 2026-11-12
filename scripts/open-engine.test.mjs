// Enforces Euclid's open-engine rule: shipped environments are made from parts agents can use.
// See docs/environment-authoring.md. Exceptions live in open-engine-debt.json and may only shrink.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const debt = JSON.parse(fs.readFileSync(path.join(root, 'scripts/open-engine-debt.json'), 'utf8'));
const zonesDir = path.join(root, 'world/data/zones');
const packages = fs.readdirSync(zonesDir, { withFileTypes: true })
  .filter(entry => entry.isDirectory() && fs.existsSync(path.join(zonesDir, entry.name, 'zone.json')))
  .map(entry => JSON.parse(fs.readFileSync(path.join(zonesDir, entry.name, 'zone.json'), 'utf8')));
const pieceTypes = JSON.parse(fs.readFileSync(path.join(root, 'world/data/pieces/types.json'), 'utf8'));

function files(dir, extension, skip = []) {
  const found = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    const relative = path.relative(root, full).split(path.sep).join('/');
    if (skip.some(prefix => relative.startsWith(prefix))) continue;
    if (entry.isDirectory()) found.push(...files(full, extension, skip));
    else if (entry.name.endsWith(extension) && !entry.name.endsWith('.test.mjs')) found.push(relative);
  }
  return found;
}

test('shared code does not name a specific environment package', () => {
  const ids = packages.map(item => item.id).join('|');
  const literal = new RegExp(`["'\`](${ids})["'\`]`, 'g');
  const shared = [
    ...files(path.join(root, 'world/scripts'), '.gd', ['world/scripts/zones/', 'world/scripts/diagnostics/']),
    ...files(path.join(root, 'gateway'), '.mjs'),
  ];
  const problems = [];
  for (const file of shared) {
    const count = (fs.readFileSync(path.join(root, file), 'utf8').match(literal) ?? []).length;
    const allowed = debt.environment_names[file]?.count ?? 0;
    if (count > allowed) {
      problems.push(`${file} names an environment package ${count} time(s) (allowed ${allowed}). ` +
        'Put what that environment needs in its package data or a piece type instead.');
    } else if (count < allowed) {
      problems.push(`${file} now names environment packages ${count} time(s); lower its count in ` +
        'scripts/open-engine-debt.json to lock in the fix.');
    }
  }
  for (const file of Object.keys(debt.environment_names)) {
    if (!fs.existsSync(path.join(root, file))) problems.push(`${file} no longer exists; remove it from the debt file.`);
  }
  assert.deepEqual(problems, []);
});

test('environment packages are documents, not code builders', () => {
  const problems = [];
  for (const item of packages) {
    if (item.builder && !(item.id in debt.code_builders)) {
      problems.push(`${item.id} uses a code builder. Build new environments from pieces (world/data/pieces/types.json).`);
    }
    if (!item.builder && item.id in debt.code_builders) {
      problems.push(`${item.id} no longer has a code builder; remove it from code_builders in the debt file.`);
    }
    if (!item.builder && !Array.isArray(item.pieces)) problems.push(`${item.id} has neither pieces nor a builder.`);
  }
  for (const id of Object.keys(debt.code_builders)) {
    if (!packages.some(item => item.id === id)) problems.push(`${id} is not an installed package; remove it from the debt file.`);
  }
  assert.deepEqual(problems, []);
});

test('every piece uses a registered piece type and its declared fields', () => {
  const common = Object.keys(pieceTypes.common);
  const problems = [];
  const visit = (owner, pieces, ids) => {
    for (const piece of pieces) {
      const type = pieceTypes.types[piece?.type];
      if (!type) {
        problems.push(`${owner}: piece ${piece?.id ?? '?'} has unregistered type ${piece?.type}`);
        continue;
      }
      if (ids.has(piece.id)) problems.push(`${owner}: duplicate piece id ${piece.id}`);
      ids.add(piece.id);
      for (const key of Object.keys(piece)) {
        if (key !== 'children' && !common.includes(key) && !(key in type.fields)) {
          problems.push(`${owner}: piece ${piece.id} has field ${key}, which ${piece.type} does not declare`);
        }
      }
      if (piece.children) visit(owner, piece.children, ids);
    }
  };
  for (const item of packages) if (Array.isArray(item.pieces)) visit(item.id, item.pieces, new Set());
  for (const [id, type] of Object.entries(pieceTypes.types)) {
    const script = type.script ?? '';
    if (!script.startsWith('res://scripts/pieces/') || !fs.existsSync(path.join(root, 'world', script.slice('res://'.length)))) {
      problems.push(`piece type ${id} names a missing factory ${script}`);
    }
  }
  assert.deepEqual(problems, []);
});
