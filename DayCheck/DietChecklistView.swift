import SwiftUI

/// Marker value for pushing `DietChecklistView` via `NavigationLink(value:)`,
/// registered on `ContentView`'s own `NavigationStack` — see `HistoryRoute`
/// in HistoryView.swift for why this has to be done at that level.
struct DietRoute: Hashable {}

/// Checked by default each day — uncheck whatever you skipped from the plan.
/// Diet % is computed from checked/total items rather than typed in manually.
struct DietChecklistView: View {
    var dietPlanStore: DietPlanStore
    @Binding var checkedItemIDs: Set<UUID>

    @State private var isShowingAddMealAlert = false
    @State private var newMealName = ""
    @State private var addingItemToMealID: UUID?
    @State private var newItemName = ""
    @State private var newItemQuantity = ""
    @State private var mealPendingDeletion: DietMeal?

    private var allItems: [DietItem] { dietPlanStore.meals.flatMap(\.items) }
    private var totalItems: Int { allItems.count }
    private var checkedCount: Int { allItems.filter { checkedItemIDs.contains($0.id) }.count }

    private var percent: Int {
        guard totalItems > 0 else { return 100 }
        return Int((Double(checkedCount) / Double(totalItems) * 100).rounded())
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("\(checkedCount)/\(totalItems) items")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(percent)%")
                        .font(.title3.bold())
                }
            }

            ForEach(dietPlanStore.meals) { meal in
                Section {
                    ForEach(meal.items) { item in
                        row(for: item)
                    }
                    .onDelete { offsets in
                        dietPlanStore.deleteItems(in: meal.id, at: offsets)
                    }

                    Button {
                        addingItemToMealID = meal.id
                        newItemName = ""
                        newItemQuantity = ""
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                } header: {
                    HStack {
                        Text(meal.name)
                        Spacer()
                        Button(role: .destructive) {
                            mealPendingDeletion = meal
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Diet Checklist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newMealName = ""
                    isShowingAddMealAlert = true
                } label: {
                    Label("Add Meal", systemImage: "plus.circle")
                }
            }
        }
        .alert("New Meal", isPresented: $isShowingAddMealAlert) {
            TextField("Meal name", text: $newMealName)
            Button("Add") { dietPlanStore.addMeal(name: newMealName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "New Item",
            isPresented: Binding(
                get: { addingItemToMealID != nil },
                set: { if !$0 { addingItemToMealID = nil } }
            )
        ) {
            TextField("Food name", text: $newItemName)
            TextField("Quantity", text: $newItemQuantity)
            Button("Add") {
                if let mealID = addingItemToMealID {
                    dietPlanStore.addItem(to: mealID, name: newItemName, quantity: newItemQuantity)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \"\(mealPendingDeletion?.name ?? "")\" and all its items?",
            isPresented: Binding(
                get: { mealPendingDeletion != nil },
                set: { if !$0 { mealPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Meal", role: .destructive) {
                if let meal = mealPendingDeletion,
                   let index = dietPlanStore.meals.firstIndex(where: { $0.id == meal.id }) {
                    dietPlanStore.deleteMeals(at: IndexSet(integer: index))
                }
                mealPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func row(for item: DietItem) -> some View {
        Button {
            if checkedItemIDs.contains(item.id) {
                checkedItemIDs.remove(item.id)
            } else {
                checkedItemIDs.insert(item.id)
            }
        } label: {
            HStack {
                Image(systemName: checkedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checkedItemIDs.contains(item.id) ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .foregroundStyle(.primary)
                    Text(item.quantity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        DietChecklistView(dietPlanStore: DietPlanStore(), checkedItemIDs: .constant([]))
    }
}
