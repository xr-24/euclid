import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import { createGateway } from './server.mjs';

test('player voice routes authorize in the browser, paginate account voices and return MP3 bytes', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'euclid-voice-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const apiKey = 'fixture-api-key';
  const envFile = path.join(directory, '.env.local');
  const authorizationUrl = 'https://elevenlabs.io/app/oauth/authorize?state=test';
  const approve = Promise.withResolvers();
  const calls = [];
  let waits = 0;
  const speechOptions = {
    env: {}, envFile,
    async onboard(directory, file, args) {
      assert.equal(file, envFile);
      if (args.includes('--no-browser')) return { next: 'wait', say: 'Open ' + authorizationUrl };
      if (++waits === 1) return { next: 'wait' };
      await approve.promise;
      await writeFile(file, 'ELEVENLABS_API_KEY=' + apiKey);
      return { details: { key_status: 'created' } };
    },
    clientFor(key) {
      assert.equal(key, apiKey);
      return {
        voices: { async search({ pageSize, nextPageToken }) {
          assert.equal(pageSize, 100);
          calls.push(nextPageToken);
          return nextPageToken
            ? { voices: [{ voiceId: 'v1', name: 'Avery' }], hasMore: false }
            : { voices: [{ voiceId: 'v2', name: 'Zoe' }], hasMore: true, nextPageToken: 'after-Zoe' };
        } },
        textToSpeech: { async convert(voice, request) {
          assert.equal(voice, 'v2');
          assert.equal(request.outputFormat, 'mp3_44100_64');
          assert.equal(request.text, 'Hello from Euclid.');
          return new ReadableStream({ start(controller) {
            controller.enqueue(Uint8Array.of(73, 68, 51));
            controller.close();
          } });
        } },
      };
    },
  };
  const dataDir = path.join(directory, 'data');
  await mkdir(dataDir);
  const { server } = await createGateway({ dataDir, token: 'world', workbenchToken: 'player', speechOptions });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const post = (action, body = {}, desktop = true) => fetch(`http://127.0.0.1:${server.address().port}/v1/speech/${action}`,
      { method: 'POST', headers: { Authorization: 'Bearer world', 'Content-Type': 'application/json',
        ...(desktop && { 'X-Euclid-Workbench': 'player' }) }, body: JSON.stringify(body) });
    assert.equal((await post('synthesize', {}, false)).status, 403);
    assert.equal((await (await post('voices')).json()).connect, true);
    assert.deepEqual(await (await post('authorize')).json(), { authorization_url: authorizationUrl });
    assert.deepEqual(await (await post('voices')).json(), { connecting: true });
    approve.resolve();
    let catalog;
    for (let attempt = 0; attempt < 20; attempt++) {
      catalog = await (await post('voices')).json();
      if (catalog.voices) break;
      await delay(50);
    }
    assert.deepEqual(catalog.voices, [{ id: 'v1', name: 'Avery' }, { id: 'v2', name: 'Zoe' }]);
    assert.deepEqual(calls, [undefined, 'after-Zoe']);
    assert.equal((await post('synthesize', { voice: '../settings', text: 'hello' })).status, 400);
    const audio = await post('synthesize', { voice: 'v2', text: 'Hello from Euclid.' });
    assert.equal(audio.headers.get('content-type'), 'audio/mpeg');
    assert.deepEqual([...new Uint8Array(await audio.arrayBuffer())], [73, 68, 51]);
  } finally {
    approve.resolve();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});
