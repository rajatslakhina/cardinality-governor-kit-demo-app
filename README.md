# CardinalityGovernor — Demo App

A SwiftUI app that drives four synthetic telemetry label spaces through [**cardinality-governor-kit**](https://github.com/rajatslakhina/cardinality-governor-kit) and renders, window by window, what the governor is actually doing to them.

The library repo argues the design. This repo makes it move.

---

## Why this is a separate repository

The package is consumed the way a real consumer consumes it — as a **remote Swift Package with a version requirement**, resolved from GitHub against published tags:

```
XCRemoteSwiftPackageReference "cardinality-governor-kit"
    repositoryURL = "https://github.com/rajatslakhina/cardinality-governor-kit.git"
    requirement   = { kind = upToNextMajorVersion; minimumVersion = 1.0.0; }
```

Not a local path reference, and not `branch = main`. Both of those shortcuts are common in demo projects and both quietly destroy the thing a demo is supposed to prove. A **local path** means the package was never published, never resolved, and never version-resolvable by anyone else — it proves the code compiles on the author's disk. A **branch pin** means the build is not reproducible: the same commit of this app resolves to different library code tomorrow, and when it breaks there is no version to bisect.

A remote reference against published tags is the only arrangement where "it builds" is a claim about the *published package* rather than about the author's working copy. It also makes this repo's CI a real signal: a failure here would mean the release is broken for everyone.

**To be exact about what "pinned" means here, since the word gets used loosely:** `upToNextMajorVersion` is a *range*, not a single tag — it accepts any 1.x. That is the correct default for a consumer, because it takes patch fixes automatically while refusing breaking changes, and it is the same semantics as SwiftPM's `from:`. It is emphatically not the same guarantee as a branch pin, which accepts *anything*. Exact reproducibility comes from `Package.resolved`, which Xcode writes on first resolve; this repo does not commit one, so the CI job prints the resolved version in its log rather than leaving you to assume it.

---

## What the dashboard shows

Four scenarios, all deterministic — every run of a given scenario produces the same numbers, because the whole system is seeded and contains no wall-clock or `Hasher` dependency.

| Scenario | What it demonstrates |
|---|---|
| **Healthy** | Every dimension inside budget. Nothing is governed; the ledger is flat. The control case — a governor that visibly does nothing when nothing is wrong. |
| **Locale tail** | A Zipf-distributed `locale` far past its budget. Heavy hitters keep their identity, the long tail collapses into `__other__`, and the conservation total does not move. |
| **Declared free text** | A declared-but-open dimension taking effectively unbounded values — the realistic version of the cardinality bug, since the key *was* declared and *did* have a budget. |
| **Undeclared free text** | An undeclared key. Dropped rather than admitted, and counted per key, because a dimension with no budget is unbounded by definition. This is the scenario where the drop counter is the whole point. |

Each window, the app renders:

- the **conservation ledger** — admitted vs. the sum over every series, `__other__` and `__overflow__` included, with the invariant evaluated live rather than asserted
- **per-key budget allocation** from the largest-remainder apportionment, and how it shifts as HyperLogLog's demand estimate changes
- **survivor churn** — promotions, and refusals attributed to insufficient separation, which is where the anti-flapping rule becomes visible instead of theoretical
- **estimated distinct values** per open dimension with the standard error alongside, because a point estimate with no error bar invites exactly the false-precision reasoning the library is arguing against

The app's own code is deliberately thin: it builds `DimensionSchema` and `Configuration` values and hands them to `GovernorDashboardView`. Everything interesting lives in the package, which is the correct split — a demo that reimplements the library is not a demo of the library.

---

## Requirements

Xcode 16+, iOS 17+, Swift 6. Open `Demo.xcodeproj`; Xcode resolves the package on first open.

---

## Verification

**What was actually run, and what was not.**

- ✅ CI resolves the remote package from GitHub and builds the app for `generic/platform=iOS Simulator` with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, so "no warnings" is machine-checked rather than assumed. The `Package.resolved` contents are printed in the job log, so the resolved version is visible rather than assumed. Live results: **[Actions](https://github.com/rajatslakhina/cardinality-governor-kit-demo-app/actions)**.
- ❌ **This app was never launched on a Simulator.** It was built for a Simulator; it was not run on one. Those are different claims and this repo does not merge them.

  The automated pipeline that produced this repo requested Simulator access three times — twice for Xcode and Simulator together, once narrowed to Simulator alone — and was refused each time, verbatim:

  > *"Computer-use access to 'Simulator' can't be approved during a scheduled run. To grant it, send a message in this conversation (the approval card will appear), or add the app to the scheduled task's settings."*

  Rather than work around the refusal on a shared machine with other people's projects open, the run stopped and recorded it.

- ❌ **There are no screenshots in this repository, and no `Screenshots/` directory.** Since the app was never run, there is nothing to screenshot, and a directory of renders produced by any other means would be a description of an app rather than evidence of one. The dashboard section above describes what the code draws; it is not a claim about an image.

The library's own correctness is verified separately and more strongly — 107 tests across 10 suites, green on Linux and macOS 15, with the behavioural tests checked by mutation rather than by inspection. See [its verification section](https://github.com/rajatslakhina/cardinality-governor-kit#verification).

---

## License

MIT — see [LICENSE](LICENSE).
