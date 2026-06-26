import Testing
@testable import CatchKit

@Suite
struct GooseModelMenuTests {
    @Test
    func supportedGooseModelsIncludeFableAndFilterDatabricksIDs() {
        let models = MainViewModel.gooseModels(from: [
            "databricks-gpt-5-5",
            "goose-claude-fable-5",
            "goose-gpt-5-5"
        ])

        #expect(models.map(\.id) == [
            "goose-gpt-5-5",
            "goose-claude-fable-5"
        ])
        #expect(models.map(\.name) == [
            "GPT-5.5",
            "Claude Fable 5"
        ])
    }

    @Test
    func recommendedModelsAreLatestPerFamily() {
        let models = MainViewModel.gooseModels(from: [
            "goose-claude-4-6-sonnet",
            "goose-claude-4-7-opus",
            "goose-claude-opus-4-8",
            "goose-claude-fable-5",
            "goose-claude-haiku-4-5",
            "goose-gpt-5-4-mini",
            "goose-gpt-5-5"
        ])

        let recommendedIDs = models.filter(\.isRecommended).map(\.id)
        let overflowIDs = models.filter { !$0.isRecommended }.map(\.id)

        #expect(recommendedIDs == [
            "goose-gpt-5-5",
            "goose-claude-opus-4-8",
            "goose-claude-fable-5",
            "goose-claude-4-6-sonnet",
            "goose-gpt-5-4-mini",
            "goose-claude-haiku-4-5"
        ])
        #expect(overflowIDs == [
            "goose-claude-4-7-opus"
        ])
    }
}
