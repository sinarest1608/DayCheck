import Foundation
import SwiftUI

struct DietItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var quantity: String
}

struct DietMeal: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var items: [DietItem]
}

@Observable
final class DietPlanStore {
    private(set) var meals: [DietMeal]

    private let fileURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("diet_plan.json")
        if let loaded = Self.load(from: fileURL) {
            meals = loaded
        } else {
            meals = Self.defaultMeals
            persist()
        }
    }

    var allItemIDs: Set<UUID> {
        Set(meals.flatMap(\.items).map(\.id))
    }

    func addMeal(name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        meals.append(DietMeal(name: name, items: []))
        persist()
    }

    func deleteMeals(at offsets: IndexSet) {
        meals.remove(atOffsets: offsets)
        persist()
    }

    func addItem(to mealID: UUID, name: String, quantity: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let index = meals.firstIndex(where: { $0.id == mealID }) else { return }
        meals[index].items.append(DietItem(name: name, quantity: quantity))
        persist()
    }

    func deleteItems(in mealID: UUID, at offsets: IndexSet) {
        guard let index = meals.firstIndex(where: { $0.id == mealID }) else { return }
        meals[index].items.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(meals) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from fileURL: URL) -> [DietMeal]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([DietMeal].self, from: data)
    }

    /// Seeded from the PDF diet chart; editable afterward since the chart
    /// gets revised periodically.
    private static var defaultMeals: [DietMeal] {
        [
            DietMeal(name: "Breakfast", items: [
                DietItem(name: "Methi seeds + kalonji water", quantity: "1tbsp + 1 pinch"),
                DietItem(name: "Avocado", quantity: "30 gm"),
                DietItem(name: "Egg white", quantity: "4 eggs"),
                DietItem(name: "Wheat/bread", quantity: "50 gm / 2 slices"),
                DietItem(name: "Ghee/oil", quantity: "3 gm"),
                DietItem(name: "Milk (toned)", quantity: "300 ml"),
            ]),
            DietMeal(name: "Lunch", items: [
                DietItem(name: "Rice/wheat", quantity: "60 gm (~2 chapati)"),
                DietItem(name: "Rajma/chickpeas + tofu", quantity: "40 gm + 100 gm"),
                DietItem(name: "Cooked veggies (gourd family)", quantity: "1 bowl"),
                DietItem(name: "Ghee/oil", quantity: "5 gm"),
            ]),
            DietMeal(name: "Snacks", items: [
                DietItem(name: "Chamomile tea", quantity: "1 cup"),
                DietItem(name: "Soaked sabja seed", quantity: "1 tsp"),
                DietItem(name: "Electrolyte drink (sugar free)", quantity: "1"),
                DietItem(name: "Oikos pro yogurt", quantity: "150 gm"),
            ]),
            DietMeal(name: "Dinner", items: [
                DietItem(name: "Chamomile tea", quantity: "before bedtime"),
                DietItem(name: "Dal (any)", quantity: "40 gm"),
                DietItem(name: "Rice/wheat", quantity: "60 gm"),
                DietItem(name: "Tofu + Green salad", quantity: "50 gm + 1 bowl"),
                DietItem(name: "Ghee", quantity: "5 gm"),
                DietItem(name: "Psyllium husk", quantity: "1 tbsp, 1hr before dinner"),
            ]),
        ]
    }
}
