import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
	@State private var model = MemeForgeModel()
	@State private var showsSettings = SharedSettings.appShowsSettings

	var body: some View {
		NavigationStack {
			Group {
				if showsSettings {
					SettingsView()
				} else {
					MemeForgeView(model: model)
				}
			}
			.navigationTitle(showsSettings ? "Settings" : "Memeforge")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button(action: toggleMode) {
						Image(systemName: "gearshape")
					}
					.accessibilityLabel(showsSettings ? "Show Memeforge" : "Show settings")
				}
			}
			.onOpenURL { url in
				if url.host == "setup" || url.path == "/setup" {
					setShowsSettings(true)
				}
			}
		}
	}

	private func toggleMode() {
		setShowsSettings(!showsSettings)
	}

	private func setShowsSettings(_ value: Bool) {
		showsSettings = value
		SharedSettings.appShowsSettings = value
	}
}

private struct MemeForgeView: View {
	@Bindable var model: MemeForgeModel
	@State private var addPickerItems: [PhotosPickerItem] = []
	@State private var pickPickerItems: [PhotosPickerItem] = []
	@FocusState private var inputFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			Picker("Mode", selection: $model.mode) {
				ForEach(MemeMode.allCases) { mode in
					Text(mode.title).tag(mode)
				}
			}
			.pickerStyle(.segmented)
			.padding(.horizontal)
			.padding(.top, 8)

			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					inputArea

					if let requestError = model.requestError {
						RequestErrorView(requestError: requestError)
					}

					if model.isLoading, model.results.isEmpty {
						LoadingTilesGrid(mode: model.mode)
					}

					if !model.results.isEmpty {
						MemeResultsGrid(model: model)
					}
				}
				.padding()
			}
			.scrollDismissesKeyboard(.interactively)
			.overlay(alignment: .bottom) {
				if let statusMessage = model.statusMessage {
					Text(statusMessage)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.white)
						.padding(.horizontal, 16)
						.padding(.vertical, 10)
						.background(.black.opacity(0.76), in: Capsule())
						.padding(.bottom, 16)
						.transition(.move(edge: .bottom).combined(with: .opacity))
				}
			}
		}
		.animation(.snappy, value: model.statusMessage)
		.onAppear {
			model.refreshHistoryIfNeeded()
			model.refreshGenerationAssetCollection()
		}
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
			model.refreshHistoryIfNeeded()
			model.refreshGenerationAssetCollection()
		}
	}

	private var inputArea: some View {
		VStack(alignment: .leading, spacing: 10) {
			if model.mode == .generate && model.showingAssetPicker {
				generationAssetPickerArea
			} else {
				queryInputArea
				if model.mode == .generate, !model.selectedGenerationAssets.isEmpty {
					SelectedGenerationAssetsStrip(assets: model.selectedGenerationAssets) { asset in
						model.removeGenerationAsset(asset)
					}
				}
			}
		}
		.onChange(of: addPickerItems) { _, items in
			importPickerItems(items, saveToCollection: true)
			addPickerItems = []
		}
		.onChange(of: pickPickerItems) { _, items in
			importPickerItems(items, saveToCollection: false)
			pickPickerItems = []
		}
	}

	private var queryInputArea: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .top, spacing: 8) {
				ZStack(alignment: .trailing) {
					TextField(model.mode.placeholder, text: $model.query, axis: .vertical)
						.lineLimit(1...5)
						.padding(.leading, 10)
						.padding(.trailing, model.query.isEmpty ? 10 : 38)
						.padding(.vertical, 7)
						.background {
							RoundedRectangle(cornerRadius: 5)
								.fill(Color(.systemBackground))
								.stroke(Color(.separator).opacity(0.45), lineWidth: 1)
						}
						.textInputAutocapitalization(model.mode == .search ? .never : .sentences)
						.autocorrectionDisabled(model.mode == .search)
						.submitLabel(model.mode == .search ? .search : .done)
						.focused($inputFocused)
						.onSubmit {
							model.submit()
							inputFocused = false
						}

					if !model.query.isEmpty {
						Button {
							model.clearQuery()
							inputFocused = true
						} label: {
							Image(systemName: "xmark.circle.fill")
								.font(.body)
								.foregroundStyle(.secondary)
								.frame(width: 30, height: 30)
						}
						.buttonStyle(.plain)
						.padding(.trailing, 3)
						.accessibilityLabel("Clear")
					}
				}

				if model.mode == .generate {
					Button {
						model.showingAssetPicker = true
						inputFocused = false
					} label: {
						Image(systemName: "photo.stack")
							.frame(width: 22, height: 22)
					}
					.buttonStyle(.bordered)
					.disabled(model.isLoading)
					.accessibilityLabel("Choose generation assets")
				}
			}
		}
	}

	private var generationAssetPickerArea: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 10) {
				PhotosPicker(selection: $addPickerItems, maxSelectionCount: nil, matching: .images) {
					Label("Add", systemImage: "plus")
				}
				.buttonStyle(.borderedProminent)
				.disabled(model.isLoading)

				PhotosPicker(selection: $pickPickerItems, maxSelectionCount: nil, matching: .images) {
					Label("Pick", systemImage: "photo")
				}
				.buttonStyle(.bordered)
				.disabled(model.isLoading)

				Spacer()

				Button {
					model.showingAssetPicker = false
					inputFocused = true
				} label: {
					Image(systemName: "keyboard")
						.frame(width: 22, height: 22)
				}
				.buttonStyle(.bordered)
				.accessibilityLabel("Return to prompt")
			}

			if !model.selectedGenerationAssets.isEmpty {
				SelectedGenerationAssetsStrip(assets: model.selectedGenerationAssets) { asset in
					model.removeGenerationAsset(asset)
				}
			}

			if !model.generationAssetCollection.isEmpty {
				GenerationAssetCollectionGrid(items: model.generationAssetCollection) { item in
					model.insertGenerationAsset(item)
				}
			}
		}
	}

	private func importPickerItems(_ items: [PhotosPickerItem], saveToCollection: Bool) {
		guard !items.isEmpty else { return }
		inputFocused = false
		Task {
			var payloads: [SharedSettings.GenerationAssetPayload] = []
			for item in items {
				guard let data = try? await item.loadTransferable(type: Data.self),
					let payload = SharedSettings.normalizedGenerationAssetPayload(from: data)
				else {
					continue
				}
				payloads.append(payload)
			}
			await MainActor.run {
				model.insertPickedGenerationAssets(payloads, saveToCollection: saveToCollection)
			}
		}
	}

}

private struct MemeResultsGrid: View {
	@Bindable var model: MemeForgeModel

	private var columns: [GridItem] {
		resultGridColumns(for: model.mode)
	}

	var body: some View {
		LazyVGrid(columns: columns, spacing: 8) {
			ForEach(model.results) { result in
				MemeResultCell(result: result, copied: model.copiedResultID == result.id) {
					model.copy(result)
				}
				.onAppear {
					model.loadMoreSearchResultsIfNeeded(appearingResultID: result.id)
				}
			}

			if model.isLoading, !model.results.isEmpty {
				ProgressView()
					.frame(maxWidth: .infinity)
					.gridCellColumns(columns.count)
					.padding(.vertical, 16)
			}
		}
	}
}

private struct LoadingTilesGrid: View {
	let mode: MemeMode

	private var columns: [GridItem] {
		resultGridColumns(for: mode)
	}

	private var tileCount: Int {
		mode == .generate ? 2 : 6
	}

	var body: some View {
		LazyVGrid(columns: columns, spacing: 8) {
			ForEach(0..<tileCount, id: \.self) { _ in
				ZStack {
					Color(.secondarySystemBackground)
					ProgressView()
						.controlSize(.small)
				}
				.aspectRatio(1, contentMode: .fit)
				.clipShape(RoundedRectangle(cornerRadius: 8))
			}
		}
	}
}

private func resultGridColumns(for mode: MemeMode) -> [GridItem] {
	let minimum: CGFloat = mode == .generate ? 156 : 106
	return [GridItem(.adaptive(minimum: minimum), spacing: 8)]
}

private struct SelectedGenerationAssetsStrip: View {
	let assets: [SelectedGenerationAsset]
	let remove: (SelectedGenerationAsset) -> Void

	var body: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				ForEach(assets) { asset in
					SelectedGenerationAssetThumbnail(asset: asset) {
						remove(asset)
					}
				}
			}
			.padding(.vertical, 2)
		}
		.frame(height: 68)
	}
}

private struct SelectedGenerationAssetThumbnail: View {
	let asset: SelectedGenerationAsset
	let remove: () -> Void

	var body: some View {
		ZStack(alignment: .topTrailing) {
			Group {
				if let image = UIImage(data: asset.imageData) {
					Image(uiImage: image)
						.resizable()
						.scaledToFill()
				} else {
					Image(systemName: "photo")
						.font(.title2)
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
			}
			.frame(width: 64, height: 64)
			.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
			.clipShape(RoundedRectangle(cornerRadius: 8))

			Button(action: remove) {
				Image(systemName: "xmark")
					.font(.caption2.weight(.bold))
					.foregroundStyle(.white)
					.frame(width: 20, height: 20)
					.background(.black.opacity(0.72), in: Circle())
			}
			.buttonStyle(.plain)
			.padding(4)
			.accessibilityLabel("Remove generation asset")
		}
	}
}

private struct GenerationAssetCollectionGrid: View {
	let items: [SharedSettings.GenerationAssetItem]
	let select: (SharedSettings.GenerationAssetItem) -> Void

	private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

	var body: some View {
		LazyVGrid(columns: columns, spacing: 8) {
			ForEach(items) { item in
				GenerationAssetCollectionCell(item: item) {
					select(item)
				}
			}
		}
	}
}

private struct GenerationAssetCollectionCell: View {
	let item: SharedSettings.GenerationAssetItem
	let select: () -> Void

	@State private var image: UIImage?

	var body: some View {
		Button(action: select) {
			ZStack(alignment: .topTrailing) {
				ZStack {
					Color(.secondarySystemBackground)
					if let image {
						Image(uiImage: image)
							.resizable()
							.scaledToFill()
					} else {
						Image(systemName: "photo")
							.font(.title2)
							.foregroundStyle(.secondary)
					}
				}
				.aspectRatio(1, contentMode: .fill)
				.frame(maxWidth: .infinity)
				.clipShape(RoundedRectangle(cornerRadius: 8))

				if item.useCount > 0 {
					Text(item.useCount > 999 ? "999+" : "\(item.useCount)")
						.font(.caption2.weight(.bold))
						.foregroundStyle(.white)
						.padding(.horizontal, 6)
						.frame(minHeight: 20)
						.background(.black.opacity(0.68), in: Capsule())
						.padding(6)
				}
			}
		}
		.buttonStyle(.plain)
		.task(id: item.id) {
			image = SharedSettings.generationAssetData(for: item).flatMap(UIImage.init(data:))
		}
		.accessibilityLabel("Saved generation asset")
	}
}

private struct MemeResultCell: View {
	let result: MemeResult
	let copied: Bool
	let copy: () -> Void

	var body: some View {
		Button(action: copy) {
			ZStack(alignment: .topTrailing) {
				MemePreview(result: result)
					.frame(maxWidth: .infinity)
					.aspectRatio(1, contentMode: .fit)
					.clipShape(RoundedRectangle(cornerRadius: 8))
					.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

				if result.useCount > 0 {
					Text(result.useCount > 999 ? "999+" : "\(result.useCount)")
						.font(.caption2.weight(.bold))
						.foregroundStyle(.white)
						.padding(.horizontal, 6)
						.frame(minHeight: 20)
						.background(.black.opacity(0.68), in: Capsule())
						.padding(6)
				}

				if copied {
					Image(systemName: "checkmark.circle.fill")
						.font(.title2)
						.foregroundStyle(.white, .green)
						.padding(6)
				}
			}
			.contentShape(RoundedRectangle(cornerRadius: 8))
		}
		.buttonStyle(.plain)
		.accessibilityLabel(result.title.isEmpty ? "Meme" : result.title)
		.accessibilityHint("Copies this meme")
	}
}

private struct MemePreview: View {
	let result: MemeResult

	var body: some View {
		GeometryReader { proxy in
			ZStack {
				Color(.secondarySystemBackground)

				if let imageData = result.imageData, let image = UIImage.animatedGIF(data: imageData) ?? UIImage(data: imageData) {
					Image(uiImage: image)
						.resizable()
						.scaledToFill()
						.frame(width: proxy.size.width, height: proxy.size.height)
						.clipped()
				} else if let url = result.previewURL {
					AsyncImage(url: url) { phase in
						switch phase {
						case .empty:
							ProgressView()
						case .success(let image):
							image
								.resizable()
								.scaledToFill()
								.frame(width: proxy.size.width, height: proxy.size.height)
								.clipped()
						case .failure:
							Image(systemName: "photo")
								.font(.title2)
								.foregroundStyle(.secondary)
						@unknown default:
							EmptyView()
						}
					}
				} else {
					Image(systemName: "photo")
						.font(.title2)
						.foregroundStyle(.secondary)
				}
			}
		}
	}
}

private struct RequestErrorView: View {
	let requestError: RequestError

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Label(requestError.title, systemImage: "exclamationmark.triangle.fill")
				.font(.subheadline.weight(.bold))
				.foregroundStyle(.red)

			Text(requestError.detail)
				.font(.footnote)
				.foregroundStyle(.secondary)
				.textSelection(.enabled)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(12)
		.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
	}
}

private struct SettingsView: View {
	@Environment(\.scenePhase) private var scenePhase
	@State private var keyboardHasFullAccess = SharedSettings.keyboardHasFullAccess
	@State private var keyboardTest = ""
	@State private var copiedImage: UIImage?
	@State private var copiedPreviewVersion = SharedSettings.copiedMemePreviewVersion
	@FocusState private var keyboardTestFocused: Bool

	private let previewTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

	var body: some View {
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
		.onAppear {
			refreshPermissionState()
			refreshCopiedImage(force: true)
		}
		.onReceive(previewTimer) { _ in
			refreshCopiedImage()
		}
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
			refreshPermissionState()
			refreshCopiedImage(force: true)
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .active {
				refreshPermissionState()
				refreshCopiedImage(force: true)
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

@MainActor
@Observable
private final class MemeForgeModel {
	var mode: MemeMode {
		didSet {
			guard oldValue != mode else { return }
			SharedSettings.appMemeMode = mode.rawValue
			if mode != .generate {
				showingAssetPicker = false
			}
			resetResults()
			refreshHistoryIfNeeded()
			refreshGenerationAssetCollection()
		}
	}
	var query = "" {
		didSet {
			guard oldValue != query else { return }
			resetResults()
			refreshHistoryIfNeeded()
		}
	}
	var results: [MemeResult] = []
	var requestError: RequestError?
	var isLoading = false
	var showingHistory = false
	var showingAssetPicker = false {
		didSet {
			if showingAssetPicker {
				refreshGenerationAssetCollection()
			}
		}
	}
	var selectedGenerationAssets: [SelectedGenerationAsset] = []
	var generationAssetCollection: [SharedSettings.GenerationAssetItem] = []
	var statusMessage: String?
	var copiedResultID: UUID?

	private var searchQuery = ""
	private var searchOffset = 0
	private var canLoadMoreSearchResults = false
	private var pendingGenerationCount = 0
	private var currentTask: Task<Void, Never>?
	private var copyTask: Task<Void, Never>?
	private var statusTask: Task<Void, Never>?
	private var generationID = UUID()
	private var historyUseCounts: [String: Int] = [:]

	private let searchPageSize = 30
	private let generatedStyles = [
		"Classic photographic meme style.",
		"Bold illustrated meme style.",
	]

	init() {
		mode = MemeMode(rawValue: SharedSettings.appMemeMode) ?? .search
		refreshHistoryIfNeeded()
		refreshGenerationAssetCollection()
	}

	func submit() {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		requestError = nil
		guard !trimmed.isEmpty else {
			refreshHistoryIfNeeded()
			return
		}

		switch mode {
		case .search:
			search(trimmed)
		case .generate:
			generate(trimmed)
		}
	}

	func clearQuery() {
		query = ""
	}

	func refreshGenerationAssetCollection() {
		generationAssetCollection = SharedSettings.generationAssetCollection
	}

	func insertPickedGenerationAssets(_ payloads: [SharedSettings.GenerationAssetPayload], saveToCollection: Bool) {
		guard !payloads.isEmpty else { return }

		var assets: [SelectedGenerationAsset] = []
		for payload in payloads {
			if saveToCollection {
				guard let item = SharedSettings.addGenerationAsset(payload) else { continue }
				assets.append(SelectedGenerationAsset(collectionItem: item, imageData: payload.data))
			} else {
				assets.append(SelectedGenerationAsset(collectionID: nil, imageData: payload.data, mimeType: payload.mimeType, useCount: 0))
			}
		}
		guard !assets.isEmpty else { return }

		selectedGenerationAssets.append(contentsOf: assets)
		refreshGenerationAssetCollection()
		resetResults()
	}

	func insertGenerationAsset(_ item: SharedSettings.GenerationAssetItem) {
		guard !selectedGenerationAssets.contains(where: { $0.collectionID == item.id }),
			let data = SharedSettings.generationAssetData(for: item)
		else {
			return
		}
		selectedGenerationAssets.append(SelectedGenerationAsset(collectionItem: item, imageData: data))
		resetResults()
	}

	func removeGenerationAsset(_ asset: SelectedGenerationAsset) {
		selectedGenerationAssets.removeAll { $0.id == asset.id }
		resetResults()
	}

	func refreshHistoryIfNeeded() {
		guard mode == .search, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
		currentTask?.cancel()
		searchQuery = ""
		searchOffset = 0
		canLoadMoreSearchResults = false
		isLoading = false
		requestError = nil
		generationID = UUID()
		pendingGenerationCount = 0

		let history = SharedSettings.giphyMemeHistory
		historyUseCounts = history.reduce(into: [:]) { counts, item in
			counts[item.copyURL.absoluteString] = item.useCount
		}
		results = history.map(MemeResult.init(historyItem:))
		showingHistory = !results.isEmpty
	}

	func loadMoreSearchResultsIfNeeded(appearingResultID: UUID) {
		guard mode == .search,
			!showingHistory,
			canLoadMoreSearchResults,
			!isLoading,
			!searchQuery.isEmpty,
			results.last?.id == appearingResultID
		else {
			return
		}

		currentTask?.cancel()
		let query = searchQuery
		let offset = searchOffset
		currentTask = Task { [weak self] in
			await self?.fetchSearchResults(for: query, offset: offset, replacingResults: false)
		}
	}

	func copy(_ result: MemeResult) {
		copyTask?.cancel()
		copyTask = Task { [weak self] in
			await self?.copyResult(result)
		}
	}

	private func resetResults() {
		currentTask?.cancel()
		searchQuery = ""
		searchOffset = 0
		canLoadMoreSearchResults = false
		isLoading = false
		requestError = nil
		showingHistory = false
		results = []
		generationID = UUID()
		pendingGenerationCount = 0
		copiedResultID = nil
	}

	private func search(_ trimmed: String) {
		guard !SharedSettings.giphyAPIKey.isEmpty else {
			showRequestError(title: "GIPHY API key missing", detail: "MemeforgeGIPHYAPIKey is empty in this build.")
			return
		}

		currentTask?.cancel()
		searchQuery = trimmed
		searchOffset = 0
		canLoadMoreSearchResults = true
		isLoading = true
		showingHistory = false
		results = []

		currentTask = Task { [weak self] in
			await self?.fetchSearchResults(for: trimmed, offset: 0, replacingResults: true)
		}
	}

	private func fetchSearchResults(for query: String, offset: Int, replacingResults: Bool) async {
		isLoading = true

		do {
			let page = try await Self.giphyPage(for: query, offset: offset, pageSize: searchPageSize)
			guard searchQuery == query else { return }
			let countedItems = page.items.map(resultWithHistoryCount)
			results = replacingResults ? countedItems : results + countedItems
			requestError = nil
			searchOffset = page.nextOffset
			canLoadMoreSearchResults = page.hasMore && !page.items.isEmpty
			showingHistory = false
			isLoading = false
		} catch is CancellationError {
			guard searchQuery == query else { return }
			isLoading = false
		} catch let error as RequestError {
			guard searchQuery == query else { return }
			isLoading = false
			canLoadMoreSearchResults = false
			if results.isEmpty {
				requestError = error
			}
		} catch {
			guard searchQuery == query else { return }
			isLoading = false
			canLoadMoreSearchResults = false
			if results.isEmpty {
				requestError = RequestError(title: "GIPHY request failed", detail: error.localizedDescription)
			}
		}
	}

	private func generate(_ trimmed: String) {
		guard !SharedSettings.geminiAPIKey.isEmpty else {
			showRequestError(title: "Gemini API key missing", detail: "MemeforgeGeminiAPIKey is empty in this build.")
			return
		}

		currentTask?.cancel()
		let generationID = UUID()
		self.generationID = generationID
		searchQuery = ""
		searchOffset = 0
		canLoadMoreSearchResults = false
		isLoading = true
		showingHistory = false
		pendingGenerationCount = generatedStyles.count
		results = []
		let assets = selectedGenerationAssets
		recordSelectedGenerationAssetUses(assets)

		currentTask = Task { [weak self] in
			await self?.generateResults(for: trimmed, assets: assets, generationID: generationID)
		}
	}

	private func generateResults(for prompt: String, assets: [SelectedGenerationAsset], generationID: UUID) async {
		var firstError: RequestError?

		await withTaskGroup(of: Result<MemeResult, RequestError>.self) { group in
			for style in generatedStyles {
				group.addTask {
					await Self.geminiResult(for: prompt, style: style, assets: assets)
				}
			}

			for await generated in group {
				guard self.generationID == generationID else { return }
				pendingGenerationCount -= 1
				switch generated {
				case .success(let result):
					results.append(result)
				case .failure(let error):
					firstError = firstError ?? error
				}
			}
		}

		guard self.generationID == generationID else { return }
		isLoading = false
		pendingGenerationCount = 0
		if results.isEmpty {
			requestError = firstError ?? RequestError(title: "Generation failed", detail: "No image data came back from Gemini.")
		}
	}

	private func recordSelectedGenerationAssetUses(_ assets: [SelectedGenerationAsset]) {
		let counts = SharedSettings.recordGenerationAssetUses(assets.compactMap(\.collectionID))
		guard !counts.isEmpty else { return }

		refreshGenerationAssetCollection()
		for index in selectedGenerationAssets.indices {
			guard let collectionID = selectedGenerationAssets[index].collectionID,
				let useCount = counts[collectionID]
			else {
				continue
			}
			selectedGenerationAssets[index].useCount = useCount
		}
	}

	private func copyResult(_ result: MemeResult) async {
		do {
			let payload = try await Self.copyPayload(for: result)
			UIPasteboard.general.setData(payload.data, forPasteboardType: payload.pasteboardType)
			SharedSettings.updateCopiedMemePreview(payload.data)
			recordHistoryUse(for: result, pasteboardType: payload.pasteboardType)
			copiedResultID = result.id
			showStatus("Copied")
		} catch let error as RequestError {
			showRequestError(title: error.title, detail: error.detail)
		} catch {
			showRequestError(title: "Copy failed", detail: error.localizedDescription)
		}
	}

	private func showRequestError(title: String, detail: String) {
		requestError = RequestError(title: title, detail: detail)
		isLoading = false
		canLoadMoreSearchResults = false
		if results.isEmpty {
			showingHistory = false
		}
	}

	private func showStatus(_ text: String) {
		statusTask?.cancel()
		statusMessage = text
		statusTask = Task { [weak self] in
			try? await Task.sleep(nanoseconds: 1_400_000_000)
			await MainActor.run {
				if self?.statusMessage == text {
					self?.statusMessage = nil
					self?.copiedResultID = nil
				}
			}
		}
	}

	private func recordHistoryUse(for result: MemeResult, pasteboardType: String) {
		guard let copyURL = result.copyURL else { return }
		let useCount = SharedSettings.recordGiphyMeme(
			title: result.title,
			previewURL: result.previewURL,
			previewVideoURL: result.previewVideoURL,
			copyURL: copyURL,
			pasteboardType: pasteboardType
		)

		historyUseCounts[copyURL.absoluteString] = useCount
		guard let index = results.firstIndex(where: { $0.id == result.id }) else { return }
		results[index] = results[index].withUseCount(useCount)
	}

	private func resultWithHistoryCount(_ result: MemeResult) -> MemeResult {
		guard let key = result.historyKey, let useCount = historyUseCounts[key] else { return result }
		return result.withUseCount(useCount)
	}

	private nonisolated static func giphyPage(for query: String, offset: Int, pageSize: Int) async throws -> SearchPage {
		var components = URLComponents(string: "https://api.giphy.com/v1/gifs/search")
		components?.queryItems = [
			URLQueryItem(name: "api_key", value: SharedSettings.giphyAPIKey),
			URLQueryItem(name: "q", value: query),
			URLQueryItem(name: "limit", value: "\(pageSize)"),
			URLQueryItem(name: "offset", value: "\(offset)"),
			URLQueryItem(name: "rating", value: "pg-13"),
			URLQueryItem(name: "lang", value: "en"),
		]

		guard let url = components?.url else {
			throw RequestError(title: "GIPHY request failed", detail: "Could not build the search URL.")
		}

		let (data, response) = try await URLSession.shared.data(from: url)
		if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
			throw giphyHTTPError(statusCode: httpResponse.statusCode, data: data)
		}

		do {
			let response = try JSONDecoder().decode(GiphyResponse.self, from: data)
			let items = response.data.compactMap(MemeResult.init(giphyItem:))
			let loadedCount = response.pagination?.count ?? items.count
			let nextOffset = offset + loadedCount
			let totalCount = response.pagination?.totalCount
			let hasMore = totalCount.map { nextOffset < $0 } ?? (items.count == pageSize)
			return SearchPage(items: items, nextOffset: nextOffset, hasMore: hasMore)
		} catch {
			throw RequestError(title: "Could not read GIPHY response", detail: responseDetail(error: error, data: data))
		}
	}

	private nonisolated static func geminiResult(for prompt: String, style: String, assets: [SelectedGenerationAsset]) async -> Result<MemeResult, RequestError> {
		guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(SharedSettings.geminiModel):generateContent") else {
			return .failure(RequestError(title: "Generation failed", detail: "Could not build the Gemini URL."))
		}

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue(SharedSettings.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = geminiRequestBody(for: prompt, style: style, assets: assets)

		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
				return .failure(geminiHTTPError(statusCode: httpResponse.statusCode, data: data))
			}

			let decodedResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
			if let message = decodedResponse.error?.message, !message.isEmpty {
				return .failure(RequestError(title: "Generation failed", detail: message))
			}
			guard let part = decodedResponse.candidates?.flatMap(\.content.parts).first(where: { $0.inlineData != nil }),
				let inlineData = part.inlineData,
				let imageData = Data(base64Encoded: inlineData.data)
			else {
				return .failure(RequestError(title: "Generation failed", detail: "No image data came back from Gemini."))
			}

			let pasteboardType = UTType(mimeType: inlineData.mimeType)?.identifier ?? UTType.png.identifier
			return .success(MemeResult(title: prompt, previewURL: nil, previewVideoURL: nil, copyURL: nil, imageData: imageData, pasteboardType: pasteboardType))
		} catch {
			return .failure(RequestError(title: "Generation failed", detail: error.localizedDescription))
		}
	}

	private nonisolated static func copyPayload(for result: MemeResult) async throws -> CopyPayload {
		if let imageData = result.imageData {
			return normalizedCopyPayload(data: imageData, pasteboardType: result.pasteboardType)
		}

		guard let url = result.copyURL else {
			throw RequestError(title: "Copy failed", detail: "This result does not include a copy URL.")
		}

		let (data, response) = try await URLSession.shared.data(from: url)
		if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
			throw RequestError(title: "Copy failed", detail: "HTTP \(httpResponse.statusCode)")
		}

		let mimeType = (response as? HTTPURLResponse)?
			.value(forHTTPHeaderField: "Content-Type")?
			.components(separatedBy: ";")
			.first?
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let pasteboardType = mimeType.flatMap { UTType(mimeType: $0)?.identifier } ?? result.pasteboardType
		return normalizedCopyPayload(data: data, pasteboardType: pasteboardType)
	}

	private nonisolated static func normalizedCopyPayload(data: Data, pasteboardType: String) -> CopyPayload {
		if pasteboardType == UTType.gif.identifier || UIImage.isAnimatedGIF(data: data) {
			return CopyPayload(data: data, pasteboardType: UTType.gif.identifier)
		}

		if let image = UIImage(data: data), let pngData = image.pngData() {
			return CopyPayload(data: pngData, pasteboardType: UTType.png.identifier)
		}

		return CopyPayload(data: data, pasteboardType: pasteboardType)
	}

	private nonisolated static func geminiRequestBody(for idea: String, style: String, assets: [SelectedGenerationAsset]) -> Data? {
		var parts: [[String: Any]] = [
			["text": idea],
		]
		parts.append(contentsOf: assets.map { asset in
			[
				"inlineData": [
					"mimeType": asset.mimeType,
					"data": asset.imageData.base64EncodedString(),
				],
			]
		})

		let body: [String: Any] = [
			"systemInstruction": [
				"parts": [
					["text": style],
				],
			],
			"contents": [
				[
					"parts": parts,
				],
			],
			"generationConfig": [
				"responseModalities": ["IMAGE"],
			],
		]
		return try? JSONSerialization.data(withJSONObject: body)
	}

	fileprivate nonisolated static func pasteboardType(for url: URL?) -> String {
		guard let pathExtension = url?.pathExtension, !pathExtension.isEmpty else {
			return UTType.png.identifier
		}
		return UTType(filenameExtension: pathExtension)?.identifier ?? UTType.png.identifier
	}

	private nonisolated static func giphyHTTPError(statusCode: Int, data: Data?) -> RequestError {
		var detail = "HTTP \(statusCode)"
		if let data,
			let response = try? JSONDecoder().decode(GiphyErrorResponse.self, from: data),
			let message = response.meta?.msg ?? response.message ?? response.error,
			!message.isEmpty
		{
			detail += ": \(message)"
		} else if let snippet = responseSnippet(from: data) {
			detail += ": \(snippet)"
		}
		return RequestError(title: "GIPHY request failed", detail: detail)
	}

	private nonisolated static func geminiHTTPError(statusCode: Int, data: Data?) -> RequestError {
		var detail = "HTTP \(statusCode)"
		if let data,
			let response = try? JSONDecoder().decode(GeminiResponse.self, from: data),
			let message = response.error?.message,
			!message.isEmpty
		{
			detail += ": \(message)"
		} else if let snippet = responseSnippet(from: data) {
			detail += ": \(snippet)"
		}
		return RequestError(title: "Generation failed", detail: detail)
	}

	private nonisolated static func responseDetail(error: Error, data: Data?) -> String {
		var detail = error.localizedDescription
		if let snippet = responseSnippet(from: data), !snippet.isEmpty {
			detail += "\n\(snippet)"
		}
		return detail
	}

	private nonisolated static func responseSnippet(from data: Data?) -> String? {
		guard let data, let text = String(data: data, encoding: .utf8) else { return nil }
		let collapsed = text
			.replacingOccurrences(of: "\n", with: " ")
			.replacingOccurrences(of: "\t", with: " ")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !collapsed.isEmpty else { return nil }
		return String(collapsed.prefix(280))
	}
}

private enum MemeMode: String, CaseIterable, Identifiable, Sendable {
	case search
	case generate

	var id: Self { self }

	var title: String {
		switch self {
		case .search:
			"Search"
		case .generate:
			"Generate"
		}
	}

	var placeholder: String {
		switch self {
		case .search:
			"type a meme search"
		case .generate:
			"describe a static meme"
		}
	}
}

private struct MemeResult: Identifiable, Hashable, Sendable {
	let id = UUID()
	let title: String
	let previewURL: URL?
	let previewVideoURL: URL?
	let copyURL: URL?
	let imageData: Data?
	let pasteboardType: String
	let useCount: Int

	var historyKey: String? {
		copyURL?.absoluteString
	}

	init(
		title: String,
		previewURL: URL?,
		previewVideoURL: URL?,
		copyURL: URL?,
		imageData: Data?,
		pasteboardType: String,
		useCount: Int = 0
	) {
		self.title = title
		self.previewURL = previewURL
		self.previewVideoURL = previewVideoURL
		self.copyURL = copyURL
		self.imageData = imageData
		self.pasteboardType = pasteboardType
		self.useCount = useCount
	}

	init?(giphyItem item: GiphyItem) {
		let preview = item.images.fixedWidthStill?.url ?? item.images.downsizedStill?.url ?? item.images.originalStill?.url
		let previewVideo = item.images.fixedWidthSmall?.mp4 ?? item.images.fixedWidth?.mp4 ?? item.images.downsizedSmall?.mp4
		let previewImage = item.images.fixedWidth?.url ?? item.images.downsized?.url ?? preview
		guard previewVideo != nil || previewImage != nil else {
			return nil
		}
		let copy = item.images.downsized?.url ?? item.images.original?.url ?? previewImage ?? preview
		self.init(
			title: item.title,
			previewURL: previewImage ?? preview,
			previewVideoURL: previewVideo,
			copyURL: copy,
			imageData: nil,
			pasteboardType: MemeForgeModel.pasteboardType(for: copy)
		)
	}

	init(historyItem item: SharedSettings.GiphyMemeHistoryItem) {
		self.init(
			title: item.title,
			previewURL: item.previewURL,
			previewVideoURL: item.previewVideoURL,
			copyURL: item.copyURL,
			imageData: nil,
			pasteboardType: item.pasteboardType,
			useCount: item.useCount
		)
	}

	func withUseCount(_ useCount: Int) -> MemeResult {
		MemeResult(
			title: title,
			previewURL: previewURL,
			previewVideoURL: previewVideoURL,
			copyURL: copyURL,
			imageData: imageData,
			pasteboardType: pasteboardType,
			useCount: useCount
		)
	}
}

private struct RequestError: Error, Equatable, Identifiable, Sendable {
	let id = UUID()
	let title: String
	let detail: String
}

private struct SearchPage: Sendable {
	let items: [MemeResult]
	let nextOffset: Int
	let hasMore: Bool
}

private struct CopyPayload: Sendable {
	let data: Data
	let pasteboardType: String
}

private struct SelectedGenerationAsset: Identifiable, Hashable, Sendable {
	let id: UUID
	let collectionID: UUID?
	let imageData: Data
	let mimeType: String
	var useCount: Int

	init(id: UUID = UUID(), collectionID: UUID?, imageData: Data, mimeType: String, useCount: Int) {
		self.id = id
		self.collectionID = collectionID
		self.imageData = imageData
		self.mimeType = mimeType
		self.useCount = useCount
	}

	init(collectionItem: SharedSettings.GenerationAssetItem, imageData: Data) {
		self.init(
			collectionID: collectionItem.id,
			imageData: imageData,
			mimeType: collectionItem.mimeType,
			useCount: collectionItem.useCount
		)
	}
}

private struct GiphyResponse: Decodable {
	let data: [GiphyItem]
	let pagination: GiphyPagination?
}

private struct GiphyErrorResponse: Decodable {
	let meta: GiphyErrorMeta?
	let message: String?
	let error: String?
}

private struct GiphyErrorMeta: Decodable {
	let msg: String?
}

private struct GiphyPagination: Decodable {
	let totalCount: Int
	let count: Int

	enum CodingKeys: String, CodingKey {
		case totalCount = "total_count"
		case count
	}
}

private struct GiphyItem: Decodable {
	let title: String
	let images: GiphyImages
}

private struct GiphyImages: Decodable {
	let fixedWidth: GiphyRendition?
	let fixedWidthSmall: GiphyRendition?
	let fixedWidthStill: GiphyRendition?
	let downsized: GiphyRendition?
	let downsizedSmall: GiphyRendition?
	let downsizedStill: GiphyRendition?
	let original: GiphyRendition?
	let originalStill: GiphyRendition?

	enum CodingKeys: String, CodingKey {
		case fixedWidth = "fixed_width"
		case fixedWidthSmall = "fixed_width_small"
		case fixedWidthStill = "fixed_width_still"
		case downsized
		case downsizedSmall = "downsized_small"
		case downsizedStill = "downsized_still"
		case original
		case originalStill = "original_still"
	}
}

private struct GiphyRendition: Decodable {
	let url: URL?
	let mp4: URL?
}

private struct GeminiResponse: Decodable {
	let candidates: [GeminiCandidate]?
	let error: GeminiError?
}

private struct GeminiError: Decodable {
	let message: String
}

private struct GeminiCandidate: Decodable {
	let content: GeminiContent
}

private struct GeminiContent: Decodable {
	let parts: [GeminiPart]
}

private struct GeminiPart: Decodable {
	let text: String?
	let inlineData: GeminiInlineData?

	enum CodingKeys: String, CodingKey {
		case text
		case inlineData
		case inlineDataSnake = "inline_data"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		text = try container.decodeIfPresent(String.self, forKey: .text)
		inlineData = try container.decodeIfPresent(GeminiInlineData.self, forKey: .inlineData)
			?? container.decodeIfPresent(GeminiInlineData.self, forKey: .inlineDataSnake)
	}
}

private struct GeminiInlineData: Decodable {
	let mimeType: String
	let data: String

	enum CodingKeys: String, CodingKey {
		case mimeType
		case mimeTypeSnake = "mime_type"
		case data
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
			?? container.decode(String.self, forKey: .mimeTypeSnake)
		data = try container.decode(String.self, forKey: .data)
	}
}

private extension UIImage {
	static func animatedGIF(data: Data) -> UIImage? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
		let frameCount = CGImageSourceGetCount(source)
		guard frameCount > 1 else { return nil }

		var frames: [UIImage] = []
		var duration: TimeInterval = 0
		for index in 0..<frameCount {
			guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
			frames.append(UIImage(cgImage: cgImage))
			duration += gifFrameDuration(source: source, index: index)
		}

		guard !frames.isEmpty else { return nil }
		return UIImage.animatedImage(with: frames, duration: duration)
	}

	static func isAnimatedGIF(data: Data) -> Bool {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
		return CGImageSourceGetCount(source) > 1
	}

	private static func gifFrameDuration(source: CGImageSource, index: Int) -> TimeInterval {
		let defaultDuration = 0.1
		guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
			let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
		else {
			return defaultDuration
		}

		let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
		let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval
		let duration = unclamped ?? clamped ?? defaultDuration
		return duration < 0.02 ? defaultDuration : duration
	}
}
