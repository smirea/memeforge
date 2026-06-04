import Foundation

enum SharedSettings {
	static let appGroupID = "group.com.stefan.memeforge"
	static let geminiModel = "gemini-3.1-flash-image"

	private static let keyboardFullAccessKey = "keyboardHasFullAccess"

	static var store: UserDefaults {
		UserDefaults(suiteName: appGroupID) ?? .standard
	}

	static var giphyAPIKey: String {
		bundledValue(forInfoKey: "MemeforgeGIPHYAPIKey")
	}

	static var geminiAPIKey: String {
		bundledValue(forInfoKey: "MemeforgeGeminiAPIKey")
	}

	static var keyboardHasFullAccess: Bool {
		get { store.bool(forKey: keyboardFullAccessKey) }
		set { store.set(newValue, forKey: keyboardFullAccessKey) }
	}

	private static func bundledValue(forInfoKey key: String) -> String {
		let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
		let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return trimmed.hasPrefix("$(") ? "" : trimmed
	}
}
