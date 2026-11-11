import { appendFile, mkdir, readFile, rename, stat } from 'node:fs/promises';
import path from 'node:path';

// A durable record of what happened to each Workbench draft: who drafted it, each
// revision and check, and whether it was committed, discarded or reverted. Entries
// are JSON lines. When the file passes its size limit it becomes the one older file
// and a new one starts. Recording never fails the action it records.
export const journalEvents = Object.freeze(['drafted', 'revised', 'restored_previous', 'checked', 'committed', 'discarded', 'reverted']);
const fields = ['draft', 'version', 'owner', 'files', 'summary', 'status', 'scope', 'error', 'commit', 'message', 'reverted'];
const limits = { summary: 320, error: 400, message: 100 };

function entry(event, details, now) {
  if (!journalEvents.includes(event)) throw new Error(`Unknown journal event: ${event}`);
  const item = { at: now().toISOString(), event };
  for (const name of fields) {
    let value = details[name];
    if (value === undefined || value === null || value === '') continue;
    if (name === 'files') value = Array.isArray(value) ? value.filter(file => typeof file === 'string').slice(0, 64) : undefined;
    else if (typeof value !== 'string') continue;
    else if (limits[name] && value.length > limits[name]) value = `${value.slice(0, limits[name])}…`;
    if (value !== undefined) item[name] = value;
  }
  return item;
}

export function createJournal(file, { maxBytes = 1024 * 1024, now = () => new Date(), onError = () => {} } = {}) {
  const older = file.replace(/(\.jsonl)?$/, '.1.jsonl');
  let turn = Promise.resolve();

  async function write(line) {
    await mkdir(path.dirname(file), { recursive: true });
    const size = await stat(file).then(info => info.size, error => { if (error.code === 'ENOENT') return 0; throw error; });
    if (size && size + Buffer.byteLength(line) > maxBytes) await rename(file, older);
    await appendFile(file, line);
  }

  function record(event, details = {}) {
    const line = JSON.stringify(entry(event, details, now)) + '\n';
    const next = turn.then(() => write(line));
    turn = next.catch(error => onError(error));
    return turn;
  }

  async function lines(name) {
    const text = await readFile(name, 'utf8').catch(error => { if (error.code === 'ENOENT') return ''; throw error; });
    return text.split('\n').flatMap(line => {
      try { const item = JSON.parse(line); return item && typeof item === 'object' && journalEvents.includes(item.event) ? [item] : []; }
      catch { return []; }
    });
  }

  // Newest first. With a draft id, only that draft's entries.
  async function read({ limit = 50, draft } = {}) {
    await turn;
    const items = [...await lines(older), ...await lines(file)];
    const chosen = draft ? items.filter(item => item.draft === draft) : items;
    return chosen.slice(-Math.max(1, Math.min(limit, 500))).reverse();
  }

  return { record, read, file };
}
