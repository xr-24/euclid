import { lstat, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { sourceDraftLimit } from './workbench-agent-draft.mjs';
import { agentFileLimit, isAgentSourcePath } from './workbench-source.mjs';

const totalLimit = 480 * 1024;
const maxEdits = 48;

const normalizeSummary = summary => typeof summary === 'string' ? summary.replace(/\s+/g, ' ').trim().slice(0, 320) : '';
function assertAgentPath(name) {
  if (!isAgentSourcePath(name)) throw new Error(`A draft cannot change ${typeof name === 'string' ? name.slice(0, 120) : 'that path'}.`);
}

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
    assertAgentPath(name);
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
  const summary = normalizeSummary(body.summary);
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

// Turns targeted edits, new files and deletions into a draft author so connected
// agents can patch existing files without resending full contents.
export function patchSubmission(body) {
  const edits = body?.edits ?? [];
  const create = body?.create ?? [];
  const removed = body?.delete ?? [];
  if (!Array.isArray(edits) || !Array.isArray(create) || !Array.isArray(removed)) {
    throw new Error('Patch edits, create and delete must be arrays.');
  }
  if (edits.length + create.length + removed.length < 1) {
    throw new Error('Provide at least one edit, create or delete operation.');
  }
  if (edits.length > maxEdits) throw new Error(`A patch may contain at most ${maxEdits} edits.`);
  if (create.length > sourceDraftLimit || removed.length > sourceDraftLimit) {
    throw new Error(`A patch may create or delete at most ${sourceDraftLimit} files.`);
  }
  const editedPaths = new Set();
  const createdPaths = new Set();
  const removedPaths = new Set();
  const touched = new Set();
  for (const item of edits) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) throw new Error('Each edit must be an object.');
    assertAgentPath(item.path);
    if (typeof item.old_text !== 'string' || !item.old_text.length || item.old_text.includes('\0')) {
      throw new Error(`${item.path} old_text must be non-empty UTF-8 text.`);
    }
    if (typeof item.new_text !== 'string' || item.new_text.includes('\0')) {
      throw new Error(`${item.path} new_text must be UTF-8 text.`);
    }
    if (item.replace_all !== undefined && typeof item.replace_all !== 'boolean') {
      throw new Error(`${item.path} replace_all must be a boolean.`);
    }
    if (Buffer.byteLength(item.new_text) > agentFileLimit) throw new Error(`${item.path} exceeds 256 KiB.`);
    editedPaths.add(item.path);
    touched.add(item.path);
  }
  for (const item of create) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) throw new Error('Each create entry must be an object.');
    assertAgentPath(item.path);
    if (createdPaths.has(item.path)) throw new Error(`${item.path} appears more than once in create.`);
    if (editedPaths.has(item.path)) throw new Error(`${item.path} cannot appear in both edits and create.`);
    if (typeof item.content !== 'string' || item.content.includes('\0')) throw new Error(`${item.path} must be UTF-8 text.`);
    if (Buffer.byteLength(item.content) > agentFileLimit) throw new Error(`${item.path} exceeds 256 KiB.`);
    createdPaths.add(item.path);
    touched.add(item.path);
  }
  for (const name of removed) {
    assertAgentPath(name);
    if (removedPaths.has(name)) throw new Error(`${name} appears more than once in delete.`);
    if (editedPaths.has(name) || createdPaths.has(name)) throw new Error(`${name} cannot be both deleted and modified.`);
    removedPaths.add(name);
    touched.add(name);
  }
  if (touched.size > sourceDraftLimit) throw new Error(`A patch may touch at most ${sourceDraftLimit} files.`);
  const summary = normalizeSummary(body?.summary);
  return async ({ workspace }) => {
    const finalBytes = new Map();
    for (const edit of edits) {
      const file = path.join(workspace, edit.path);
      const raw = await readFile(file, 'utf8').catch(error => {
        throw error.code === 'ENOENT' ? new Error(`${edit.path} does not exist.`) : error;
      });
      const crlf = raw.includes('\r\n');
      const haystack = raw.replace(/\r\n/g, '\n');
      const oldNorm = edit.old_text.replace(/\r\n/g, '\n');
      const newNorm = edit.new_text.replace(/\r\n/g, '\n');
      let count = 0;
      let at = 0;
      while ((at = haystack.indexOf(oldNorm, at)) !== -1) {
        count++;
        at += oldNorm.length;
      }
      if (count === 0) throw new Error(`old_text not found in ${edit.path}.`);
      if (count > 1 && edit.replace_all !== true) {
        throw new Error(`old_text matched ${count} times in ${edit.path}; provide more context or set replace_all: true.`);
      }
      const replaced = edit.replace_all ? haystack.split(oldNorm).join(newNorm) : haystack.replace(oldNorm, () => newNorm);
      const updated = crlf ? replaced.replace(/\n/g, '\r\n') : replaced;
      const size = Buffer.byteLength(updated);
      if (size > agentFileLimit) throw new Error(`${edit.path} exceeds 256 KiB.`);
      finalBytes.set(edit.path, size);
      await writeFile(file, updated);
    }
    for (const item of create) {
      const file = path.join(workspace, item.path);
      const exists = await lstat(file).then(() => true, error => {
        if (error.code === 'ENOENT') return false;
        throw error;
      });
      if (exists) throw new Error(`${item.path} already exists; use edits or submit_draft.`);
      await mkdir(path.dirname(file), { recursive: true });
      await writeFile(file, item.content);
      finalBytes.set(item.path, Buffer.byteLength(item.content));
    }
    for (const name of removed) {
      await rm(path.join(workspace, name)).catch(error => {
        throw error.code === 'ENOENT' ? new Error(`${name} does not exist in the draft.`) : error;
      });
    }
    let bytes = 0;
    for (const size of finalBytes.values()) bytes += size;
    if (bytes > totalLimit) throw new Error('The patched files exceed 480 KiB in total.');
    return summary;
  };
}
