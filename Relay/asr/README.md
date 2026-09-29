# PC-local streaming ASR (experimental)

The iPhone picker adds Nemotron 3.5 ASR 0.6B and Qwen3-ASR 1.7B. Both run on the PC GPU, one at a time, with no speech API charges. They do not call Meta. The existing authenticated `/v1/speech` tunnel carries PCM16 mono at 16 kHz and cumulative captions. The phone requires a matching provider/sample-rate acknowledgement before starting its microphone.

## Existing PC installation

Keep Docker Desktop and LiveCue Desktop running. The installed lab is a sibling folder `LiveCue-ASR` next to the `LiveCue` app folder. The relay invokes only its fixed `Start-ASR-Lab.ps1` launcher with one of two allowlisted model names. The launcher reuses a ready model, rejects switching during another lab test, or replaces only its own labeled container. It never deletes images or weights. First load/switch commonly takes tens of seconds; the phone displays loading time and starts recording after readiness. A disconnected launch retains its switching lock until completion.

The Docker service stays bound to `127.0.0.1:8765`; do not publish that port. The desktop relay and Funnel proxy must both be updated so `X-LiveCue-Speech-Model` reaches the relay. The encrypted Meta key is not passed to the launcher or Docker. No new public routes or credential stores are needed.

Source snapshots in this folder correspond to the installed lab server/launcher. Weights, recordings, private fixtures, API keys, pairing data, and model caches are intentionally absent. Runtime images remain `livecue-asr-nemotron:0.1` and `livecue-asr-qwen3:0.1`; no image rebuild is needed when the bind-mounted Python service changes.

## Testing on iPhone

Install the new IPA over LiveCue in LiveContainer, open Settings → Transcription, select either PC model, then start a conversation. Watch the first-words timing, tap Assist, and pause/stop to finalize. History records provider, zero API cost, first-word delay and last finalization time. The first-word number includes initial silence and network delay; it is not pure inference time. Compare using the same spoken passage and network.

Models currently use independent 30-second windows to bound GPU context during longer conversations. Audio samples are retained across boundaries, but model context resets there, so a word cut by a boundary may be less accurate. Sessions are limited to 30 minutes per stream; pause/resume reconnects. Backgrounding, phone-call interruptions or connection loss pause capture; this is not a background recorder.

## Verification

`npm test` in Relay covers authentication, provider selection, no paid fallback, PCM forwarding, sanitization and tunnel header forwarding. `node --experimental-strip-types scripts/verify-pc-asr.ts nemotron <synthetic-16k-mono-wav> 3` exercises real-time PCM through an isolated relay and tunnel with the actual GPU model; use `qwen3` to switch. It uses an ephemeral token, no Meta key, and does not open a microphone. `python test_protocol.py` inside the lab container covers native protocol and exact sample preservation. Simulator UI tests use explicit fixtures, not the PC GPU or physical iPhone microphone.
