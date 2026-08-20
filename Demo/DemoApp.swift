import SwiftUI
import CardinalityGovernor
import CardinalityGovernorUI

// MARK: - Scenario catalog

/// The label spaces this demo drives the governor with.
///
/// **Owned by the app, not the library.** `CardinalityGovernorUI` ships the dashboard and
/// `CardinalityGovernor` ships the policy; what a realistic label space actually looks like
/// — which flows exist, how many device tiers there are, how long the locale tail is — is
/// domain knowledge that belongs to whoever is instrumenting the app. That is why
/// `GovernorDashboardView` takes a scenario catalog as a parameter, and why this file
/// imports the *core* module as well as the UI one: it builds `DimensionSchema`,
/// `CardinalityGovernor.Configuration` and `LabelSet` values directly.
///
/// Every generator is driven by the deterministic `SplitMix64` the library exposes, so two
/// people running this demo see exactly the same numbers.
enum DemoScenarios {

    // MARK: Shared value spaces

    /// Closed by construction: these are the app's screens, which are enum cases in real
    /// code rather than runtime strings.
    static let flows: Set<String> = ["home", "search", "cart", "checkout"]

    /// Closed and small.
    static let deviceTiers: Set<String> = ["low", "mid", "high"]
    /// Sorted once. `Set` iteration order is not stable across launches, and every event
    /// generator here has to be reproducible from a seed.
    static let sortedFlows: [String] = flows.sorted()
    static let sortedDeviceTiers: [String] = deviceTiers.sorted()

    /// Open: variant identifiers are minted server-side, so the app cannot enumerate them.
    static let steadyVariants = ["control", "treatment-a", "treatment-b"]

    /// The head of a realistic locale distribution.
    static let commonLocales = ["en_US", "en_GB", "de_DE", "fr_FR", "ja_JP"]

    /// A 160-value locale space: five that carry most of the traffic and a long tail of
    /// markets with a handful of sessions each. This is the shape that breaks a naive
    /// dimensioning layer.
    static let longTailLocales: [String] = commonLocales + (0..<155).map { "loc_\($0)" }

    static let flowKey = StateReportingAdapter.flow
    static let variantKey = StateReportingAdapter.variant
    static let deviceTierKey = StateReportingAdapter.deviceTier
    static let localeKey = StateReportingAdapter.locale
    static let queryKey = DimensionKey("searchQuery")

    // MARK: Helpers

    /// Picks from a list with a bias towards the head — `min` of two draws is a cheap,
    /// dependency-free Zipf-ish skew, which is the distribution real telemetry has.
    static func skewedPick(_ values: [String], _ generator: inout SplitMix64) -> String {
        guard !values.isEmpty else { return "" }
        let first = generator.nextIndex(upperBound: values.count)
        let second = generator.nextIndex(upperBound: values.count)
        let index = min(first, second)
        return values.indices.contains(index) ? values[index] : values[0]
    }

    static func uniformPick(_ values: [String], _ generator: inout SplitMix64) -> String {
        guard !values.isEmpty else { return "" }
        let index = generator.nextIndex(upperBound: values.count)
        return values.indices.contains(index) ? values[index] : values[0]
    }

    static func baseSchema() -> DimensionSchema {
        StateReportingAdapter.schema(
            flows: flows,
            deviceTiers: deviceTiers,
            variantFloor: 4,
            localeFloor: 6
        )
    }

    static func baseLabels(locale: String, variant: String, _ generator: inout SplitMix64) -> LabelSet {
        var labels = LabelSet()
        // Hoisted: `Array(someSet).sorted()` inline here allocates and sorts twice per
        // generated event, 400 events per burst. In a demo about instrumentation overhead
        // that would be a poor look.
        labels.set(flowKey, uniformPick(sortedFlows, &generator))
        labels.set(deviceTierKey, uniformPick(sortedDeviceTiers, &generator))
        labels.set(variantKey, variant)
        labels.set(localeKey, locale)
        return labels
    }

    // MARK: Scenarios

    /// Everything inside budget: the baseline a reviewer should see first so the collapse
    /// behaviour in the other scenarios reads as a *change* rather than as the norm.
    static let healthy = Scenario(
        id: "healthy",
        title: "Healthy label space",
        explanation: "4 flows × 3 device tiers × 3 variants × 5 locales = 180 combinations, comfortably inside a 256-series budget. Nothing collapses; the ledger is the control case.",
        schema: baseSchema(),
        configuration: .init(distinctValueBudget: 32, jointSeriesBudget: 256),
        makeEvent: { generator in
            let locale = uniformPick(commonLocales, &generator)
            let variant = uniformPick(steadyVariants, &generator)
            return baseLabels(locale: locale, variant: variant, &generator)
        }
    )

    /// The classic explosion: one dimension grows a long tail. Watch `locale` fill its
    /// slots with the heavy hitters and push everything else into `__other__`.
    static let localeTail = Scenario(
        id: "locale-tail",
        title: "Locale grows a long tail",
        explanation: "The same app, now shipping in 160 markets. Locale keeps its budgeted slots for the heavy hitters and collapses the tail to __other__ — the observations are still counted, only the attribution is lost.",
        schema: baseSchema(),
        // Deliberately generous: 4 flows × 3 tiers × 3 variants × ~29 locale slots is over
        // a thousand reachable series, and this scenario is about the *per-key* collapse
        // to `__other__`. A tight joint budget here saturates during warm-up and renders
        // as `__overflow__` — visually identical to the two free-text scenarios below,
        // which are the ones that exist to show the joint cap firing.
        configuration: .init(distinctValueBudget: 32, jointSeriesBudget: 1_500),
        makeEvent: { generator in
            let locale = skewedPick(longTailLocales, &generator)
            let variant = uniformPick(steadyVariants, &generator)
            return baseLabels(locale: locale, variant: variant, &generator)
        }
    )

    /// A free-text dimension that someone *did* declare. Governed, so it costs a stated
    /// budget and collapses loudly instead of quietly becoming 10,000 series.
    static let declaredFreeText = Scenario(
        id: "declared-free-text",
        title: "Search query, declared",
        explanation: "Someone adds the search query as a dimension and declares it with a floor of 4. Every value is unique, so the collapse rate goes to ~100% and the joint budget starts overflowing — visibly, with the count still conserved.",
        schema: {
            var schema = baseSchema()
            schema.declare(queryKey, .open(floor: 4))
            return schema
        }(),
        configuration: .init(distinctValueBudget: 32, jointSeriesBudget: 128),
        makeEvent: { generator in
            let locale = skewedPick(longTailLocales, &generator)
            let variant = uniformPick(steadyVariants, &generator)
            var labels = baseLabels(locale: locale, variant: variant, &generator)
            labels.set(queryKey, "q-\(generator.next())")
            return labels
        }
    )

    /// The same free-text value, this time *not* declared. The key never becomes a label at
    /// all — which is the point of making declaration mandatory.
    static let undeclaredFreeText = Scenario(
        id: "undeclared-free-text",
        title: "Search query, undeclared",
        explanation: "Identical instrumentation, but the schema never declared searchQuery. The key is dropped before it can become a label and the drop is counted — no unbounded series, and no user-typed text reaching a telemetry backend.",
        schema: baseSchema(),
        configuration: .init(distinctValueBudget: 32, jointSeriesBudget: 128),
        makeEvent: { generator in
            let locale = skewedPick(longTailLocales, &generator)
            let variant = uniformPick(steadyVariants, &generator)
            var labels = baseLabels(locale: locale, variant: variant, &generator)
            labels.set(queryKey, "q-\(generator.next())")
            return labels
        }
    )

    static let all: [Scenario] = [healthy, localeTail, declaredFreeText, undeclaredFreeText]
}

// MARK: - App

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            GovernorDashboardView(scenarios: DemoScenarios.all)
        }
    }
}
