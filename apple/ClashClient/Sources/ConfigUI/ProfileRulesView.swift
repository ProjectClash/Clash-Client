import ClashClientUI
import SwiftUI

 
 
 
struct ProfileRulesAdapter: View {
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    private let profile: Profile
    private let sourceYAML: String?
    private let ownsNavigationContainer: Bool
    private let save: (ProfileRulesDraft) throws -> Void
    @Environment(\.locale) private var locale
    @State private var deviations: ConfigDeviationReport?

    init(
        profile: Profile,
        sourceYAML: String? = nil,
        ownsNavigationContainer: Bool = true,
        save: @escaping (ProfileRulesDraft) throws -> Void
    ) {
        self.profile = profile
        self.sourceYAML = sourceYAML
        self.ownsNavigationContainer = ownsNavigationContainer
        self.save = save
    }

     
     
     
     
     
     
     
     
    @State private var prepared: (token: UUID, snapshot: AppleClientSnapshot)?

    var body: some View {
        ClashFeatureNavigationContainer(
            ownsNavigationContainer: ownsNavigationContainer
        ) {
            Group {
                if let prepared {
                     
                     
                    EquatableEditor(
                        token: prepared.token,
                        snapshot: prepared.snapshot,
                        presentationClass: presentationClass,
                        showsDismissControl: ownsNavigationContainer,
                        actions: sharedActions,
                        deviations: deviations,
                        loadPolicyOptions: {
                            await Self.loadPolicyOptions(sourceYAML: sourceYAML, profile: profile)
                        },
                        loadRuleSets: {
                            await Self.loadPublishedRuleSets(of: profile)
                        },
                        draftKey: "Routing Rules|\(profile.id)"
                    )
                } else {
                    ClashOpeningProgress()
                }
            }
            .task(
                id: PreparationKey(profile: profile, sourceYAML: sourceYAML)
            ) {
                await prepare()
            }
            .task(id: RunningCoreDeviations.taskKey(for: profile)) {
                let profile = profile
                let locale = locale
                deviations = await Task.detached(priority: .userInitiated) {
                    RunningCoreDeviations.report(
                        profile: profile,
                        sidecarYAML: RunningCoreDeviations.sidecarYAML(for: profile),
                        locale: locale
                    )
                }.value
            }
            .clashFeaturePresentation(
                ownsNavigationContainer: ownsNavigationContainer
            )
        }
    }

    private struct EquatableEditor: View, Equatable {
        let token: UUID
        let snapshot: AppleClientSnapshot
        let presentationClass: ClashClientUI.ClashPresentationClass
        let showsDismissControl: Bool
        let actions: AppleClientActions
         
         
        let deviations: ConfigDeviationReport?
        let loadPolicyOptions: @MainActor () async
            -> ClashClientUI.ClashRulePolicyOptions
        let loadRuleSets: @MainActor () async
            -> ClashClientUI.ClashRulePolicyOptions
         
         
        let draftKey: String

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.token == rhs.token
                && lhs.presentationClass == rhs.presentationClass
                && lhs.showsDismissControl == rhs.showsDismissControl
                && lhs.deviations == rhs.deviations
        }

        var body: some View {
            ClashClientUI.ClashProfileRulesView(
                snapshot: snapshot,
                actions: actions,
                presentationClass: presentationClass,
                runtimeProfile: clashAppleRuntimeProfile,
                palette: ClashClientUI.ClashProductPalette.clashProduct,
                showsDismissControl: showsDismissControl,
                loadPolicyOptions: loadPolicyOptions,
                loadRuleSets: loadRuleSets,
                draftStore: SourceEditDrafts.shared,
                draftKey: draftKey,
                loadGeoValues: { resource in
                    await GeoCategoryCache.shared.categories(
                        for:
                            resource == .geoIP
                                ? .geoip
                                : .geosite
                    )
                }
            ) { symbol in
                ClashSymbolImage(symbol: symbol)
            } trailing: {
                 
                 
                 
                ConfigDeviationSection(
                    report: deviations,
                    fields: RunningCoreDeviations.fields(for: [.routingRules]),
                    identifierPrefix: "profile-rules.deviation"
                )
            }
        }
    }

    private struct PreparationKey: Equatable {
        let profile: Profile
        let sourceYAML: String?
    }

    @MainActor
    private func prepare() async {
        let profile = profile
        let began = DispatchTime.now().uptimeNanoseconds
        let snapshot = await Task.detached(priority: .userInitiated) {
            Self.buildSnapshot(profile: profile)
        }.value
        ClashClientUI.ClashPerf.span(
            "rules.landing.prepare",
            milliseconds: Self.elapsedMilliseconds(since: began),
            detail: "personal=\(snapshot.rules.editor?.rules.count ?? 0)"
        )
        prepared = (token: UUID(), snapshot: snapshot)
    }

    @MainActor
    private static func loadPolicyOptions(
        sourceYAML: String?,
        profile: Profile
    ) async -> ClashClientUI.ClashRulePolicyOptions {
        let began = DispatchTime.now().uptimeNanoseconds
        let options = await Task.detached(priority: .userInitiated) {
            buildPolicyOptions(sourceYAML: sourceYAML, profile: profile)
        }.value
        ClashClientUI.ClashPerf.span(
            "rules.policy.prepare",
            milliseconds: elapsedMilliseconds(since: began),
            detail:
                "groups=\(options.groups.count) proxies=\(options.proxies.count)"
        )
        return options
    }

    nonisolated private static func elapsedMilliseconds(
        since began: UInt64
    ) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
    }

    private var presentationClass: ClashClientUI.ClashPresentationClass {
#if os(macOS)
         
         
        .regularTouch
#else
        horizontalSizeClass == .regular
            ? .regularTouch
            : .compactTouch
#endif
    }

    private var productPalette: ClashClientUI.ClashProductPalette {
        ClashClientUI.ClashProductPalette.clashProduct
    }

     
     
    nonisolated static func buildSnapshot(
        profile: Profile
    ) -> AppleClientSnapshot {
        let draft = ProfileRulesDraft(profile: profile)
        return AppleClientSnapshot(
            revision: 0,
            connection: AppleClientConnectionSnapshot(
                phase: .unavailable
            ),
            rules: ClashRulesSnapshot(
                editor: ClashProfileRulesSnapshot(
                    profileName: profile.label,
                    rules: draft.rules.map {
                        ClashPersonalRuleSnapshot(
                            raw: $0,
                            isEnabled:
                                !draft.disabledRules.contains($0),
                            comment: draft.comments[$0]
                        )
                    },
                    prependRules: draft.prependRules,
                    policyOptions: .empty,
                    initialRuleBuilderRaw:
                        initialRuleBuilderRaw,
                    initialRuleBuilderRoute:
                        initialRuleBuilderRoute
                )
            ),
            capabilities: AppleClientCapabilities([
                .rules: .available,
            ])
        )
    }

     
     
     
     
     
     
     
    nonisolated static func publishedRuleSets(of profile: Profile) -> ClashClientUI.ClashRulePolicyOptions {
        guard let sets = ProfilesViewModel.publishedRuleSetsAndSubRules(for: profile)?.ruleSets else {
            return ClashClientUI.ClashRulePolicyOptions(ruleSetsAreKnown: false)
        }
        return ClashClientUI.ClashRulePolicyOptions(ruleSets: sets.sorted(), ruleSetsAreKnown: true)
    }

     
    static func loadPublishedRuleSets(of profile: Profile) async -> ClashClientUI.ClashRulePolicyOptions {
        await Task.detached(priority: .userInitiated) { publishedRuleSets(of: profile) }.value
    }

     
     
     
     
     
    nonisolated static func buildPolicyOptions(
        sourceYAML: String?,
        profile: Profile? = nil
    ) -> ClashClientUI.ClashRulePolicyOptions {
         
        RulePolicyOptions.make(sourceYAML: sourceYAML)
            .adopting(published: profile.map(publishedRuleSets(of:)))
            .shared
    }

    private var sharedActions: AppleClientActions {
        AppleClientActions(capability: .rules) { action in
            guard case .rules(
                .saveProfileRules(let sharedDraft)
            ) = action else {
                return
            }
            var draft = ProfileRulesDraft(profile: profile)
            draft.rules = sharedDraft.rules.map(\.raw)
            draft.prependRules = sharedDraft.prependRules
            draft.disabledRules = Set(
                sharedDraft.rules
                    .filter { !$0.isEnabled }
                    .map(\.raw)
            )
             
             
            draft.comments = Dictionary(
                sharedDraft.rules.compactMap {
                    rule in
                    guard let comment = rule.comment,
                        !comment.isEmpty
                    else {
                        return nil
                    }
                    return (rule.raw, comment)
                },
                uniquingKeysWith: { first, _ in first }
            )
            try save(draft)
        }
    }

    nonisolated private static var initialRuleBuilderRaw: String? {

        nil

    }

    nonisolated private static var initialRuleBuilderRoute: ClashRuleBuilderRoute? {

        nil

    }
}
