import SwiftUI

struct CoachView: View {
    @Environment(TrainingStore.self) private var store
    @State private var db = ExerciseDatabase.shared
    @AppStorage("anthropicKey") private var apiKey = ""
    @State private var profile = CoachProfile.saved
    @State private var plan: CoachPlan? = CoachPlan.saved
    @State private var working = false
    @State private var error: String?
    @State private var applied = false

    var body: some View {
        Form {
            if !AIClient.hasKey {
                Section {
                    SecureField("Claude-API-Key (sk-ant-…)", text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    NavigationLink { KeyGuideView(guide: .claude) } label: {
                        Label("So bekommst du den Key", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("KI einrichten")
                } footer: {
                    Text("Du zahlst nur, was du nutzt: ein Plan kostet etwa 10–20 Rappen.")
                }
            }

            Section("Dein Profil") {
                Picker("Ziel", selection: $profile.goal) { ForEach(CoachProfile.goals, id: \.self) { Text($0) } }
                Picker("Erfahrung", selection: $profile.level) { ForEach(CoachProfile.levels, id: \.self) { Text($0) } }
                Stepper("\(profile.daysPerWeek) Tage pro Woche", value: $profile.daysPerWeek, in: 2...6)
                Stepper("\(profile.minutes) Min pro Einheit", value: $profile.minutes, in: 30...120, step: 15)
                Picker("Ausrüstung", selection: $profile.equipment) { ForEach(CoachProfile.equipments, id: \.self) { Text($0) } }
                NavigationLink {
                    List(MuscleGroup.allCases) { g in
                        Button {
                            if let i = profile.focus.firstIndex(of: g) { profile.focus.remove(at: i) } else { profile.focus.append(g) }
                        } label: {
                            HStack {
                                Text(g.label).foregroundStyle(.primary)
                                Spacer()
                                if profile.focus.contains(g) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                    }
                    .navigationTitle("Schwerpunkte")
                } label: {
                    LabeledContent("Schwerpunkte", value: profile.focus.isEmpty ? "Ausgewogen" : profile.focus.map(\.label).joined(separator: ", "))
                }
                TextField("Beschwerden (z.B. Knie, Schulter)", text: $profile.limitations, axis: .vertical)
                TextField("Wünsche (z.B. mehr Arme, kein Kreuzheben)", text: $profile.wishes, axis: .vertical)
            }

            Section {
                Button {
                    Task { await generate(revise: false) }
                } label: {
                    HStack {
                        Label(plan == nil ? "Plan erstellen" : "Neuen Plan erstellen", systemImage: "sparkles")
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(working || !AIClient.hasKey)
                if plan != nil {
                    Button {
                        Task { await generate(revise: true) }
                    } label: {
                        Label("Plan mit meinen Wünschen überarbeiten", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(working || !AIClient.hasKey)
                }
            } footer: {
                if working { Text("Der Coach plant … das dauert meist 30–90 Sekunden.") }
                if let error { Text(error).foregroundStyle(.red) }
            }

            if let plan {
                Section(plan.planName) {
                    Text(plan.summary).font(.subheadline)
                }
                ForEach(plan.days, id: \.self) { day in
                    Section(day.name) {
                        ForEach(day.exercises, id: \.self) { e in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(e.germanName).font(.headline)
                                    Spacer()
                                    Text("\(e.sets) × \(e.repMin)–\(e.repMax)").monospacedDigit()
                                }
                                Text("\(e.rir) RIR · Pause \(e.restSeconds / 60):\(String(format: "%02d", e.restSeconds % 60)) · \(e.cue)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Steigerung") { Text(plan.progression).font(.subheadline) }
                Section("Deload") { Text(plan.deload).font(.subheadline) }
                Section {
                    Button {
                        Coach.apply(plan, store: store, db: db, replaceOld: true)
                        applied = true
                    } label: {
                        Label(applied ? "Übernommen ✓" : "Plan übernehmen (ersetzt alte KI-Pläne)", systemImage: "checkmark.circle.fill")
                            .fontWeight(.semibold)
                    }
                    .disabled(applied)
                }
            }
        }
        .navigationTitle("KI-Coach")
        .onChange(of: profile) { _, p in CoachProfile.saved = p }
        .task { await db.loadIfNeeded() }
    }

    private func generate(revise: Bool) async {
        working = true
        error = nil
        defer { working = false }
        do {
            plan = try await Coach.generate(profile: profile, store: store, db: db, previous: revise ? plan : nil)
            applied = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
