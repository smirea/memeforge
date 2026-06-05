import Foundation

enum SharedSettings {
	static let appGroupID = "group.com.stefan.memeforge"
	static let geminiModel = "gemini-3.1-flash-image"

	private static let keyboardFullAccessKey = "keyboardHasFullAccess"
	private static let copiedPreviewDataKey = "copiedMemePreviewData"
	private static let copiedPreviewVersionKey = "copiedMemePreviewVersion"
	private static let giphyMemeHistoryKey = "giphyMemeHistory"
	private static let appShowsSettingsKey = "appShowsSettings"
	private static let appMemeModeKey = "appMemeMode"

	struct GiphyMemeHistoryItem: Codable, Equatable {
		var title: String
		var previewURL: URL?
		var previewVideoURL: URL?
		var copyURL: URL
		var pasteboardType: String
		var useCount: Int
		var lastUsedAt: TimeInterval
	}

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

	static var appShowsSettings: Bool {
		get { store.object(forKey: appShowsSettingsKey) as? Bool ?? false }
		set { store.set(newValue, forKey: appShowsSettingsKey) }
	}

	static var appMemeMode: String {
		get { store.string(forKey: appMemeModeKey) ?? "search" }
		set { store.set(newValue, forKey: appMemeModeKey) }
	}

	static var copiedMemePreviewData: Data? {
		store.data(forKey: copiedPreviewDataKey)
	}

	static var copiedMemePreviewVersion: Double {
		store.double(forKey: copiedPreviewVersionKey)
	}

	static func updateCopiedMemePreview(_ data: Data) {
		store.set(data, forKey: copiedPreviewDataKey)
		store.set(Date().timeIntervalSince1970, forKey: copiedPreviewVersionKey)
	}

	static var giphyMemeHistory: [GiphyMemeHistoryItem] {
		guard let data = store.data(forKey: giphyMemeHistoryKey),
			let history = try? JSONDecoder().decode([GiphyMemeHistoryItem].self, from: data)
		else {
			return []
		}
		return history
	}

	@discardableResult
	static func recordGiphyMeme(
		title: String,
		previewURL: URL?,
		previewVideoURL: URL?,
		copyURL: URL,
		pasteboardType: String
	) -> Int {
		var history = giphyMemeHistory
		let now = Date().timeIntervalSince1970

		if let existingIndex = history.firstIndex(where: { $0.copyURL == copyURL }) {
			var item = history.remove(at: existingIndex)
			item.title = title
			item.previewURL = previewURL
			item.previewVideoURL = previewVideoURL
			item.pasteboardType = pasteboardType
			item.useCount = max(0, item.useCount) + 1
			item.lastUsedAt = now
			history.insert(item, at: 0)
			saveGiphyMemeHistory(history)
			return item.useCount
		}

		let item = GiphyMemeHistoryItem(
			title: title,
			previewURL: previewURL,
			previewVideoURL: previewVideoURL,
			copyURL: copyURL,
			pasteboardType: pasteboardType,
			useCount: 1,
			lastUsedAt: now
		)
		history.insert(item, at: 0)
		saveGiphyMemeHistory(history)
		return item.useCount
	}

	private static func bundledValue(forInfoKey key: String) -> String {
		let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
		let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return trimmed.hasPrefix("$(") ? "" : trimmed
	}

	private static func saveGiphyMemeHistory(_ history: [GiphyMemeHistoryItem]) {
		guard let data = try? JSONEncoder().encode(history) else { return }
		store.set(data, forKey: giphyMemeHistoryKey)
	}
}
