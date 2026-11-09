import SwiftUI
import PhotosUI
import VisionKit

struct NutritionView: View {
    @Environment(NutritionStore.self) private var store
    @Environment(WeightStore.self) private var weight
    @State private var day = Date()
    @State private var sheet: AddMode?

    enum AddMode: String, Identifiable { case photo, barcode, manual, targets; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            let t = store.totals(on: day)
            List {
                Section {
                    HStack {
                        Button { day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text(Calendar.current.isDateInToday(day) ? "Heute" : day.formatted(date: .complete, time: .omitted)).font(.headline)
                        Spacer()
                        Button { day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day } label: { Image(systemName: "chevron.right") }
                            .disabled(Calendar.current.isDateInToday(day))
                    }
                    .buttonStyle(.borderless)
                    progress("Kalorien", value: t.kcal, target: store.kcalTarget, unit: "kcal", color: .orange)
                    progress("Protein", value: t.protein, target: store.proteinTarget, unit: "g", color: Theme.accent)
                    HStack {
                        Text("Kohlenhydrate \(Int(t.carbs)) g")
                        Spacer()
                        Text("Fett \(Int(t.fat)) g")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    HStack(spacing: 10) {
                        addButton("Foto (KI)", "camera.viewfinder", .photo)
                        addButton("Barcode", "barcode.viewfinder", .barcode)
                        addButton("Manuell", "square.and.pencil", .manual)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section("Mahlzeiten") {
                    let list = store.entries(on: day)
                    if list.isEmpty { Text("Noch nichts eingetragen.").foregroundStyle(.secondary) }
                    ForEach(list) { e in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.name).lineLimit(2)
                                Text("\(e.date.formatted(date: .omitted, time: .shortened)) · \(e.source)\(e.grams.map { " · \(Int($0)) g" } ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(Int(e.kcal)) kcal").monospacedDigit()
                                Text("\(Int(e.protein)) g P").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in store.delete(idx.map { list[$0].id }) }
                }

                if !store.favorites.isEmpty {
                    Section("Schnell erneut hinzufügen") {
                        ForEach(store.favorites.prefix(8)) { f in
                            Button {
                                var e = f
                                e.id = UUID()
                                e.date = Calendar.current.isDateInToday(day) ? Date() : day
                                store.add(e)
                            } label: {
                                HStack {
                                    Text(f.name).lineLimit(1).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(Int(f.kcal)) kcal").foregroundStyle(.secondary)
                                    Image(systemName: "plus.circle")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Essen")
            .toolbar {
                Button { sheet = .targets } label: { Image(systemName: "target") }
            }
            .sheet(item: $sheet) { mode in
                switch mode {
                case .photo: PhotoMealView(day: day)
                case .barcode: BarcodeFoodView(day: day)
                case .manual: ManualFoodView(day: day)
                case .targets: TargetsView()
                }
            }
        }
    }

    private func progress(_ title: String, value: Double, target: Double, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) / \(Int(target)) \(unit)").monospacedDigit()
                    .foregroundStyle(value > target * 1.1 ? .orange : .primary)
            }
            .font(.subheadline)
            ProgressView(value: min(value / max(target, 1), 1)).tint(color)
        }
    }

    private func addButton(_ title: String, _ icon: String, _ mode: AddMode) -> some View {
        Button { sheet = mode } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Photo (AI)

struct PhotoMealView: View {
    @Environment(NutritionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: Date
    @State private var image: UIImage?
    @State private var item: PhotosPickerItem?
    @State private var showCamera = false
    @State private var hint = ""
    @State private var result: FoodVision.Result?
    @State private var chosen: Set<String> = []
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if !AIClient.hasKey {
                    Section { Text("Für die Foto-Erkennung brauchst du einen Claude-Key (Einstellungen → KI-Coach).").foregroundStyle(.orange) }
                }
                Section {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    HStack {
                        Button { showCamera = true } label: { Label("Kamera", systemImage: "camera") }
                            .buttonStyle(.borderless)
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        Spacer()
                        PhotosPicker(selection: $item, matching: .images) { Label("Fotos", systemImage: "photo") }
                            .buttonStyle(.borderless)
                    }
                    TextField("Hinweis (optional, z.B. „grosse Portion, mit Sauce“)", text: $hint)
                    Button {
                        Task { await analyse() }
                    } label: {
                        HStack { Label("Nährwerte schätzen", systemImage: "sparkles"); if working { Spacer(); ProgressView() } }
                    }
                    .disabled(image == nil || working || !AIClient.hasKey)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if let r = result {
                    Section {
                        ForEach(r.items, id: \.self) { it in
                            Toggle(isOn: Binding(get: { chosen.contains(it.name) }, set: { if $0 { chosen.insert(it.name) } else { chosen.remove(it.name) } })) {
                                VStack(alignment: .leading) {
                                    Text("\(it.name) · \(Int(it.grams)) g")
                                    Text("\(Int(it.kcal)) kcal · P \(Int(it.protein)) · K \(Int(it.carbs)) · F \(Int(it.fat))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: { Text("Erkannt") } footer: { Text(r.note) }
                    Section {
                        Button("Ausgewählte eintragen") {
                            let date = Calendar.current.isDateInToday(day) ? Date() : day
                            for it in r.items where chosen.contains(it.name) {
                                store.add(FoodEntry(date: date, name: it.name, kcal: it.kcal, protein: it.protein, carbs: it.carbs,
                                                    fat: it.fat, grams: it.grams, source: "Foto"))
                            }
                            dismiss()
                        }
                        .disabled(chosen.isEmpty)
                    }
                }
            }
            .navigationTitle("Mahlzeit fotografieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .fullScreenCover(isPresented: $showCamera) { CameraPicker(image: $image).ignoresSafeArea() }
            .onChange(of: item) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) { image = UIImage(data: data) }
                }
            }
        }
    }

    private func analyse() async {
        guard let image, let jpeg = image.resizedForUpload().jpegData(compressionQuality: 0.7) else { return }
        working = true
        error = nil
        defer { working = false }
        do {
            let r = try await FoodVision.analyse(jpeg: jpeg, hint: hint)
            result = r
            chosen = Set(r.items.map(\.name))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension UIImage {
    func resizedForUpload(maxSide: CGFloat = 1280) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Barcode

struct BarcodeFoodView: View {
    @Environment(NutritionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: Date
    @State private var code: String?
    @State private var manualCode = ""
    @State private var product: OpenFoodFacts.Product?
    @State private var grams: Double = 100
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if product == nil {
                    Section {
                        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                            BarcodeScanner { scanned in
                                if code == nil { code = scanned; Task { await lookup(scanned) } }
                            }
                            .frame(height: 280)
                            .listRowInsets(EdgeInsets())
                        } else {
                            Text("Kamera-Scanner auf diesem Gerät nicht verfügbar.").foregroundStyle(.secondary)
                        }
                        HStack {
                            TextField("Barcode eintippen", text: $manualCode).keyboardType(.numberPad)
                            Button("Suchen") { Task { await lookup(manualCode) } }.disabled(manualCode.count < 6)
                        }
                    } footer: {
                        Text("Daten von Open Food Facts (freie Datenbank).")
                    }
                }
                if loading { ProgressView() }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.orange)
                        Button("Nochmals scannen") { code = nil; self.error = nil }
                    }
                }
                if let p = product {
                    Section(p.name) {
                        Stepper("Menge: \(Int(grams)) g", value: $grams, in: 5...2000, step: 5)
                        LabeledContent("Kalorien", value: "\(Int(p.kcal100 * grams / 100)) kcal")
                        LabeledContent("Protein", value: "\(Int(p.protein100 * grams / 100)) g")
                        LabeledContent("Kohlenhydrate", value: "\(Int(p.carbs100 * grams / 100)) g")
                        LabeledContent("Fett", value: "\(Int(p.fat100 * grams / 100)) g")
                    }
                    Section {
                        Button("Eintragen") {
                            let f = grams / 100
                            store.add(FoodEntry(date: Calendar.current.isDateInToday(day) ? Date() : day, name: p.name,
                                                kcal: p.kcal100 * f, protein: p.protein100 * f, carbs: p.carbs100 * f,
                                                fat: p.fat100 * f, grams: grams, source: "Barcode"))
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Barcode scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }

    private func lookup(_ barcode: String) async {
        loading = true
        defer { loading = false }
        do {
            if let p = try await OpenFoodFacts.product(barcode) { product = p } else { error = "Produkt \(barcode) nicht gefunden – manuell eintragen." }
        } catch {
            self.error = "Keine Verbindung zur Datenbank."
        }
    }
}

struct BarcodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .balanced,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let b) = item, let value = b.payloadStringValue {
                    dataScanner.stopScanning()
                    onScan(value)
                    return
                }
            }
        }
    }
}

// MARK: - Manual & targets

struct ManualFoodView: View {
    @Environment(NutritionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: Date
    @State private var name = ""
    @State private var kcal: Double = 0
    @State private var protein: Double = 0
    @State private var carbs: Double = 0
    @State private var fat: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Was? (z.B. Proteinshake)", text: $name)
                field("Kalorien (kcal)", $kcal)
                field("Protein (g)", $protein)
                field("Kohlenhydrate (g)", $carbs)
                field("Fett (g)", $fat)
            }
            .navigationTitle("Manuell eintragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        store.add(FoodEntry(date: Calendar.current.isDateInToday(day) ? Date() : day, name: name, kcal: kcal,
                                            protein: protein, carbs: carbs, fat: fat, grams: nil, source: "Manuell"))
                        dismiss()
                    }
                    .disabled(name.isEmpty || kcal <= 0)
                }
            }
        }
    }

    private func field(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
        }
    }
}

struct TargetsView: View {
    @Environment(NutritionStore.self) private var store
    @Environment(WeightStore.self) private var weight
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    Stepper("Kalorien: \(Int(store.kcalTarget)) kcal", value: $store.kcalTarget, in: 1200...5000, step: 50)
                    Stepper("Protein: \(Int(store.proteinTarget)) g", value: $store.proteinTarget, in: 40...300, step: 5)
                } header: {
                    Text("Tagesziele")
                }
                if let w = weight.currentTrend {
                    Section {
                        Button("Protein auf \(Int(w * 1.8)) g setzen (1.8 g pro kg)") { store.proteinTarget = (w * 1.8).rounded() }
                    } footer: {
                        Text("Für Muskelaufbau gelten etwa 1.6–2.2 g Protein pro kg Körpergewicht als sinnvoll.")
                    }
                }
            }
            .navigationTitle("Ziele")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}
