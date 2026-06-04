import SwiftUI
import UIKit

struct ContentView: View {
	@Environment(\.scenePhase) private var scenePhase
	@State private var keyboardHasFullAccess = SharedSettings.keyboardHasFullAccess
	@State private var keyboardTest = ""
	@State private var copiedImage: UIImage?
	@State private var copiedPreviewVersion = SharedSettings.copiedMemePreviewVersion
	@FocusState private var keyboardTestFocused: Bool

	private let previewTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

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
					HStack(spacing: 12) {
						TextField("Test keyboard input", text: $keyboardTest)
							.textInputAutocapitalization(.never)
							.autocorrectionDisabled()
							.focused($keyboardTestFocused)

						if let copiedImage {
							Image(uiImage: copiedImage)
								.resizable()
								.scaledToFill()
								.frame(width: 64, height: 64)
								.clipShape(RoundedRectangle(cornerRadius: 8))
								.accessibilityLabel("Copied meme preview")
						}
					}
					.contentShape(Rectangle())
					.simultaneousGesture(TapGesture().onEnded(focusKeyboardTestInput))
				}

				Section("Generation") {
					LabeledContent("Model", value: SharedSettings.geminiModel)
				}
			}
			.navigationTitle("Memeforge")
			.onAppear {
				refreshPermissionState()
				refreshCopiedImage(force: true)
			}
			.onReceive(previewTimer) { _ in
				refreshCopiedImage()
			}
			.onChange(of: scenePhase) { _, phase in
				if phase == .active {
					refreshPermissionState()
					refreshCopiedImage(force: true)
				}
			}
		}
	}

	private func refreshPermissionState() {
		keyboardHasFullAccess = SharedSettings.keyboardHasFullAccess
	}

	private func refreshCopiedImage(force: Bool = false) {
		let version = SharedSettings.copiedMemePreviewVersion
		guard force || version != copiedPreviewVersion else { return }
		copiedPreviewVersion = version
		copiedImage = SharedSettings.copiedMemePreviewData.flatMap(UIImage.init(data:))
	}

	private func focusKeyboardTestInput() {
		keyboardTestFocused = false
		DispatchQueue.main.async {
			keyboardTestFocused = true
		}
	}
}
