# PC streaming verification — 2026-09-28

Hardware: RTX 3080 10 GB. Existing Docker images, one model loaded at a time.
Fixture: synthetic technical speech, resampled to PCM16 mono 16 kHz, repeated three times (41.031 seconds). Replayed at speaking speed through an isolated authenticated relay and the Funnel adapter. No microphone, Meta API key, or Codex request was used for these measurements.

| Model | Setup / switch | First text from stream start | Finalization after stop | Completed windows | Final words |
|---|---:|---:|---:|---:|---:|
| Nemotron 3.5 ASR 0.6B | 0.028 s (already warm) | 0.925 s | 0.084 s | 2 | 108 |
| Qwen3-ASR 1.7B | 55.703 s (cold switch) | 1.227 s | 0.355 s | 2 | 108 |

These are single controlled runs, not a general speed/accuracy ranking. First text includes silence and speaking time; real iPhone capture and internet latency are not represented. The word counts confirm nonempty final output across the 30-second rollover, not a formal WER evaluation.

- 16 Node relay/tunnel/security tests passed, including no-Meta fallback, fixed provider selection, failed startup, disconnected loading lease, and model header forwarding.
- 8 Python protocol tests passed in each model's runtime, including native-only origin checks, stream finalization, and exact sample preservation across window boundaries.
- The deployed Funnel adapter's SHA-256 matched the tested repository copy.
- Existing Docker images and weights were retained. Only the owned model container was switched.

The release workflow separately runs Swift core tests and simulator UI tests before producing the device IPA. Simulator speech uses fixtures; final phone microphone/network behavior must be checked on the physical iPhone.
