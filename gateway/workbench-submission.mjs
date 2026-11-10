import { mkdir, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { sourceDraftLimit } from './workbench-agent-draft.mjs';
import { agentFileLimit, isAgentSourcePath } from './workbench-source.mjs';

const totalLimit = 480 * 1024;

// Turns files sent by a connected agent into a draft author. It writes into the
// same temporary workspace a local source agent would edit, so the submission
// passes through the same path, size and diff validation afterwards.
export function sourceSubmission(body) {
  const files = body.files ?? [];
  const removed = body.delete ?? [];
  if (!Array.isArray(files) || !Array.isArray(removed) || files.length + removed.length < 1 || files.length + removed.length > sourceDraftLimit) {
    throw new Error(`Submit 1 to ${sourceDraftLimit} files to write or delete.`);
  }
  const names = new Set();
  let bytes = 0;
  for (const name of [...files.map(file => file?.path), ...removed]) {
    if (!isAgentSourcePath(name)) throw new Error(`A draft cannot change ${typeof name === 'string' ? name.slice(0, 120) : 'that path'}.`);
    if (names.has(name)) throw new Error(`${name} appears more than once.`);
    names.add(name);
  }
  for (const { path: name, content } of files) {
    if (typeof content !== 'string' || content.includes('\0')) throw new Error(`${name} must be UTF-8 text.`);
    const size = Buffer.byteLength(content);
    if (size > agentFileLimit) throw new Error(`${name} exceeds 256 KiB.`);
    bytes += size;
  }
  if (bytes > totalLimit) throw new Error('The submitted files exceed 480 KiB in total.');
  const summary = typeof body.summary === 'string' ? body.summary.replace(/\s+/g, ' ').trim().slice(0, 320) : '';
  return async ({ workspace }) => {
    for (const { path: name, content } of files) {
      const file = path.join(workspace, name);
      await mkdir(path.dirname(file), { recursive: true });
      await writeFile(file, content);
    }
    for (const name of removed) {
      await rm(path.join(workspace, name)).catch(error => {
        throw error.code === 'ENOENT' ? new Error(`${name} does not exist in the draft.`) : error;
      });
    }
    return summary;
  };
}
