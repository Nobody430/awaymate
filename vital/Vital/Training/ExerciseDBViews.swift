import SwiftUI

/// Alternates between the start and end photo – a lightweight "video" of the movement.
struct ExerciseAnimation: View {
    let db: DBExercise
    var height: CGFloat = 220

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.9)) { context in
            let urls = db.imageURLs
            let index = urls.isEmpty ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.9) % urls.count
            ZStack {
                ForEach(urls.indices, id: \.self) { i in
                    AsyncImage(url: urls[i]) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFit()
                        case .failure: Image(systemName: "photo").foregroundStyle(.secondary)
                        default: ProgressView()
                        }
                    }
                    .opacity(i == index ? 1 : 0)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: index)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct ExerciseGuideSection: View {
    let db: DBExercise
    @State private var translated: [String]?
    @State private var translating = false

    var body: some View {
        Section("Ausführung") {
            ExerciseAnimation(db: db)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            HStack {
                Label(db.primaryMuscles.map(DBExercise.germanMuscle).joined(separator: ", "), systemImage: "figure.strengthtraining.traditional")
                Spacer()
                Text(DBExercise.germanEquipment(db.equipment)).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            if !db.secondaryMuscles.isEmpty {
                Text("Mitbeteiligt: " + db.secondaryMuscles.map(DBExercise.germanMuscle).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array((translated ?? db.instructions).enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)").font(.caption.bold()).frame(width: 20, height: 20)
                        .background(Theme.accent.opacity(0.25), in: Circle())
                    Text(step).font(.subheadline)
                }
            }
            if translated == nil && AIClient.hasKey {
                Button {
                    Task {
                        translating = true
                        defer { translating = false }
                        translated = try? await AIClient.translate(db.instructions)
                    }
                } label: {
                    HStack {
                        Label("Auf Deutsch übersetzen (KI)", systemImage: "character.bubble")
                        if translating { Spacer(); ProgressView() }
                    }
                }
            }
            if let url = db.youtubeURL {
                Link(destination: url) {
                    Label("Ausführungsvideos auf YouTube", systemImage: "play.rectangle.fill")
                }
            }
        }
    }
}

struct ExerciseDatabaseView: View {
    @Environment(TrainingStore.self) private var store
    @State private var db = ExerciseDatabase.shared
    @State private var search = ""
    @State private var muscle: MuscleGroup?
    @State private var equipment: String?

    private var results: [DBExercise] {
        db.strength.filter { e in
            (search.isEmpty || e.name.localizedCaseInsensitiveContains(search)) &&
            (muscle == nil || e.muscleGroup == muscle) &&
            (equipment == nil || e.equipment == equipment)
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip("Alle", selected: muscle == nil) { muscle = nil }
                        ForEach(MuscleGroup.allCases) { g in chip(g.label, selected: muscle == g) { muscle = g } }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip("Jedes Gerät", selected: equipment == nil) { equipment = nil }
                        ForEach(["barbell", "dumbbell", "cable", "machine", "body only", "kettlebells", "bands", "e-z curl bar"], id: \.self) { e in
                            chip(DBExercise.germanEquipment(e), selected: equipment == e) { equipment = e }
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            if db.loading { HStack { ProgressView(); Text("Lade Übungsdatenbank …") } }
            if let error = db.error { Text(error).foregroundStyle(.orange) }

            Section("\(results.count) Übungen") {
                ForEach(results) { e in
                    NavigationLink { DBExerciseDetailView(db: e) } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: e.imageURLs.first) { img in img.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.2) }
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.name).lineLimit(2)
                                Text("\(e.primaryMuscles.map(DBExercise.germanMuscle).joined(separator: ", ")) · \(DBExercise.germanEquipment(e.equipment))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if store.exercises.contains(where: { $0.dbID == e.id }) {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "z.B. Squat, Curl, Row")
        .navigationTitle("Übungsdatenbank")
        .task { await db.loadIfNeeded() }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(selected ? Color.black : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct DBExerciseDetailView: View {
    @Environment(TrainingStore.self) private var store
    let db: DBExercise

    var body: some View {
        let inLibrary = store.exercises.first { $0.dbID == db.id }
        List {
            ExerciseGuideSection(db: db)
            Section {
                if let e = inLibrary {
                    NavigationLink("In meinen Übungen ansehen") { ExerciseDetailView(exerciseID: e.id) }
                } else {
                    Button {
                        _ = store.exercise(forDB: db)
                    } label: {
                        Label("Zu meinen Übungen hinzufügen", systemImage: "plus.circle.fill")
                    }
                }
            }
            Section("Details") {
                LabeledContent("Level", value: db.level?.capitalized ?? "–")
                LabeledContent("Mechanik", value: db.mechanic == "compound" ? "Mehrgelenkig" : db.mechanic == "isolation" ? "Isolation" : "–")
            }
        }
        .navigationTitle(db.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
