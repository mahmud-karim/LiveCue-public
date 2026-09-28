// Explicit manual smoke test only. Uses one synthetic PCM clip; no microphone or auto retries.
import { readFile } from 'node:fs/promises';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { WebSocket } from '../Relay/node_modules/ws/wrapper.mjs';
import { createLiveCueServer } from '../Relay/src/server.ts';
import { hashToken } from '../Relay/src/security.ts';
const wav = await readFile(process.argv[2]);
let pcm;
for (let i = 12; i + 8 <= wav.length;) {
  const length = wav.readUInt32LE(i + 4);
  if (wav.toString('ascii', i, i + 4) === 'data') pcm = wav.subarray(i + 8, i + 8 + length);
  i += 8 + length + length % 2;
}
if (!pcm || pcm.length > 30 * 48000) throw Error('Use a synthetic mono PCM16 24kHz WAV under 30 seconds.');
if (!process.env.LIVECUE_META_API_KEY) throw Error('Credential not loaded.');
const server = createLiveCueServer(hashToken('local-smoke-test'));
server.listen(0, '127.0.0.1'); await once(server, 'listening');
const ws = new WebSocket(`ws://127.0.0.1:${server.address().port}/v1/speech`, { headers: { Authorization: 'Bearer local-smoke-test' } });
let accepted; const ready = new Promise(resolve => { accepted = resolve; });
let partials = 0, finals = 0, failure = false;
ws.on('error', () => { failure = true; accepted(false); });
ws.on('message', raw => {
  const event = JSON.parse(raw.toString());
  if (event.type === 'ready') accepted(true);
  if (event.type === 'error') { failure = true; accepted(false); }
  if (event.type === 'transcript') partials++;
  if (event.type === 'speechComplete' && event.transcript) finals++;
});
ws.on('close', () => accepted(false));
const closed = once(ws, 'close');
const timer = setTimeout(() => { failure = true; ws.terminate(); }, 45000);
try {
  if (!await ready) throw Error('Cloud proxy did not become ready.');
  const audio = Buffer.concat([pcm, Buffer.alloc(48000)]);
  for (let i = 0; i < audio.length; i += 3840) { ws.send(audio.subarray(i, i + 3840)); await sleep(80); }
  ws.send(JSON.stringify({ type: 'endStream' })); await closed;
  if (failure || !partials || !finals) throw Error('Cloud proxy smoke test failed.');
  console.log(JSON.stringify({ ok: true, audioSeconds: audio.length / 48000, partials, finals, noAudioSavedByRelay: true }));
} finally { clearTimeout(timer); ws.terminate(); server.close(); }
