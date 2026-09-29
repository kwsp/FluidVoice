# Fork policy

- This fork aims to keep user data completely local. STT model downloads are allowed. Do not add outbound telemetry, transcript/audio uploads, or remote inference without an explicit change to this policy.
- See `NETWORK_AUDIT.md` for the initial static audit of existing network paths. The audit documents issues; it does not mean they have been removed.
- Track remediation and upstream-rebase review in `PRIVACY_CHECKLIST.md`. Run `python3 Tests/check_network_policy.py` after upstream changes; review new network paths before updating its baseline. AI requests must use `LocalOnlyNetworking`, including provider checks and model catalogs. Model-download and updater transports are separately inventoried.

# Local build notes

- Build the macOS app with `./build.sh unsigned` when no Apple Development signing certificate is available. This invokes `xcodebuild` on `Fluid.xcodeproj`, scheme `Fluid`, configuration `Debug`.
- Output: `DerivedData/Build/Products/Debug/FluidVoice Debug.app`. Launch with `open "DerivedData/Build/Products/Debug/FluidVoice Debug.app"`.
- For signed development builds, run `./build.sh` after creating an Apple Development certificate in Xcode Settings > Accounts > Manage Certificates. A Personal Team is sufficient. The script also repairs the CTranscribe framework layout and verifies the signature.
- Minimum deployment target is macOS 15. Dependencies resolve through Swift Package Manager. WebRTC's static XCFramework is checked in under `Vendor/WebRTCAudioProcessing`; it does not need a separate build.
- `./build.sh fi` requires a private script absent from this public checkout; use the public build for local development.
- Xcode needs access to user caches and the network for initial dependency resolution. If the agent sandbox blocks these, request escalation for the build.
- Unsigned rebuilds may require granting macOS Accessibility, microphone, and Screen Recording permissions again.
- Integration test command: `xcodebuild test -project Fluid.xcodeproj -scheme Fluid -destination 'platform=macOS' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`. CI skips `FluidDictationIntegrationTests/DictationE2ETests/testDictationEndToEnd_whisperTiny_transcribesFixture` because it is nondeterministic on hosted runners.
- `tools/verify_debug_app_install.sh` contains the upstream developer's fixed signing identity and assumes an installed app under `/Applications`; it is not a generic local build check.
- Keep personal signing team IDs and API keys out of commits.
