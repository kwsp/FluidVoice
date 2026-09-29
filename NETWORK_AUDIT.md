# Network and data-egress audit

Historical baseline: remediation status and rebase procedure are tracked in [PRIVACY_CHECKLIST.md](PRIVACY_CHECKLIST.md). The findings below describe the original audited code; line numbers predate remediation.

Audited 2026-09-29 against `3b509ea1`, plus the resolved dependency sources from the local Debug build. Fork policy: keep user data on this Mac; STT model downloads are permitted. This is a static source audit, not a packet capture or a guarantee about opaque frameworks. No application behavior was changed during this audit, and no upload endpoints were exercised.

## Findings that conflict with local-only operation

### 1. PostHog telemetry runs by default, including after detailed analytics is disabled

- Destination: `POST https://eu.i.posthog.com/batch`, configurable through the app bundle.
- Transport: [AnalyticsService.swift](Sources/Fluid/Analytics/AnalyticsService.swift), lines 654–676. The flush loop checks every 30 seconds (line 581), with persisted batches and retries; bootstrap can flush immediately.
- Enabled in this checkout: [Info.plist](Info.plist), lines 35–38, supplies an ingestion key and host. [AnalyticsConfig.swift](Sources/Fluid/Analytics/AnalyticsConfig.swift) considers any nonempty key configured.
- Startup: [AppDelegate.swift](Sources/Fluid/AppDelegate.swift), line 103; application activation records activity at line 250. Usage, onboarding, model downloads, and insertion paths also record events.
- Detailed analytics defaults to **true**: [SettingsStore.swift](Sources/Fluid/Persistence/SettingsStore.swift), line 1508.
- Turning it off does **not** disable telemetry: `writeActivity` at AnalyticsService line 484 is independent of the detailed preference; detailed events can fall back to an activity event at line 499.
- All event payloads include a persistent random installation ID, timestamp, app version, platform, RAM, and chip, including the supposedly minimal daily activity event. See [AnalyticsDatabase.swift](Sources/Fluid/Analytics/AnalyticsDatabase.swift), lines 778–816. Detailed events additionally include mode counts, provider/model identifiers, onboarding progress/outcomes, model-download status/duration, and insertion timing/outcomes.
- Beta performance collection also bypasses the detailed preference: AnalyticsService line 352; it includes OS version and performance histograms. This checkout's version is `1.6.10-beta.7`. `purgeDetailedAnalytics` at AnalyticsDatabase line 668 deliberately retains both activity and performance-summary outbox entries.
- I did not find transcript text or audio in these telemetry payloads. They are still outbound usage/device data, and the receiver sees the network connection's source address.

Action: remove or disable the transport independently of user preferences, remove bundle configuration and recording hooks, and purge queued telemetry during migration. A default-off preference alone is insufficient.

### 2. Legacy Apple Speech explicitly permits online recognition

- [AppleSpeechProvider.swift](Sources/Fluid/Services/AppleSpeechProvider.swift), lines 82–92, creates an audio-buffer recognition request, sets `requiresOnDeviceRecognition = false`, appends the recorded PCM, and starts a recognition task. The source explicitly states that macOS may choose local or online recognition.
- This can send microphone/file-transcription audio through Apple's Speech framework; no app-owned URLSession upload is needed, and the destination is managed by the OS rather than hardcoded here.
- [ASRService.swift](Sources/Fluid/Services/ASRService.swift), lines 1098–1106 and 1228–1235, also falls back from the newer Apple Speech Analyzer selection to this legacy provider on macOS before 26.
- This contradicts the unconditional local-processing language in the microphone/speech usage descriptions in Info.plist.

Action: remove the legacy engine and its fallback, or require supported on-device recognition and fail closed when unavailable. Do not silently fall back to online speech.

### 3. Configured AI providers receive user content

Primary transport: [LLMClient.swift](Sources/Fluid/Services/LLMClient.swift), request construction at line 244, POST/body/auth at lines 267–276, nonstreaming send at line 502, Responses streaming at line 534, and chat streaming at line 645.

Destinations come from provider settings. [ModelRepository.swift](Sources/Fluid/Services/ModelRepository.swift), lines 76–95, supplies defaults for OpenAI, Anthropic, xAI, Groq, Cerebras, Google Gemini, OpenRouter, Ollama, and LM Studio. Custom provider URLs and built-in URL overrides are also supported. Actual inference URLs use `/chat/completions`, `/responses`, or an already supplied `/api/chat` or `/api/generate` path. The provider connection test additionally supports Anthropic `/messages`.

| Calling feature | Source | Content sent when a remote provider is selected |
| --- | --- | --- |
| Dictation AI enhancement | [ContentView.swift](Sources/Fluid/ContentView.swift), lines 2744–2872 | Transcribed text and the effective/custom prompt; streaming failure can retry the same payload without streaming. |
| Shared postprocessing service | [DictationPostProcessingService.swift](Sources/Fluid/Services/DictationPostProcessingService.swift), lines 268–303 | Transcript and selected cleanup prompt. Reachable from local HTTP `/v1/postprocess`. |
| Edit/rewrite | [RewriteModeService.swift](Sources/Fluid/Services/RewriteModeService.swift), lines 231–239, 357–396 | Selected text from the target app, instructions, and rewrite conversation messages. |
| Command mode | [CommandModeService.swift](Sources/Fluid/Services/CommandModeService.swift), lines 860–943, 992 | Conversation history, shell commands, working-directory arguments, tool schema, and terminal results. File contents printed by a command can become subsequent model input. |

These paths depend on selecting/configuring AI functionality; they are not proof of unconditional transcript uploads. The main LLM client refuses an empty base URL, but has no local-only destination policy.

Two additional HTTP implementations remain in source with **no call sites found** outside their own declarations:

- [AIProvider.swift](Sources/Fluid/Networking/AIProvider.swift): `OpenAICompatibleProvider.process`, POST at lines 111–123; system prompt and user text. Empty base URL falls back to OpenAI.
- [FunctionCallingProvider.swift](Sources/Fluid/Networking/FunctionCallingProvider.swift): `processWithTools`, POST at lines 243–255; `continueWithToolResults`, POST at lines 369–380; conversation, tools, and results. Empty base URL also falls back to OpenAI.

Action: remove cloud routes and unused HTTP implementations, or enforce a single fail-closed loopback-only policy across inference and provider setup. If retaining Ollama/LM Studio, the server itself must also be configured not to proxy inference to cloud services; a loopback address alone cannot establish that.

### 4. User-triggered transcript example upload

- Destination: `POST https://altic.dev/api/fluid/examples`.
- [TranscriptionFeedbackReporter.swift](Sources/Fluid/Services/TranscriptionFeedbackReporter.swift), lines 4–8 and 28–41: JSON contains `rawText`, `processedText`, `processingModel`, and `comments`.
- [TranscriptionHistoryView.swift](Sources/Fluid/UI/TranscriptionHistoryView.swift), lines 669–759: history's “Share anonymous datapoint” sheet is initialized with actual raw and processed text; “Send Example” invokes the upload. The user can edit the fields before sending.
- This is explicit submission, not a background upload, but “anonymous” does not anonymize identifying information inside a transcript. No audio attachment is part of this payload.

Action: remove the submission UI and transport for a local-only fork.

### 5. User-triggered feedback upload

- Destination: `POST https://altic.dev/api/fluid/feedback`.
- [FeedbackClient.swift](Sources/Fluid/Services/FeedbackClient.swift), lines 33–76 and 82–91: email address, feedback category/message, and optional app/build/macOS details. JSON field names are `email_id` and `feedback`.
- [FeedbackView.swift](Sources/Fluid/UI/FeedbackView.swift), line 314, sends after explicit submission. `includeDetails` defaults to false at line 10. No automatic transcript, recording, or log attachment is present in this payload.

Action: remove the transport/UI, or replace it with a local export.

### 6. Command execution is a separate egress path

[TerminalService.swift](Sources/Fluid/Services/TerminalService.swift), lines 66–104, launches arbitrary `/bin/zsh -c` commands, inherits the user's environment, and captures stdout/stderr. Command mode executes through it at [CommandModeService.swift](Sources/Fluid/Services/CommandModeService.swift), line 680. Such a command can invoke network tools or automate Mail/Messages independently of the app's HTTP clients. The command-mode prompt even gives an iMessage-send example.

The app target explicitly has `ENABLE_APP_SANDBOX = NO` in [project.pbxproj](Fluid.xcodeproj/project.pbxproj), lines 973 and 1028. Removing URLSession calls therefore does not constrain subprocess networking.

Action: disable Command mode in a strictly local dictation fork, or design enforceable process/network restrictions. A model prompt telling commands to be safe is not a network boundary.

## Other non-model network calls

| Purpose | Call sites and trigger | Data/destination |
| --- | --- | --- |
| Provider model catalog | [ModelRepository.swift](Sources/Fluid/Services/ModelRepository.swift), lines 241–281; provider setup/model-fetch UI in `AIEnhancementSettingsViewModel.swift` and `AddProviderSheet.swift` | `GET <configured base>/models`, sending an API key when present. No transcript payload. This is a cloud AI model list, not an STT model download. |
| Provider verification | [AIEnhancementSettingsViewModel.swift](Sources/Fluid/UI/AISettings/AIEnhancementSettingsViewModel.swift), lines 885–965 | POST to configured provider; model ID, API key, and fixed `test`/`Hi` input. |
| Update checks/release notes | [SimpleUpdater.swift](Sources/Fluid/Services/SimpleUpdater.swift), lines 535–540 | `GET https://api.github.com/repos/<owner>/<repo>/releases`. AppDelegate lines 494–518 use `altic-dev/Fluid-oss`; update checks default on in SettingsStore line 2748, with an hourly eligibility check and a startup delay. Manual update and changelog paths also call this service. |
| Update download/install | SimpleUpdater line 403 | Downloads the selected release asset URL; the updater can replace/relaunch the app after the update flow. No transcript upload found. Upstream updates could undo this fork's privacy changes; disable or retarget the updater. |
| External navigation | [ChangelogView.swift](Sources/Fluid/UI/ChangelogView.swift), [FeedbackView.swift](Sources/Fluid/UI/FeedbackView.swift), [AISettingsView+AIConfiguration.swift](Sources/Fluid/UI/AISettingsView+AIConfiguration.swift), [ContentView.swift](Sources/Fluid/ContentView.swift), [SettingsView.swift](Sources/Fluid/UI/SettingsView.swift), [MenuBarManager.swift](Sources/Fluid/Services/MenuBarManager.swift), [AnalyticsPrivacyView.swift](Sources/Fluid/UI/AnalyticsPrivacyView.swift) | User clicks open GitHub releases/sponsors, docs.altic.dev, provider key/setup pages, or a `mailto:` link. These delegate to another app/browser; no automatic transcript attachment found. |

The local-endpoint helper in ModelRepository lines 154–166 also accepts `10.*`, `192.168.*`, and `172.16–31.*`; analogous helpers exist in the old clients and ContentView. This is primarily an API-key heuristic, not an egress restriction, and a LAN machine is not this Mac. Any future policy must also validate redirects and avoid treating string-prefix host checks as validated IP addresses.

## Model downloads to preserve

| Path | Network behavior |
| --- | --- |
| [ModelDownloader.swift](Sources/Fluid/Networking/ModelDownloader.swift), URL setup at lines 43–97, network operations at 567–596 and 750 | Hugging Face tree listing GETs, file-size HEADs, and model-file downloads. Used for Core ML/Nemotron/external-model artifacts. |
| [WhisperProvider.swift](Sources/Fluid/Services/WhisperProvider.swift), lines 89 and 427–438 | Downloads Whisper GGUF from `huggingface.co/handy-computer/<repo>-gguf/resolve/main/<model>` through `ProgressiveFileDownloader`. |
| [FluidAudioProvider.swift](Sources/Fluid/Services/FluidAudioProvider.swift), line 333; [ParakeetRealtimeProvider.swift](Sources/Fluid/Services/ParakeetRealtimeProvider.swift), preparation; speaker/meeting model loaders | FluidAudio model loading can download missing speech and speaker-processing assets. Its resolved source uses `DownloadUtils.swift` and `Shared/AssetDownloader.swift` for GET/download operations. No recorded-audio request body found in those helpers. |
| [AppleSpeechAnalyzerProvider.swift](Sources/Fluid/Services/AppleSpeechAnalyzerProvider.swift), lines 74–88 | Apple `AssetInventory` downloads and installs speech assets. Separate from the legacy provider that permits online recognition. |

FluidAudio's `ModelRegistry.swift` defaults to Hugging Face but accepts `REGISTRY_URL`/`MODEL_REGISTRY_URL` overrides and proxy configuration. `DownloadUtils.swift`, lines 18–31, attaches an HF token from environment variables when available. Downloads expose requested model paths and normal connection metadata; optional credentials are also outbound data. Preserve downloads through a narrow, dedicated transport and handle expected CDN redirects explicitly, without permitting transcript POSTs through it.

## Local interfaces, exports, and dependencies

- **Local API:** [LocalAPIModels.swift](Sources/Fluid/Services/LocalAPI/LocalAPIModels.swift), lines 3–22, defaults to disabled, port 47733. [LocalAPIServer.swift](Sources/Fluid/Services/LocalAPI/LocalAPIServer.swift), lines 33–40, creates a TCP listener without an explicit loopback bind but rejects peers unless `isLoopback` accepts them (line 97). The router exposes history/dictionary/transcribe/postprocess without an authentication check. It is not a discovered remote upload, but explicit loopback binding and authentication would better protect local data. `/v1/postprocess` invokes the cloud-capable postprocessing service; localhost ingress does not imply local inference.
- **Sharing/exports:** [StatsShareCard.swift](Sources/Fluid/UI/StatsShareCard.swift), line 273, exposes an explicit macOS ShareLink for a statistics image. History can export an audio/transcript ZIP (TranscriptionHistoryView line 631), and meeting/file/settings views can write local exports. The selected share service or a cloud-synced save location may subsequently transfer them; these are not automatic app-owned uploads.
- **Delivery to other apps:** TypingService and PasteDeliveryCoordinator intentionally deliver text to a user-selected app; TypingService line 661 can also post the configured Return key. A destination chat/web app may transmit that text. This is separate from STT/AI inference privacy and must be considered when defining a “never leaves this Mac” guarantee.
- **Resolved dependency source scan:** FluidAudio's identified runtime networking is model-download related. Its tokenizer callers use `AutoTokenizer.from(modelFolder:)`. `swift-transformers`/`swift-huggingface` also contain network-capable SDK helpers, including remote inference/upload APIs, but no app/FluidAudio call to those remote inference/upload APIs was found. Their mere presence is not evidence of active uploads.
- **AppUpdater dependency:** `DerivedData/SourcePackages/checkouts/AppUpdater/AppUpdater.swift`, lines 80 and 118–121, contains GitHub release GET/download calls. No `AppUpdater` import/call was found in app source; active update code is SimpleUpdater. Remove unused dependencies to reduce the audit surface.
- **Zeppelin:** the app uses local namespaces in `Persistence/Zeppelin/FluidZeppelinRoot.swift`; a scan of its Swift bindings and core/FFI Rust source found no upload/network implementation. Its prebuilt binary still requires separate provenance/runtime validation.
- **Binary dependencies:** TranscribeCpp downloads a prebuilt XCFramework from GitHub at build time; Zeppelin does likewise. WebRTC's audio-processing XCFramework is checked in. Source scanning does not prove the compiled binaries match source or exclude all binary-internal behavior.
- **Private Fluid Intelligence:** the public checkout exposes interfaces and unavailable shims, including nil download metadata. Its separate private implementation is not present and cannot be certified by this audit; meeting summary registration can supply a provider outside the public implementation.
- **Build/CI:** Package.swift and Xcode package resolution fetch dependencies and binary artifacts. `.github/workflows/pr-archive.yml`, line 312, uploads build artifacts to GitHub Actions; these are developer/CI operations, not recording uploads from the installed app. The scanned tools/scripts did not reveal another runtime upload service. Tests include URL fixtures; an address in a fixture is not itself a network call.

## Proposed implementation order

1. Remove PostHog transport/configuration and migrate away queued telemetry.
2. Remove feedback/example submission transports and UI.
3. Require on-device STT; eliminate legacy online recognition and fallback.
4. Remove cloud AI routes, unused HTTP clients, provider verification/catalog egress, and LAN-as-local assumptions. Retain only audited on-device or strictly loopback inference if desired.
5. Disable or constrain Command mode's subprocess capability.
6. Disable upstream update traffic and remove/retarget update UI and dependencies.
7. Keep model acquisition isolated; verify offline operation after download and test that forbidden destinations, redirects, imported provider settings, and queued telemetry cannot bypass the policy.

Static inspection establishes the above call sites and payload construction. A subsequent validation should exercise first launch, analytics opt-out, dictation, editing, command mode, feedback, history, local API, provider setup, and updates under outbound-network observation. OS-managed Speech behavior and precompiled dependencies remain outside what a Swift source scan can conclusively prove.
