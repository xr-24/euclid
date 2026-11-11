import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile, appendFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createJournal } from './workbench-journal.mjs';

async function folder(t) {
  const area = await mkdtemp(path.join(os.tmpdir(), 'euclid-journal-'));
  t.after(() => rm(area, { recursive: true, force: true }));
  return area;
}

test('the journal keeps events in order and filters by draft', async t => {
  const area = await folder(t);
  let clock = Date.parse('2026-11-10T12:00:00Z');
  const journal = createJournal(path.join(area, 'nested/journal.jsonl'), { now: () => new Date(clock += 1000) });
  const a = '11111111-1111-1111-1111-111111111111', b = '22222222-2222-2222-2222-222222222222';
  journal.record('drafted', { draft: a, owner: 'codex', files: ['world/main.tscn', 7], summary: 'x'.repeat(400), unknown: 'dropped' });
  journal.record('checked', { draft: a, status: 'failed', scope: 'full', error: 'Godot check failed' });
  journal.record('drafted', { draft: b, owner: 'claude', files: ['gateway/server.mjs'] });
  await journal.record('committed', { draft: a, commit: 'f'.repeat(40), message: 'Fix the villa' });

  const all = await journal.read();
  assert.deepEqual(all.map(item => item.event), ['committed', 'drafted', 'checked', 'drafted']);
  assert.equal(all[0].at, '2026-11-10T12:00:04.000Z');
  const first = all.at(-1);
  assert.deepEqual(first.files, ['world/main.tscn']);
  assert.equal(first.summary.length, 321);
  assert.equal(first.unknown, undefined);
  assert.deepEqual((await journal.read({ draft: a })).map(item => item.event), ['committed', 'checked', 'drafted']);
  assert.deepEqual((await journal.read({ limit: 1 })).map(item => item.event), ['committed']);
  assert.throws(() => journal.record('installed', {}), /Unknown journal event/);
});

test('the journal survives a restart, rolls over, and skips damaged lines', async t => {
  const area = await folder(t);
  const file = path.join(area, 'journal.jsonl');
  const first = createJournal(file, { maxBytes: 400 });
  for (let index = 0; index < 6; index++) await first.record('discarded', { draft: `${index}`.repeat(36) });
  await appendFile(file, 'not json\n{"event":"rewritten"}\n');

  const second = createJournal(file, { maxBytes: 400 });
  const entries = await second.read({ limit: 500 });
  assert.ok(entries.length >= 3 && entries.length <= 6, `kept ${entries.length}`);
  assert.equal(entries[0].draft, '5'.repeat(36));
  assert.ok((await readFile(path.join(area, 'journal.1.jsonl'), 'utf8')).length > 0);
  assert.ok((await readFile(file, 'utf8')).length <= 400 + 60);
});

test('a journal that cannot be written reports the error and never throws', async t => {
  const area = await folder(t);
  await writeFile(path.join(area, 'blocked'), 'a file where a folder should be');
  const errors = [];
  const journal = createJournal(path.join(area, 'blocked/journal.jsonl'), { onError: error => errors.push(error) });
  await journal.record('drafted', { draft: 'a' });
  await journal.record('discarded', { draft: 'a' });
  assert.equal(errors.length, 2);
  assert.deepEqual(await journal.read().catch(error => error.code), 'ENOTDIR');
});
