# LiveCue

LiveCue is a personal iPhone conversation assistant with public source code and a private Windows relay. Two tabs compare local transcription: **Voz on Assist** records in memory and transcribes on demand; **Live Parakeet** produces continuous captions. Both send only text context through Tailscale to Codex CLI on the owner's Windows PC.

Requires iOS 18 or later. End the current conversation before switching tabs, then prepare that tab's model (downloads are cached). Voz shows audio duration and transcription wall time; Parakeet shows the last buffer's processing time, not end-to-end caption latency. Simulator UI tests use fixtures: real model speed and microphone behavior must be compared on the iPhone. The vendor's 10-minute/2-second claim is not a measured LiveCue result.

## Privacy and consent

Always obtain the informed consent of everyone being recorded and follow local recording laws. LiveCue visibly indicates recording. Normal session audio is not saved; transcripts, answers, summaries, and notes remain locally on the iPhone until deleted. The Windows relay deliberately does not log request bodies or answers.

## First-time Windows setup

1. Install and sign into Tailscale on the PC and iPhone.
2. Confirm Codex CLI is signed into the ChatGPT subscription (`codex login status`).
3. In `Relay`, run `npm install` once.
4. Double-click **LiveCue Desktop.cmd**, then click **Start relay**. Close an old relay terminal first if one is running. The desktop checks Codex/Tailscale and displays the PC endpoint.
5. Click **Generate new pairing QR** if needed (this invalidates old pairing), then on iPhone open **Pair Windows PC → Scan PC QR code → Verify and pair**. Camera denial has a manual JSON fallback using the terminal launcher.
6. Choose a tab, open **Model Library**, tap **Download & use**, go back, then start a conversation.

The relay binds only to `127.0.0.1`; `tailscale serve` exposes it as private HTTPS inside the tailnet. To rotate the pairing token, use the desktop pairing button or run `./Start-LiveCueRelay.ps1 -ResetPairing`.

## Windows companion

The native WPF companion requires Windows PowerShell, Node.js 24+, Codex CLI, and Tailscale. Start/stop the relay, pause new requests, see recent authenticated phone activity, and inspect the exact incoming text context and returned answer. The phone sends a heartbeat every five seconds while the app is active; "last seen" does not prove the phone is offline when iOS backgrounds it. Closing the window stops its relay and cancels pending requests. Activity is bounded in memory and cleared on close; nothing is written to conversation logs. The QR hides after two minutes and is never sent to a remote QR service. Desktop control uses a private stdin/stdout pipe, not HTTP endpoints. The terminal launcher remains available.

Model Library shows the SDK-reported download/setup percentage, byte/file counters, and elapsed time. Compilation/Neural Engine preparation may continue after the file download completes; this phase is not a promise of a fixed remaining time.

## Development and releases

`project.yml` is the XcodeGen source of truth. GitHub's macOS runner generates the Xcode project, dynamically selects an available iPhone simulator, runs unit and UI tests, captures test evidence, then separately builds an unsigned ARM64 iPhoneOS app. The release job packages `Payload/LiveCue.app` as `LiveCue.ipa`, publishes it to the private GitHub release, re-downloads it, and verifies its checksum and structure.

The IPA is intended for LiveContainer. It is not signed for direct installation and is not an App Store/TestFlight build.

Public development repository: https://github.com/mahmud-karim/LiveCue-public. Public builds use standard GitHub-hosted macOS runners. Never commit pairing payloads, local logs, credentials, or personal conversation data. Pairing is generated locally; publishing this source does not expose a running relay or grant access to it. The two-tab version is experimental and still requires a successful iOS build and physical-device validation.

## Architecture

- `Sources/LiveCueCore`: testable transcript, rolling-memory, relay schemas, and benchmark logic.
- `Sources/LiveCue`: SwiftUI interface, SwiftData persistence, Keychain token storage, Voz batch/FluidAudio Parakeet streaming, and relay client.
- `Relay`: Node 24 TypeScript service that invokes `gpt-5.6-sol` with low reasoning, the default speed tier, structured output, an empty ephemeral working directory, read-only sandboxing, and shell disabled.
- `.github/workflows`: simulator evidence and gated unsigned IPA release.

## Current v1 boundaries

English only, no speaker diarization, no TTS, no invisible overlay, no lock-screen control, and no arbitrary third-party model source. Background microphone capture uses iOS audio background mode, but iOS can still interrupt recording for calls, route changes, or system policy.
# Assistant model comparison (v0.4)

On iPhone, open **Assistant models & timing** (or the model row during a conversation). Refresh the authenticated PC catalog, choose a model and supported reasoning level, then tap Assist. The selection also applies to session summaries. Models are sourced from the local Codex catalog; account access is confirmed only when a request succeeds. Service tier remains default.

Each saved answer records its model, reasoning, STT mode, transcript character count, and timings. **Retry same text** reuses the exact previous text, instruction, and rolling context with a fresh request ID and your newly selected assistant settings. It does not retranscribe audio.

Timing boundaries: iPhone monotonic tap-to-answer, pending STT after the tap, context preparation, full HTTP round trip; PC monotonic Codex CLI invocation and remaining relay overhead. CLI time includes startup, cloud work and output handling, not pure model inference. Round trip minus PC duration is a transfer/client-overhead estimate, not separate upload/download measurements. Live Parakeet processing occurs before the tap; its last chunk timing is shown separately. Old saved sessions remain readable.

Restart the PC desktop after updating its source so the running relay exposes the new authenticated model catalog and timing fields. No pairing reset is needed.
