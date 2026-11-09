import SwiftUI
import Charts

struct TrainingHomeView: View {
    @Environment(TrainingStore.self) private var store
    @State private var showActive = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        StatTile(title: "Diese Woche", value: "\(store.workoutsThisWeek)", icon: "calendar")
                        StatTile(title: "Serie", value: "\(store.streakWeeks) Wo.", icon: "flame")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if store.active != nil {
                    Section {
                        Button { showActive = true } label: {
                            Label("Laufendes Training fortsetzen", systemImage: "play.circle.fill").font(.headline)
                        }
                    }
                }

                Section {
                    NavigationLink { CoachView() } label: {
                        Label("KI-Trainingsplan erstellen", systemImage: "sparkles")
                    }
                    NavigationLink { ExerciseDatabaseView() } label: {
                        Label("Übungsdatenbank (870+ mit Anleitung)", systemImage: "books.vertical")
                    }
                }

                Section("Training starten") {
                    ForEach(store.templates) { t in
                        Button {
                            start(t)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(.headline)
                                Text(t.items.compactMap { store.exercise($0.exerciseID)?.name }.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .disabled(store.active != nil)
                    }
                    Button { start(nil) } label: { Label("Freies Training", systemImage: "plus") }
                        .disabled(store.active != nil)
                }

                Section("Verlauf") {
                    if store.workouts.isEmpty {
                        Text("Noch keine Trainings.").foregroundStyle(.secondary)
                    }
                    ForEach(store.workouts) { w in
                        NavigationLink { WorkoutSummaryView(workout: w) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.name).font(.headline)
                                Text("\(w.start.formatted(date: .abbreviated, time: .shortened)) · \(Int(w.duration / 60)) Min · \(w.doneSets) Sätze · \(Int(w.volume).formatted()) kg")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in store.deleteWorkouts(idx.map { store.workouts[$0].id }) }
                }
            }
            .navigationTitle("Training")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { ExerciseLibraryView() } label: { Image(systemName: "list.bullet.rectangle") }
                }
            }
            .fullScreenCover(isPresented: $showActive) { ActiveWorkoutView() }
        }
    }

    private func start(_ t: WorkoutTemplate?) {
        store.start(template: t)
        showActive = true
    }
}

struct ActiveWorkoutView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var workout = Workout(name: "", start: Date())
    @State private var loaded = false
    @State private var picking = false
    @State private var confirmFinish = false

    var body: some View {
        NavigationStack {
            List {
                ForEach($workout.entries) { $entry in
                    Section {
                        if let summary = store.lastSummary(for: entry.exerciseID) {
                            Text(summary).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Satz").frame(width: 34, alignment: .leading)
                            Text("kg").frame(maxWidth: .infinity)
                            Text("Wdh.").frame(maxWidth: .infinity)
                            Spacer().frame(width: 44)
                        }
                        .font(.caption).foregroundStyle(.secondary)

                        ForEach($entry.sets) { $set in
                            let index = entry.sets.firstIndex { $0.id == set.id } ?? 0
                            HStack {
                                Text("\(index + 1)").frame(width: 34, alignment: .leading).foregroundStyle(.secondary)
                                TextField("0", value: $set.weight, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                TextField("0", value: $set.reps, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                Button {
                                    set.done.toggle()
                                    if set.done { store.startRest(store.restSeconds(for: entry)) }
                                } label: {
                                    Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(set.done ? Theme.accent : .secondary)
                                }
                                .buttonStyle(.borderless)
                                .frame(width: 44)
                            }
                            .font(.body.monospacedDigit())
                            .overlay(alignment: .trailing) {
                                if store.isRecord(set, exerciseID: entry.exerciseID) {
                                    Image(systemName: "trophy.fill").foregroundStyle(.yellow).font(.caption).offset(x: -46)
                                }
                            }
                        }
                        .onDelete { idx in entry.sets.remove(atOffsets: idx) }

                        Button {
                            let last = entry.sets.last
                            entry.sets.append(SetEntry(weight: last?.weight ?? 0, reps: last?.reps ?? 8))
                        } label: {
                            Label("Satz hinzufügen", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.exercise(entry.exerciseID)?.name ?? "Übung").font(.headline).foregroundStyle(.primary)
                            Text(store.suggestion(for: entry.exerciseID).note).font(.caption).foregroundStyle(Theme.accent)
                            if let note = entry.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .textCase(nil)
                    }
                }
                .onDelete { idx in workout.entries.remove(atOffsets: idx) }

                Section {
                    Button { picking = true } label: { Label("Übung hinzufügen", systemImage: "plus.circle") }
                    Button("Training verwerfen", role: .destructive) {
                        store.discard()
                        dismiss()
                    }
                }
            }
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
                ToolbarItem(placement: .principal) {
                    Text(timerInterval: workout.start...Date.distantFuture, countsDown: false)
                        .font(.headline.monospacedDigit())
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { confirmFinish = true }.fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { RestTimerBar() }
            .sheet(isPresented: $picking) {
                ExercisePicker { id in workout.entries.append(store.makeEntry(id)) }
            }
            .confirmationDialog("Training beenden?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Speichern & beenden") {
                    store.updateActive(workout)
                    store.finish()
                    dismiss()
                }
            } message: {
                Text("Nur abgehakte Sätze werden gespeichert.")
            }
            .onAppear {
                if !loaded, let a = store.active {
                    workout = a
                    loaded = true
                }
            }
            .onChange(of: workout) { _, w in
                if store.active != nil { store.updateActive(w) }
            }
        }
    }
}

struct RestTimerBar: View {
    @Environment(TrainingStore.self) private var store

    var body: some View {
        if let end = store.restEnd {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(end.timeIntervalSince(context.date)))
                HStack {
                    Button { store.adjustRest(-15) } label: { Text("−15") }
                    Spacer()
                    VStack(spacing: 0) {
                        Text("Pause").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                            .font(.title2.monospacedDigit().weight(.semibold))
                    }
                    Spacer()
                    Button { store.adjustRest(15) } label: { Text("+15") }
                    Button { store.stopRest() } label: { Image(systemName: "xmark.circle.fill") }
                        .padding(.leading, 8)
                }
                .padding()
                .background(.ultraThinMaterial)
                .onChange(of: remaining) { _, r in if r == 0 { store.stopRest() } }
            }
        }
    }
}

struct ExercisePicker: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onPick: (UUID) -> Void
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(MuscleGroup.allCases) { group in
                    let items = store.exercises.filter {
                        $0.muscle == group && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
                    }
                    if !items.isEmpty {
                        Section(group.label) {
                            ForEach(items) { e in
                                Button(e.name) {
                                    onPick(e.id)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Übung suchen")
            .safeAreaInset(edge: .bottom) {
                NavigationLink {
                    ExerciseDatabaseView()
                } label: {
                    Label("Mehr Übungen in der Datenbank (870+)", systemImage: "books.vertical")
                        .frame(maxWidth: .infinity).padding().background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Übung wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }
}

struct WorkoutSummaryView: View {
    @Environment(TrainingStore.self) private var store
    let workout: Workout

    var body: some View {
        List {
            Section {
                LabeledContent("Datum", value: workout.start.formatted(date: .complete, time: .shortened))
                LabeledContent("Dauer", value: "\(Int(workout.duration / 60)) Min")
                LabeledContent("Sätze", value: "\(workout.doneSets)")
                LabeledContent("Volumen", value: "\(Int(workout.volume).formatted()) kg")
            }
            ForEach(workout.entries) { e in
                Section {
                    ForEach(Array(e.sets.enumerated()), id: \.element.id) { i, s in
                        HStack {
                            Text("Satz \(i + 1)").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(s.weight.clean) kg × \(s.reps)").monospacedDigit()
                        }
                    }
                } header: {
                    NavigationLink(store.exercise(e.exerciseID)?.name ?? "Übung") {
                        ExerciseDetailView(exerciseID: e.exerciseID)
                    }
                }
            }
        }
        .navigationTitle(workout.name)
    }
}

struct ExerciseDetailView: View {
    @Environment(TrainingStore.self) private var store
    let exerciseID: UUID
    @State private var metric = 0

    var body: some View {
        let history = store.history(for: exerciseID)
        List {
            if history.count >= 2 {
                Section {
                    Picker("Wert", selection: $metric) {
                        Text("1RM (geschätzt)").tag(0)
                        Text("Top-Gewicht").tag(1)
                        Text("Volumen").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Chart(history) { p in
                        let v = metric == 0 ? p.e1rm : metric == 1 ? p.topWeight : p.volume
                        LineMark(x: .value("Datum", p.date), y: .value("Wert", v))
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Datum", p.date), y: .value("Wert", v))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(height: 200)
                }
            }
            if let db = ExerciseDatabase.shared.entry(store.exercise(exerciseID)?.dbID) {
                ExerciseGuideSection(db: db)
            }
            Section("Rekorde") {
                LabeledContent("Bestes 1RM (geschätzt)", value: "\((history.map(\.e1rm).max() ?? 0).clean) kg")
                LabeledContent("Schwerstes Gewicht", value: "\((history.map(\.topWeight).max() ?? 0).clean) kg")
                LabeledContent("Trainings", value: "\(history.count)")
            }
            Section("Nächstes Mal") {
                let s = store.suggestion(for: exerciseID)
                Text("\(s.sets) × \(s.reps) mit \(s.weight.clean) kg")
                Text(s.note).font(.caption).foregroundStyle(.secondary)
            }
            if let ex = store.exercise(exerciseID) {
                Section("Einstellungen") {
                    NavigationLink("Bearbeiten") { ExerciseEditView(exercise: ex) }
                }
            }
        }
        .navigationTitle(store.exercise(exerciseID)?.name ?? "Übung")
        .task { await ExerciseDatabase.shared.loadIfNeeded() }
    }
}

struct ExerciseLibraryView: View {
    @Environment(TrainingStore.self) private var store

    var body: some View {
        List {
            ForEach(MuscleGroup.allCases) { group in
                let items = store.exercises.filter { $0.muscle == group }
                if !items.isEmpty {
                    Section(group.label) {
                        ForEach(items) { e in
                            NavigationLink(e.name) { ExerciseDetailView(exerciseID: e.id) }
                        }
                        .onDelete { idx in store.deleteExercises(idx.map { items[$0].id }) }
                    }
                }
            }
        }
        .navigationTitle("Übungen")
        .toolbar {
            NavigationLink { ExerciseDatabaseView() } label: { Label("Datenbank", systemImage: "books.vertical") }
            NavigationLink {
                ExerciseEditView(exercise: Exercise(name: "", muscle: .brust))
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

struct ExerciseEditView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var exercise: Exercise

    var body: some View {
        Form {
            TextField("Name", text: $exercise.name)
            Picker("Muskelgruppe", selection: $exercise.muscle) {
                ForEach(MuscleGroup.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Körpergewicht", isOn: $exercise.bodyweight)
            Stepper("Wdh. min: \(exercise.repMin)", value: $exercise.repMin, in: 1...50)
            Stepper("Wdh. max: \(exercise.repMax)", value: $exercise.repMax, in: exercise.repMin...60)
            Stepper("Steigerung: \(exercise.increment.clean) kg", value: $exercise.increment, in: 0...20, step: 0.5)
        }
        .navigationTitle(exercise.name.isEmpty ? "Neue Übung" : exercise.name)
        .toolbar {
            Button("Sichern") {
                store.upsert(exercise)
                dismiss()
            }
            .disabled(exercise.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

struct TemplatesView: View {
    @Environment(TrainingStore.self) private var store

    var body: some View {
        List {
            ForEach(store.templates) { t in
                NavigationLink(t.name) { TemplateEditView(template: t) }
            }
            .onDelete { idx in store.deleteTemplates(idx.map { store.templates[$0].id }) }
        }
        .navigationTitle("Pläne")
        .toolbar {
            NavigationLink { TemplateEditView(template: WorkoutTemplate(name: "")) } label: { Image(systemName: "plus") }
        }
    }
}

struct TemplateEditView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var template: WorkoutTemplate
    @State private var picking = false

    var body: some View {
        Form {
            TextField("Name (z.B. Oberkörper A)", text: $template.name)
            Section("Übungen") {
                ForEach($template.items) { $item in
                    Stepper("\(store.exercise(item.exerciseID)?.name ?? "?") · \(item.sets) Sätze", value: $item.sets, in: 1...10)
                }
                .onDelete { template.items.remove(atOffsets: $0) }
                .onMove { template.items.move(fromOffsets: $0, toOffset: $1) }
                Button { picking = true } label: { Label("Übung hinzufügen", systemImage: "plus") }
            }
        }
        .navigationTitle(template.name.isEmpty ? "Neuer Plan" : template.name)
        .toolbar {
            Button("Sichern") {
                store.upsert(template)
                dismiss()
            }
            .disabled(template.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .sheet(isPresented: $picking) {
            ExercisePicker { id in template.items.append(TemplateItem(exerciseID: id)) }
        }
    }
}
