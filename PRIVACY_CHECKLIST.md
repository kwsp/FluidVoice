# Local-data fork checklist

Policy: user data stays on this Mac. Downloading STT models is allowed. Initial findings are preserved in [NETWORK_AUDIT.md](NETWORK_AUDIT.md); that document describes the pre-remediation code, not the current status.

## Implementation: items 1–4

- [x] Remove PostHog request transport, background flush/retry loop, bundle key/host, and installation-ID generation.
- [x] Replace AnalyticsService with an inert compatibility facade. Upstream recording hooks cannot collect or upload anything. Retain local first-launch bookkeeping used by onboarding; legacy database code is only exercised by regression fixtures, not the runtime service.
- [x] Delete the legacy Analytics directory (including database sidecars) and stored installation ID at startup. Retry cleanup on subsequent launches if deletion fails. Force the detailed preference off even when imported settings contain true.
- [x] Remove feedback and transcript-example clients, forms, send buttons, and history reporting actions. Remove the leftover disabled feedback page and navigation destination as well.
- [x] Require `supportsOnDeviceRecognition` and `requiresOnDeviceRecognition = true` for legacy Apple Speech. Unsupported languages fail instead of using online recognition.
- [x] Replace pre-macOS-26 Analyzer fallback with an unavailable provider that returns an actionable error.
- [x] Restrict AI inference, model-list discovery, and connection tests to canonical loopback addresses. Normalize localhost to 127.0.0.1, reject credentials embedded in URLs, LAN/public hosts, alternate IP spellings, and invalid ports.
- [x] Use ephemeral AI sessions with proxies/cookies/credential storage disabled and refuse every redirect. Preserve the same restriction for saved/imported provider settings at the request boundary.
- [x] Remove cloud built-in choices/default inference URLs and unused OpenAICompatibleProvider/FunctionCallingProvider HTTP implementations. Keep custom loopback servers, Ollama, and LM Studio.
- [x] Leave the separate STT download transports intact.
- [x] Add a reviewed network-call inventory and CI checks for rebase review.

## Validation for this change

- [x] Unsigned Debug build passed; final targeted xcodebuild test also rebuilt the app successfully.
- [x] Loopback HTTP test: normal POST succeeds, 307 redirects to both local and external destinations are refused, and synthetic content/auth reaches only the intended fixture.
- [x] Integration tests (7 privacy tests): remote/LAN endpoints blocked before inference or catalog requests; local requests retain payloads; remote provider setup rejected; imported telemetry setting cannot re-enable collection.
- [x] Existing LLM body/stream parsing regressions using loopback fixtures (27 tests; 34 integration tests total).
- [x] Provider-setup harness: 89 assertions; command-provider catalog harness: 54 checks.
- [x] Network inventory and `git diff --check` pass.
- [ ] Live UI, microphone/Apple Speech, and packet-capture validation. Requires interactive app testing; static tests do not establish opaque framework behavior.

## Deferred, still possible egress

- [ ] Item 5: restrict/remove Command mode subprocess networking. It still runs arbitrary shell commands; loopback-only inference does not constrain those commands.
- [x] Item 6: remove startup/hourly update checks, update controls, and remote changelog loading. Updater discovery/install entry points fail closed; their network transports are removed. Imported settings cannot re-enable checks. The unused upstream AppUpdater dependency still needs provenance/dependency cleanup.
- [ ] Item 7: isolate model-download transport with explicit artifact/CDN policy and validate offline operation.
- [ ] Review local API authentication and explicit loopback bind; it remains disabled by default and filters accepted peers.
- [ ] Audit precompiled dependency behavior/provenance and any future private AI implementation. A local AI server can itself proxy to cloud services; configure it for on-device inference.
- [ ] Consider explicit share/export, paste/Return into other applications, and cloud-synced output folders when defining the user-facing privacy guarantee.

## Repeat for every upstream rebase

1. Record upstream base/revision and review `git diff <previous-upstream>..<new-upstream> -- Sources Info.plist Package.swift Package.resolved Fluid.xcodeproj Vendor .github`.
2. Run `python3 Tests/check_network_policy.py`. Review every inventory change, including URLSession, alternate network frameworks, subprocesses, external navigation, and model SDK calls. Never blindly regenerate the baseline to make CI pass.
3. Check new dependencies and binaries separately; the source inventory is heuristic and cannot find every indirect SDK call or arbitrary shell upload. Check provider routing, request-body construction, first-launch code, telemetry preferences/migrations, and Apple Speech fallback behavior.
4. Delete new upload/telemetry implementations or route retained AI features through LocalOnlyNetworking. Check imported settings and redirects, not only UI defaults. Model downloads must never carry transcript/audio/prompt data.
5. After review, update this checklist/audit findings, then run `python3 Tests/check_network_policy.py --write-reviewed-baseline` and inspect the JSON diff.
6. Run `python3 Tests/run_local_network_transport_tests.py`, targeted NetworkPrivacyTests/LLM tests, and `./build.sh unsigned`. For changes to recognition, downloads, or SDKs, also exercise offline use and observe outbound traffic.
7. Commit the reviewed inventory, tests, checklist, and code together. Do not claim complete local-only operation while deferred egress paths remain.

## Work log

- 2026-09-29: removed the remaining disabled FeedbackView and feedback navigation case. Confirmed no Send Example implementation remains; feedback/example upload clients were deleted in the initial remediation. Updated page-presentation coverage and the rebase guard. Final unsigned build passed; page-presentation harness passed 12,661 checks; privacy inventory and whitespace checks passed.

- 2026-09-29: removed upstream updater transport and automatic scheduling; replaced update settings/changelog with fork-build guidance and removed update/rollback menu controls. Retained disabled updater entry points for rebase compatibility and local rollback helpers; no UI offers rollback to an upstream build.
- Removed the model-card liquid animation timeline and both talking-visualizer animation timers. Visualizers now react to audio-level/threshold changes; static settings cards no longer redraw continuously. Other recording/processing animations and the active-app tracker are unchanged.
- [x] Validation: unsigned Debug build passed; 36 integration tests passed (9 privacy/updater, 27 LLM request/streaming). Reviewed network inventory and whitespace checks passed. Idle CPU reduction still requires measurement in the running app.

- 2026-09-29: added certificate-free ad-hoc Release packaging and a downloadable GitHub Actions artifact workflow. Signing/package verification is local; CI uploads only the built app, checksum, build metadata, and installation notes. STT models and user recordings/settings are not bundled.
- Validation: `./build.sh adhoc` passed on arm64 with Xcode 27. The app and ZIP-extracted copy passed `codesign --verify --deep --strict`; microphone entitlement, architecture, and embedded runtime dependencies were checked. Shell/YAML syntax and the network inventory passed. The GitHub-hosted workflow has not been run yet.

- 2026-09-29: static audit of upstream `3b509ea1`; identified telemetry, Apple online recognition, remote AI, feedback/example uploads, updater traffic, and shell-command egress.
- 2026-09-29: implemented requested items 1–4. Used inert telemetry compatibility methods to keep future upstream merges small without retaining a collector or transport. No app traffic was sent to telemetry, feedback, or remote inference services during implementation/testing.

Validation commands used:

```sh
./build.sh unsigned
python3 Tests/run_local_network_transport_tests.py
python3 Tests/check_network_policy.py
sh Tests/run_command_model_catalog_tests.sh
sh scripts/test_provider_setup_boundary.sh
xcodebuild test -project Fluid.xcodeproj -scheme Fluid -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:FluidDictationIntegrationTests/NetworkPrivacyTests \
  -only-testing:FluidDictationIntegrationTests/LLMClientRequestBodyTests \
  -only-testing:FluidDictationIntegrationTests/LLMClientStreamingTests \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Build retains existing upstream warnings (including CTranscribe framework symlink and Swift concurrency/deprecation warnings). SwiftLint was not installed locally; it was not run. No real audio or user transcript was used in network fixtures.

- 2026-09-29: first hosted CI run passed the privacy guard but found five strict SwiftLint violations in fork changes. Corrected argument/statement formatting, blank lines, and explicit discard of forbidden imported preference values. Hosted build/test and artifact verification pending.
