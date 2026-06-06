import Foundation
import UIKit

enum SharedSettings {
	static let appGroupID = "group.com.stefan.memeforge"
	static let geminiModel = "gemini-3.1-flash-image"

	private static let keyboardFullAccessKey = "keyboardHasFullAccess"
	private static let copiedPreviewDataKey = "copiedMemePreviewData"
	private static let copiedPreviewVersionKey = "copiedMemePreviewVersion"
	private static let giphyMemeHistoryKey = "giphyMemeHistory"
	private static let generationAssetCollectionKey = "generationAssetCollection"
	private static let appShowsSettingsKey = "appShowsSettings"
	private static let appMemeModeKey = "appMemeMode"
	private static let generationAssetMaxSide: CGFloat = 1280

	struct GiphyMemeHistoryItem: Codable, Equatable {
		var title: String
		var previewURL: URL?
		var previewVideoURL: URL?
		var copyURL: URL
		var pasteboardType: String
		var useCount: Int
		var lastUsedAt: TimeInterval
	}

	struct GenerationAssetPayload: Hashable, Sendable {
		var data: Data
		var mimeType: String
	}

	struct GenerationAssetItem: Codable, Equatable, Identifiable, Sendable {
		var id: UUID
		var filename: String
		var mimeType: String
		var addedAt: TimeInterval
		var useCount: Int
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

	static var generationAssetCollection: [GenerationAssetItem] {
		guard let data = store.data(forKey: generationAssetCollectionKey),
			let collection = try? JSONDecoder().decode([GenerationAssetItem].self, from: data)
		else {
			return []
		}
		return collection.sorted { $0.addedAt > $1.addedAt }
	}

	static func normalizedGenerationAssetPayload(from data: Data) -> GenerationAssetPayload? {
		guard let image = UIImage(data: data) else { return nil }
		let normalized = image.resizedToFit(maxSide: generationAssetMaxSide)

		if normalized.hasAlpha, let pngData = normalized.pngData() {
			return GenerationAssetPayload(data: pngData, mimeType: "image/png")
		}
		if let jpegData = normalized.jpegData(compressionQuality: 0.9) {
			return GenerationAssetPayload(data: jpegData, mimeType: "image/jpeg")
		}
		if let pngData = normalized.pngData() {
			return GenerationAssetPayload(data: pngData, mimeType: "image/png")
		}
		return nil
	}

	@discardableResult
	static func addGenerationAsset(_ payload: GenerationAssetPayload) -> GenerationAssetItem? {
		guard let directory = generationAssetDirectory() else { return nil }
		let id = UUID()
		let filename = "\(id.uuidString).\(generationAssetExtension(for: payload.mimeType))"
		let url = directory.appendingPathComponent(filename)

		do {
			try payload.data.write(to: url, options: .atomic)
		} catch {
			return nil
		}

		let item = GenerationAssetItem(
			id: id,
			filename: filename,
			mimeType: payload.mimeType,
			addedAt: Date().timeIntervalSince1970,
			useCount: 0
		)
		var collection = generationAssetCollection
		collection.insert(item, at: 0)
		saveGenerationAssetCollection(collection)
		return item
	}

	static func generationAssetData(for item: GenerationAssetItem) -> Data? {
		guard let url = generationAssetURL(for: item.filename) else { return nil }
		return try? Data(contentsOf: url)
	}

	@discardableResult
	static func deleteGenerationAsset(id: UUID) -> Bool {
		var collection = generationAssetCollection
		guard let index = collection.firstIndex(where: { $0.id == id }) else { return false }
		let item = collection.remove(at: index)
		if let url = generationAssetURL(for: item.filename) {
			try? FileManager.default.removeItem(at: url)
		}
		saveGenerationAssetCollection(collection)
		return true
	}

	@discardableResult
	static func recordGenerationAssetUses(_ ids: [UUID]) -> [UUID: Int] {
		let usedIDs = Set(ids)
		guard !usedIDs.isEmpty else { return [:] }

		var collection = generationAssetCollection
		var counts: [UUID: Int] = [:]
		for index in collection.indices where usedIDs.contains(collection[index].id) {
			collection[index].useCount = max(0, collection[index].useCount) + 1
			counts[collection[index].id] = collection[index].useCount
		}
		saveGenerationAssetCollection(collection)
		return counts
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

	@discardableResult
	static func deleteGiphyMeme(copyURL: URL) -> Bool {
		var history = giphyMemeHistory
		let oldCount = history.count
		history.removeAll { $0.copyURL == copyURL }
		guard history.count != oldCount else { return false }
		saveGiphyMemeHistory(history)
		return true
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

	private static func saveGenerationAssetCollection(_ collection: [GenerationAssetItem]) {
		let sorted = collection.sorted { $0.addedAt > $1.addedAt }
		guard let data = try? JSONEncoder().encode(sorted) else { return }
		store.set(data, forKey: generationAssetCollectionKey)
	}

	private static func generationAssetDirectory() -> URL? {
		let baseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
			?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
		guard let directory = baseURL?.appendingPathComponent("GenerationAssets", isDirectory: true) else { return nil }
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	private static func generationAssetURL(for filename: String) -> URL? {
		generationAssetDirectory()?.appendingPathComponent(filename)
	}

	private static func generationAssetExtension(for mimeType: String) -> String {
		switch mimeType {
		case "image/jpeg":
			"jpg"
		case "image/png":
			"png"
		default:
			"img"
		}
	}
}

private extension UIImage {
	var hasAlpha: Bool {
		guard let alphaInfo = cgImage?.alphaInfo else { return false }
		switch alphaInfo {
		case .first, .last, .premultipliedFirst, .premultipliedLast:
			return true
		default:
			return false
		}
	}

	func resizedToFit(maxSide: CGFloat) -> UIImage {
		let longestSide = max(size.width, size.height)
		guard longestSide > maxSide, longestSide > 0 else { return self }
		let scale = maxSide / longestSide
		let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = !hasAlpha
		return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
			draw(in: CGRect(origin: .zero, size: targetSize))
		}
	}
}
