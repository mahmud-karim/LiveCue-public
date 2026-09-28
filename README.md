# LiveCue

LiveCue is a personal iPhone conversation assistant with public source and a private Windows relay. Midnight Mint uses 16-point default body text (scaling with iOS Dynamic Type). **Meta Muse** streams live captions through your PC; **Voz on Assist** and **Live Parakeet** remain available under Settings as on-device alternatives. Assist sends the current text context to Codex CLI on your Windows PC.

Requires iOS 18 or later. End the current conversation before changing transcription provider. Local models require preparation; Meta needs no model download. Cloud shows first partial timing from stream start, which includes time spent speaking, not isolated inference latency. Simulator UI tests use fixtures; microphone hardware and actual latency require iPhone testing.

## Privacy and consent

Obtain informed consent before recording. Audio is not saved by LiveCue. In Meta mode it streams to Meta and incurs provider charges; local modes keep audio on the phone. Transcripts, answers and notes persist on the iPhone until deleted. Desktop shows conversation text in bounded memory, not disk logs. Provider processing is subject to Meta's terms; this is not a claim of zero provider retention.

The Meta key is never in the phone app or GitHub. Windows launchers decrypt a CurrentUser DPAPI credential at `%LOCALAPPDATA%/LiveCue/meta-stt-key.xml` into only the relay child's environment. That file must be a `PSCredential` exported with `Export-Clixml` by the same Windows user; restrict its ACL to that user. No credentials are required for GitHub builds. Codex subprocesses do not inherit the Meta key. The native phone uses its existing Keychain pairing token over Tailscale WSS. The relay restricts cloud connections to one at a time, fixed PCM/model/endpoint, bounded buffers, idle timeout and 30-minute sessions. Pause/resume starts a fresh cloud stream; disconnections do not automatically retry billable requests. These are application limits, not a provider spending cap.

## First-time Windows setup

1. Install and sign into Tailscale on the PC and iPhone.
2. Confirm Codex CLI is signed into the ChatGPT subscription (`codex login status`).
3. In `Relay`, run `npm install` once.
4. Double-click **LiveCue Desktop.cmd**, then click **Start relay**. Close an old relay terminal first if one is running. The desktop checks Codex/Tailscale and displays the PC endpoint.
5. Click **Generate new pairing QR** if needed (this invalidates old pairing), then on iPhone open **Pair Windows PC → Scan PC QR code → Verify and pair**. Camera denial has a manual JSON fallback using the terminal launcher.
6. Start a conversation for Meta live captions (requires the PC credential above). For local alternatives, select the provider in Settings, then prepare it in Model Library.

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
