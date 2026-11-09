import SwiftUI

/// Step-by-step instructions shown inside the app.
struct KeyGuide {
    let title: String
    let intro: String
    let steps: [(text: String, link: URL?)]
    let note: String?

    static let claude = KeyGuide(
        title: "Claude-Key (KI-Coach & Foto-Erkennung)",
        intro: "Du zahlst nur, was du nutzt: ein Trainingsplan kostet etwa 10–20 Rappen, eine Foto-Schätzung wenige Rappen.",
        steps: [
            ("Anthropic Console öffnen und mit E-Mail oder Google ein Konto erstellen.", URL(string: "https://console.anthropic.com/")),
            ("Unter „Billing“ (Plans & Billing) Guthaben aufladen, z.B. 5 $. Optional ein monatliches Limit setzen.", URL(string: "https://console.anthropic.com/settings/billing")),
            ("Unter „API Keys“ auf „Create Key“ tippen, Name „Vital“, und den Key (beginnt mit sk-ant-) kopieren. Er wird nur einmal angezeigt.", URL(string: "https://console.anthropic.com/settings/keys")),
            ("Zurück in Vital: Einstellungen → KI-Coach → Key einfügen.", nil),
            ("Testen: Training → „KI-Trainingsplan erstellen“ oder Essen → „Foto (KI)“.", nil),
        ],
        note: "Der Key bleibt nur auf deinem iPhone. Bei Verdacht auf Missbrauch kannst du ihn in der Console jederzeit löschen.")
}

extension KeyGuide {
    static let openai = KeyGuide(
        title: "OpenAI-Key",
        intro: "Achtung: Ein ChatGPT-Abo (Plus/Pro) gilt NICHT für die API. Die API wird separat über Guthaben abgerechnet.",
        steps: [
            ("OpenAI-Plattform öffnen und mit deinem ChatGPT-/OpenAI-Konto anmelden.", URL(string: "https://platform.openai.com/")),
            ("Unter „Billing“ prüfen, ob API-Guthaben vorhanden ist – sonst z.B. 5 $ aufladen.", URL(string: "https://platform.openai.com/settings/organization/billing/overview")),
            ("Unter „API keys“ → „Create new secret key“ → Name „Vital“ → Key kopieren (beginnt mit sk-, wird nur einmal angezeigt).", URL(string: "https://platform.openai.com/api-keys")),
            ("Zurück in der App: Einstellungen → KI → „OpenAI“ wählen → Key einfügen.", nil),
            ("Modell: Standard ist „gpt-5-mini“. Unter platform.openai.com/docs/models siehst du die aktuellen Namen, falls du ein anderes willst.", URL(string: "https://platform.openai.com/docs/models")),
        ],
        note: "Für Foto-Erkennung muss das Modell Bilder verstehen (bei den aktuellen GPT-Modellen der Fall).")
}

struct KeyGuideView: View {
    let guide: KeyGuide

    var body: some View {
        List {
            Section { Text(guide.intro) }
            Section("Schritte") {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)").font(.headline).frame(width: 28, height: 28)
                            .background(Theme.accent.opacity(0.25), in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(step.text)
                            if let link = step.link {
                                Link(destination: link) { Label("Öffnen", systemImage: "arrow.up.right.square") }
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
            }
            if let note = guide.note { Section { Text(note).font(.footnote).foregroundStyle(.secondary) } }
        }
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
