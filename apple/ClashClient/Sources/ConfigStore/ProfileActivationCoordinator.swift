import CryptoKit
import Foundation
import ClashClientKit
import ClashClientUI

enum PipelineError: LocalizedError {
    case planRejected([RemoteResourcePlan.Failure])
    case externalResources([IOSExternalResourceFinding])
    case sourceUnavailable(String)
    case notModifiedWithoutActive
    case preflightFailed(String)
    case providerNotFound(String)
     
     
     
     
     
     
    case activationReadback
     
     
     
    case sourceSuperseded

    var errorDescription: String? {
        switch self {
        case .planRejected(let failures):
            return failures.map { "\($0.field): \($0.reason)" }.joined(separator: "; ")
        case .externalResources(let findings):
            return findings.compactMap(\.errorDescription).joined(separator: " ")
        case .sourceUnavailable(let reason):
            return reason
        case .notModifiedWithoutActive:
            return "The profile URL was not modified, but this profile has no active revision."
        case .preflightFailed(let reason):
            return "Configuration validation failed: \(reason)"
        case .providerNotFound(let name):
            return "Provider '\(name)' is no longer present in this profile."
        case .activationReadback:
            return "The activated revision could not be read back after publication."
        case .sourceSuperseded:
            return "The source changed while it was downloaded; the newer one is kept."
        }
    }

     
     
     
     
     
     
     
    var authoredText: AuthoredText {
        switch self {
        case .planRejected, .externalResources, .sourceUnavailable:
            return .app(errorDescription ?? "")
        case .notModifiedWithoutActive:
            return .app("The profile URL was not modified, but this profile has no active revision.")
        case .preflightFailed(let reason):
            return .app("Configuration validation failed: %@", arguments: [reason])
        case .providerNotFound(let name):
            return .app("Provider '%@' is no longer present in this profile.", arguments: [name])
        case .activationReadback:
            return .app("The activated revision could not be read back after publication.")
        case .sourceSuperseded:
            return .app("The source changed while it was downloaded; the newer one is kept.")
        }
    }
}

struct ProviderRuntimeUpdate: Equatable {
    let name: String
    let kind: String
    let payload: Data
     
     
     
    var publishedIn: ActiveConfigurationPointer? = nil
}

struct ProviderRefreshResult: Equatable {
    let pointer: ActiveConfigurationPointer
     
     
    let runtimeUpdate: ProviderRuntimeUpdate?
}

private struct ProfilePublicationResult {
    let pointer: ActiveConfigurationPointer
     
    var previous: ActiveConfigurationPointer? = nil
    let runtimeUpdates: [String: ProviderRuntimeUpdate]
     
    var firstLoadPending: [String] = []
    var publishedRouteNames: Set<String> = []
}

 
 
 
 
enum ProfileRuntimeConfigBuilder {
    static func buildProduction(
        raw: String,
        profile: Profile,
        runtimeOverride: OverrideSpec = FlClashRuntimeConfig.load(),
        applyProviderDefinitions: Bool = true,
        applyProxyChain: Bool = true,
        applyLegacyRelayMigration: Bool = true,
        scripts caller: ScriptEngine.Caller = .surfaced
    ) throws -> String {


        return try buildProductionStages(
            raw: raw,
            profile: profile,
            runtimeOverride: runtimeOverride,
            applyProviderDefinitions: applyProviderDefinitions,
            applyProxyChain: applyProxyChain,
            applyLegacyRelayMigration: applyLegacyRelayMigration,
            scripts: caller
        ).finished()
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    static func buildProductionStages(
        raw: String,
        profile: Profile,
        runtimeOverride: OverrideSpec = FlClashRuntimeConfig.load(),
        globalOverride: OverrideSpec = GlobalConfig.load(),
        applyProviderDefinitions: Bool = true,
        applyProxyChain: Bool = true,
        applyLegacyRelayMigration: Bool = true,
        scripts caller: ScriptEngine.Caller = .surfaced
    ) throws -> RuntimeBuildStages {
        try ProfilePostMergeScriptOwnershipPolicy.validate(
            postMergeScriptID: profile.postMergeScriptID,
            legacyGlobalScriptEnabled: ScriptSettings.enabled()
        )
        return try buildStages(
            raw: raw,
            profile: profile,
            globalOverride: globalOverride,
            runtimeOverride: runtimeOverride,
            profileScript: { try ScriptLibrary.apply(id: $0, to: $1, profileName: $2, caller: caller) },
            configScript: { try ScriptSettings.apply(toConfigYAML: $0, profileName: $1, caller: caller) },
            postMergeScript: { try ScriptLibrary.apply(id: $0, to: $1, profileName: $2, caller: caller) },
            applyProviderDefinitions: applyProviderDefinitions,
            applyProxyChain: applyProxyChain,
            applyLegacyRelayMigration: applyLegacyRelayMigration
        )
    }

     
     
     
     
     
    static func udpFallbackGuardInput(
        raw: String,
        profile: Profile,
        runtimeOverride: OverrideSpec = FlClashRuntimeConfig.load()
    ) throws -> ConfigTransforms.UDPFallbackGuardInput {
        try ConfigTransforms.udpFallbackGuardInput(
            buildProductionStages(
                 
                raw: raw, profile: profile, runtimeOverride: runtimeOverride, scripts: .silent
            ).beforeClientRuntimePolicy
        )
    }

     
     
     
     
     
     
     
     
    struct RuntimeBuildStages {
         
         
        let afterClientTransforms: String
         
         
        let beforeClientRuntimePolicy: String
         
        let udpFallback: UDPFallbackPolicy
         
         
         
        var excludeAPNsRoute = false
         
         
         
         
        var providerMerge = ProviderDefinitionMergeReport()
         
         
         
         
         
         
        var profileLogLevel: String?
         
         
         
        var logLevelSetByApp = false
        var modeSetByApp = false
         
         
         
        var listenerWrittenBack: [String] = []
         
         
         
         
        var beforeClientRuntimePolicyJSON: String?
         
         
         
         
         
        var nodesJSON: String?

         
        func finished() throws -> String {
            try ConfigTransforms.applyClientRuntimePolicy(
                beforeClientRuntimePolicy,
                udpFallback: udpFallback,
                excludeAPNsRoute: excludeAPNsRoute,
                json: beforeClientRuntimePolicyJSON
            )
        }
    }

     
     
     
     
     
     
     
    static func finishedReading(_ stages: RuntimeBuildStages) throws -> (yaml: String, root: [String: Any]?) {
        let reading = try ConfigTransforms.applyClientRuntimePolicyReading(
            stages.beforeClientRuntimePolicy,
            udpFallback: stages.udpFallback,
            excludeAPNsRoute: stages.excludeAPNsRoute,
            json: stages.beforeClientRuntimePolicyJSON
        )
         
         
        func readWhole() -> [String: Any]? {
            reading.omitsRules
                ? (try? ConfigTransforms.foundationRoot(ofYAML: reading.yaml, omitting: ["rules"])) ?? nil
                : (try? ConfigTransforms.foundationRoot(ofYAML: reading.yaml)) ?? nil
        }
        guard var root = (try? ConfigTransforms.foundationRoot(ofJSON: reading.json)) ?? nil else {
            return (reading.yaml, readWhole())
        }
        if reading.omitsNodes {
            guard let nodesJSON = stages.nodesJSON,
                  let nodes = (try? ConfigTransforms.foundationRoot(ofJSON: nodesJSON)) ?? nil else {
                return (reading.yaml, readWhole())
            }
            root["proxies"] = nodes["proxies"]
        }
        return (reading.yaml, root)
    }

    static func build(
        raw: String,
        profile: Profile,
        globalOverride: OverrideSpec,
        runtimeOverride: OverrideSpec = OverrideSpec(),
        profileScript: (String?, String, String) throws -> String,
        configScript: (String, String) throws -> String,
        postMergeScript: (String?, String, String) throws -> String = { _, yaml, _ in yaml },
        applyProviderDefinitions: Bool = true,
        applyProxyChain: Bool = true,
        applyLegacyRelayMigration: Bool = true,
        logLevelDirective: ClashLogSettings.LevelDirective? = nil
    ) throws -> String {
        try buildStages(
            raw: raw,
            profile: profile,
            globalOverride: globalOverride,
            runtimeOverride: runtimeOverride,
            profileScript: profileScript,
            configScript: configScript,
            postMergeScript: postMergeScript,
            applyProviderDefinitions: applyProviderDefinitions,
            applyProxyChain: applyProxyChain,
            applyLegacyRelayMigration: applyLegacyRelayMigration,
            logLevelDirective: logLevelDirective
        ).finished()
    }

    static func buildStages(
        raw: String,
        profile: Profile,
        globalOverride: OverrideSpec,
        runtimeOverride: OverrideSpec = OverrideSpec(),
         
         
         
         
        profileScript: (String?, String, String) throws -> String,
        configScript: (String, String) throws -> String,
        postMergeScript: (String?, String, String) throws -> String = { _, yaml, _ in yaml },
        applyProviderDefinitions: Bool = true,
        applyProxyChain: Bool = true,
        applyLegacyRelayMigration: Bool = true,
         
         
         
         
         
         
        logLevelDirective: ClashLogSettings.LevelDirective? = nil
    ) throws -> RuntimeBuildStages {
         
         
         
         
        let late: Set<String>
        do {
            let first = try autoreleasepool { try buildPass(
                raw: raw, profile: profile, globalOverride: globalOverride, runtimeOverride: runtimeOverride,
                profileScript: profileScript, configScript: configScript, postMergeScript: postMergeScript,
                applyProviderDefinitions: applyProviderDefinitions, applyProxyChain: applyProxyChain,
                applyLegacyRelayMigration: applyLegacyRelayMigration, logLevelDirective: logLevelDirective, leavingOut: []) }
            guard !first.late.isEmpty else { return first.stages }
            late = first.late
        }
        return try buildPass(
            raw: raw, profile: profile, globalOverride: globalOverride, runtimeOverride: runtimeOverride,
            profileScript: profileScript, configScript: configScript, postMergeScript: postMergeScript,
            applyProviderDefinitions: applyProviderDefinitions, applyProxyChain: applyProxyChain,
            applyLegacyRelayMigration: applyLegacyRelayMigration, logLevelDirective: logLevelDirective, leavingOut: late
        ).stages
    }

     
     
     
    private static func buildPass(
        raw: String,
        profile: Profile,
        globalOverride: OverrideSpec,
        runtimeOverride: OverrideSpec,
        profileScript: (String?, String, String) throws -> String,
        configScript: (String, String) throws -> String,
        postMergeScript: (String?, String, String) throws -> String,
        applyProviderDefinitions: Bool,
        applyProxyChain: Bool,
        applyLegacyRelayMigration: Bool,
        logLevelDirective: ClashLogSettings.LevelDirective?,
        leavingOut leftOut: Set<String>
    ) throws -> (stages: RuntimeBuildStages, late: Set<String>) {
        let profileWorking: String
        let pageListener = Self.lanSharingListener(of: profile)
         
        var mergedRules: [String] = []
        var mergedPolicies: Set<String> = []
         
        var personalRules: [String] = []
        var personalRulesPrepend = false
        switch profile.overwriteMode ?? .standard {
        case .standard, .script:
            var spec = profile.override
             
             
             
            spec.patchJSON = OverridePatch(
                patchJSON: spec.patchJSON
            ).profileOwnedPatch.patchJSON
             
             
            let muted = Set(spec.disabledAppendRules ?? [])
            personalRules = spec.appendRules.filter { !muted.contains($0) }
            personalRulesPrepend = spec.prependRules
            spec.appendRules = []
            let patched = try ConfigTransforms.mergeOverride(
                raw: raw,
                overrideJSON: overrideJSON(from: spec)
            )
             
             
             
            profileWorking = profile.overwriteMode == .script
                ? try profileScript(profile.selectedScriptID, patched, profile.label)
                : patched
        case .custom:
            let overwritten = try (profile.customOverwrite ?? CustomOverwriteSpec())
                .applyForFinalRuntimeMigration(to: raw)
             
             
             
             
             
            profileWorking = pageListener.patchJSON.isEmpty ? overwritten : try ConfigTransforms.mergeOverride(
                raw: overwritten,
                overrideJSON: overrideJSON(from: OverrideSpec(patchJSON: pageListener.patchJSON))
            )
        }

        var effectiveGlobal = profile.migratedGlobalOverride ?? globalOverride
         
         
         
         
         
         
         
         
        if (profile.overwriteMode ?? .standard) != .standard {
            effectiveGlobal.appendRules = []
        }
        let disabledRules = Set(profile.override.disabledGlobalRules ?? [])
        effectiveGlobal.appendRules.removeAll { disabledRules.contains($0) }
         
         
        let merged = try ConfigTransforms.mergeOverride(
            raw: profileWorking,
            overrideJSON: overrideJSON(from: OverrideSpec(patchJSON: effectiveGlobal.patchJSON))
        )
        let profileScripted = try postMergeScript(
            profile.postMergeScriptID, merged, profile.label
        )
        let scriptsDone = try configScript(profileScripted, profile.label)
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        personalRules = try resolvedFallbackTargets(personalRules, mergedInto: scriptsDone).filter { !leftOut.contains($0) }
        let judged = droppingUnknownTargets(personalRules, mergedInto: scriptsDone)
        mergedRules += judged.kept
        mergedPolicies.formUnion(judged.policies ?? [])
        let withPersonalRules = judged.kept.isEmpty ? scriptsDone : try ConfigTransforms.mergeOverride(
            raw: scriptsDone,
            overrideJSON: overrideJSON(from: OverrideSpec(appendRules: judged.kept, prependRules: personalRulesPrepend))
        )
        let globalRules = try resolvedFallbackTargets(
            effectiveGlobal.appendRules, mergedInto: withPersonalRules
        ).filter { !leftOut.contains($0) }
        let globalJudged = droppingUnknownTargets(globalRules, mergedInto: withPersonalRules)
        mergedRules += globalJudged.kept
        mergedPolicies.formUnion(globalJudged.policies ?? [])
        let scripted = globalJudged.kept.isEmpty ? withPersonalRules : try ConfigTransforms.mergeOverride(
            raw: withPersonalRules,
            overrideJSON: overrideJSON(from: OverrideSpec(appendRules: globalJudged.kept, prependRules: effectiveGlobal.prependRules))
        )
        var providerMerge = ProviderDefinitionMergeReport()
        var profileLogLevel: String?
        var scriptsListener: [String: Any]?
        var trimmedJSON: String?
        var trimmedNodesJSON: String?
        let trimmed = try applyClientTransforms(
            to: scripted,
            profile: profile,
            applyProviderDefinitions: applyProviderDefinitions,
            applyProxyChain: applyProxyChain,
            applyLegacyRelayMigration: applyLegacyRelayMigration,
            providerMerge: &providerMerge,
            inspectLogLevel: { _, level in
                profileLogLevel = level
            },
            inspectListener: { scriptsListener = $0 },
            unchangedJSON: { trimmedJSON = $0 },
            nodesJSON: { trimmedNodesJSON = $0 }
        )

        var effectiveRuntime = runtimeOverride
        var runtimePatch = OverridePatch(
            patchJSON: effectiveRuntime.patchJSON
        ).globalRuntimePatch
         
         
         
         
         
         
         
        if runtimeOverride.dnsOverridesProfiles != true,
           runtimePatch.hasDNSOverride,
           Self.hasEnabledOwnDNS(yaml: trimmed) {
            runtimePatch.clearDNS()
        }
         
         
         
         
         
        var ownLayerLogLevel: String?
         
         
         
         
        var modeSetByApp = runtimePatch.mode != nil
        let ownLayer = Self.ownLayer(of: profile, over: trimmed)
        if var layer = ownLayer {
             
             
             
             
             
            if runtimePatch.mode != nil { layer.mode = nil }
            ownLayerLogLevel = layer.logLevel
            layer.logLevel = nil
            runtimePatch = runtimePatch.overlaying(layer)
        }
         
         
        if runtimePatch.mode == nil, let legacyMode = profile.outboundMode {
            runtimePatch.mode = legacyMode.rawValue
            modeSetByApp = true
        }
         
         
        let listenerWrittenBack = Self.lanSharingWrittenBack(pageListener, over: scriptsListener, ownLayer: ownLayer)
        for key in listenerWrittenBack {
            runtimePatch.setTopLevelNode(key, pageListener.topLevelNode(key))
        }
         
         
         
         
         
         
         
        let directive = logLevelDirective ?? ClashLogSettings.levelDirective(
            from: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite) ?? .standard
        )
        switch directive {
        case .forced(let forcedLevel):
            runtimePatch.logLevel = forcedLevel.rawValue
        case .followProfile:
             
             
             
             
             
             
            if let ownLayerLogLevel {
                runtimePatch.logLevel = ownLayerLogLevel
                profileLogLevel = ownLayerLogLevel
            } else {
                runtimePatch.logLevel = nil
            }
        }
        effectiveRuntime.patchJSON = runtimePatch.patchJSON
        let disabledRuntimeRules = Set(
            profile.override.disabledGlobalRules ?? []
        )
        effectiveRuntime.appendRules.removeAll {
            disabledRuntimeRules.contains($0)
        }
        effectiveRuntime.appendRules = try resolvedFallbackTargets(
            effectiveRuntime.appendRules,
            mergedInto: trimmed
        )
        let runtimeOverrideJSON = try overrideJSON(from: effectiveRuntime)
        let runtimeApplied = try ConfigTransforms.mergeOverride(
            raw: trimmed,
            overrideJSON: runtimeOverrideJSON
        )
         
         
         
         
        let late = leftOut.isEmpty ? lateLeftOut(mergedRules, in: runtimeApplied, policies: mergedPolicies) : []
        let stages = RuntimeBuildStages(
            afterClientTransforms: trimmed,
            beforeClientRuntimePolicy: runtimeApplied,
            udpFallback: UDPFallbackSettings.resolved(
                profile: profile.udpFallbackPolicy,
                global: UDPFallbackSettings.policy()
            ),
            excludeAPNsRoute: ClashTunnelRouteShaping.Switches.read(
                from: UDPFallbackSettings.appGroupDefaults
            ).excludeAPNsRoute,
            providerMerge: providerMerge,
            profileLogLevel: profileLogLevel,
            logLevelSetByApp: { if case .forced = directive { return true } else { return false } }(),
            modeSetByApp: modeSetByApp,
            listenerWrittenBack: listenerWrittenBack,
             
             
            beforeClientRuntimePolicyJSON: trimmedJSON.flatMap { runtimeApplied == trimmed ? $0 : nil },
             
             
            nodesJSON: runtimeOverrideJSON.isEmpty || ConfigTransforms.overrideLeavesNodes(runtimeOverrideJSON)
                ? trimmedNodesJSON : nil
        )
        return (stages, late)
    }

     
     
     
     
     
     
     
     
     
     
    static func applyClientTransforms(
        to scripted: String,
        profile: Profile,
        applyProviderDefinitions: Bool = true,
        applyProxyChain: Bool = true,
        applyLegacyRelayMigration: Bool = true
    ) throws -> String {
        var report = ProviderDefinitionMergeReport()
        return try applyClientTransforms(
            to: scripted,
            profile: profile,
            applyProviderDefinitions: applyProviderDefinitions,
            applyProxyChain: applyProxyChain,
            applyLegacyRelayMigration: applyLegacyRelayMigration,
            providerMerge: &report
        )
    }

    static func applyClientTransforms(
        to scripted: String,
        profile: Profile,
        applyProviderDefinitions: Bool = true,
        applyProxyChain: Bool = true,
        applyLegacyRelayMigration: Bool = true,
        providerMerge: inout ProviderDefinitionMergeReport,
        inspectLogLevel: ((Bool, String?) -> Void)? = nil,
         
         
        inspectListener: (([String: Any]) -> Void)? = nil,
         
         
         
        unchangedJSON: ((String) -> Void)? = nil,
         
         
         
        nodesJSON: ((String) -> Void)? = nil
    ) throws -> String {
         
         
         
        if let spliced = try applyClientTransformsAroundRules(
            to: scripted, profile: profile, applyProviderDefinitions: applyProviderDefinitions,
            applyProxyChain: applyProxyChain, applyLegacyRelayMigration: applyLegacyRelayMigration,
            providerMerge: &providerMerge, inspectLogLevel: inspectLogLevel, inspectListener: inspectListener,
            nodesJSON: nodesJSON) {
            return spliced
        }
        return try applyClientTransforms(
            to: scripted, profile: profile, applyProviderDefinitions: applyProviderDefinitions,
            applyProxyChain: applyProxyChain, applyLegacyRelayMigration: applyLegacyRelayMigration,
            providerMerge: &providerMerge, inspectLogLevel: inspectLogLevel, inspectListener: inspectListener,
            unchangedJSON: unchangedJSON,
            nodesJSON: nodesJSON, rulesStandIn: nil)
    }

     
    private struct RulesStandInTouched: Error {}

     
     
     
     
     
     
     
     
    private static func applyClientTransformsAroundRules(
        to scripted: String,
        profile: Profile,
        applyProviderDefinitions: Bool,
        applyProxyChain: Bool,
        applyLegacyRelayMigration: Bool,
        providerMerge: inout ProviderDefinitionMergeReport,
        inspectLogLevel: ((Bool, String?) -> Void)?,
        inspectListener: (([String: Any]) -> Void)?,
        nodesJSON: ((String) -> Void)?
    ) throws -> String? {
        guard scripted.utf8.count >= ConfigTransforms.ruleSectionCutFromBytes,
              !(profile.memoryTrim ?? MemoryTrimSpec()).dropsRuleLines,
              let cut = TopLevelYAMLSections.cutting(["rules"], from: scripted),
              let section = cut.sectionText("rules"), let lines = RuleLines(section) else { return nil }
        let standIn = NSArray(array: try lines.rules(whoseLinesHold: ["match"]))
        var report = providerMerge
        var restNodes: String?
        let rest: String
        do {
            rest = try applyClientTransforms(
                to: cut.rest, profile: profile, applyProviderDefinitions: applyProviderDefinitions,
                applyProxyChain: applyProxyChain, applyLegacyRelayMigration: applyLegacyRelayMigration,
                providerMerge: &report, inspectLogLevel: inspectLogLevel, inspectListener: inspectListener, unchangedJSON: nil,
                nodesJSON: { restNodes = $0 }, rulesStandIn: standIn)
        } catch is RulesStandInTouched {
            return nil
        }
        if ConfigTransforms.sameText(rest, cut.rest) {
            return finishAroundRules(scripted, report, restNodes, &providerMerge, nodesJSON)
        }
        guard let spliced = cut.splicing(into: rest) else { return nil }
        return finishAroundRules(spliced, report, restNodes, &providerMerge, nodesJSON)
    }

    private static func finishAroundRules(_ text: String, _ report: ProviderDefinitionMergeReport, _ restNodes: String?,
                                          _ providerMerge: inout ProviderDefinitionMergeReport,
                                          _ nodesJSON: ((String) -> Void)?) -> String {
        providerMerge = report
        if let restNodes { nodesJSON?(restNodes) }
        return text
    }

    private static func applyClientTransforms(
        to scripted: String,
        profile: Profile,
        applyProviderDefinitions: Bool,
        applyProxyChain: Bool,
        applyLegacyRelayMigration: Bool,
        providerMerge: inout ProviderDefinitionMergeReport,
        inspectLogLevel: ((Bool, String?) -> Void)?,
        inspectListener: (([String: Any]) -> Void)?,
        unchangedJSON: ((String) -> Void)?,
        nodesJSON: ((String) -> Void)?,
         
         
         
         
        rulesStandIn: NSArray?
    ) throws -> String {
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        var document = try ConfigTransforms.ParsedDocument(yaml: scripted)
        if let rulesStandIn { document.root["rules"] = rulesStandIn }
         
         
         
        let writtenNodes = document.root["proxies"].map { $0 as AnyObject }
        var touched = false
        if applyProviderDefinitions {
            let spec = profile.providerDefinitions ?? ProfileProviderDefinitionSpec()
            if !spec.isEmpty {
                providerMerge = try spec.apply(to: &document.root)
                touched = true
            }
        }
        let materialized = try CustomNodesGroupMaterializer.applyReportingChange(
            to: &document.root
        )
        touched = touched || materialized
        let overrides = profile.proxyNodeOverrides ?? ProxyNodeOverrideSpec()
        if !overrides.isEmpty {
            try overrides.apply(to: &document.root)
            touched = true
        }
        if applyProxyChain {
            let chain = profile.proxyChain ?? ProxyChainSpec()
            if !chain.assignments.isEmpty {
                try chain.apply(to: &document.root)
                touched = true
            }
        }
        if applyLegacyRelayMigration {
            touched = try LegacyRelayMigrationEngine.apply(
                profile.legacyRelayMigrations ?? [],
                to: &document.root
            ) || touched
        }
        touched = try (profile.memoryTrim ?? MemoryTrimSpec())
            .apply(to: &document.root) || touched
         
         
         
         
        touched = ConfigurationComposer.refreshingGeneratedGlobal(&document.root) || touched
        if let rulesStandIn {
            guard let rules = document.root["rules"], (rules as AnyObject) === rulesStandIn else {
                throw RulesStandInTouched()
            }
            document.root.removeValue(forKey: "rules")
        }
        let docLogLevel = document.root["log-level"] as? String
        inspectLogLevel?(docLogLevel != nil && !(document.root["log-level"] is NSNull), docLogLevel)
        inspectListener?(document.root.filter { OverridePatch.listenerKeys.contains($0.key) })
         
         
         
         
        var trimmed = scripted
        if touched, let writtenNodes, let nodes = document.root["proxies"], (nodes as AnyObject) === writtenNodes,
           let json = document.json, let spliced = try document.serializedLeavingNodes(as: scripted) {
             
             
            trimmed = spliced
            nodesJSON?(json)
        } else if touched {
            let written = try document.serializedReading()
            trimmed = written.yaml
            nodesJSON?(written.json)
        } else if let json = document.json {
            nodesJSON?(json)
        }
         
        if profile.dnsBootstrapInsurance == true {
            trimmed = try ConfigTransforms.applyDNSBootstrapInsurance(trimmed)
        } else if !touched, let json = document.json {
            unchangedJSON?(json)
        }
         
         
         
         
         
        return trimmed
    }

     
     
     
     
     
    static func runtimePreview(
        raw: String,
        profile: Profile,
        runtimeOverride: OverrideSpec = FlClashRuntimeConfig.load(),
        scripts caller: ScriptEngine.Caller = .surfaced
    ) throws -> String {
        try buildProduction(
            raw: raw,
            profile: profile,
            runtimeOverride: runtimeOverride,
            scripts: caller
        )
    }

     
     
    static let builtinPolicies: Set<String> = ConfigurationComposer.builtins.union(["MATCH"])

     
     
     
    static func knownPolicies(in yaml: String) -> Set<String>? {
         
         
         
         
         
         
        let text = ConfigTransforms.keepsLargeRuleLines(yaml)
            ? TopLevelYAMLSections.cutting(["rules"], from: yaml)?.rest ?? yaml : yaml
        var error: NSError?
        let json = AppCore.policyNamesJSON(text, &error)
        guard error == nil,
              let names = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        else { return nil }
        var known = builtinPolicies
        for key in ["proxies", "groups"] {
            for case let name as String in (names[key] as? [Any]) ?? [] { known.insert(name) }
        }
        return known
    }

     
     
    static func knownPolicies(root: [String: Any]) -> Set<String> {
        var names = builtinPolicies
        for key in ["proxies", "proxy-groups"] {
            for case let entry as [String: Any] in (root[key] as? [Any]) ?? [] {
                if let name = entry["name"] as? String { names.insert(name) }
            }
        }
        return names
    }

     
     
     
     
     
     
    static func declaredRuleSetsAndSubRules(in yaml: String, readersOwn: Bool = false)
        -> (ruleSets: Set<String>?, subRules: Set<String>?) {
        var text = yaml
        if let cut = text.withUTF8({ declared(inBytes: $0) }) { return sets(of: cut, readersOwn: readersOwn) }
        let whole = (try? ConfigTransforms.foundationRoot(
            ofYAML: yaml, omitting: ["proxies", "proxy-groups", "proxy-providers", "rules"])) ?? nil
        return sets(of: whole, readersOwn: readersOwn)
    }

     
     
    static func declaredRuleSetsAndSubRules(inBytes data: Data, readersOwn: Bool = false)
        -> (ruleSets: Set<String>?, subRules: Set<String>?)? {
        guard let cut = data.withUnsafeBytes({ declared(inBytes: $0.bindMemory(to: UInt8.self)) }) else { return nil }
        return sets(of: cut, readersOwn: readersOwn)
    }

     
     
    private static func declared(inBytes bytes: UnsafeBufferPointer<UInt8>) -> [String: Any]?? {
        let keys = ["rule-providers", "sub-rules"]
        guard let cut = TopLevelYAMLSections.sections(Set(keys), inBytes: bytes), cut.refused.isEmpty else { return nil }
        let written = keys.compactMap { cut.texts[$0] }.map { $0.hasSuffix("\n") ? $0 : $0 + "\n" }.joined()
        let read: [String: Any]? = written.isEmpty ? [:] : (try? ConfigTransforms.foundationRoot(ofYAML: written)) ?? nil
        return .some(read)
    }

    private static func sets(of declared: [String: Any]?, readersOwn: Bool) -> (ruleSets: Set<String>?, subRules: Set<String>?) {
        guard readersOwn, let declared, let providers = declared["rule-providers"] as? [String: Any] else {
             
            return (names("rule-providers", in: declared), names("sub-rules", in: declared))
        }
        return (Set(ModuleRuleSetSyntax.readersOwn(providers).keys), names("sub-rules", in: declared))
    }

    private static func names(_ key: String, in declared: [String: Any]?) -> Set<String>? {
        guard let declared else { return nil }
         
         
        guard let value = declared[key], !(value is NSNull) else { return [] }
        return (value as? [String: Any]).map { Set($0.keys) }
    }

     
     
    static func ruleNames(in yaml: String, root: [String: Any]? = nil) -> ClashRuleNames? {
        guard let policies = root.map(knownPolicies(root:)) ?? knownPolicies(in: yaml) else { return nil }
        if let root {
            return ClashRuleNames(policies: policies, ruleSets: names("rule-providers", in: root),
                                  subRules: names("sub-rules", in: root))
        }
        let declared = declaredRuleSetsAndSubRules(in: yaml)
        return ClashRuleNames(policies: policies, ruleSets: declared.ruleSets, subRules: declared.subRules)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    static func droppingUnknownTargets(
        _ rules: [String],
        mergedInto yaml: String
    ) -> (kept: [String], dropped: [String], policies: Set<String>?) {
        guard !rules.isEmpty, let known = knownPolicies(in: yaml) else { return (rules, [], nil) }
        let names = ClashRuleNames(policies: known, ruleSets: nil, subRules: nil)
        var kept: [String] = []
        var dropped: [String] = []
        for rule in rules {
            if names.leavesOut(rule) {
                dropped.append(rule)
            } else {
                kept.append(rule)
            }
        }
        return (kept, dropped, known)
    }

     
     
     
     
    static func lateLeftOut(_ rules: [String], in yaml: String, policies: Set<String>) -> Set<String> {
        let asking = rules.filter {
            StructuredRule.parse($0)?.action == .subRule || !StructuredRule.ruleSetNames(in: $0).isEmpty
        }
        guard !asking.isEmpty else { return [] }
        let declared = declaredRuleSetsAndSubRules(in: yaml)
         
         
        let names = ClashRuleNames(policies: policies.isEmpty ? nil : policies,
                                   ruleSets: declared.ruleSets, subRules: declared.subRules)
         
         
        return Set(asking.filter { rule in
            switch names.missing(in: rule) {
            case .ruleSet?, .subRule?: return true
            case .policy?, nil: return false
            }
        })
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    static func personalRulesLeftOut(
        of yaml: String, root: [String: Any]? = nil, profile: Profile, globalOverride: OverrideSpec = GlobalConfig.load()
    ) -> [String] {
        guard let known = ruleNames(in: yaml, root: root) else { return [] }
        var candidates: [String] = []
        switch profile.overwriteMode ?? .standard {
        case .standard, .script:
            let muted = Set(profile.override.disabledAppendRules ?? [])
            candidates += profile.override.appendRules.filter { !muted.contains($0) }
        case .custom:
            break
        }
        if (profile.overwriteMode ?? .standard) == .standard {
            let disabled = Set(profile.override.disabledGlobalRules ?? [])
            candidates += (profile.migratedGlobalOverride ?? globalOverride).appendRules.filter { !disabled.contains($0) }
        }
         
         
        return candidates.filter(known.leavesOut)
    }

     
     
     
     
     
     
     
     
     
    static func resolvedFallbackTargets(
        _ rules: [String],
        mergedInto yaml: String
    ) throws -> [String] {
        let needsResolution = rules.contains {
            StructuredRule.parse($0)?.target == "MATCH"
        }
        guard needsResolution else { return rules }
         
         
         
         
         
        let sourceRules: [Any]
        if let matches = try ConfigTransforms.largeRules(of: yaml, whoseLinesHold: ["match"]) {
            sourceRules = matches
        } else {
            let root = try ConfigTransforms.foundationRoot(ofYAML: yaml, omitting: ["proxies"])
            sourceRules = (root?["rules"] as? [Any]) ?? []
        }
        let fallback = sourceRules.lazy
            .compactMap { entry -> String? in
                guard let line = entry as? String,
                      let parsed = StructuredRule.parse(line),
                      parsed.action == .match, !parsed.target.isEmpty,
                      parsed.target != "MATCH" else { return nil }
                return parsed.target
            }
            .first ?? "DIRECT"
        return rules.map { rule in
            guard var parsed = StructuredRule.parse(rule),
                  parsed.target == "MATCH" else { return rule }
            parsed.target = fallback
            return parsed.rawValue
        }
    }

     
    static func hasEnabledOwnDNS(yaml: String) -> Bool {
         
         
        guard let root = (try? ConfigTransforms.foundationRoot(ofYAML: yaml, omitting: ConfigTransforms.nodesAndRules)) ?? nil,
              let dns = root["dns"] as? [String: Any] else {
            return false
        }
        return (dns["enable"] as? Bool) == true
    }

     
     
    static func lanSharingListener(of profile: Profile) -> OverridePatch {
        OverridePatch(patchJSON: profile.override.patchJSON).retainingTopLevelKeys(OverridePatch.listenerKeys)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func lanSharingWrittenBack(_ listener: OverridePatch, over left: [String: Any]?,
                                      ownLayer: OverridePatch?) -> [String] {
        listener.topLevelKeys.filter { key in
             
             
             
            guard let running = ownLayer?.value(at: [key]) ?? left?[key], !(running is NSNull) else { return true }
            return !(running as AnyObject).isEqual(listener.value(at: [key]))
        }
    }

     
     
     
     
     
     
     
     
    static func ownLayer(of profile: Profile, over document: String) -> OverridePatch? {
        guard let legacy = profile.legacyRuntimePatchJSON, !legacy.isEmpty else { return nil }
        var layer = OverridePatch(patchJSON: legacy)
        if profile.legacyRuntimeDNSGated == true, layer.hasDNSOverride, hasEnabledOwnDNS(yaml: document) {
            layer.clearDNS()
        }
        return layer
    }

     
     
     
     
     
     
     
     
     
     
    static func applyingOwnLayer(of profile: Profile, to document: String,
                                 listenerWrittenBack: [String]) throws -> String {
        var layer = ownLayer(of: profile, over: document) ?? OverridePatch(patchJSON: "")
        if !listenerWrittenBack.isEmpty {
            let listener = lanSharingListener(of: profile)
            for key in listenerWrittenBack { layer.setTopLevelNode(key, listener.topLevelNode(key)) }
        }
        guard !layer.topLevelKeys.isEmpty else { return document }
        return try ConfigTransforms.mergeOverride(
            raw: document,
            overrideJSON: overrideJSON(from: OverrideSpec(patchJSON: layer.patchJSON))
        )
    }

    private static func overrideJSON(from spec: OverrideSpec) throws -> String {
        if spec.patchJSON.isEmpty && spec.appendRules.isEmpty { return "" }
        var payload: [(key: String, value: OrderedJSON)] = []
        if !spec.patchJSON.isEmpty {
             
             
             
             
             
             
            payload.append((key: "patch", value: try OrderedJSON.parse(spec.patchJSON)))
        }
        if !spec.appendRules.isEmpty {
            payload.append((key: "appendRules", value: .array(spec.appendRules.map(OrderedJSON.string))))
            payload.append((key: "prependRules", value: .scalar(spec.prependRules ? "true" : "false")))
        }
        return OrderedJSON.object(payload).serialized()
    }

}

 
 
 
 
 
 
 
 
 
 
 
 
 
enum PublishedSourceLedger {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var digests: [String: String] = [:]
    nonisolated(unsafe) private static var order: [String: [String]] = [:]
     
    nonisolated(unsafe) private static var configurations: [String] = []
    static let keptPerConfiguration = 8
    static let keptConfigurations = 32

     
    static func retain(only profileIDs: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        for gone in configurations where !profileIDs.contains(gone) { forgetLocked(gone) }
    }

     
    static var count: Int { lock.lock(); defer { lock.unlock() }; return digests.count }

    private static func forgetLocked(_ profileID: String) {
        for slot in order[profileID] ?? [] { digests.removeValue(forKey: slot) }
        order.removeValue(forKey: profileID)
        configurations.removeAll { $0 == profileID }
    }

    private static func key(_ pointer: ActiveConfigurationPointer) -> String {
        pointer.profileID + "\n" + pointer.revision
    }

    static func resetForTesting() {
        lock.lock(); digests = [:]; order = [:]; configurations = []; lock.unlock()
    }

    static func digest(of source: String) -> String {
         
        var text = source
        return text.withUTF8 { SHA256.hash(data: UnsafeRawBufferPointer($0)) }
            .map { String(format: "%02x", $0) }.joined()
    }

     
    static func record(_ pointer: ActiveConfigurationPointer, source: String?) {
        record(pointer, digest: source.map { Self.digest(of: $0) })
    }

     
     
    static func record(_ pointer: ActiveConfigurationPointer, digest sourceDigest: String?) {
        let slot = Self.key(pointer)
        lock.lock(); defer { lock.unlock() }
        var slots = order[pointer.profileID] ?? []
        slots.removeAll { $0 == slot }
        digests[slot] = sourceDigest
        if sourceDigest != nil { slots.append(slot) }
        while slots.count > keptPerConfiguration { digests.removeValue(forKey: slots.removeFirst()) }
        order[pointer.profileID] = slots
        configurations.removeAll { $0 == pointer.profileID }
        configurations.append(pointer.profileID)
        while configurations.count > keptConfigurations { forgetLocked(configurations[0]) }
    }

     
     
    static func published(_ pointer: ActiveConfigurationPointer, from source: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return digests[key(pointer)] == digest(of: source)
    }
}

 
 
 
final class HandedSource: @unchecked Sendable {
    private let lock = NSLock()
    private var text: String?
    let holdsText: Bool

    init(_ text: String?) {
        self.text = text
        holdsText = text != nil
    }

     
    func take() -> String? {
        lock.lock(); defer { lock.unlock() }
        let taken = text
        text = nil
        return taken
    }
}

 
 
struct PublishedSourceDigest {
    let ledger: String
    let presentationPrefix: SHA256

    init(_ source: String) {
        ledger = PublishedSourceLedger.digest(of: source)
        presentationPrefix = PublishedPresentation.sourcePrefix(source)
    }
}

 
 
 
 
 
final class ProfileActivationCoordinator {



     
     
     
     
    private(set) var firstLoadPendingOfLastPublication: [String] = []
     
     
     
     
    private(set) var lastPublicationPreflight: (pointer: ActiveConfigurationPointer, outcome: PreflightOutcome)?
     
     
     
     
    private(set) var lastPublicationNotices: (pointer: ActiveConfigurationPointer, notices: [String])?
     
     
     
     
    struct ModulePublication: Equatable {
        let degradedBecause: [ModuleDegradeReason]
        let record: ModuleActivationRecord?
         
        var disclosures: [ModuleDisclosure] = []
         
         
        var certEntryIP: String? = nil
         
        var skipped: [ModuleIgnoredEntry] = []
         
         
        var engineAssignment: ModuleEngineAssignment? = nil
         
         
         
        var changes: [ModuleChange] = []
    }
     
     
    private(set) var lastPublicationModule: (pointer: ActiveConfigurationPointer, outcome: ModulePublication)?
     
     
     
     
     
    static let maxProviderBytes = Int.max
    static let maxGeodataBytes = Int.max
     
     
    nonisolated(unsafe) static var finalizeOrderReference = true

     
     
     
     
     
     
     
     
    static func givesTheHeapBack(planReadAFile: Bool, finalizesThatFile: Bool,
                                 givenBackAfterDownloads: Bool) -> Bool {
        planReadAFile && !finalizesThatFile && !givenBackAfterDownloads
    }

    private let store: ConfigResourceStore
    private let profileStore: ProfileStore
    private let credentials: CredentialStore
    private let coreHomeDir: URL
     
     
     
    private let compileRuleSets: Bool
    private let writesNodeLibrary: Bool
     
     
    private let deferRuleSetCompilation: Bool
    private let stagingPublisher: (String, Int, Bool) -> Void
    private let scheduleDeferredCompilation: (@escaping () -> Void) -> Void

     
     
     
    static let deferredCompilationQueue = DispatchQueue(
        label: "network.clash.provider-staging.compile", qos: .utility
    )

     
     
     
    static var scheduledCompiles: UInt64 { compileCount.value }
    private static let compileCount = CompileQueueCounter()

     
     
     
     
     
     
     
    @discardableResult
    static func drainDeferredCompilation(timeout: TimeInterval = 60) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = CompileQueueOnce()
            deferredCompilationQueue.async { if once.claim() { continuation.resume(returning: true) } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                if once.claim() { continuation.resume(returning: false) }
            }
        }
    }

     
     
     
     
     
     
     
     
     
    static func onCompilationQueue<T>(deadline: TimeInterval, finished: @escaping () -> Void = {},
                                      _ body: @escaping () throws -> T) async throws -> T? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T?, Error>) in
            let run = CompileQueueRun()
            deferredCompilationQueue.async {
                guard run.start() else { finished(); return }
                let result = Result { try body() }
                finished()
                if run.answer() { continuation.resume(with: result.map { Optional($0) }) }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + deadline) {
                run.expire()
                if run.answer() { continuation.resume(returning: nil) }
            }
        }
    }

     
     
     
     
     
     
     
    private func publishStaging(finalYAML: String, providerCount: Int) {
        guard compileRuleSets, deferRuleSetCompilation else {
            stagingPublisher(finalYAML, providerCount, compileRuleSets)
            return
        }
        stagingPublisher(finalYAML, providerCount, false)
        scheduleCompile(finalYAML: finalYAML, providerCount: providerCount)
    }

     
    private func scheduleCompile(finalYAML: String, providerCount: Int) {
        Self.compileCount.increment()
        let staged = try? store.activeIdentity()
        let store = self.store
        let publish = self.stagingPublisher
        scheduleDeferredCompilation {
            guard (try? store.activeIdentity()) == staged else { return }
            publish(finalYAML, providerCount, true)
            AppCore.returnFreeMemory()
        }
    }

     
     
     
     
     
     
    private func compileUnchanged(finalYAML: String, providerCount: Int) {
        guard compileRuleSets else { return }
        if deferRuleSetCompilation {
            scheduleCompile(finalYAML: finalYAML, providerCount: providerCount)
        } else {
            stagingPublisher(finalYAML, providerCount, true)
        }
    }
    private let activationFetchBudget: ProviderFetchBudget
     
     
     
    private var activationReuseSource = "unset"
    private let globalOverride: () -> OverrideSpec
    private let runtimeOverride: () -> OverrideSpec
     
     
     
    private let downloadIdentity: () -> String
     
     
     
    private let profileScript: ((String?, String, String) throws -> String)?
    private let configScript: ((String, String) throws -> String)?
    private let postMergeScript: ((String?, String, String) throws -> String)?
    private let activator: (URL) throws -> Void
    private let subscriptions: SubscriptionManager
    private let materializer: ProviderMaterializer
    private let geodata: GeodataManager
    private let preflight: (String) -> PreflightOutcome
     
     
     
     
    private let preflightIsCallers: Bool
    private let intentContainer: URL
    private let intentSettings: IPStackSettings?
     
     
     
     
     
    private let prepareCore: () throws -> Void
    private let now: () -> Date
     
     
     
     
    private let log: (String) -> Void
     
     
     
    private let modules: () -> ModuleActivationInput?
     
     
    private let modulesFromReadiness: Bool

    init(store: ConfigResourceStore, profileStore: ProfileStore,
         credentials: CredentialStore, downloader: HTTPFetching,
         coreHomeDir: URL,
          
          
          
          
          
          
          
         compileRuleSets: Bool = false,
          
          
          
          
          
         writesNodeLibrary: Bool = true,
          
          
          
          
          
          
          
          
          
          
         deferRuleSetCompilation: Bool = false,
          
          
          
          
         activationFetchBudget: ProviderFetchBudget = .activation,
         globalOverride: @escaping () -> OverrideSpec = { GlobalConfig.load() },
         runtimeOverride: @escaping () -> OverrideSpec = {
             FlClashRuntimeConfig.load()
         },
         downloadIdentity: @escaping () -> String = { ClientUserAgent.downloadIdentity() },
          
          
          
          
          
          
          
          
         logDefaults: UserDefaults = UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite) ?? .standard,
         profileScript: ((String?, String, String) throws -> String)? = nil,
         configScript: ((String, String) throws -> String)? = nil,
         postMergeScript: ((String?, String, String) throws -> String)? = nil,
         activator: @escaping (URL) throws -> Void,
         preflight: ((String) -> PreflightOutcome)? = nil,
          
          
          
          
         intentContainer: URL? = nil,
         intentSettings: IPStackSettings? = nil,
         prepareCore: @escaping () throws -> Void = {},
          
         stagingPublisher: @escaping (String, Int, Bool) -> Void = {
             ProviderStagingPublisher.publish(
                 finalYAML: $0, providerCount: $1, compileRuleSets: $2
             )
         },
          
          
         scheduleDeferredCompilation: @escaping (@escaping () -> Void) -> Void = {
             ProfileActivationCoordinator.deferredCompilationQueue.async(execute: $0)
         },
          
          
          
         modules: (() -> ModuleActivationInput?)? = nil,
         now: @escaping () -> Date = Date.init,
         log: @escaping (String) -> Void = {
             ClashLogStore.shared.append($0, stream: .app)
         }) {
        self.store = store
        self.profileStore = profileStore
        self.credentials = credentials
        self.coreHomeDir = coreHomeDir
        self.compileRuleSets = compileRuleSets
        self.writesNodeLibrary = writesNodeLibrary
        self.deferRuleSetCompilation = deferRuleSetCompilation
        self.stagingPublisher = stagingPublisher
        self.scheduleDeferredCompilation = scheduleDeferredCompilation
        self.activationFetchBudget = activationFetchBudget
        self.globalOverride = globalOverride
        self.runtimeOverride = runtimeOverride
        self.downloadIdentity = downloadIdentity
        self.logDefaults = logDefaults
        self.profileScript = profileScript
        self.configScript = configScript
        self.postMergeScript = postMergeScript
        self.activator = activator
        self.subscriptions = SubscriptionManager(downloader: downloader, credentials: credentials)
        self.materializer = ProviderMaterializer(downloader: downloader, credentials: credentials)
        self.geodata = GeodataManager(downloader: downloader)
        self.preflightIsCallers = preflight != nil
        let intentContainer = intentContainer ?? coreHomeDir.deletingLastPathComponent()
        self.intentContainer = intentContainer
        self.intentSettings = intentSettings
        self.preflight = preflight ?? { finalYAML in
            PreflightService.intent(finalYAML: finalYAML, container: intentContainer, settings: intentSettings)
        }
        self.prepareCore = prepareCore
        self.now = now
        self.log = log
        let modulesContainer = coreHomeDir.deletingLastPathComponent()
        self.modulesFromReadiness = modules == nil
        self.modules = modules ?? {
             
             
             
             
             
            guard var input = ModuleActivationInput.loadPublished(locations: ModuleLocations(container: modulesContainer),
                                                                  engine: .unavailable) else { return nil }
            if input.manifest.enabled {
                input.engine = ModuleEngineReadinessSource.shared(modulesContainer).statusForPublication(
                    ports: input.manifest.ports, publishedFingerprint: input.manifest.caFingerprintSHA256)
            }
            return input
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    private struct FailureRecord {
         
         
         
         
        let stage: String
        let error: String
        let cancelled: Bool

        init(_ error: Error) {
            cancelled = error is CancellationError
            switch error {
            case let pipeline as PipelineError:
                switch pipeline {
                case .sourceUnavailable: (stage, self.error) = ("source", "sourceUnavailable")
                case .notModifiedWithoutActive:
                    (stage, self.error) = ("source", "notModifiedWithoutActive")
                case .planRejected: (stage, self.error) = ("plan", "planRejected")
                case .providerNotFound: (stage, self.error) = ("plan", "providerNotFound")
                case .externalResources: (stage, self.error) = ("resources", "externalResources")
                case .preflightFailed: (stage, self.error) = ("preflight", "preflightFailed")
                case .activationReadback: (stage, self.error) = ("publish", "activationReadback")
                case .sourceSuperseded: (stage, self.error) = ("source", "sourceSuperseded")
                }
            case is CancellationError:
                (stage, self.error) = ("cancelled", "CancellationError")
            default:
                 
                 
                (stage, self.error) = ("unknown", String(describing: type(of: error)))
            }
        }
    }

     
     
     
     
     
    private func record(_ error: Error, profile: Profile, since start: Date) {
        let record = FailureRecord(error)
        let millis = Int((now().timeIntervalSince(start) * 1000).rounded())
        var line = "profile activation \(record.cancelled ? "cancelled" : "failed")  "
            + "id=\(profile.id) stage=\(record.stage) "
            + "error=\(record.error) after=\(millis)ms"
         
         
        if !record.cancelled {
            let reason = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            if !reason.isEmpty {
                 
                 
                 
                 
                let bounded = reason.count > 400
                    ? String(reason.prefix(400)) + "…(truncated)"
                    : reason
                line += "  reason=\(bounded)"
            }
        }
        log(line)
    }

    @discardableResult
     
     
     
     
     
    func activate(profile given: Profile, sourceYAML: String?,
                  onlyIfActive expected: ActiveConfigurationPointer? = nil) async throws -> ActiveConfigurationPointer {
        try await activate(profile: given, sourceYAML: sourceYAML, handedSource: nil, onlyIfActive: expected)
    }

     
     
     
    @discardableResult
    func activate(profile given: Profile, handedSource: HandedSource,
                  onlyIfActive expected: ActiveConfigurationPointer? = nil,
                  forceFreshFetch: Bool = false) async throws -> ActiveConfigurationPointer {
        try await activate(profile: given, sourceYAML: nil, handedSource: handedSource.holdsText ? handedSource : nil,
                           onlyIfActive: expected, forceFreshFetch: forceFreshFetch)
    }

     
     
     
    private func activate(profile given: Profile, sourceYAML: String?, handedSource: HandedSource?,
                          onlyIfActive expected: ActiveConfigurationPointer?,
                          forceFreshFetch: Bool = false) async throws -> ActiveConfigurationPointer {
         
         
         
        let startedAt = now()
         
         
         
         
         
         
         
        let stored = profileStore.load().first(where: { $0.id == given.id })
        let profile = stored ?? given
         
         
        guard stored != nil || expected == nil else {
            let gone = PipelineError.sourceUnavailable("the profile is no longer available")
            record(gone, profile: profile, since: startedAt)
            throw gone
        }
        do {
            try prepareCore()
            let pointer = try await activateResolved(
                given: given, sourceYAML: sourceYAML, handedSource: handedSource, forceFreshFetch: forceFreshFetch,
                onlyIfActive: expected, firstActivation: stored == nil
            )
             
             
            log("profile activated  id=\(profile.id) rev=\(pointer.revision)")
            return pointer
        } catch let original {
             
             
             
             
             
             
            guard !(original is CancellationError), sourceYAML != nil || handedSource != nil,
                  !Self.lostToASwitch(original), !Self.superseded(original),
                   
                   
                  stored == nil || profileStore.load().contains(where: { $0.id == profile.id }),
                  case .url = profile.source else {
                record(original, profile: profile, since: startedAt)
                throw original
            }
            do {
                 
                 
                let pointer = try await activateResolved(
                    given: given, sourceYAML: nil, forceFreshFetch: true, onlyIfActive: expected,
                    firstActivation: stored == nil, healing: true
                )
                 
                 
                 
                 
                 
                log(
                    "profile activated  id=\(profile.id) rev=\(pointer.revision) "
                        + "healed=refetched"
                )
                return pointer
            } catch is CancellationError {
                record(CancellationError(), profile: profile, since: startedAt)
                throw CancellationError()
            } catch let yielded where Self.lostToASwitch(yielded) || Self.superseded(yielded) {
                 
                 
                record(yielded, profile: profile, since: startedAt)
                throw yielded
            } catch {
                 
                record(original, profile: profile, since: startedAt)
                throw original
            }
        }
    }

     
     
    static func lostToASwitch(_ error: Error) -> Bool {
        if case ConfigResourceStoreError.activeConfigurationChanged? = error as? ConfigResourceStoreError { return true }
        return false
    }

     
    static func superseded(_ error: Error) -> Bool {
        if case PipelineError.sourceSuperseded? = error as? PipelineError { return true }
        return false
    }

    private func activateResolved(
        given: Profile,
        sourceYAML: String?,
        handedSource: HandedSource? = nil,
        forceFreshFetch: Bool,
        onlyIfActive expected: ActiveConfigurationPointer? = nil,
        firstActivation: Bool,
        healing: Bool = false
    ) async throws -> ActiveConfigurationPointer {
         
         
         
         
         
         
         
         
        let workingDirectory = coreHomeDir
        let sidecarPath = sidecarURL(profileID: given.id).path
         
         
        let givenSource = sourceYAML != nil || handedSource != nil
        let (storedAtStart, identityAtStart) = ProfileStore.withWriteLock {
            () -> (Profile?, ProfileSourceIdentity?) in
            let record = profileStore.load().first(where: { $0.id == given.id })
            let judgesSource = !givenSource || !FileManager.default.fileExists(atPath: sidecarPath)
            return (record, judgesSource ? record.map { ProfileSourceIdentity($0, workingDirectory: workingDirectory) } : nil)
        }
        guard firstActivation || storedAtStart != nil else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        var profile = storedAtStart ?? given
         
        if healing { profile.usesLocalSourceOverride = false }
        func sourceIsAsItWas(_ current: Profile?) -> Bool {
            guard let current, let identityAtStart else { return false }
            return ProfileSourceIdentity(current, workingDirectory: workingDirectory) == identityAtStart
        }
        var fetchedBody = false
        var fetchedInfo: SubscriptionInfo?
        var fetchedETag: String?
        var fetchedLastModified: String?
        var fetchedName: String?
        var raw: String
        if givenSource {
            raw = sourceYAML ?? handedSource?.take() ?? ""
        } else {
            guard case .url = profile.source else {
                throw PipelineError.sourceUnavailable(
                    "profile '\(profile.label)' has no stored YAML and no profile URL")
            }
            if let fetched = try await subscriptions.fetch(
                profile: profile,
                useConditionalValidators: !forceFreshFetch
            ) {
                raw = fetched.yaml
                fetchedBody = true
                fetchedInfo = fetched.subscriptionInfo
                fetchedETag = fetched.etag
                fetchedLastModified = fetched.lastModified
                fetchedName = fetched.suggestedName
            } else {
                 
                 
                 
                 
                 
                 
                try? profileStore.updateIfPresent(id: profile.id, when: sourceIsAsItWas) {
                    $0.lastUpdatedAt = Date()
                }
                 
                if let current = try store.activePointer(), current.profileID == profile.id {
                    return current
                }

                 
                 
                 
                 
                 
                 
                 
                if !forceFreshFetch, let cached = try? String(
                    contentsOf: sidecarURL(profileID: profile.id),
                    encoding: .utf8
                ), !cached.isEmpty {
                    raw = cached
                } else if let fetched = try await subscriptions.fetch(
                    profile: profile,
                    useConditionalValidators: false
                ) {
                    raw = fetched.yaml
                    fetchedBody = true
                    fetchedInfo = fetched.subscriptionInfo
                    fetchedETag = fetched.etag
                    fetchedLastModified = fetched.lastModified
                    fetchedName = fetched.suggestedName
                } else {
                    throw PipelineError.notModifiedWithoutActive
                }
            }
        }

         
         
         
         
        var laps = PerfLedger.Laps()
        try ConfigTransforms.validateSource(raw)
        AppCore.returnFreeMemoryNow(after: raw)
        laps.mark("activation.validate")
         
         
         
         
         
         
         
         
        let sourceDigest = PublishedSourceDigest(raw)
        let keepsSource = handedSource == nil || !givenSource || !FileManager.default.fileExists(atPath: sidecarPath)
        let stagedSidecar = keepsSource && (!givenSource || !FileManager.default.fileExists(atPath: sidecarPath))
            ? try ProfileSourceStore.stage(document: raw, workingDirectory: coreHomeDir, profileID: profile.id)
            : nil
        var placedSidecar: ProfileSourceStore.Replaced?
        defer {
            if let placedSidecar { ProfileSourceStore.retire(placedSidecar) }
            else if let stagedSidecar { ProfileSourceStore.discard(stagedSidecar) }
        }
         
         
        let chainSource = HandedSource(raw)
        if !keepsSource || stagedSidecar != nil { raw = "" }
         
         
         
        let heldRoot = ConfigTransforms.HeldRoot()
         
         
         
        let prepared: String = try autoreleasepool {
             
            let reading = try prepareConfigReading(handed: chainSource, profile: profile, scripts: .surfaced)
            heldRoot.value = reading.root
            return reading.yaml
        }
         
         
        AppCore.returnFreeMemoryNow(after: prepared)
        laps.mark("activation.prepare")
        let rulesLeftOut = ProfileRuntimeConfigBuilder.personalRulesLeftOut(of: prepared, root: heldRoot.value,
                                                                           profile: profile,
                                                                           globalOverride: globalOverride())
         
         
         
         
         
         
        let (reusableProviders, reuseSource) = reusableProvidersDirectory(for: profile)
        activationReuseSource = reuseSource
        let profileStore = self.profileStore
        let publication = try await buildPublishActivate(
            profile: profile,
            merged: prepared,
            heldRoot: heldRoot,
            reuseDir: reusableProviders,
            reuseDirIsOwnRevision: reuseSource.hasPrefix("own"),
             
            replacing: expected,
             
             
             
             
            fetchBudget: activationFetchBudget,
             
             
             
            beforePublish: storedAtStart == nil ? nil : { [profileID = profile.id] in
                let current = profileStore.load().first(where: { $0.id == profileID })
                guard current != nil else {
                    throw PipelineError.sourceUnavailable("the profile is no longer available")
                }
                if !givenSource, !sourceIsAsItWas(current) {
                    throw PipelineError.sourceSuperseded
                }


            },
            source: raw.isEmpty ? nil : raw,
            sourceDigest: sourceDigest
        )
        laps.mark("activation.publish")
        let pointer = publication.pointer
        ProviderFirstLoadRetry.noteActivation(
            pending: firstLoadPendingOfLastPublication, profileID: profile.id
        )

         
         
        for rule in rulesLeftOut {
             
            ClashLogStore.shared.append(
                "personal rule left out of the runtime: \(rule) names a policy, rule set or sub-rule this configuration does not define",
                stream: .app, level: .warning)
        }
         
         
         
         
         
        let merge = lastProviderMerge
        let unfrozen = merge.unfrozen
         
         
         
        func applyActivationOwned(_ current: inout Profile) {
            current.activeRevision = pointer.revision
            if !merge.notices.isEmpty {
                current.providerDefinitionNotices =
                    (current.providerDefinitionNotices ?? []) + merge.notices
            }
            if !unfrozen.isEmpty, let spec = current.providerDefinitions {
                let kept = spec.droppingUnfrozen(unfrozen, asInspectedIn: profile.providerDefinitions)
                current.providerDefinitions = kept.isEmpty ? nil : kept
            }
        }
         
        func applyFetchOwned(_ current: inout Profile, otherLabels: [String]) {
            guard !givenSource else { return }
            current.lastUpdatedAt = Date()
            if let fetchedInfo { current.subscriptionInfo = fetchedInfo }
             
             
             
             
            let asItWas = current
            ProfileLabelPolicy.adoptPanelName(
                fetchedName,
                into: &current,
                for: asItWas,
                otherLabels: otherLabels
            )
            current.subscriptionETag = fetchedETag ?? current.subscriptionETag
            current.subscriptionLastModified = fetchedLastModified ?? current.subscriptionLastModified
             
             
             
            if fetchedBody { current.usesLocalSourceOverride = false }
        }
         
         
         
        func placeSidecar() throws {
            if let stagedSidecar {
                placedSidecar = try ProfileSourceStore.swapIn(stagedSidecar)
            } else {
                try writeSourceSidecar(raw, profileID: profile.id)
            }
        }
         
         
        let written: Bool = try ProfileStore.withWriteLock {
            let profiles = profileStore.load()
            let otherLabels = profiles.filter { $0.id != profile.id }.map(\.label)
            let sidecarExists = FileManager.default.fileExists(atPath: sidecarURL(profileID: profile.id).path)
            guard let current = profiles.first(where: { $0.id == profile.id }) else {
                 
                 
                 
                guard storedAtStart == nil else { return false }
                var fresh = profile
                applyActivationOwned(&fresh)
                applyFetchOwned(&fresh, otherLabels: otherLabels)
                try profileStore.upsert(fresh)
                if keepsSource, !givenSource || !sidecarExists {
                    try placeSidecar()
                }
                return true
            }
             
             
             
             
            let sourceUnchanged = sourceIsAsItWas(current)
            try profileStore.updateIfPresent(id: profile.id) { record in
                applyActivationOwned(&record)
                if sourceUnchanged { applyFetchOwned(&record, otherLabels: otherLabels) }
            }
             
             
             
             
             
             
             
             
             
            if sourceUnchanged, keepsSource, !givenSource || !sidecarExists {
                try placeSidecar()
            }
            return true
        }
        laps.mark("activation.record")
        guard written else {
             
             
             
             
            if let previous = publication.previous {
                _ = try? store.activateIfCurrentMatches(pointer, replacement: previous)
            } else {
                _ = try? store.deactivateIfCurrentMatches(pointer)
            }
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        return pointer
    }

     
     
     
     
     
     
    @discardableResult
    func regenerateRuntime(
        profile given: Profile,
        storedSourceYAML: String,
        sourceIsStoredSidecar: Bool = true,
        replacing previousRuntime: ActiveConfigurationPointer
    ) async throws -> ActiveConfigurationPointer {
        let profile = onDisk(given)
        try prepareCore()
        try ConfigTransforms.validateSource(storedSourceYAML)
        let prepared = try prepareConfig(raw: storedSourceYAML, profile: profile)
         
         
         
         
        let (reusableProviders, reuseSource) = reusableProvidersDirectory(for: profile)
        activationReuseSource = reuseSource
        let pointer = try await buildPublishActivate(
            profile: profile,
            merged: prepared,
            reuseDir: reusableProviders,
            reuseDirIsOwnRevision: reuseSource.hasPrefix("own"),
            replacing: previousRuntime,
            fetchBudget: activationFetchBudget,
            source: storedSourceYAML
        ).pointer
        ProviderFirstLoadRetry.noteActivation(
            pending: firstLoadPendingOfLastPublication, profileID: profile.id
        )

         
         
         
        ProfileStore.withWriteLock {
            recordRevision(pointer, of: profile)
            if !sourceIsStoredSidecar,
               !FileManager.default.fileExists(atPath: sidecarURL(profileID: profile.id).path) {
                 
                 
                 
                 
                try? writeSourceSidecar(storedSourceYAML, profileID: profile.id)
            }
        }
        return pointer
    }

     
     
     
     
     
    @discardableResult
    func refreshProvider(
        named name: String, profile given: Profile,
        fetchBudget: ProviderFetchBudget = .patient
    ) async throws -> ProviderRefreshResult {
        try prepareCore()
        let (inUse, profile) = try inUseAndOnDisk(given)
        guard let raw = try? String(contentsOf: sidecarURL(profileID: profile.id),
                                    encoding: .utf8) else {
            throw PipelineError.sourceUnavailable(
                "profile '\(profile.label)' has no cached source; update the profile once first")
        }
         
        try ConfigTransforms.validateSource(raw)
        let merged = try prepareConfig(raw: raw, profile: profile)

         
         
        let reuseDir = store.providersDirectory(profileID: inUse.profileID, revision: inUse.revision)

        let publication = try await buildPublishActivate(
            profile: profile, merged: merged,
            reuseDir: reuseDir, forceRefresh: [name],
            replacing: inUse,
            fetchBudget: fetchBudget,
            source: raw)
        recordRevision(publication.pointer, of: profile)
        announceProviderContent(of: profile)
        return ProviderRefreshResult(
            pointer: publication.pointer,
            runtimeUpdate: publication.runtimeUpdates[name]
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
    func providerRetryCatalog(profile given: Profile) throws -> ProviderCatalog {
        let profile = onDisk(given)
        let raw = try String(contentsOf: sidecarURL(profileID: profile.id), encoding: .utf8)
        let (merged, root) = try prepareConfigReading(raw: raw, profile: profile)
         
         
        let ownUserAgent = ClientUserAgent.written(in: root)
        let plan = try ConfigTransforms.planResources(mergedYAML: merged)
            .carrying(userAgent: ClientUserAgent.choice(ownUserAgent, identity: downloadIdentity()))
        guard plan.errors.isEmpty else { throw PipelineError.planRejected(plan.errors) }
        return ProviderCatalog.from(plan: plan,
            routeSetProviders: try ConfigTransforms.routeSetProviderNames(mergedYAML: merged),
            userAgent: ownUserAgent ?? "")
    }

     
     
    func coreOwnedRouteRecoveryNames(profile given: Profile, current: ActiveConfigurationPointer) throws -> Set<String> {
        let profile = onDisk(given)
        guard current.profileID == profile.id,
              let directory = store.providersDirectory(profileID: current.profileID, revision: current.revision) else { return [] }
        let catalog = ProviderCatalog.load(providersDir: directory)
        if let catalog, let routes = catalog.routeSetProviders, let coreFetched = catalog.coreFetchedProviders,
           routes.isDisjoint(with: coreFetched) { return [] }
        let adopted = catalog?.coreRouteSeeds ?? []
        let raw = try String(contentsOf: sidecarURL(profileID: profile.id), encoding: .utf8)
        let merged = try prepareConfig(raw: raw, profile: profile)
        let plan = try ConfigTransforms.planResources(mergedYAML: merged)
        let names = try ConfigTransforms.routeSetProviderNames(mergedYAML: merged)
        let cache = try CoreOwnedRouteCache(mergedYAML: merged, plan: plan, routeSetProviders: names,
            profileID: profile.id, workingDirectory: coreHomeDir)
        guard !cache.paths.isEmpty else { return [] }
        let yaml = try store.loadConfiguration(profileID: current.profileID, revision: current.revision).text ?? ""
        let json = try ConfigTransforms.yamlToJSON(yaml)
        let root = try ConfigTransforms.jsonObject(json) as? [String: Any] ?? [:]
        let definitions = root["rule-providers"] as? [String: [String: Any]] ?? [:]
        return Set(plan.providers.compactMap { provider -> String? in
            guard let path = cache.paths[provider.name], provider.kind == "rule" else { return nil }
            let definition = definitions[provider.name]
             
             
             
             
            if !adopted.contains(provider.name), definition?["type"] as? String == "file",
               definition?["path"] as? String == directory.appendingPathComponent(provider.path).path { return nil }
             
             
             
             
            let written = (definition?["x-clash-refresh"] as? [String: Any])?["legacy-path"] as? String
                ?? definition?["path"] as? String
            if written != path { return provider.name }
            guard let bytes = cache.snapshots[provider.name] else { return nil }
            let old = try? Data(contentsOf: directory.appendingPathComponent(provider.path))
            return old == bytes ? nil : provider.name
        })
    }

    func refreshPendingProviders(
        profile given: Profile, names: [String], fetchBudget: ProviderFetchBudget,
        expectedActive: ActiveConfigurationPointer? = nil
    ) async throws -> (pointer: ActiveConfigurationPointer,
                       runtimeUpdates: [String: ProviderRuntimeUpdate],
                       stillPending: [String], publishedRouteNames: Set<String>) {
        try prepareCore()
        let (current, profile) = try inUseAndOnDisk(given, expected: expectedActive)
        guard current.profileID == profile.id else {
            throw ConfigResourceStoreError.activeConfigurationChanged
        }
        let expected = expectedActive ?? current
        guard let raw = try? String(contentsOf: sidecarURL(profileID: profile.id),
                                    encoding: .utf8) else {
            throw PipelineError.sourceUnavailable(
                "profile '\(profile.label)' has no cached source; update the profile once first")
        }
        try ConfigTransforms.validateSource(raw)
        let merged = try prepareConfig(raw: raw, profile: profile)
        let reuseDir = try store.providersDirectory(profileID: expected.profileID, revision: expected.revision)
        let publication = try await buildPublishActivate(
            profile: profile, merged: merged,
            reuseDir: reuseDir,
            replacing: expected,
            fetchBudget: fetchBudget,
            fetchOnly: Set(names),
            capturePayloads: Set(names),
            source: raw,
            overTheCatalogItRead: true)
         
         
        recordRevision(publication.pointer, of: profile)
        announceProviderContent(of: profile)
        return (publication.pointer,
                publication.runtimeUpdates.filter { names.contains($0.key) },
                publication.firstLoadPending.filter { names.contains($0) },
                publication.publishedRouteNames.intersection(names))
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func refreshProviders(
        named names: [String],
        profile given: Profile,
        fetchBudget: ProviderFetchBudget = .patient,
        expectedActive: ActiveConfigurationPointer? = nil,
        downloadRound: ProviderDownloadRound? = nil,
        scripts caller: ScriptEngine.Caller = .surfaced
    ) async throws -> (pointer: ActiveConfigurationPointer,
                       runtimeUpdates: [String: ProviderRuntimeUpdate]) {
        try prepareCore()
        let (inUse, profile) = try inUseAndOnDisk(given, expected: expectedActive)
        guard let raw = try? String(contentsOf: sidecarURL(profileID: profile.id),
                                    encoding: .utf8) else {
            throw PipelineError.sourceUnavailable(
                "profile '\(profile.label)' has no cached source; update the profile once first")
        }
        try ConfigTransforms.validateSource(raw)
        let merged = try prepareConfig(raw: raw, profile: profile, scripts: caller)
        let reuseDir = store.providersDirectory(profileID: inUse.profileID, revision: inUse.revision)
        let publication = try await buildPublishActivate(
            profile: profile, merged: merged,
            reuseDir: reuseDir, forceRefresh: Set(names),
            replacing: inUse,
            fetchBudget: fetchBudget,
            downloadRound: downloadRound,
            source: raw,
            overTheCatalogItRead: true)
        recordRevision(publication.pointer, of: profile)
        announceProviderContent(of: profile)
        return (publication.pointer,
                publication.runtimeUpdates.filter { names.contains($0.key) })
    }

    @discardableResult
    func sideLoadProvider(
        named name: String,
        data: Data,
        profile given: Profile
    ) async throws -> ProviderRefreshResult {
        try prepareCore()
        let (inUse, profile) = try inUseAndOnDisk(given)
        guard let raw = try? String(
            contentsOf: sidecarURL(profileID: profile.id),
            encoding: .utf8
        ) else {
            throw PipelineError.sourceUnavailable(
                "profile '\(profile.label)' has no cached source; update the profile once first"
            )
        }
         
        try ConfigTransforms.validateSource(raw)
         
         
        let merged = try prepareConfig(raw: raw, profile: profile, scripts: .surfaced)
        let reuseDir = store.providersDirectory(profileID: inUse.profileID, revision: inUse.revision)
        let publication = try await buildPublishActivate(
            profile: profile,
            merged: merged,
            reuseDir: reuseDir,
            providerOverrides: [name: data],
            replacing: inUse,
            source: raw
        )
        recordRevision(publication.pointer, of: profile)
        announceProviderContent(of: profile)
        return ProviderRefreshResult(
            pointer: publication.pointer,
            runtimeUpdate: publication.runtimeUpdates[name]
        )
    }

     
     
     
     
     
     
     
     
     
     
    private var lastProviderMerge = ProviderDefinitionMergeReport()
     
     
    private var lastProfileLogLevel: String?
     
     
    private var lastLogLevelSetByApp = false
    private var lastModeSetByApp = false
     
     
    private var lastListenerKeysSetByApp: Set<String> = []
     
    private let logDefaults: UserDefaults

     
     
     
    private func prepareConfig(raw: String, profile: Profile,
                               scripts caller: ScriptEngine.Caller = .silent) throws -> String {
        try prepareConfigReading(handed: HandedSource(raw), profile: profile, scripts: caller).yaml
    }

     
     
     
     
     
     
     
    private func presentationInputs(source: PublishedSourceDigest?, profile: Profile) -> String? {
        guard let source else { return nil }
        var settings = PublishedPresentation.Settings.live()
        settings.global = globalOverride()
        settings.runtime = runtimeOverride()
        return PublishedPresentation.inputs(sourcePrefix: source.presentationPrefix, profile: profile, settings: settings)
    }

     
     
     
     
     
    private func prepareConfigReading(raw: String, profile: Profile) throws -> (yaml: String, root: [String: Any]?) {
        try prepareConfigReading(handed: HandedSource(raw), profile: profile, scripts: .silent)
    }

     
     
     
    private func prepareConfigReading(handed: HandedSource, profile: Profile,
                                      scripts caller: ScriptEngine.Caller) throws -> (yaml: String, root: [String: Any]?) {
        var laps = PerfLedger.Laps()
        let libraryScript: (String?, String, String) throws -> String = {
            try ScriptLibrary.apply(id: $0, to: $1, profileName: $2, caller: caller)
        }
        let appWideScript: (String, String) throws -> String = {
            try ScriptSettings.apply(toConfigYAML: $0, profileName: $1, caller: caller)
        }
         
         
         
        let stages = try autoreleasepool { try ProfileRuntimeConfigBuilder.buildStages(
            raw: handed.take() ?? "",
            profile: profile,
            globalOverride: globalOverride(),
            runtimeOverride: runtimeOverride(),
            profileScript: profileScript ?? libraryScript,
            configScript: configScript ?? appWideScript,
             
             
             
             
             
             
             
             
             
            postMergeScript: postMergeScript ?? libraryScript,
            logLevelDirective: ClashLogSettings.levelDirective(from: logDefaults)
        ) }
        lastProviderMerge = stages.providerMerge
        lastProfileLogLevel = stages.profileLogLevel
        lastLogLevelSetByApp = stages.logLevelSetByApp
        lastModeSetByApp = stages.modeSetByApp
        lastListenerKeysSetByApp = Set(ProfileRuntimeConfigBuilder.lanSharingListener(of: profile).topLevelKeys)
         
         
        AppCore.returnFreeMemoryNow(after: stages.beforeClientRuntimePolicy)
        laps.mark("prepare.chain")
         
         
        let (runtime, root) = try ProfileRuntimeConfigBuilder.finishedReading(stages)
        laps.mark("prepare.policy")
        laps.mark("prepare.read")
        noteExternalResources(in: root, profile: profile)
        laps.mark("prepare.noteResources")
         
         
         
         
         
        let page = ProfileRuntimeConfigBuilder.lanSharingListener(of: profile)
        for key in stages.listenerWrittenBack {
            let value = page.topLevelNode(key)?.serialized() ?? ""
             
            ClashLogStore.shared.append(
                #"\#(key) ran otherwise after the scripts; it runs as LAN Sharing set it (\#(value))"#,
                stream: .app, level: .info)
        }
        return (runtime, root)
    }

     
     
     
     
     
     
     
    static func providerAgeSecretKeys(in mergedYAML: String) throws -> [String: String] {
         
         
        try ConfigTransforms.providerAgeSecretKeys(mergedYAML: mergedYAML)
    }

     
     
     
     
     
     
     
     
     
     
     
    private func noteExternalResources(in runtimeRoot: [String: Any]?, profile: Profile) {
        guard let runtimeRoot else { return }
        let source: IOSExternalResourceSource
        switch profile.source {
        case .url: source = .subscription
        case .file: source = .localFile
        case .clipboard: source = .clipboard
        }
         
         
        let requirements = IOSExternalResourceCatalog.requirements(root: runtimeRoot)
        var externalResources = IOSExternalResourceCatalog.inspect(
            root: runtimeRoot,
            source: source,
            requirements: requirements
        )
         
         
        externalResources.removeAll { $0.resolution == .managedRuntimeStateRequired }
        let references = profile.externalResources ?? []
        var allowed: [String: Int] = [:]
        for requirement in requirements
        where requirement.capability.disposition == .publicFileOrInline {
            let digest = ProfileExternalResourceImporter.sha256(
                Data(requirement.rawValue.utf8)
            )
            if references.contains(where: {
                $0.capabilityID == requirement.capability.id
                    && $0.proxy == requirement.proxyName
                    && $0.fieldPath == requirement.capability.fieldPath
                    && $0.sourceValueSHA256 == digest
            }) {
                allowed[requirement.capability.id, default: 0] += 1
            }
        }
        externalResources.removeAll { finding in
            guard (finding.resolution == .localImportRequired
                    || finding.resolution == .subscriptionCannotReadFile),
                  let count = allowed[finding.capabilityID], count > 0 else {
                return false
            }
            allowed[finding.capabilityID] = count - 1
            return true
        }
        for finding in externalResources {
            log("external resource left to the kernel  id=\(profile.id) capability=\(finding.capabilityID) resolution=\(finding.resolution)")
        }
    }

     
     
     
     
     
     
     
     
     
     
     
    private func reusableProvidersDirectory(for profile: Profile) -> (URL?, String) {
         
         
         
         
         
        let recorded = profileStore.load().first { $0.id == profile.id }?.activeRevision
        for revision in [recorded, profile.activeRevision].compactMap({ $0 }) {
            if let own = store.providersDirectory(profileID: profile.id, revision: revision),
               FileManager.default.fileExists(atPath: own.path) {
                return (own, "own(\(fileCount(in: own)))")
            }
        }
        if let newest = store.newestProvidersDirectory(profileID: profile.id) {
            return (newest, "newest(\(fileCount(in: newest)))")
        }
        if let active = try? store.activeProvidersDirectory() {
            return (active, "active(\(fileCount(in: active)))")
        }
        return (nil, "none")
    }

    private func fileCount(in directory: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.count ?? -1
    }

    private func buildPublishActivate(
        profile: Profile, merged: String,
         
         
        mergedRoot: [String: Any]? = nil,
         
         
        heldRoot: ConfigTransforms.HeldRoot? = nil,
        reuseDir: URL? = nil,
        reuseDirIsOwnRevision: Bool = true,
        forceRefresh: Set<String> = [],
        providerOverrides: [String: Data] = [:],
        replacing previousRuntime: ActiveConfigurationPointer? = nil,
        fetchBudget: ProviderFetchBudget = .patient,
         
         
         
         
        fetchOnly: Set<String>? = nil,
        capturePayloads: Set<String> = [],
         
         
         
        beforePublish: (() throws -> Void)? = nil,
        downloadRound: ProviderDownloadRound? = nil,
         
        source: String? = nil,
         
        sourceDigest: PublishedSourceDigest? = nil,
         
         
         
         
        overTheCatalogItRead: Bool = false
    ) async throws -> ProfilePublicationResult {
        var laps = PerfLedger.Laps()
         
         
         
         
        let sourceDigest = sourceDigest ?? source.map(PublishedSourceDigest.init)
        let presentationAtStart = presentationInputs(source: sourceDigest, profile: profile)
         
         
        let catalogAsRead = overTheCatalogItRead ? previousRuntime.map { store.catalogData(of: $0) } : nil
        let candidate = try store.beginCandidate(profileID: profile.id)
        let previous: ActiveConfigurationPointer?
         
        var unchanged: ActiveConfigurationPointer?
        var publishedPreflight: PreflightOutcome?
        var publishedNotices: [String]?
        var publishedModule: ModulePublication?
         
         
        var heldEngine: String?
        let modulesLocations = ModuleLocations(container: coreHomeDir.deletingLastPathComponent())
         
         
        var recordedCandidate: ActiveConfigurationPointer?
         
         
        var readinessAsked: ModuleEngineReadinessSource.Asked?
        var composedFromModules: String?
         
         
        var rulesAsWritten: String?
        var runtimeUpdates: [String: ProviderRuntimeUpdate] = [:]
        var firstLoadPending: [String] = []
        var publishedRouteNames: Set<String> = []
        do {
            let materializedMerged = try ProfileExternalResourceMaterializer.materialize(
                yaml: merged,
                root: mergedRoot ?? heldRoot?.value,
                profile: profile,
                coreHomeDir: coreHomeDir,
                candidate: candidate
            )
            laps.mark("publish.materialize")
             
             
             
             
             
             
             
             
            let (ageSecretKeys, routeSetProviders, ownUserAgent) = try {
                () throws -> ([String: String], Set<String>, String?) in
                let root = mergedRoot ?? heldRoot?.value
                let materializedRoot = (root != nil && materializedMerged == merged)
                    ? root : try ConfigTransforms.foundationRoot(ofYAML: materializedMerged)
                 
                 
                return (ConfigTransforms.providerAgeSecretKeys(root: materializedRoot),
                        ConfigTransforms.routeSetProviderNames(root: materializedRoot),
                        ClientUserAgent.written(in: materializedRoot))
            }()
             
             
             
             
            let identity = downloadIdentity()
            let userAgent = ownUserAgent ?? identity
            heldRoot?.release()
             
             
            AppCore.returnFreeMemoryNow(after: materializedMerged)
            laps.mark("publish.readPlanned")
             
             
             
            let runtimeFile = try ConfigTransforms.CoreTextFile.make(materializedMerged,
                                                                     sourceAt: sidecarURL(profileID: profile.id))


             
             
             
            let plan = try (runtimeFile.map { try ConfigTransforms.planResources(atPath: $0.url) }
                ?? ConfigTransforms.planResources(mergedYAML: materializedMerged))
                .carrying(userAgent: ClientUserAgent.choice(ownUserAgent, identity: identity))
             
             
             
             
            laps.mark("publish.plan")
            guard plan.errors.isEmpty else {
                throw PipelineError.planRejected(plan.errors)
            }
            let coreRouteCache = try CoreOwnedRouteCache(
                mergedYAML: materializedMerged, plan: plan, routeSetProviders: routeSetProviders,
                profileID: profile.id, workingDirectory: coreHomeDir)
            var reusedCoreFilePaths: Set<String> = []
            if fetchOnly != nil, plan.providers.contains(where: { ProviderFetchedByCore.applies(toProxy: $0.proxy) }),
               let previousRuntime, let reuseDir,
               let previousYAML = try store.loadConfiguration(
                    profileID: previousRuntime.profileID, revision: previousRuntime.revision).text {
                let json = try ConfigTransforms.yamlToJSON(previousYAML)
                let root = try ConfigTransforms.jsonObject(json) as? [String: Any] ?? [:]
                 
                 
                let adopted = ProviderCatalog.load(providersDir: reuseDir)?.coreRouteSeeds ?? []
                 
                 
                 
                reusedCoreFilePaths = Set(plan.providers.compactMap { provider in
                    guard ProviderFetchedByCore.applies(toProxy: provider.proxy),
                          !adopted.contains(provider.name) else { return nil }
                    let section = provider.kind == "rule" ? "rule-providers" : "proxy-providers"
                    let definition = (root[section] as? [String: [String: Any]])?[provider.name]
                    guard definition?["type"] as? String == "file",
                          definition?["path"] as? String == reuseDir.appendingPathComponent(provider.path).path
                    else { return nil }
                    return provider.path
                })
            }
             
             
             
             
             
            for provider in plan.providers where provider.kind == "proxy" {
                if let resourceKey = provider.resourceKey {
                    try? credentials.remove("provider.age.\(profile.id).\(resourceKey)")
                }
            }
            let requestedProviders = forceRefresh.union(Set(providerOverrides.keys)).union(capturePayloads)
            for name in requestedProviders
            where !plan.providers.contains(where: { $0.name == name }) {
                throw PipelineError.providerNotFound(name)
            }
            let stages = ActivationStopwatch()
            let libraryFiles = ConfigurationCollectionContentBridge.cachedLibraryFiles(
                for: plan.providers, workingDirectory: coreHomeDir)
            let materialized = try await materializer.materializeDetailed(
                plan: plan,
                into: candidate.stagingProvidersDirectory,
                publishedProvidersDir: candidate.publishedProvidersDirectory,
                maxBytesEach: Self.maxProviderBytes,
                reuseDir: reuseDir,
                reuseDirIsOwnRevision: reuseDirIsOwnRevision,
                forceRefresh: forceRefresh,
                ageSecretKeys: ageSecretKeys,
                localOverrides: providerOverrides,
                cachedNodeFiles: libraryFiles.nodes,
                cachedRuleFiles: libraryFiles.rules,
                captureRefreshedPayloads: requestedProviders,
                userAgent: userAgent,
                routeSetProviders: routeSetProviders,
                coreRouteSnapshots: coreRouteCache.snapshots,
                coreRouteDates: coreRouteCache.dates,
                reusedCoreFilePaths: reusedCoreFilePaths,
                fetchOnly: fetchOnly,
                fetchBudget: fetchBudget,
                payloadStore: store.payloadStore,
                downloadRound: downloadRound
            )
             
             
             
             
             
            ConfigurationCollectionContentBridge.keepInLibrary(plan.providers.compactMap { provider in
                guard provider.kind == "proxy", materialized.downloadedNames.contains(provider.name),
                      let path = materialized.readPaths[provider.name] else { return nil }
                return (provider, URL(fileURLWithPath: path), materialized.entryCounts[provider.name] ?? 0,
                        materialized.subscriptionUserInfo[provider.name].flatMap { SubscriptionInfo.parse(header: $0) }
                            .map(ConfigurationCenterSourceBridge.subscriptionUsage))
            }, userAgent: ownUserAgent, identity: identity, workingDirectory: coreHomeDir)
            firstLoadPending = materialized.firstLoadPending
            firstLoadPendingOfLastPublication = firstLoadPending
            publishedRouteNames = Set(plan.providers.filter {
                $0.kind == "rule" && $0.behavior.lowercased() == "ipcidr"
                    && routeSetProviders.contains($0.name) && materialized.readPaths[$0.name] != nil
            }.map(\.name))
            let providerPaths = materialized.paths
             
             
             
             
             
             
             
            let providerKinds = Dictionary(
                plan.providers.map { ($0.name, $0.kind) },
                uniquingKeysWith: { first, _ in first }
            )
            runtimeUpdates = Dictionary(
                uniqueKeysWithValues: materialized.refreshedPayloads.compactMap { name, payload in
                    guard let kind = providerKinds[name] else { return nil }
                    return (name, ProviderRuntimeUpdate(
                        name: name, kind: kind, payload: payload,
                        publishedIn: ActiveConfigurationPointer(profileID: profile.id, revision: candidate.revision)))
                }
            )
             
             
             
             
             
             
             
            let providerReadPaths = materialized.readPaths
             
             
            let reusedEntries = reuseDir.flatMap {
                ProviderCatalog.load(providersDir: $0)
            }?.entries ?? []
            var subscriptionInfo = Dictionary(
                reusedEntries
                    .compactMap { entry in
                        entry.subscriptionInfo.map { (entry.name, $0) }
                    },
                uniquingKeysWith: { first, _ in first }
            )
            var lastUpdatedAt: [String: Date] = [:]
            for entry in reusedEntries {
                if let timestamp = entry.lastUpdatedAt {
                    lastUpdatedAt[entry.name] = timestamp
                } else if let reuseDir,
                          let attributes = try? FileManager.default.attributesOfItem(
                            atPath: reuseDir.appendingPathComponent(entry.path).path
                          ),
                          let timestamp = attributes[.modificationDate] as? Date {
                     
                     
                    lastUpdatedAt[entry.name] = timestamp
                }
            }
             
             
             
             
             
            for name in materialized.firstLoadPending { lastUpdatedAt.removeValue(forKey: name) }
            let refreshedAt = now()
            for name in materialized.refreshedNames {
                 
                 
                lastUpdatedAt[name] = materialized.libraryCopyDates[name] ?? refreshedAt
                 
                guard materialized.libraryCopyDates[name] == nil else { continue }
                subscriptionInfo.removeValue(forKey: name)
                if let header = materialized.subscriptionUserInfo[name],
                   let parsed = SubscriptionInfo.parse(header: header) {
                    subscriptionInfo[name] = parsed
                }
            }
             
             
             
             
             
             
            for name in materialized.libraryCopyDates.keys {
                if let usage = libraryFiles.nodeUsage[name] { subscriptionInfo[name] = usage }
            }
             
             
             
             
             
             
             
             
            if let state = ProviderRefreshState.read(workingDirectory: coreHomeDir) {
                for provider in plan.providers where provider.kind == "proxy"
                    && !materialized.firstLoadPending.contains(provider.name) {
                    if let newer = state.newerEntry(kind: provider.kind, name: provider.name, url: provider.url,
                                                    than: lastUpdatedAt[provider.name]),
                       let usage = newer.usage {
                        subscriptionInfo[provider.name] = usage
                    }
                }
            }
            try ProviderCatalog.from(
                plan: plan,
                entryCounts: materialized.entryCounts,
                subscriptionInfo: subscriptionInfo,
                lastUpdatedAt: lastUpdatedAt,
                notes: Dictionary(
                    materialized.validationWarnings.map { ($0.provider, $0.note) },
                    uniquingKeysWith: { first, _ in first }
                ),
                 
                 
                notedAt: Dictionary(
                    materialized.validationWarnings.map { ($0.provider, $0.notedAt ?? refreshedAt) },
                    uniquingKeysWith: { first, _ in first }
                ),
                payloadSourceURLs: materialized.payloadSourceURLs,
                payloadRequests: materialized.payloadRequests,
                acquiredAt: materialized.acquiredAt,
                routeSetProviders: routeSetProviders,
                coreRouteSeeds: materialized.coreRouteSeeds,
                seedPaths: materialized.seedPaths,
                 
                userAgent: ownUserAgent ?? ""
            ).write(providersDir: candidate.stagingProvidersDirectory)
            stages.mark(
                "providers",
                count: plan.providers.count,
                detail: "reused=\(materialized.reusedCount) fetched=\(materialized.fetchedCount) "
                    + "from=\(activationReuseSource)"
                     
                     
                     
                    + (materialized.staleFallbacks.isEmpty
                        ? ""
                        : " kept-old=\(materialized.staleFallbacks.count)")
            )
             
             
             
            try await geodata.stage(
                plan: plan,
                homeDir: coreHomeDir,
                maxBytesEach: Self.maxGeodataBytes,
                preferBundled: true,
                reuseExisting: true
            )

            stages.mark("geodata")
            laps.mark("publish.providers")
             
             
             
             
             
             
             
             
             
             
            var seeds = ConfigTransforms.ProviderSeedFacts()
            for provider in plan.providers {
                let key = provider.kind + ":" + provider.name
                if let at = materialized.acquiredAt[provider.path] { seeds.fetchedAt[key] = Int64(at.timeIntervalSince1970) }
                if provider.kind == "proxy", let info = materialized.subscriptionUserInfo[provider.name] {
                    seeds.subscriptionInfo[key] = info
                }
            }
             
             
             
             
             
             
             
            let nodeLibraryDirectory = writesNodeLibrary
                ? NodeLibraries.directory(container: coreHomeDir.deletingLastPathComponent())
                : nil
            let ruleIndexDirectory = nodeLibraryDirectory
             
             
            let finalizedFile = ConfigTransforms.sameText(coreRouteCache.runtimeYAML, materializedMerged) ? runtimeFile : nil
            let orderReference = Self.finalizeOrderReference
                && !ConfigTransforms.sameText(coreRouteCache.runtimeYAML, merged) ? merged : nil
            let orderReferenceFile = orderReference.map { ConfigTransforms.sameText($0, materializedMerged) } == true
                ? runtimeFile : nil
             
             
             
             
            let heapGivenBack = !materialized.downloadedNames.isEmpty || !materialized.refreshedNames.isEmpty
            if heapGivenBack {
                AppCore.returnFreeMemoryNow(after: materializedMerged)
            }
             
             
             
             
             
             
             
             
             
             
            let seedFacts = seeds
            let runtimeYAML = coreRouteCache.runtimeYAML
            let finalizeText = { (mergedYAML: String, handover: ModuleFinalizeHandover) throws -> FinalizedText in
                let prependRules = handover.prependRules
                let ruleProviders = handover.ruleSets?.definitions
                let file = ConfigTransforms.sameText(mergedYAML, runtimeYAML) ? finalizedFile : nil
                 
                 
                if Self.givesTheHeapBack(planReadAFile: runtimeFile != nil, finalizesThatFile: file != nil,
                                         givenBackAfterDownloads: heapGivenBack) {
                    AppCore.returnFreeMemoryNow(after: mergedYAML)
                }
                var publication: ConfigTransforms.FinalizedPublication
                var setUpRefused = false
                if self.preflightIsCallers {
                    var text = try file.map {
                        try ConfigTransforms.finalize(atPath: $0.url, providerPaths: providerPaths,
                                                      providerReadPaths: providerReadPaths, seeds: seedFacts,
                                                      nodeLibraryDirectory: nodeLibraryDirectory,
                                                      ruleIndexDirectory: ruleIndexDirectory, prependRules: prependRules,
                                                      ruleProviders: ruleProviders)
                    } ?? ConfigTransforms.finalize(
                        mergedYAML: mergedYAML,
                        providerPaths: providerPaths,
                        providerReadPaths: providerReadPaths,
                        seeds: seedFacts,
                        nodeLibraryDirectory: nodeLibraryDirectory,
                        ruleIndexDirectory: ruleIndexDirectory,
                        prependRules: prependRules,
                        ruleProviders: ruleProviders)
                    try ConfigTransforms.carryGlobalUA(identity, into: &text,
                                                       beforeGrowing: { AppCore.returnFreeMemoryNow(after: mergedYAML) })
                    publication = .init(text: text, preflight: self.preflight(text), geodataMode: nil,
                                        listenerPorts: nil, listenerPortsAnswered: false, notices: nil)
                } else {
                    publication = try ConfigTransforms.finalizeForPublication(
                        mergedYAML: mergedYAML,
                        providerPaths: providerPaths,
                        providerReadPaths: providerReadPaths,
                        seeds: seedFacts,
                         
                         
                         
                         
                        orderReference: orderReference,
                        container: self.intentContainer,
                        settings: self.intentSettings,
                        nodeLibraryDirectory: nodeLibraryDirectory,
                        ruleIndexDirectory: ruleIndexDirectory,
                        mergedPath: file?.url,
                        orderReferencePath: orderReferenceFile?.url,
                        prependRules: prependRules,
                        ruleProviders: ruleProviders)
                     
                     
                     
                    setUpRefused = !publication.preflight.ok && !publication.listenerPortsAnswered
                }
                 
                if !self.preflightIsCallers {
                    try Self.carryGlobalUA(identity, into: &publication, givingBackAfter: mergedYAML)
                }
                 
                 
                 
                 
                let rulesAsWritten = publication.preflight.ok && ConfigTransforms.ruleIndexPath(in: publication.text) != nil
                    ? PublishedRulesAsWritten.section(ofFinalized: mergedYAML, prepending: prependRules ?? []) : nil
                return FinalizedText(publication: publication, setUpRefused: setUpRefused, rulesAsWritten: rulesAsWritten)
            }
             
             
             
            composedFromModules = ModulePublicationRecord.manifestDigest(locations: modulesLocations)
             
             
             
             
            let stripped = ModuleActivationStep.strippingAnEarlierEngine(coreRouteCache.runtimeYAML)
            if !stripped.removed.isEmpty {
                log(#"modules: a published configuration fed back, an earlier engine's entries taken out: "#
                    + stripped.removed.joined(separator: ", ") + (stripped.heldInALibrary ? #"; its node stays in the library, hidden"# : ""))
            }
            heldEngine = stripped.heldInALibrary ? stripped.engineName : nil
            let finalized = try await finalizeCarryingModule(
                stripped.text, ruleIndexDirectory: ruleIndexDirectory,
                candidate: ActiveConfigurationPointer(profileID: profile.id, revision: candidate.revision),
                asked: &readinessAsked, laps: &laps, finalize: finalizeText)
            let publication = finalized.publication
            publishedModule = finalized.modules
            recordedCandidate = finalized.recordedFor
            rulesAsWritten = finalized.rulesAsWritten
             
             
            let finalYAML = publication.text
             
             
            AppCore.returnFreeMemoryNow(after: coreRouteCache.runtimeYAML)

            stages.mark("finalize")
            laps.mark("publish.finalize")
            let outcome = publication.preflight
            stages.mark("preflight")
            laps.mark("publish.preflight")
            guard outcome.ok else {
                throw PipelineError.preflightFailed(outcome.errorMessage ?? "preflight failed")
            }
            publishedPreflight = outcome
             
             
             
            publishedNotices = publication.notices.map { $0.filter { !ModuleRuleSetSyntax.isModuleNotice($0) } }

             
             
             
             
             
             
             
             
             
             
            GeoSiteCompiler.prepare(finalYAML: finalYAML)
             
             
             
             
             
             
            GeoSiteCompiler.prepareRulePayloads(
                in: candidate.stagingProvidersDirectory,
                plan: plan,
                readPaths: materialized.seedPaths
            )
             
             
             
             
             
             
             
             
             
             
             
             
             
            let geodataMode = publication.geodataMode ?? GeoIPCompiler.geodataModeEnabled(in: finalYAML)
            GeoIPCompiler.prepare(finalYAML: finalYAML, geodataMode: geodataMode)
            GeoIPCompiler.prepareRulePayloads(
                in: candidate.stagingProvidersDirectory,
                plan: plan,
                geodataMode: geodataMode,
                readPaths: materialized.seedPaths
            )
            stages.mark("geosite")
            stages.report()
            laps.mark("publish.compileCaches")

             
             
             
             
            let store = self.store
            let finalData = Data(finalYAML.utf8)
            let expectation: ConfigResourceStore.ActiveExpectation = previousRuntime.map { previous in
                catalogAsRead.map { .matchesWithCatalog(previous, catalog: $0) } ?? .matches(previous)
            } ?? .unconstrained
            if let inUse = store.adoptIfEquivalentToActive(
                candidate, finalData: finalData, expectation: expectation) {
                 
                 
                 
                 
                 
                 
                if let beforePublish { try ProfileStore.withWriteLock { try beforePublish() } }
                try? store.discard(candidate)
                previous = inUse
                unchanged = inUse
                 
                 
                 
                if let recorded = recordedCandidate, let assignment = finalized.modules?.engineAssignment {
                    refreshEnginePlan(assignment, inUse: inUse, candidate: recorded)
                }
                recordedCandidate = nil
                 
                 
                 
                 
                 
                 
                if finalized.finalizedUnpublished, nodeLibraryDirectory != nil {
                    NodeLibraries.prune(container: coreHomeDir.deletingLastPathComponent())
                }
                laps.mark("publish.unchanged")
                ClashLogSettings.setActiveProfileLogLevel(lastProfileLogLevel, in: logDefaults)
                 
                 
                 
                 
                let inUseText = (try? store.loadConfiguration(profileID: inUse.profileID, revision: inUse.revision).text)
                    ?? finalYAML.replacingOccurrences(of: candidate.revision, with: inUse.revision)
                compileUnchanged(finalYAML: inUseText, providerCount: plan.providers.count)
                AppCore.returnFreeMemory()
            } else {
                let staged = try store.stage(candidate, finalData: finalData)
                do {
                    if let beforePublish {
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                        var activated: ActiveConfigurationPointer??
                        for _ in 0..<200 where activated == nil {
                            activated = try ProfileStore.withWriteLock { () -> ActiveConfigurationPointer?? in
                                try beforePublish()
                                switch try store.activateStagedIfLockFree(staged, expectation: expectation) {
                                case .activated(let before): return .some(before)
                                case .busy: return nil
                                }
                            }
                            if activated == nil { try store.waitUntilLockIsFree() }
                        }
                        guard let settled = activated else { throw ConfigResourceStoreError.lockTimedOut }
                        previous = settled
                    } else {
                        previous = try store.activateStaged(staged, expectation: expectation)
                    }
                } catch {
                    store.discardStaged(staged)
                    throw error
                }
                store.finishActivation(staged)
                laps.mark("publish.stage")
                 
                 
                 
                NodeLibraries.prune(container: coreHomeDir.deletingLastPathComponent())
                 
                 
                 
                ClashLogSettings.setActiveProfileLogLevel(lastProfileLogLevel, in: logDefaults)
                 
                 
                 
                 
                 
                 
                 
                publishStaging(finalYAML: finalYAML, providerCount: plan.providers.count)
                laps.mark("publish.listenersAndStaging")
                 
                 
                AppCore.returnFreeMemory()
                 
                 
                 
                 
                if let intentJSON = outcome.intentJSON {
                    PublishedTunIntent.publish(
                        intentJSON: intentJSON,
                        defaults: UserDefaults(suiteName: ClashAppIdentifiers.defaultsSuite)
                    )
                }
            }
        } catch {
             
            try? store.discard(candidate)
            if let recordedCandidate { forgetEnginePlan(of: recordedCandidate) }
            throw error
        }

        defer { laps.mark("publish.activator") }
        do {
            try activator(store.activeConfigURL)
        } catch {
             
             
             
             
             
            do {
                try store.restoreActive(previous)
            } catch {
                _ = try? store.recoverCurrentFromLastKnownGood()
            }
            if let recordedCandidate { forgetEnginePlan(of: recordedCandidate) }
            throw error
        }

        let published = unchanged ?? ActiveConfigurationPointer(profileID: profile.id, revision: candidate.revision)
         
         
        if let recordedCandidate {
            ModuleEnginePlan.settle(ModuleRunningRevision(profileID: recordedCandidate.profileID, revision: recordedCandidate.revision))
        }
         
         
        if publishedModule?.record == nil { pruneEnginePlans(published: published, previous: previous) }
         
         
        if modulesFromReadiness {
            ModuleEngineReadinessSource.shared(coreHomeDir.deletingLastPathComponent()).confirm(readinessAsked)
        }
        PublishedSourceLedger.record(published, digest: sourceDigest?.ledger)
        PublishedRulesAsWritten.record(published, section: rulesAsWritten, workingDirectory: coreHomeDir)
         
         
         
         
         
         
         
        ModulePublicationRecord.store(
            ModulePublicationRecord(profileID: published.profileID, revision: published.revision,
                                     manifestSHA256: composedFromModules, engine: publishedModule?.record,
                                     heldEngine: heldEngine, composition: ModuleInjection.composition),
            locations: modulesLocations)
         
         
        ModulePublicationSummary.store(ModulePublicationSummary.summary(of: publishedModule, at: now(),
                                                                         profileID: published.profileID),
                                        locations: modulesLocations)
        let presentationNow = presentationInputs(source: sourceDigest, profile: profile)
        PublishedPresentation.record(
            published,
            inputs: presentationNow == presentationAtStart ? presentationNow : nil,
            workingDirectory: coreHomeDir
        )
        lastPublicationPreflight = publishedPreflight.map { (published, $0) }
        lastPublicationNotices = publishedNotices.map { (published, $0) }
        lastPublicationModule = publishedModule.map { (published, $0) }
        return ProfilePublicationResult(
            pointer: published,
            previous: previous,
            runtimeUpdates: runtimeUpdates,
            firstLoadPending: firstLoadPending,
            publishedRouteNames: publishedRouteNames
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private static func carryGlobalUA(_ identity: String, into publication: inout ConfigTransforms.FinalizedPublication,
                                      givingBackAfter mergedYAML: String) throws {
        let (preflight, geodataMode, ports, portsAnswered, notices) = (publication.preflight,
            publication.geodataMode, publication.listenerPorts, publication.listenerPortsAnswered, publication.notices)
        var text = publication.text
        publication = .init(text: "", preflight: preflight, geodataMode: geodataMode, listenerPorts: ports,
                            listenerPortsAnswered: portsAnswered, notices: notices)
        try ConfigTransforms.carryGlobalUA(identity, into: &text,
                                           beforeGrowing: { AppCore.returnFreeMemoryNow(after: mergedYAML) })
        publication = .init(text: text, preflight: preflight, geodataMode: geodataMode, listenerPorts: ports,
                            listenerPortsAnswered: portsAnswered, notices: notices)
    }

    private struct FinalizedText {
        let publication: ConfigTransforms.FinalizedPublication
        let setUpRefused: Bool
         
         
         
        var rulesAsWritten: String? = nil
    }

     
    private struct ModuleFinalized {
        let finalized: FinalizedText
        let modules: ModulePublication?
         
         
         
         
        let finalizedUnpublished: Bool
         
         
        var recordedFor: ActiveConfigurationPointer? = nil

        var publication: ConfigTransforms.FinalizedPublication { finalized.publication }
        var rulesAsWritten: String? { finalized.rulesAsWritten }
    }

     
    private enum InjectedFinalize {
        case accepted(FinalizedText)
         
        case refused(String)
        case setUpRefused(FinalizedText)
         
         
        case misread(String)
    }

     
     
     
     
    private var modulesStepPriority: TaskPriority { compileRuleSets ? Task.currentPriority : .utility }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func finalizeCarryingModule(
        _ runtimeYAML: String,
        ruleIndexDirectory: URL?,
        candidate: ActiveConfigurationPointer,
        asked: inout ModuleEngineReadinessSource.Asked?,
        laps: inout PerfLedger.Laps,
        finalize: (String, ModuleFinalizeHandover) throws -> FinalizedText
    ) async throws -> ModuleFinalized {
         
         
         
         
         
         
        let nothing = ruleIndexDirectory != nil
            && ModuleActivationStep.namesAPublication(runtimeYAML, facts: { ModuleActivationStep.facts(of: runtimeYAML) })
            ? ModuleFinalizeHandover(prependRules: [], ruleSets: ModuleRuleSetHandover()) : ModuleFinalizeHandover()
        guard var input = modules() else {
            return ModuleFinalized(finalized: try finalize(runtimeYAML, nothing), modules: nil, finalizedUnpublished: false)
        }
         
         
        if modulesFromReadiness, input.manifest.enabled {
            asked = .init(status: input.engine, ports: input.manifest.ports,
                          publishedFingerprint: input.manifest.caFingerprintSHA256)
        }
         
         
        input.geodataDirectory = coreHomeDir
        input.ruleIndexDirectory = ruleIndexDirectory
        input.logLevelSetByApp = lastLogLevelSetByApp
        input.modeSetByApp = lastModeSetByApp
        input.listenerKeysSetByApp = lastListenerKeysSetByApp
        await stageModuleGeodata(for: input, runtimeYAML: runtimeYAML)
        let priority = modulesStepPriority
        var outcome = await ModuleActivationStep.prepare(runtimeYAML, input: input, priority: priority)
        laps.mark("publish.modules")
        if let line = outcome.logLine { log(line) }
        if outcome.needsNewPorts { drawModulePorts(avoiding: outcome.portsInUse) }
         
         
         
         
        guard outcome.prependRules != nil || outcome.ruleSets?.definitions.isEmpty == false
                || !ConfigTransforms.sameText(outcome.text, runtimeYAML) else {
            return ModuleFinalized(finalized: try finalize(runtimeYAML, nothing),
                                    modules: outcome.logLine == nil ? nil : ModulePublication(outcome: outcome),
                                    finalizedUnpublished: false)
        }
        var redone = false

         
         
        func again() async {
            redone = true
            outcome.text = ""
            outcome = await ModuleActivationStep.prepare(runtimeYAML, input: input, priority: priority)
            if let line = outcome.logLine { log(line) }
        }
        func published(_ finalized: FinalizedText, recordedFor: ActiveConfigurationPointer? = nil) -> ModuleFinalized {
             
            if let level = outcome.moduleLogLevel { lastProfileLogLevel = level }
            return ModuleFinalized(finalized: finalized, modules: ModulePublication(outcome: outcome),
                                    finalizedUnpublished: redone, recordedFor: recordedFor)
        }
         
         
         
         
         
        func without(_ refusal: String) async throws -> ModuleFinalized {
            if outcome.carriesSettings, input.settingsRefused == nil {
                log("modules: the configuration was refused with module settings in it, so it is finalized again without them: \(refusal)")
                input.settingsRefused = refusal
                await again()
                return try await passes()
            }
            log("modules not applied: the configuration was refused with modules in it, so it is finalized again without it: \(refusal)")
            return try plain()
        }
         
        func unlike(_ difference: String) throws -> ModuleFinalized {
            log("modules not applied: the finalized configuration does not read back as what modules wrote, so it is finalized again without it: \(difference)")
            return try plain()
        }
        func plain() throws -> ModuleFinalized {
            outcome.text = ""
            return ModuleFinalized(finalized: try finalize(runtimeYAML, nothing),
                                    modules: ModulePublication(degradedBecause: [.refusedWithModules], record: nil),
                                    finalizedUnpublished: true)
        }
         
         
         
        func setUpFailed(_ refused: FinalizedText) -> ModuleFinalized {
            log("modules: the core could not be set up for this publication, so it is not finalized again: \(refused.publication.preflight.errorMessage ?? "setup failed")")
            return ModuleFinalized(finalized: refused, modules: nil, finalizedUnpublished: false)
        }
         
         
         
         
         
         
         
        func publishing(_ finalized: FinalizedText) async throws -> ModuleFinalized? {
            if let refusal = tunnelRefused(finalized.publication.text, candidate: candidate) { return try await without(refusal) }
            guard let assignment = outcome.engineAssignment else { return published(finalized) }
            do {
                try recordEnginePlan(assignment, for: candidate)
                return published(finalized, recordedFor: candidate)
            } catch {
                log("modules: the engine plan for \(candidate.profileID)/\(candidate.revision) could not be recorded, so the engine is left out of this publication: \(error)")
                return nil
            }
        }
         
        func withoutTheEngine() async throws -> ModuleFinalized {
            input.engine = .withheld(.engineUnavailable)
            await again()
            switch try finalizeInjected(outcome, finalize) {
            case .setUpRefused(let refused): return setUpFailed(refused)
            case .misread(let difference): return try unlike(difference)
            case .refused(let refusal): return try await without(refusal)
            case .accepted(let finalized): return try await publishing(finalized) ?? published(finalized)
            }
        }

         
         
         
        func passes() async throws -> ModuleFinalized {
             
             
            var unrecorded = false
            var unrouted: Set<String> = []
            switch try finalizeInjected(outcome, finalize) {
            case .setUpRefused(let refused): return setUpFailed(refused)
            case .misread(let difference): return try unlike(difference)
            case .refused(let refusal): return try await without(refusal)
            case .accepted(let finalized):
                let missing = outcome.certEntryIPNeedsConfirming && outcome.certEntryIP != nil
                    ? ModuleActivationStep.unreachableCertEntryIPs(in: finalized.publication.text) : []
                if let address = outcome.certEntryIP, missing.contains(address) {
                    log("modules: certificate address \(address) is not routed once the route sets are expanded; again past \(missing.sorted().joined(separator: ", "))")
                    unrouted = missing
                } else {
                    if let done = try await publishing(finalized) { return done }
                    unrecorded = true
                }
            }
            if unrecorded { return try await withoutTheEngine() }

             
            input.unreachableCertEntryIPs.formUnion(unrouted)
            await again()
            switch try finalizeInjected(outcome, finalize) {
            case .setUpRefused(let refused): return setUpFailed(refused)
            case .misread(let difference): return try unlike(difference)
            case .refused(let refusal):
                 
                 
                guard let address = outcome.certEntryIP else { return try await without(refusal) }
                log("modules: the configuration was refused with certificate address \(address) in it, so the certificate page is left out: \(refusal)")
            case .accepted(let finalized):
                if outcome.certEntryIPNeedsConfirming, let address = outcome.certEntryIP,
                   !ModuleActivationStep.certEntryIP(address, reachableIn: finalized.publication.text) {
                     
                    log("modules: certificate address \(address) is not routed either; the certificate page is left out")
                } else {
                    if let done = try await publishing(finalized) { return done }
                    unrecorded = true
                }
            }
            if unrecorded { return try await withoutTheEngine() }

             
            input.unreachableCertEntryIPs = Set(ModuleCertEntry.candidates)
            await again()
            switch try finalizeInjected(outcome, finalize) {
            case .setUpRefused(let refused): return setUpFailed(refused)
            case .misread(let difference): return try unlike(difference)
            case .refused(let refusal): return try await without(refusal)
            case .accepted(let finalized):
                if let done = try await publishing(finalized) { return done }
            }
            return try await withoutTheEngine()
        }
        return try await passes()
    }

     
     
    private func finalizeInjected(_ outcome: ModuleActivationOutcome,
                                  _ finalize: (String, ModuleFinalizeHandover) throws -> FinalizedText) throws -> InjectedFinalize {
        let finalized: FinalizedText
        do {
            finalized = try finalize(outcome.text, outcome.handover)
        } catch let cancelled as CancellationError {
            throw cancelled
        } catch {
            return .refused(error.localizedDescription)
        }
        if finalized.setUpRefused { return .setUpRefused(finalized) }
        guard finalized.publication.preflight.ok else {
            return .refused(finalized.publication.preflight.errorMessage ?? "preflight failed")
        }
         
        if let difference = ModuleActivationStep.readBack(finalized.publication.text, outcome: outcome) {
            return .misread(difference)
        }
        return .accepted(finalized)
    }

     
     
     
     
     
     
     
    private func stageModuleGeodata(for input: ModuleActivationInput, runtimeYAML: String) async {
        let lines = input.manifest.routingRules.map { $0.rendered($0.policy.kernelName ?? "DIRECT") }
        let needing = lines.filter { !ModuleActivationStep.geodataNeeded(by: $0).isEmpty }
        guard !needing.isEmpty else { return }
        let home = coreHomeDir
        do {
             
            let plan: RemoteResourcePlan? = try await Task.detached(priority: modulesStepPriority) {
                let mode = ModuleActivationStep.facts(of: runtimeYAML).geodataMode
                let missing = needing.filter { line in
                    ModuleActivationStep.geodataNeeded(by: line).contains {
                        !ModuleActivationStep.geodataStaged($0, geodataMode: mode, in: home)
                    }
                }
                guard !missing.isEmpty else { return nil }
                return try ConfigTransforms.planResources(mergedYAML: try ModuleActivationStep.geodataPlanDocument(for: missing,
                                                                                                                    in: runtimeYAML))
            }.value
            guard let plan else { return }
            try await geodata.stage(plan: plan, homeDir: home, maxBytesEach: Self.maxGeodataBytes,
                                    preferBundled: true, reuseExisting: true)
            log("modules: staged the geodata the modules' rules name: \(plan.geodata.map(\.kind).joined(separator: ", "))")
        } catch {
            log("modules: the geodata the modules' rules name could not be staged: \(error.localizedDescription)")
        }
    }

     
     
     
     
    private(set) var portReroll: Task<Void, Never>?

     
     
     
    private func drawModulePorts(avoiding taken: Set<UInt16>) {
        let container = coreHomeDir.deletingLastPathComponent()
        let log = self.log
         
         
         
        let origin = ModuleStore.publishing
        portReroll = Task.detached(priority: .utility) {
            do {
                try await ModuleStore.$publishing.withValue(origin) {
                    try await ModuleStore.shared(container).rerollPorts(avoiding: taken)
                }
            } catch {
                log("modules could not draw new ports: \(error.localizedDescription)")
            }
        }
    }

     

    private var engineLocations: ModuleEngineLocations { ModuleEngineLocations.of(coreHomeDir.deletingLastPathComponent()) }

     
     
     
     
    private func enginePlanKeeping(_ also: [ActiveConfigurationPointer?]) -> Set<ModuleRunningRevision> {
        let pointers = also + [store.activeIdentityWithoutLock(), store.lastKnownGoodIdentityWithoutLock()]
        var kept = Set(pointers.compactMap { $0.map { ModuleRunningRevision(profileID: $0.profileID, revision: $0.revision) } })
        if let running = ModuleEngineReport.load(engineLocations)?.revision { kept.insert(running) }
        return kept
    }

     
     
     
    private func recordEnginePlan(_ assignment: ModuleEngineAssignment, for pointer: ActiveConfigurationPointer,
                                  inFlight: Bool = true) throws {
         
         
         
        try ModuleEnginePlan.record(assignment, for: ModuleRunningRevision(profileID: pointer.profileID, revision: pointer.revision),
                                     at: now(), keepingNow: { enginePlanKeeping([pointer]) }, locations: engineLocations,
                                     inFlight: inFlight)
    }

     
     
     
     
     
    private func forgetEnginePlan(of candidate: ActiveConfigurationPointer) {
        do {
            try ModuleEnginePlan.forget(ModuleRunningRevision(profileID: candidate.profileID, revision: candidate.revision),
                                         unlessKept: { enginePlanKeeping([]) }, locations: engineLocations)
        } catch {
            log("modules: the engine plan of \(candidate.profileID)/\(candidate.revision), which was not published, could not be taken out: \(error)")
        }
    }

     
     
     
     
    private func refreshEnginePlan(_ assignment: ModuleEngineAssignment, inUse: ActiveConfigurationPointer,
                                   candidate: ActiveConfigurationPointer) {
        forgetEnginePlan(of: candidate)
        do {
             
            try recordEnginePlan(assignment, for: inUse, inFlight: false)
        } catch {
            log("modules: the engine plan for \(inUse.profileID)/\(inUse.revision), which runs already, could not be written again: \(error)")
        }
    }

     
     
     
     
    private func pruneEnginePlans(published: ActiveConfigurationPointer, previous: ActiveConfigurationPointer?) {
        let locations = engineLocations
        guard FileManager.default.fileExists(atPath: locations.enginePlans.path) else { return }
        do {
            try ModuleEnginePlan.prune(keepingNow: { enginePlanKeeping([published, previous]) }, locations: locations)
        } catch {
            log("modules: the engine plans could not be pruned: \(error)")
        }
    }

     

     
     
     
     
    private struct ModuleRefusedRevision: Codable, Equatable {
        let profileID: String
        let revision: String
        let sha256: String
        let message: String
         
        let core: String?
    }

     
     
     
    private static let coreIdentity: String = {
        let build = AppBuildInfo.current()
        return "\(build.coreVersion) build \(build.buildNumber)"
    }()

    private static let refusedRevisionsKept = 4

    private var refusedRevisionsFile: URL {
        coreHomeDir.deletingLastPathComponent().appendingPathComponent("working/adblock/refused-revisions.json")
    }

     
     
    private static func digest(_ text: String, naming revision: String) -> String {
        ModuleJSON.sha256(Data(text.replacingOccurrences(of: revision, with: "").utf8))
    }

     
     
     
     
     
     
     
     
     
    private func tunnelRefused(_ text: String, candidate: ActiveConfigurationPointer) -> String? {
        let container = coreHomeDir.deletingLastPathComponent()
        let file = refusedRevisionsFile
        var kept = (try? Data(contentsOf: file)).flatMap { try? ModuleJSON.decoder().decode([ModuleRefusedRevision].self, from: $0) } ?? []
        if let record = StartupOutcomeRecord.read(from: container), let refused = record.requested,
           refused.profileID == candidate.profileID, refused.revision != candidate.revision,
           !kept.contains(where: { $0.profileID == refused.profileID && $0.revision == refused.revision }) {
             
             
             
             
            let document: Bool
            switch record.outcome {
            case .refused, .refusedKeptRunning: document = record.errorClass == .config
            case .recoveredFromLastKnownGood: document = record.quarantined == refused
            default: document = false
            }
            if document, let text = try? store.loadConfiguration(profileID: refused.profileID, revision: refused.revision).text {
                let words = record.message ?? "\(record.outcome)"
                kept.insert(ModuleRefusedRevision(profileID: refused.profileID, revision: refused.revision,
                                                   sha256: Self.digest(text, naming: refused.revision), message: words,
                                                   core: Self.coreIdentity), at: 0)
                kept = Array(kept.prefix(Self.refusedRevisionsKept))
                if let data = try? ModuleJSON.encoder().encode(kept) {
                    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: file, options: .atomic)
                }
            }
        }
        let mine = kept.filter { $0.profileID == candidate.profileID && $0.core == Self.coreIdentity }
        guard !mine.isEmpty else { return nil }
        let digest = Self.digest(text, naming: candidate.revision)
        return mine.first { $0.sha256 == digest }.map {
            "the tunnel refused this same configuration (\($0.revision)): \($0.message)"
        }
    }

     
     
     
     
     
     
     
    private func revisionInUse(of profile: Profile,
                               expected: ActiveConfigurationPointer? = nil) throws -> ActiveConfigurationPointer {
         
         
         
         
        guard let current = store.activeIdentityWithoutLock(), current.profileID == profile.id,
              expected == nil || current == expected else {
            throw ConfigResourceStoreError.activeConfigurationChanged
        }
        return current
    }

     
     
     
     
     
    private func inUseAndOnDisk(_ given: Profile, expected: ActiveConfigurationPointer? = nil) throws
        -> (ActiveConfigurationPointer, Profile) {
        try ProfileStore.withWriteLock {
            (try revisionInUse(of: given, expected: expected), onDisk(given))
        }
    }

     
     
     
    private func onDisk(_ profile: Profile) -> Profile {
        profileStore.load().first(where: { $0.id == profile.id }) ?? profile
    }

     
     
     
     
    private func recordRevision(_ pointer: ActiveConfigurationPointer, of profile: Profile) {
        _ = try? profileStore.updateIfPresent(id: profile.id) { $0.activeRevision = pointer.revision }
    }

     
     
     
     
     
     
     
     
     
     
     
    private func announceProviderContent(of profile: Profile) {
        let profileID = profile.id
        let workingDirectory = coreHomeDir.standardizedFileURL.path
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .clashProviderContentChanged, object: nil,
                                            userInfo: ["profileID": profileID, "workingDirectory": workingDirectory])
        }
    }

    private func sidecarURL(profileID: String) -> URL {
        coreHomeDir.appendingPathComponent("store/\(profileID)/source.yaml")
    }


    private func writeSourceSidecar(_ yaml: String, profileID: String) throws {
        let url = sidecarURL(profileID: profileID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(yaml.utf8).write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

}

extension ProfileActivationCoordinator.ModulePublication {
     
     
    init(outcome: ModuleActivationOutcome) {
        self.init(degradedBecause: outcome.degradedBecause, record: outcome.record, disclosures: outcome.disclosures,
                  certEntryIP: outcome.record == nil ? nil : outcome.certEntryIP, skipped: outcome.skipped,
                  engineAssignment: outcome.record == nil ? nil : outcome.engineAssignment, changes: outcome.changes)
    }
}

 
 
final class CompileQueueRun: @unchecked Sendable {
    private let lock = NSLock()
    private var startable = true
    private var answered = false
     
    func start() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return startable
    }
     
    func expire() {
        lock.lock(); startable = false; lock.unlock()
    }
     
    func answer() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if answered { return false }
        answered = true
        return true
    }
}

 
final class CompileQueueCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count: UInt64 = 0
    var value: UInt64 { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count &+= 1; lock.unlock() }
}

 
final class CompileQueueOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
