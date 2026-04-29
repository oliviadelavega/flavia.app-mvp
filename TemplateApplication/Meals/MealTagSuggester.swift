//
// Flavia study app
//
// On-device LLM helper that polishes dictated meal descriptions and proposes
// tags from the fixed `MealVocabulary` set. Runs through Apple's
// `FoundationModels` framework (iOS 26+) so meal text never leaves the
// device — important for the study's privacy posture, and free of the
// API-key / rate-limit overhead a cloud LLM would incur. On older iOS
// versions or hardware without Apple Intelligence support, `suggest(for:)`
// returns `nil` and the form falls back to the manual chip selector.
//
// The model is asked to produce two things in one structured response:
//   1. `cleanedDescription` — a corrected canonical version of the input.
//      Useful because Apple's speech recognizer commonly mishears food
//      words ("k-mall" → "kale", "soya" → "soy", etc.).
//   2. `tags` — a subset of the allowed vocabulary, returned as a
//      `@Generable` enum so the model can't invent values outside the set.
//
// Swap-in path for a future cloud variant: keep the public `suggest(for:)`
// signature, add a second backend that talks to a Firebase callable function.
// `MealLogView` doesn't care which path produced the suggestion.
//

import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif


struct MealSuggestion: Equatable, Sendable {
    var cleanedDescription: String
    var tags: [String]
}


@MainActor
@Observable
final class MealTagSuggester {
    @ObservationIgnored private let logger = Logger(subsystem: "com.flavia.app", category: "MealTagSuggester")

    private(set) var isWorking = false
    /// `false` on devices/OS versions where on-device generation isn't available.
    /// Views can use this to hide AI affordances rather than letting users tap a no-op button.
    let isAvailable: Bool

    init() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            self.isAvailable = SystemLanguageModel.default.isAvailable
        } else {
            self.isAvailable = false
        }
        #else
        self.isAvailable = false
        #endif
    }

    func suggest(for description: String) async -> MealSuggestion? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            return await suggestWithFoundationModels(description: trimmed)
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func suggestWithFoundationModels(description: String) async -> MealSuggestion? {
        isWorking = true
        defer { isWorking = false }

        let instructions = Self.modelInstructions

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: description,
                generating: GeneratedMealAnalysis.self
            )
            let analysis = response.content
            let mapped = analysis.tags.map(\.canonical)
            logger.debug("Suggester input=\"\(description)\" cleaned=\"\(analysis.cleanedDescription)\" tags=\(mapped)")
            return MealSuggestion(
                cleanedDescription: analysis.cleanedDescription,
                tags: mapped
            )
        } catch {
            logger.error("FoundationModels suggestion failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Tag definitions + few-shot examples in one block. The on-device model is small enough
    /// that bare tag names ("nut", "soy") aren't enough — it needs to see what each category
    /// covers and a couple of worked examples to behave reliably. Keep this prompt edited
    /// alongside `MealVocabulary.tags` and `GeneratedMealTag` so all three stay in sync.
    private static let modelInstructions: String = """
    You analyze short meal descriptions from a food-tracking app. Inputs often come from \
    voice dictation that may contain misheard ingredient names (e.g. "k-mall" for "kale", \
    "chick paste" for "chickpeas").

    Produce two outputs:
    1. cleanedDescription: a corrected, plain-English version of the meal. Fix obvious \
       transcription errors. Do not invent ingredients the user did not mention.
    2. tags: every tag from the allowed set whose category is clearly present in the meal. \
       Apply a tag whenever an ingredient that fits the category is named, including in \
       composite or branded foods (a banana split contains ice cream → dairy and sugar).

    Tag definitions:
    - dairy: milk, cheese, butter, yogurt, cream, ice cream, whey
    - gluten: wheat, bread, pasta, flour, cereal, oats (unless gluten-free), beer
    - egg: eggs in any form
    - nut: any tree nut or peanut — almond, walnut, cashew, pistachio, hazelnut, pecan, \
      peanut, peanut butter, almond milk, etc.
    - soy: soybeans, tofu, tempeh, soy sauce, edamame, miso, soy milk
    - seafood: fish or shellfish — salmon, tuna, shrimp, oysters, sushi, sashimi
    - spicy: chili peppers, hot sauce, sriracha, curry, jalapeño, kimchi, wasabi
    - processed: packaged, pre-prepared, or fast food — chips, frozen meals, deli meat, \
      fast-food items, sodas
    - sugar: added sugar, candy, dessert, sweets, syrup, soda, ice cream
    - alcohol: beer, wine, spirits, cocktails, sake
    - vegetables: any vegetable, including leafy greens, root veg, peppers, tomatoes
    - fruits: any fruit — banana, apple, berries, citrus, mango

    Apply every tag that applies; do not stop at one. Only omit a tag if no ingredient in \
    that category is present.

    Examples:
    Input: "Banana split with nuts"
    cleanedDescription: "Banana split with nuts"
    tags: dairy, sugar, nut, fruits

    Input: "salmon sashimi and edamame"
    cleanedDescription: "Salmon sashimi and edamame"
    tags: seafood, soy

    Input: "spaghetti carbonara with parmesan"
    cleanedDescription: "Spaghetti carbonara with parmesan"
    tags: gluten, dairy, egg

    Input: "chick paste salad with tomato"
    cleanedDescription: "Chickpea salad with tomato"
    tags: vegetables
    """

    @available(iOS 26.0, *)
    @Generable
    fileprivate struct GeneratedMealAnalysis {
        @Guide(
            description: "A cleaned, plain-English meal description that fixes obvious dictation errors without inventing ingredients."
        )
        let cleanedDescription: String

        @Guide(description: "Every applicable tag from the allowed set — include all that match, not just one.")
        let tags: [GeneratedMealTag]
    }

    @available(iOS 26.0, *)
    @Generable
    fileprivate enum GeneratedMealTag {
        case dairy, gluten, egg, nut, soy, seafood, spicy, processed, sugar, alcohol, vegetables, fruits

        var canonical: String {
            switch self {
            case .dairy: return "dairy"
            case .gluten: return "gluten"
            case .egg: return "egg"
            case .nut: return "nut"
            case .soy: return "soy"
            case .seafood: return "seafood"
            case .spicy: return "spicy"
            case .processed: return "processed"
            case .sugar: return "sugar"
            case .alcohol: return "alcohol"
            case .vegetables: return "vegetables"
            case .fruits: return "fruits"
            }
        }
    }
    #endif
}
