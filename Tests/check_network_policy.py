#!/usr/bin/env python3
"""Flag network-surface changes for review after upstream rebases.

This inventory is a review aid, not a sandbox or a complete data-flow analysis.
Update the baseline only after reviewing every diff against PRIVACY_CHECKLIST.md.
"""
import collections
import difflib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASELINE = ROOT / "Tests/network_surface.json"
PATTERN = re.compile(
    r"URLSession|URLRequest|httpBody|httpMethod|https?://|NWConnection|NWListener|"
    r"NSURLConnection|CFReadStream|HTTPClient|WebSocket|WKWebView|AsyncImage|"
    r"requiresOnDeviceRecognition|recognitionTask\(|AssetInventory|"
    r"Process\(|executableURL\s*=|NSWorkspace.*open|ShareLink\(|"
    r"uploadTask|dataTask|downloadTask|\.data\(for:|\.data\(from:|\.bytes\(for:|"
    r"\.download\(from:|\.upload\(|\bsocket\(|\bconnect\(|\bcurl\b"
)


def inventory():
    result = {}
    for path in sorted((ROOT / "Sources").rglob("*")):
        if path.suffix not in {".swift", ".c", ".h", ".m", ".mm", ".cpp", ".js", ".html"}:
            continue
        lines = collections.Counter(
            line.strip() for line in path.read_text().splitlines()
            if PATTERN.search(line) and not line.lstrip().startswith("//")
        )
        if lines:
            result[str(path.relative_to(ROOT))] = dict(sorted(lines.items()))
    return result


def assert_invariants():
    def source(name):
        return (ROOT / name).read_text()
    assert "POSTHOG_" not in source("Info.plist"), "Telemetry bundle configuration returned"
    analytics = source("Sources/Fluid/Analytics/AnalyticsService.swift")
    assert not re.search(r"URLSession|URLRequest|AnalyticsCore|AnalyticsDatabase\(", analytics), "Telemetry collector/transport returned"
    updater = source("Sources/Fluid/Services/SimpleUpdater.swift")
    assert not re.search(r"URLSession|URLRequest|HTTPClient|downloadTask|dataTask", updater), "Updater transport returned"
    delegate = source("Sources/Fluid/AppDelegate.swift")
    assert "schedulePeriodicUpdateChecks" not in delegate, "Periodic update checks returned"
    assert "checkForUpdatesAutomatically" not in delegate, "Startup update checks returned"
    apple = source("Sources/Fluid/Services/AppleSpeechProvider.swift")
    assert "requiresOnDeviceRecognition = true" in apple
    assert "requiresOnDeviceRecognition = false" not in apple
    assert "supportsOnDeviceRecognition" in apple
    for path in ["UI/FeedbackView.swift", "Services/FeedbackClient.swift", "Services/TranscriptionFeedbackReporter.swift", "Networking/AIProvider.swift", "Networking/FunctionCallingProvider.swift"]:
        assert not (ROOT / "Sources/Fluid" / path).exists(), f"Removed upload client returned: {path}"
    for path in (ROOT / "Sources").rglob("*.swift"):
        assert "altic.dev/api/fluid/" not in path.read_text(), f"Submission endpoint returned: {path}"


assert_invariants()
actual = json.dumps(inventory(), indent=2, sort_keys=True) + "\n"
if sys.argv[1:] == ["--write-reviewed-baseline"]:
    BASELINE.write_text(actual)
    print("Wrote reviewed inventory; include its diff in the privacy review.")
else:
    expected = BASELINE.read_text()
    if expected != actual:
        print("Network surface changed. Review PRIVACY_CHECKLIST.md before updating the baseline.")
        print("".join(difflib.unified_diff(expected.splitlines(True), actual.splitlines(True), fromfile="reviewed", tofile="current")))
        sys.exit(1)
    print("PASS: privacy invariants and reviewed network inventory")
