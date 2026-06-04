import Foundation

enum SharedSettings {
	static let appGroupID = "group.com.stefan.memeforge"
	static let geminiModel = "gemini-3.1-flash-image"

	private static let giphyKey = "giphyAPIKey"
	private static let geminiKey = "geminiAPIKey"

	static var store: UserDefaults {
		UserDefaults(suiteName: appGroupID) ?? .standard
	}

	static var giphyAPIKey: String {
		get { storedValue(forKey: giphyKey) ?? bundledValue(forInfoKey: "MemeforgeGIPHYAPIKey") }
		set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: giphyKey) }
	}

	static var geminiAPIKey: String {
		get { storedValue(forKey: geminiKey) ?? bundledValue(forInfoKey: "MemeforgeGeminiAPIKey") }
		set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: geminiKey) }
	}

	private static func storedValue(forKey key: String) -> String? {
		let value = store.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
		return value?.isEmpty == false ? value : nil
	}

	private static func bundledValue(forInfoKey key: String) -> String {
		let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
		let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return trimmed.hasPrefix("$(") ? "" : trimmed
	}
}
