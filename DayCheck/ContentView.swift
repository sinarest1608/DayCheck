import SwiftUI
import PhotosUI
import HealthKit

struct ContentView: View {
    @State private var healthManager = HealthKitManager()
    @State private var historyStore = HistoryStore()
    @State private var dietPlanStore = DietPlanStore()

    private enum Field: Hashable {
        case weight, water, steps
    }

    @State private var date = Date()
    // Backed by Strings, not Double, so the fields can be typed into freely —
    // a `TextField(value:format:)` reformats on every keystroke and resets the
    // cursor to the start, turning e.g. "2.5" into garbage like "2.50.0".
    @State private var weightText = "0.0"
    @State private var waterText = "0.0"
    @State private var stepsText = "0"
    @State private var supplementsTaken = false
    @State private var chamomileTea = false
    @State private var workoutDone = false
    @State private var checkedDietItemIDs: Set<UUID> = []
    @FocusState private var focusedField: Field?

    /// Checked/total items from `dietPlanStore`, not a manual guess.
    private var dietPercent: Int {
        let total = dietPlanStore.meals.flatMap(\.items).count
        guard total > 0 else { return 100 }
        let checked = dietPlanStore.meals.flatMap(\.items).filter { checkedDietItemIDs.contains($0.id) }.count
        return Int((Double(checked) / Double(total) * 100).rounded())
    }

    private var weightKg: Double { Double(weightText) ?? 0 }
    private var waterLiters: Double { Double(waterText) ?? 0 }
    private var steps: Double { Double(stepsText) ?? 0 }

    private var weightKgStepperBinding: Binding<Double> {
        Binding(get: { weightKg }, set: { weightText = String(format: "%.1f", $0) })
    }

    private var waterLitersStepperBinding: Binding<Double> {
        Binding(get: { waterLiters }, set: { waterText = String(format: "%.1f", $0) })
    }

    private var stepsStepperBinding: Binding<Double> {
        Binding(get: { steps }, set: { stepsText = String(Int($0)) })
    }

    @AppStorage("waterGoalLiters") private var waterGoalLiters: Double = 3.0
    @AppStorage("stepsGoal") private var stepsGoal: Int = 10_000
    @AppStorage("weightSourceBundleID") private var weightSourceBundleID: String = ""
    @AppStorage("waterSourceBundleID") private var waterSourceBundleID: String = ""
    @AppStorage("stepsSourceBundleID") private var stepsSourceBundleID: String = ""
    @AppStorage("workoutSourceBundleID") private var workoutSourceBundleID: String = ""

    @State private var weightSources: [HKSource] = []
    @State private var waterSources: [HKSource] = []
    @State private var stepSources: [HKSource] = []
    @State private var workoutSources: [HKSource] = []

    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var croppingIndex: Int?

    @State private var isShowingShareSheet = false
    @State private var isRefreshingHealth = false
    @State private var hasFetchedInitialHealthData = false

    private var entry: StatusEntry {
        StatusEntry(
            date: date,
            weightKg: weightKg,
            waterLiters: waterLiters,
            waterGoalLiters: waterGoalLiters,
            steps: steps,
            stepsGoal: Double(stepsGoal),
            supplementsTaken: supplementsTaken,
            chamomileTea: chamomileTea,
            workoutDone: workoutDone,
            dietPercent: dietPercent
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section {
                    sourcePicker("Weight source", selection: $weightSourceBundleID, sources: weightSources)
                    HStack {
                        Text("Weight (Kg)")
                        Spacer()
                        TextField("", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .focused($focusedField, equals: .weight)
                        Stepper("", value: weightKgStepperBinding, in: 0...300, step: 0.1)
                            .labelsHidden()
                    }

                    sourcePicker("Water source", selection: $waterSourceBundleID, sources: waterSources)
                    HStack {
                        Text("Water (L)")
                        Spacer()
                        TextField("", text: $waterText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .focused($focusedField, equals: .water)
                        Stepper("", value: waterLitersStepperBinding, in: 0...15, step: 0.1)
                            .labelsHidden()
                    }

                    sourcePicker("Steps source", selection: $stepsSourceBundleID, sources: stepSources)
                    HStack {
                        Text("Steps")
                        Spacer()
                        TextField("", text: $stepsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .focused($focusedField, equals: .steps)
                        Stepper("", value: stepsStepperBinding, in: 0...100_000, step: 500)
                            .labelsHidden()
                    }

                    sourcePicker("Workout source", selection: $workoutSourceBundleID, sources: workoutSources)
                    Toggle("Workout", isOn: $workoutDone)

                    Button {
                        refreshFromHealth()
                    } label: {
                        HStack {
                            Text("Refresh from Health")
                            if isRefreshingHealth {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isRefreshingHealth)
                } header: {
                    HStack {
                        Text("Metrics")
                        if isRefreshingHealth {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                Section("Habits") {
                    Toggle("Supplements", isOn: $supplementsTaken)
                    Toggle("Chamomile Tea", isOn: $chamomileTea)
                    NavigationLink(value: DietRoute()) {
                        HStack {
                            Text("Diet")
                            Spacer()
                            Text("\(dietPercent)%")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Goals") {
                    Stepper(value: $waterGoalLiters, in: 0.5...10, step: 0.1) {
                        Text("Water goal: \(waterGoalLiters, format: .number.precision(.fractionLength(1))) L")
                    }
                    Stepper(value: $stepsGoal, in: 1_000...30_000, step: 500) {
                        Text("Steps goal: \(stepsGoal)")
                    }
                }

                Section("Photos (\(selectedImages.count))") {
                    PhotosPicker(selection: $photosPickerItems, maxSelectionCount: 10, matching: .images) {
                        Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
                    }
                    if !selectedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(selectedImages.indices, id: \.self) { index in
                                    Image(uiImage: selectedImages[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .bottomTrailing) {
                                            Button {
                                                croppingIndex = index
                                            } label: {
                                                Image(systemName: "crop")
                                                    .font(.caption)
                                                    .padding(4)
                                                    .background(.black.opacity(0.6), in: Circle())
                                                    .foregroundStyle(.white)
                                            }
                                            .padding(4)
                                        }
                                }
                            }
                        }
                    }
                }

                Section("Message Preview") {
                    Text(entry.message)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Daily Status")
            .navigationDestination(for: HistoryRoute.self) { _ in
                HistoryView(historyStore: historyStore)
            }
            .navigationDestination(for: Date.self) { weekStart in
                WeekDetailView(historyStore: historyStore, weekStart: weekStart)
            }
            .navigationDestination(for: DietRoute.self) { _ in
                DietChecklistView(dietPlanStore: dietPlanStore, checkedItemIDs: $checkedDietItemIDs)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    NavigationLink(value: HistoryRoute()) {
                        Label("History", systemImage: "calendar")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        UIPasteboard.general.string = entry.message
                        isShowingShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $isShowingShareSheet) {
                ShareSheet(text: entry.message, images: selectedImages) { completed in
                    if completed {
                        historyStore.save(DailyRecord(from: entry))
                        resetForm()
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { croppingIndex != nil },
                set: { if !$0 { croppingIndex = nil } }
            )) {
                if let index = croppingIndex, selectedImages.indices.contains(index) {
                    PhotoCropView(
                        image: selectedImages[index],
                        onCancel: { croppingIndex = nil },
                        onCrop: { cropped in
                            selectedImages[index] = cropped
                            croppingIndex = nil
                        }
                    )
                }
            }
            .onDisappear { focusedField = nil }
            .onAppear {
                // `.onAppear` also fires every time this screen is uncovered again
                // (e.g. popping back from History), not just on first launch. Without
                // this guard, every trip to History and back re-did a full HealthKit
                // round trip for no reason — the actual lag the user was seeing.
                guard !hasFetchedInitialHealthData else { return }
                hasFetchedInitialHealthData = true
                checkedDietItemIDs = dietPlanStore.allItemIDs
                refreshFromHealth()
            }
            .onChange(of: date) { refreshFromHealth() }
            .onChange(of: weightSourceBundleID) { refreshFromHealth() }
            .onChange(of: waterSourceBundleID) { refreshFromHealth() }
            .onChange(of: stepsSourceBundleID) { refreshFromHealth() }
            .onChange(of: workoutSourceBundleID) { refreshFromHealth() }
            .onChange(of: photosPickerItems) { loadSelectedImages() }
        }
    }

    @ViewBuilder
    private func sourcePicker(_ title: String, selection: Binding<String>, sources: [HKSource]) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: selection) {
                Text("All sources").tag("")
                ForEach(sources, id: \.bundleIdentifier) { source in
                    Text(source.name).tag(source.bundleIdentifier)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func refreshFromHealth() {
        guard !isRefreshingHealth else { return }
        isRefreshingHealth = true
        Task {
            defer { isRefreshingHealth = false }
            await healthManager.requestAuthorization()

            async let fetchedWeightSources = healthManager.sources(for: HealthKitManager.weightType)
            async let fetchedWaterSources = healthManager.sources(for: HealthKitManager.waterType)
            async let fetchedStepSources = healthManager.sources(for: HealthKitManager.stepCountType)
            async let fetchedWorkoutSources = healthManager.workoutSources()
            weightSources = await fetchedWeightSources
            waterSources = await fetchedWaterSources
            stepSources = await fetchedStepSources
            workoutSources = await fetchedWorkoutSources

            let weightBundleID = weightSourceBundleID.isEmpty ? nil : weightSourceBundleID
            let waterBundleID = waterSourceBundleID.isEmpty ? nil : waterSourceBundleID
            let stepsBundleID = stepsSourceBundleID.isEmpty ? nil : stepsSourceBundleID
            let workoutBundleID = workoutSourceBundleID.isEmpty ? nil : workoutSourceBundleID

            if let latest = await healthManager.latestSample(
                for: HealthKitManager.weightType,
                unit: .gramUnit(with: .kilo),
                date: date,
                sourceBundleID: weightBundleID
            ) {
                weightText = String(format: "%.1f", latest)
            }

            if let total = await healthManager.total(
                for: HealthKitManager.waterType,
                unit: .liter(),
                date: date,
                sourceBundleID: waterBundleID
            ) {
                waterText = String(format: "%.1f", total)
            }

            if let total = await healthManager.total(
                for: HealthKitManager.stepCountType,
                unit: .count(),
                date: date,
                sourceBundleID: stepsBundleID
            ) {
                stepsText = String(Int(total))
            }

            if let had = await healthManager.hadWorkout(date: date, sourceBundleID: workoutBundleID) {
                workoutDone = had
            }
        }
    }

    /// Resets the daily entry after a successful share, ready for the next day.
    /// Goals and source preferences (`@AppStorage`) are left alone since they're settings, not daily data.
    private func resetForm() {
        date = Date()
        weightText = "0.0"
        waterText = "0.0"
        stepsText = "0"
        supplementsTaken = false
        chamomileTea = false
        workoutDone = false
        checkedDietItemIDs = dietPlanStore.allItemIDs
        photosPickerItems = []
        selectedImages = []
        refreshFromHealth()
    }

    private func loadSelectedImages() {
        Task {
            var images: [UIImage] = []
            for item in photosPickerItems {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            selectedImages = images
        }
    }
}

#Preview {
    ContentView()
}
