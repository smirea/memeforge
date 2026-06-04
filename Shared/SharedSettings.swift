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
		get { store.string(forKey: giphyKey) ?? "" }
		set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: giphyKey) }
	}

	static var geminiAPIKey: String {
		get { store.string(forKey: geminiKey) ?? "" }
		set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: geminiKey) }
	}
}
