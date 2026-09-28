import SwiftUI

enum MintTheme {
    static let background = Color(red: 0.043, green: 0.078, blue: 0.078)
    static let card = Color(red: 0.072, green: 0.130, blue: 0.139)
    static let mint = Color(red: 0.180, green: 0.902, blue: 0.714)
    static let teal = Color(red: 0.055, green: 0.239, blue: 0.227)
}

struct MintTypography: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var size = 16.0
    func body(content: Content) -> some View { content.font(.system(size: size)).tint(MintTheme.mint).preferredColorScheme(.dark) }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Form {
            Section("Transcription & AI") {
                Picker("Transcription", selection: $model.mode) {
                    Text("Meta Muse · live cloud").tag("meta")
                    Text("Voz · local on Assist").tag("voz")
                    Text("Parakeet · local live").tag("parakeet")
                }.disabled(model.activeSession != nil || model.isPreparing).accessibilityIdentifier("speech-provider")
                if model.mode != "meta" {
                    NavigationLink("Model Library") { ModelLibraryView() }
                    NavigationLink("Speech benchmark") { ModelLabView() }
                }
                NavigationLink { AssistantLabView() } label: { Label("Assistant models & timing", systemImage: "slider.horizontal.3") }.accessibilityIdentifier("assistant-lab")
                Text(model.mode == "meta" ? "Audio streams through your PC to Meta. No model download. Cloud usage is billed by Meta. Recording stops if the connection fails; resume to reconnect." : "Audio is transcribed on this iPhone. Only text is sent to your PC.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Section("Display") {
                LabeledContent("Text size", value: "16 pt · follows Dynamic Type")
                LabeledContent("Appearance", value: "Midnight Mint")
            }
            Section("Devices") {
                NavigationLink { PairingView() } label: { Label("Pair Windows PC", systemImage: "desktopcomputer") }.accessibilityIdentifier("pair-pc")
            }
            Section("Privacy") {
                Text("The Meta API key stays encrypted on your Windows PC and is never sent to this iPhone. Your phone stores only its PC pairing token in Keychain. Live audio is not saved by the relay; transcripts and replies appear in desktop memory and are saved in your iPhone history. Obtain permission before recording others.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(MintTheme.background).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
    }
}
