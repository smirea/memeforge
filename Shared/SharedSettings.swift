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
	private static let generationHistoryKey = "generationHistory"
	private static let appShowsSettingsKey = "appShowsSettings"
	private static let appMemeModeKey = "appMemeMode"
	private static let appMemeSortOrderKey = "appMemeSortOrder"
	private static let appearanceThemeKey = "appearanceTheme"
	private static let generationAssetMaxSide: CGFloat = 1280
	private static let generationHistoryMaxCount = 80

	enum AppearanceTheme: String, CaseIterable, Identifiable, Sendable {
		case light
		case dark
		case auto

		var id: Self { self }

		var title: String {
			switch self {
			case .light:
				"Light"
			case .dark:
				"Dark"
			case .auto:
				"Auto"
			}
		}

		var userInterfaceStyle: UIUserInterfaceStyle {
			switch self {
			case .light:
				.light
			case .dark:
				.dark
			case .auto:
				.unspecified
			}
		}
	}

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
		var name: String?
		var mimeType: String
		var addedAt: TimeInterval
		var useCount: Int
	}

	struct GenerationHistoryAsset: Codable, Equatable, Identifiable, Sendable {
		var id: UUID
		var filename: String
		var mimeType: String
	}

	struct GenerationHistoryStep: Codable, Equatable, Identifiable, Sendable {
		var id: UUID
		var prompt: String
		var createdAt: TimeInterval
		var attachments: [GenerationHistoryAsset]
		var images: [GenerationHistoryAsset]
	}

	struct GenerationHistoryItem: Codable, Equatable, Identifiable, Sendable {
		var id: UUID
		var createdAt: TimeInterval
		var updatedAt: TimeInterval
		var steps: [GenerationHistoryStep]

		init(id: UUID, createdAt: TimeInterval, updatedAt: TimeInterval, steps: [GenerationHistoryStep]) {
			self.id = id
			self.createdAt = createdAt
			self.updatedAt = updatedAt
			self.steps = steps
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			id = try container.decode(UUID.self, forKey: .id)

			if let steps = try container.decodeIfPresent([GenerationHistoryStep].self, forKey: .steps) {
				self.steps = steps
				createdAt = try container.decodeIfPresent(TimeInterval.self, forKey: .createdAt)
					?? steps.first?.createdAt
					?? 0
				updatedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .updatedAt)
					?? steps.last?.createdAt
					?? createdAt
				return
			}

			let createdAt = try container.decode(TimeInterval.self, forKey: .createdAt)
			let step = GenerationHistoryStep(
				id: id,
				prompt: try container.decode(String.self, forKey: .prompt),
				createdAt: createdAt,
				attachments: try container.decodeIfPresent([GenerationHistoryAsset].self, forKey: .attachments) ?? [],
				images: try container.decodeIfPresent([GenerationHistoryAsset].self, forKey: .images) ?? []
			)
			self.createdAt = createdAt
			updatedAt = createdAt
			steps = [step]
		}

		func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(id, forKey: .id)
			try container.encode(createdAt, forKey: .createdAt)
			try container.encode(updatedAt, forKey: .updatedAt)
			try container.encode(steps, forKey: .steps)
		}

		private enum CodingKeys: String, CodingKey {
			case id
			case createdAt
			case updatedAt
			case steps
			case prompt
			case attachments
			case images
		}
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

	static var appMemeSortOrder: String {
		get { store.string(forKey: appMemeSortOrderKey) ?? "date" }
		set { store.set(newValue, forKey: appMemeSortOrderKey) }
	}

	static var appearanceTheme: AppearanceTheme {
		get {
			store.string(forKey: appearanceThemeKey).flatMap(AppearanceTheme.init(rawValue:)) ?? .auto
		}
		set { store.set(newValue.rawValue, forKey: appearanceThemeKey) }
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
			var collection = try? JSONDecoder().decode([GenerationAssetItem].self, from: data)
		else {
			return []
		}
		if normalizeGenerationAssetCollection(&collection) {
			saveGenerationAssetCollection(collection)
		}
		return collection.sorted { $0.addedAt > $1.addedAt }
	}

	static var generationHistory: [GenerationHistoryItem] {
		guard let data = store.data(forKey: generationHistoryKey),
			let history = try? JSONDecoder().decode([GenerationHistoryItem].self, from: data)
		else {
			return []
		}
		return history.sorted { $0.updatedAt > $1.updatedAt }
	}

	static func normalizedGenerationAssetPayload(from data: Data) -> GenerationAssetPayload? {
		guard let image = UIImage(data: data) else { return nil }
		return normalizedGenerationAssetPayload(from: image)
	}

	static func normalizedGenerationAssetPayload(from image: UIImage) -> GenerationAssetPayload? {
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
		let collection = generationAssetCollection
		if let existing = collection.first(where: { item in
			guard let data = generationAssetData(for: item) else { return false }
			return data == payload.data
		}) {
			return existing
		}

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
			name: uniqueGenerationAssetName("image", excluding: id, in: collection),
			mimeType: payload.mimeType,
			addedAt: Date().timeIntervalSince1970,
			useCount: 0
		)
		var updatedCollection = collection
		updatedCollection.insert(item, at: 0)
		saveGenerationAssetCollection(updatedCollection)
		return item
	}

	static func generationAssetData(for item: GenerationAssetItem) -> Data? {
		guard let url = generationAssetURL(for: item.filename) else { return nil }
		return try? Data(contentsOf: url)
	}

	@discardableResult
	static func renameGenerationAsset(id: UUID, to rawName: String) -> GenerationAssetItem? {
		var collection = generationAssetCollection
		guard let index = collection.firstIndex(where: { $0.id == id }) else { return nil }
		collection[index].name = uniqueGenerationAssetName(rawName, excluding: id, in: collection)
		let item = collection[index]
		saveGenerationAssetCollection(collection)
		return item
	}

	static func generationHistoryData(for asset: GenerationHistoryAsset) -> Data? {
		guard let url = generationHistoryURL(for: asset.filename) else { return nil }
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
	static func recordGenerationHistory(
		id historyID: UUID,
		prompt: String,
		attachments: [GenerationAssetPayload],
		images: [GenerationAssetPayload]
	) -> GenerationHistoryItem? {
		guard !images.isEmpty, let directory = generationHistoryDirectory() else { return nil }
		let stepID = UUID()
		let now = Date().timeIntervalSince1970
		let imageAssets = images.enumerated().compactMap { index, payload in
			writeGenerationHistoryAsset(
				historyID: historyID,
				stepID: stepID,
				kind: "image",
				index: index,
				payload: payload,
				directory: directory
			)
		}
		guard !imageAssets.isEmpty else { return nil }

		let attachmentAssets = attachments.enumerated().compactMap { index, payload in
			writeGenerationHistoryAsset(
				historyID: historyID,
				stepID: stepID,
				kind: "attachment",
				index: index,
				payload: payload,
				directory: directory
			)
		}
		let step = GenerationHistoryStep(
			id: stepID,
			prompt: prompt,
			createdAt: now,
			attachments: attachmentAssets,
			images: imageAssets
		)
		var history = generationHistory
		let item: GenerationHistoryItem
		if let existingIndex = history.firstIndex(where: { $0.id == historyID }) {
			item = history.remove(at: existingIndex).appending(step, updatedAt: now)
		} else {
			item = GenerationHistoryItem(id: historyID, createdAt: now, updatedAt: now, steps: [step])
		}
		history.insert(item, at: 0)
		saveGenerationHistory(history)
		return item
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

	static func generationAssetKebabName(_ rawName: String) -> String {
		let folded = rawName
			.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
			.lowercased()

		var result = ""
		var pendingSeparator = false
		for scalar in folded.unicodeScalars {
			if CharacterSet.alphanumerics.contains(scalar) {
				if pendingSeparator, !result.isEmpty {
					result.append("-")
				}
				result.unicodeScalars.append(scalar)
				pendingSeparator = false
			} else if !result.isEmpty {
				pendingSeparator = true
			}
		}
		return result.isEmpty ? "image" : result
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

	private static func normalizeGenerationAssetCollection(_ collection: inout [GenerationAssetItem]) -> Bool {
		var changed = false
		var usedNames: Set<String> = []
		let indices = collection.indices.sorted { lhs, rhs in
			if collection[lhs].addedAt != collection[rhs].addedAt {
				return collection[lhs].addedAt < collection[rhs].addedAt
			}
			return collection[lhs].id.uuidString < collection[rhs].id.uuidString
		}

		for index in indices {
			let normalized = uniqueGenerationAssetName(collection[index].name ?? "image", usedNames: usedNames)
			usedNames.insert(normalized)
			if collection[index].name != normalized {
				collection[index].name = normalized
				changed = true
			}
		}
		return changed
	}

	private static func uniqueGenerationAssetName(_ rawName: String, excluding id: UUID, in collection: [GenerationAssetItem]) -> String {
		let usedNames = Set(collection.compactMap { item in
			item.id == id ? nil : item.displayName
		})
		return uniqueGenerationAssetName(rawName, usedNames: usedNames)
	}

	private static func uniqueGenerationAssetName(_ rawName: String, usedNames: Set<String>) -> String {
		let baseName = generationAssetKebabName(rawName)
		guard usedNames.contains(baseName) else { return baseName }

		var suffix = 2
		while usedNames.contains("\(baseName)-\(suffix)") {
			suffix += 1
		}
		return "\(baseName)-\(suffix)"
	}

	private static func saveGenerationHistory(_ history: [GenerationHistoryItem]) {
		let sorted = history.sorted { $0.updatedAt > $1.updatedAt }
		let trimmed = Array(sorted.prefix(generationHistoryMaxCount))
		guard let data = try? JSONEncoder().encode(trimmed) else { return }
		store.set(data, forKey: generationHistoryKey)
		pruneGenerationHistoryFiles(keeping: Set(trimmed.flatMap { item in
			item.steps.flatMap { step in
				(step.attachments + step.images).map(\.filename)
			}
		}))
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

	private static func generationHistoryDirectory() -> URL? {
		let baseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
			?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
		guard let directory = baseURL?.appendingPathComponent("GenerationHistory", isDirectory: true) else { return nil }
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	private static func generationHistoryURL(for filename: String) -> URL? {
		generationHistoryDirectory()?.appendingPathComponent(filename)
	}

	private static func writeGenerationHistoryAsset(
		historyID: UUID,
		stepID: UUID,
		kind: String,
		index: Int,
		payload: GenerationAssetPayload,
		directory: URL
	) -> GenerationHistoryAsset? {
		let id = UUID()
		let filename = "\(historyID.uuidString)-\(stepID.uuidString)-\(kind)-\(index)-\(id.uuidString).\(generationAssetExtension(for: payload.mimeType))"
		let url = directory.appendingPathComponent(filename)
		do {
			try payload.data.write(to: url, options: .atomic)
			return GenerationHistoryAsset(id: id, filename: filename, mimeType: payload.mimeType)
		} catch {
			return nil
		}
	}

	private static func pruneGenerationHistoryFiles(keeping retainedFilenames: Set<String>) {
		guard let directory = generationHistoryDirectory(),
			let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
		else {
			return
		}
		for url in urls where !retainedFilenames.contains(url.lastPathComponent) {
			try? FileManager.default.removeItem(at: url)
		}
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

private extension SharedSettings.GenerationHistoryItem {
	func appending(_ step: SharedSettings.GenerationHistoryStep, updatedAt: TimeInterval) -> Self {
		var item = self
		item.steps.append(step)
		item.updatedAt = updatedAt
		return item
	}
}

extension SharedSettings.GenerationAssetItem {
	var displayName: String {
		if let name, !name.isEmpty {
			return name
		}
		let baseName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
		return SharedSettings.generationAssetKebabName(baseName)
	}
}

extension String {
	var trailingGenerationAssetMentionQuery: String? {
		guard let atIndex = lastIndex(of: "@") else { return nil }
		let query = self[index(after: atIndex)...]
		guard query.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
		let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
		guard query.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else { return nil }
		return String(query)
	}

	func replacingTrailingGenerationAssetMention(with name: String) -> String {
		guard !containsGenerationAssetMention(named: name) else { return self }
		guard trailingGenerationAssetMentionQuery != nil,
			let atIndex = lastIndex(of: "@")
		else {
			return isEmpty ? "@\(name) " : "\(self) @\(name) "
		}
		return "\(self[..<atIndex])@\(name) "
	}

	private func containsGenerationAssetMention(named name: String) -> Bool {
		let mention = "@\(name)"
		var searchStart = startIndex
		let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

		while let range = range(of: mention, range: searchStart..<endIndex) {
			let startsAtBoundary = range.lowerBound == startIndex
				|| self[index(before: range.lowerBound)].isWhitespace
			let endsAtBoundary = range.upperBound == endIndex
				|| !String(self[range.upperBound]).unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
			if startsAtBoundary && endsAtBoundary {
				return true
			}
			searchStart = range.upperBound
		}
		return false
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
