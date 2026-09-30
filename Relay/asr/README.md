# PC-local streaming ASR (experimental)

The iPhone picker adds Nemotron 3.5 ASR 0.6B and Qwen3-ASR 1.7B. Both run on the PC GPU, one at a time, with no speech API charges. They do not call Meta. The existing authenticated `/v1/speech` tunnel carries PCM16 mono at 16 kHz and cumulative captions. The phone requires a matching provider/sample-rate acknowledgement before starting its microphone.

## Existing PC installation

Keep LiveCue Desktop running. Settings shows Start model, Stop model, status, elapsed loading time and safe startup errors for either PC-local provider. Start opens the verified installed Docker Desktop if its engine is unavailable, then loads the selected model. Stop unloads only the LiveCue-labeled container, retaining images and weights. Controls reject an active conversation or lab test and serialize model operations. Startup continues when the phone leaves Settings or disconnects; return to see its status.

The installed lab is a sibling folder `LiveCue-ASR` next to the `LiveCue` app folder. The relay invokes only fixed `Start-ASR-Lab.ps1` / `Stop-ASR-Lab.ps1` launchers with allowlisted model names. Loading from Settings allows up to two minutes for Docker startup and eight minutes for model initialization without a long-running HTTP request; authenticated start/stop routes return 202 and status is polled. Cold speech startup remains bounded to about three minutes; if it takes longer, wait for Ready in Settings before recording.

The Docker service stays bound to `127.0.0.1:8765`; do not publish that port. Update both relay and Funnel proxy for the speech header and authenticated `/v1/local-model` status and `/v1/local-model/start` / `stop` routes. No new credentials are needed; the same saved native pairing token authorizes controls. Browser-origin requests and arbitrary model/command inputs are rejected. The encrypted Meta key is not passed to the launcher or Docker.

Source snapshots in this folder correspond to the installed lab server/launcher. Weights, recordings, private fixtures, API keys, pairing data, and model caches are intentionally absent. Runtime images remain `livecue-asr-nemotron:0.1` and `livecue-asr-qwen3:0.1`; no image rebuild is needed when the bind-mounted Python service changes.

## Testing on iPhone

Select a PC model in Settings, tap Start model and wait for Ready before recording. After ending your conversation, Stop model frees its GPU memory. The controls do not appear for Meta or on-iPhone models.

Install the new IPA over LiveCue in LiveContainer, open Settings → Transcription, select either PC model, then start a conversation. Watch the first-words timing, tap Assist, and pause/stop to finalize. History records provider, zero API cost, first-word delay and last finalization time. The first-word number includes initial silence and network delay; it is not pure inference time. Compare using the same spoken passage and network.

Models currently use independent 30-second windows to bound GPU context during longer conversations. Audio samples are retained across boundaries, but model context resets there, so a word cut by a boundary may be less accurate. Sessions are limited to 30 minutes per stream; pause/resume reconnects. Backgrounding, phone-call interruptions or connection loss pause capture; this is not a background recorder.

## Verification

`npm test` in Relay covers authentication, provider selection, no paid fallback, PCM forwarding, sanitization and tunnel header forwarding. `node --experimental-strip-types scripts/verify-pc-asr.ts nemotron <synthetic-16k-mono-wav> 3` exercises real-time PCM through an isolated relay and tunnel with the actual GPU model; use `qwen3` to switch. It uses an ephemeral token, no Meta key, and does not open a microphone. `python test_protocol.py` inside the lab container covers native protocol and exact sample preservation. Simulator UI tests use explicit fixtures, not the PC GPU or physical iPhone microphone.
