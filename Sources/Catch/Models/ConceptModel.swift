import Foundation

struct ConceptModel: Identifiable, Equatable, Hashable, Sendable {
    static let fallbackGooseModelIDs = [
        "goose-claude-4-6-sonnet",
        "goose-claude-4-7-opus",
        "goose-claude-fable-5",
        "goose-claude-haiku-4-5",
        "goose-claude-opus-4-8",
        "goose-gpt-5-4-mini",
        "goose-gpt-5-5"
    ]
    static let fallbackGooseModels = gooseModels(from: fallbackGooseModelIDs)

    let id: String
    let name: String
    let modelID: String?
    let isRecommended: Bool

    init(_ name: String, modelID: String?, isRecommended: Bool = false) {
        id = modelID == "default" ? "default" : (modelID ?? "default")
        self.name = name
        self.modelID = modelID
        self.isRecommended = isRecommended
    }

    static func gooseModels(from ids: [String]) -> [ConceptModel] {
        let parsedModels = ids.compactMap(ParsedGooseModel.init(id:))
        let latestModelByFamily = Dictionary(grouping: parsedModels, by: \.familyKey)
            .compactMapValues { models in
                models.max { left, right in
                    left.version.lexicographicallyPrecedes(right.version)
                }?.id
            }

        return parsedModels
            .map { parsed in
                ConceptModel(
                    parsed.displayName,
                    modelID: parsed.id,
                    isRecommended: latestModelByFamily[parsed.familyKey] == parsed.id
                )
            }
            .deduplicatedByID()
            .sorted { left, right in
                let leftRank = ParsedGooseModel(id: left.id)?.sortRank ?? 4
                let rightRank = ParsedGooseModel(id: right.id)?.sortRank ?? 4
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }
}

struct ParsedGooseModel {
    let id: String
    let familyKey: String
    let familyTokens: [String]
    let version: [Int]

    init?(id: String) {
        guard id.hasPrefix("goose-") else { return nil }

        var familyTokens: [String] = []
        var version: [Int] = []
        for token in id.dropFirst("goose-".count).split(separator: "-").map(String.init) {
            if let numericToken = Int(token) {
                version.append(numericToken)
            } else {
                familyTokens.append(token)
            }
        }

        guard !familyTokens.isEmpty, !version.isEmpty else { return nil }

        self.id = id
        self.familyKey = familyTokens.joined(separator: "-")
        self.familyTokens = familyTokens
        self.version = version
    }

    var displayName: String {
        let formattedFamilyTokens = familyTokens.map(Self.formatFamilyToken)
        let versionString = version.map(String.init).joined(separator: ".")

        if formattedFamilyTokens.first == "GPT" {
            let suffix = formattedFamilyTokens.dropFirst().joined(separator: " ")
            return suffix.isEmpty ? "GPT-\(versionString)" : "GPT-\(versionString) \(suffix.lowercased())"
        }

        return (formattedFamilyTokens + [versionString]).joined(separator: " ")
    }

    var sortRank: Int {
        if familyKey == "gpt" { return 0 }
        if familyKey.contains("opus") { return 1 }
        if familyKey.contains("haiku") { return 3 }
        return 2
    }

    private static func formatFamilyToken(_ token: String) -> String {
        switch token.lowercased() {
        case "gpt":
            return "GPT"
        case "chatgpt":
            return "ChatGPT"
        default:
            guard let first = token.first else { return "" }
            return String(first).uppercased() + token.dropFirst().lowercased()
        }
    }
}

extension Array where Element == ConceptModel {
    func deduplicatedByID() -> [ConceptModel] {
        var seen: Set<String> = []
        var unique: [ConceptModel] = []

        for model in self where seen.insert(model.id).inserted {
            unique.append(model)
        }

        return unique
    }
}
