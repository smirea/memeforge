import SwiftUI

struct ContentView: View {
	@Environment(\.scenePhase) private var scenePhase
	@State private var keyboardHasFullAccess = SharedSettings.keyboardHasFullAccess
	@State private var keyboardTest = ""

	var body: some View {
		NavigationStack {
			Form {
				if !keyboardHasFullAccess {
					Section("Full Access") {
						Button("Open Settings") {
							guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
							UIApplication.shared.open(url)
						}
						Text("Go to General > Keyboard > Keyboards > Memeforge and turn on Allow Full Access.")
							.foregroundStyle(.secondary)
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
			.onAppear(perform: refreshPermissionState)
			.onChange(of: scenePhase) { _, phase in
				if phase == .active {
					refreshPermissionState()
				}
			}
		}
	}

	private func refreshPermissionState() {
		keyboardHasFullAccess = SharedSettings.keyboardHasFullAccess
	}
}
