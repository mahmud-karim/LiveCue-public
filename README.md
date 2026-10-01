# LiveCue

## 0.5.7 — cloud services directly from iPhone

Meta Muse now streams audio **directly from iPhone to Meta**, not through Windows. In **Transcription settings → Meta API key**, paste your Meta key once, save it to iPhone Keychain, and optionally test the connection without sending microphone audio. Windows credentials are not automatically copied. Keys are masked, excluded from settings/history/source, and used only at the fixed TLS provider destination; redirects are rejected. Authentication errors never display raw provider responses. Removing the key prevents new Meta streams.

For a completely PC-free workflow, choose **Meta Muse · cloud** for transcription and **OpenRouter · direct** for answers, and save both keys on iPhone. The app does not contact the saved PC while this setup is selected. Home shows Meta key readiness and that Windows is not required. Audio is processed by Meta's cloud; Assist text is processed by the chosen OpenRouter service—not by an on-device model. Transcription estimates and reported audio usage still update in conversation/history. Disconnections pause recording with no automatic paid retry or provider fallback.

Nemotron/Qwen3 remain PC-local speech routes; Codex CLI answers still need Windows. Voz/Parakeet remain fully on-iPhone speech models. You can mix these independently. Pairing and existing histories are preserved. The old relay Meta route remains compatible with older phone versions, but this version never uses it; any existing Windows credential stays untouched.

Simulator tests use synthetic credentials and cloud responses and do not make paid transcription/inference requests. Actual microphone performance, provider-key access, and LiveContainer Keychain behavior require a physical-iPhone check.

## 0.5.6 — direct OpenRouter answers

In **Assistant models & timing → Provider**, choose **OpenRouter · direct**, paste your API key into the masked field, tap **Save key**, optionally verify it without an inference request, and choose a model from the searchable catalog. Each Assist calls the selected model directly from the iPhone. Keys stay in iPhone Keychain, never in source, history or the PC relay. Removing the key stops access; there is no automatic switch to Codex, model fallback or paid retry. Stopping a session does not send an OpenRouter summary request. PC and OpenRouter selections are saved separately.

OpenRouter charges are separate from a ChatGPT subscription. Run details save provider-reported request cost in credits and token usage when available; missing usage is not treated as free. Model-picker prices are current catalog prices per million tokens, not an exact request quote. Provider-default reasoning is used on this route.

OpenRouter replaces the **answer** service, not transcription. Nemotron/Qwen3 still need the Windows GPU service; Meta now connects directly from iPhone. Choose Meta, Parakeet or Voz alongside OpenRouter for a workflow with no PC dependency. Transcripts and rolling memory go to OpenRouter and its selected model provider on Assist, subject to their policies.

The PC catalog now queries `model/list` from the same current Codex executable used for answers, with a coalesced five-minute in-memory cache and last-good recovery. It no longer trusts the shared `models_cache.json`, which unrelated older CLI clients can overwrite. This addresses the repeated Luna/Low catalog rejection without silently changing model selection.

### 0.5.4: phone controls for PC speech models

Select Nemotron or Qwen3 in Settings to start/stop its PC GPU service, see loading time and readiness, and retry startup failures. Start launches verified Docker Desktop if needed. Stop unloads only LiveCue's idle model; images and weights stay installed. Model operations require saved pairing and refuse to interrupt active transcription. Update both the relay and Funnel proxy along with the IPA.

## 0.5.3 — persistent PC pairing

Pair once. The iPhone saves the address and credential together in Keychain and an app-container file protected until first unlock and excluded from backups. Existing Keychain pairings migrate automatically. LiveContainer updates should replace the app in its existing data container to preserve settings and history.

Windows saves a recoverable QR credential with current-user DPAPI encryption. Restarting the desktop or redisplaying its QR retains authorization. Upgrading old hash-only PC credentials preserves the old phone's token too. Only an explicit `--reset-pairing` revokes them. The connection screen restores a saved PC, offers Reconnect, and distinguishes rejection from a temporary network/TLS failure; it retries automatically after reopening the app. A TLS failure is a secure-connection problem and scanning the QR cannot repair it.

## 0.5.1 — focused conversation UI

Mint-glow home screen with a bottom Start button; full-screen conversation with microphone-driven waveform and no navigation tabs until Stop. Optional assistant instructions now persist in Settings. Answers open in a dismissible sheet so the transcript remains readable.

The conversation counter updates once per second and History saves a **transcription estimate**, not a Meta invoice. Live estimates use successfully sent PCM duration; finished streams use the last reported `audioProcessedMs`, rounded down separately per stream. The session stores its rate ($0.18/hour, checked 2026-09-28), pauses/reconnects and incomplete-usage status. Credits, taxes, adjustments and assistant usage are excluded. Local STT has no cloud transcription charge. Old history without usage remains readable and does not fabricate a zero cost.

Keep development versions below 1.0 and use patch increments for iterations (0.5.1, 0.5.2, ...). Only move to 1.0 with the owner's explicit approval. Build numbers may increase independently. The release workflow checks that its tag matches the IPA version.

LiveCue is a personal iPhone conversation assistant with public source and an optional private Windows relay. Midnight Mint uses 16-point default body text (scaling with iOS Dynamic Type). **Meta Muse** streams directly to the cloud; **Voz on Assist** and **Live Parakeet** remain available under Settings as on-device alternatives. Assist sends text to your selected answer service: Codex CLI on Windows or OpenRouter directly.

Requires iOS 18 or later. End the current conversation before changing transcription provider. Local models require preparation; Meta needs no model download. Cloud shows first partial timing from stream start, which includes time spent speaking, not isolated inference latency. Simulator UI tests use fixtures; microphone hardware and actual latency require iPhone testing.

## Privacy and consent

Obtain informed consent before recording. Audio is not saved by LiveCue. Meta mode sends audio directly to Meta and incurs provider charges. Nemotron/Qwen3 send audio to your PC; Voz/Parakeet keep it on the phone. Transcripts, answers and notes persist on the iPhone until deleted. Desktop shows PC-routed conversation text in bounded memory, not disk logs. Provider processing is subject to the respective services' terms; this is not a claim of zero provider retention.

Meta and OpenRouter keys entered by the owner stay in iPhone Keychain; no credentials are required for GitHub builds. The app keeps each key separate and sends it only to that provider. Phone audio uses bounded buffers and 80 ms PCM frames. Pause/resume starts a fresh cloud stream; disconnections do not automatically retry billable requests. These are application limits, not a provider spending cap. For older phones only, Windows can still decrypt its existing CurrentUser DPAPI Meta credential into the relay environment; Codex subprocesses do not inherit that key. This release's Meta route never accesses the relay credential.

## First-time Windows setup

1. Install and sign into Tailscale on the PC and iPhone.
2. Confirm Codex CLI is signed into the ChatGPT subscription (`codex login status`).
3. In `Relay`, run `npm install` once.
4. Double-click **LiveCue Desktop.cmd**, then click **Start relay**. Close an old relay terminal first if one is running. The desktop checks Codex/Tailscale and displays the PC endpoint.
5. Click **Generate new pairing QR** if needed (this invalidates old pairing), then on iPhone open **Pair Windows PC → Scan PC QR code → Verify and pair**. Camera denial has a manual JSON fallback using the terminal launcher.
6. For Meta live captions, save a Meta key in the phone's Transcription settings. PC-local models have Start/Stop controls in Settings; on-iPhone models need preparation in Model Library. Windows setup is unnecessary for Meta plus OpenRouter.

The relay binds only to `127.0.0.1`; `tailscale serve` exposes it as private HTTPS inside the tailnet. To rotate the pairing token, use the desktop pairing button or run `./Start-LiveCueRelay.ps1 -ResetPairing`.

## Windows companion

### Optional shared Funnel access

An existing authenticated tunnel gateway can load `Relay/funnel/livecue-proxy.mjs` and route only the declared `/v1/` LiveCue HTTP endpoints and `/v1/speech` WebSocket to loopback port 47831. Construct it with `createLiveCueProxy({port: 47831})`. The running relay validates its current pairing token before any HTTP operation or speech connection; the gateway does not read or duplicate per-user pairing files. Never put the bearer or provider key in source. LiveCue requires its own bearer token, rejects browser origins, strips cookies, and does not accept the gateway's browser session as authorization. Other app routes retain their existing authentication.

After explicitly approving internet reachability and installing the adapter, save a local `%LOCALAPPDATA%/LiveCue/connection.json` with `mode` set to `funnel` and `endpoint` set to the root HTTPS Funnel address (including its port). The launcher validates that the hostname belongs to this PC, advertises that address in the QR, and leaves existing Tailscale mappings untouched. Without this local configuration, the existing private mode remains. Scan a new QR on the iPhone to change its saved endpoint. LiveCue v0.5.0 already supports this; no IPA rebuild is needed. Keep Tailscale and LiveCue running on the PC, but the iPhone needs only ordinary internet. Generating a QR verifies the advertised HTTPS health endpoint without logging the bearer.

Funnel access is internet-reachable, protected by the random pairing token, not tailnet membership. Rotating the LiveCue QR invalidates old LiveCue tokens; it does not revoke other apps' browser sessions. Keep PC connection configuration, pairing state and provider keys outside this public repository.

The native WPF companion requires Windows PowerShell, Node.js 24+, Codex CLI, and Tailscale. Start/stop the relay, pause new requests, see recent authenticated phone activity, and inspect the exact incoming text context and returned answer. The phone sends a heartbeat every five seconds while the app is active; "last seen" does not prove the phone is offline when iOS backgrounds it. Closing the window stops its relay and cancels pending requests. Activity is bounded in memory and cleared on close; nothing is written to conversation logs. The QR hides after two minutes and is never sent to a remote QR service. Desktop control uses a private stdin/stdout pipe, not HTTP endpoints. The terminal launcher remains available.

Model Library shows the SDK-reported download/setup percentage, byte/file counters, and elapsed time. Compilation/Neural Engine preparation may continue after the file download completes; this phase is not a promise of a fixed remaining time.

## Development and releases

`project.yml` is the XcodeGen source of truth. GitHub's macOS runner runs simulator unit/UI tests, captures evidence, then separately builds an unsigned ARM64 iPhoneOS app. The release packages `Payload/LiveCue.app` as `LiveCue.ipa`, publishes it to the public GitHub release, re-downloads it, and verifies checksum and structure. Builds do not contact Meta or use provider credentials.

The IPA is intended for LiveContainer. It is not signed for direct installation and is not an App Store/TestFlight build.

Public development repository: https://github.com/mahmud-karim/LiveCue-public. Public builds use standard GitHub-hosted macOS runners. Never commit pairing payloads, local logs, credentials, or personal conversation data. Pairing is generated locally; publishing this source does not expose a running relay or grant access to it. The two-tab version is experimental and still requires a successful iOS build and physical-device validation.

## Architecture

- `Sources/LiveCueCore`: testable transcript, rolling-memory, relay schemas, and benchmark logic.
- `Sources/LiveCue`: SwiftUI interface, SwiftData persistence, Keychain token storage, Voz batch/FluidAudio Parakeet streaming, and relay client.
- `Relay`: Node 24 TypeScript service that invokes `gpt-5.6-sol` with low reasoning, the default speed tier, structured output, an empty ephemeral working directory, read-only sandboxing, and shell disabled.
- `.github/workflows`: simulator evidence and gated unsigned IPA release.

## Current v1 boundaries

Local transcription targets English; Meta automatically detects supported languages. No diarization, TTS, invisible overlay, lock-screen control, or arbitrary model URLs. iOS can interrupt recording for calls, audio-route changes or system policy. Real-device cloud microphone behavior remains an on-device check.
# Assistant model comparison (v0.4)

On iPhone, open **Assistant models & timing** (or the model row during a conversation). Refresh the authenticated PC catalog, choose a model and supported reasoning level, then tap Assist. The selection also applies to session summaries. Models are sourced from the local Codex catalog; account access is confirmed only when a request succeeds. Service tier remains default.

GPT-6 Astra appears when the PC catalog refreshes. **None (no reasoning)** is additionally enabled for GPT-5.6 Sol/Terra/Luna and GPT-5.5, verified with signed-in CLI structured-output requests. Astra and Spark start at Low. No-reasoning is not a guarantee of instant response; CLI startup and network time remain. Paid/multiplier Fast mode is not enabled.

Each saved answer records its model, reasoning, STT mode, transcript character count, and timings. **Retry same text** reuses the exact previous text, instruction, and rolling context with a fresh request ID and your newly selected assistant settings. It does not retranscribe audio.

Timing boundaries: iPhone monotonic tap-to-answer, pending STT after the tap, context preparation, full HTTP round trip; PC monotonic Codex CLI invocation and remaining relay overhead. CLI time includes startup, cloud work and output handling, not pure model inference. Round trip minus PC duration is a transfer/client-overhead estimate, not separate upload/download measurements. Live Parakeet processing occurs before the tap; its last chunk timing is shown separately. Old saved sessions remain readable.

Restart the PC desktop after updating its source so the running relay exposes the new authenticated model catalog and timing fields. No pairing reset is needed.
