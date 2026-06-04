import SwiftUI

struct ContentView: View {
	@State private var giphyAPIKey = SharedSettings.giphyAPIKey
	@State private var geminiAPIKey = SharedSettings.geminiAPIKey
	@State private var keyboardTest = ""
	@State private var saved = false

	var body: some View {
		NavigationStack {
			Form {
				Section("API Keys") {
					SecureField("GIPHY API key", text: $giphyAPIKey)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
					SecureField("Gemini API key", text: $geminiAPIKey)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
					Button(saved ? "Saved" : "Save Keys") {
						SharedSettings.giphyAPIKey = giphyAPIKey
						SharedSettings.geminiAPIKey = geminiAPIKey
						saved = true
					}
				}

				Section("Full Access") {
					Label("Settings > General > Keyboard > Keyboards > Memeforge", systemImage: "keyboard")
					Label("Turn on Allow Full Access", systemImage: "network")
					Button("Open Settings") {
						guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
						UIApplication.shared.open(url)
					}
				}

				Section("Keyboard Test") {
					TextField("Test keyboard input", text: $keyboardTest)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
				}

				Section("Generation") {
					LabeledContent("Model", value: SharedSettings.geminiModel)
				}
			}
			.navigationTitle("Memeforge")
			.onChange(of: giphyAPIKey) { _, _ in saved = false }
			.onChange(of: geminiAPIKey) { _, _ in saved = false }
		}
	}
}
