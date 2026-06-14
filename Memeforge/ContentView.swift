import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

private let floatingSettingsButtonContentTopPadding: CGFloat = 76

struct ContentView: View {
	@State private var model = MemeForgeModel()
	@State private var currentScreen = AppScreen.initial
	@State private var appearanceTheme = SharedSettings.appearanceTheme

	var body: some View {
		NavigationStack {
			screenPager
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background(Color(.systemBackground).ignoresSafeArea())
			.toolbar(.hidden, for: .navigationBar)
			.onOpenURL { url in
				if url.host == "setup" || url.path == "/setup" {
					withAnimation(.snappy) {
						setScreen(.settings)
					}
				}
			}
			.onChange(of: model.mode) { _, mode in
				let screen = AppScreen(mode: mode)
				guard currentScreen != .settings, currentScreen != screen else { return }
				withAnimation(.snappy) {
					setScreen(screen)
				}
			}
		}
		.preferredColorScheme(appearanceTheme.colorScheme)
	}

	@ViewBuilder
	private var screenPager: some View {
		if model.usesGeneratedStage, currentScreen == .generate {
			screenContent(.generate)
		} else {
			TabView(selection: screenSelection) {
				ForEach(AppScreen.allCases) { screen in
					screenContent(screen)
						.tag(screen)
				}
			}
			.tabViewStyle(.page(indexDisplayMode: .never))
		}
	}

	private var screenSelection: Binding<AppScreen> {
		Binding(
			get: { currentScreen },
			set: { setScreen($0) }
		)
	}

	@ViewBuilder
	private func screenContent(_ screen: AppScreen) -> some View {
		if screen == .settings {
			VStack(spacing: 0) {
				SettingsHeader {
					toggleMode()
				}
				SettingsView(appearanceTheme: $appearanceTheme)
			}
		} else if let mode = screen.mode {
			ZStack(alignment: .topTrailing) {
				MemeForgeView(model: model, screenMode: mode)

				if !model.usesGeneratedStage {
					FloatingControlsRow(
						sortOrder: model.sortOrder,
						showsSortControl: screen.sortable,
						setSortOrder: { sortOrder in
							model.sortOrder = sortOrder
						}
					) {
						toggleMode()
					}
					.padding(.top, 10)
					.padding(.trailing, 16)
				}
			}
		}
	}

	private func toggleMode() {
		withAnimation(.snappy) {
			setScreen(currentScreen == .settings ? AppScreen(mode: model.mode) : .settings)
		}
	}

	private func setScreen(_ screen: AppScreen) {
		currentScreen = screen
		if let mode = screen.mode {
			SharedSettings.appShowsSettings = false
			if model.mode != mode {
				model.mode = mode
			}
		} else {
			SharedSettings.appShowsSettings = true
		}
	}
}

private enum MemeSortOrder: String, CaseIterable, Identifiable, Sendable {
	case date
	case count

	var id: Self { self }

	var title: String {
		switch self {
		case .date:
			"Date"
		case .count:
			"Count"
		}
	}
}

private enum AppScreen: CaseIterable, Identifiable, Sendable {
	case search
	case generate
	case history
	case settings

	static var initial: Self {
		if SharedSettings.appShowsSettings {
			return .settings
		}
		return AppScreen(mode: MemeMode(rawValue: SharedSettings.appMemeMode) ?? .search)
	}

	var id: Self { self }

	init(mode: MemeMode) {
		switch mode {
		case .search:
			self = .search
		case .generate:
			self = .generate
		case .history:
			self = .history
		}
	}

	var mode: MemeMode? {
		switch self {
		case .search:
			.search
		case .generate:
			.generate
		case .history:
			.history
		case .settings:
			nil
		}
	}

	var sortable: Bool {
		switch self {
		case .search, .generate:
			true
		case .history, .settings:
			false
		}
	}
}

private struct SettingsHeader: View {
	let toggleMode: () -> Void

	var body: some View {
		HStack(alignment: .center, spacing: 16) {
			Text("Settings")
				.font(.largeTitle.weight(.bold))
				.lineLimit(1)
				.minimumScaleFactor(0.75)

			Spacer()

			SettingsToggleButton(settingsActive: true) {
				toggleMode()
			}
		}
		.padding(.horizontal, 16)
		.padding(.top, 10)
		.padding(.bottom, 8)
	}
}

private struct SettingsToggleButton: View {
	let settingsActive: Bool
	let toggleMode: () -> Void

	var body: some View {
		Button(action: toggleMode) {
			Image(systemName: settingsActive ? "gearshape.fill" : "gearshape")
				.font(.title3.weight(.semibold))
				.foregroundStyle(settingsActive ? Color.accentColor : Color.primary)
				.frame(width: 48, height: 48)
				.background {
					if settingsActive {
						Circle()
							.fill(Color.accentColor.opacity(0.18))
					}
				}
		}
		.buttonStyle(.plain)
		.liquidGlassSurface(cornerRadius: 24, interactive: true)
		.accessibilityLabel(settingsActive ? "Show Memeforge" : "Show settings")
		.accessibilityValue(settingsActive ? "On" : "Off")
		.accessibilityAddTraits(settingsActive ? .isSelected : [])
	}
}

private struct FloatingControlsRow: View {
	let sortOrder: MemeSortOrder
	let showsSortControl: Bool
	let setSortOrder: (MemeSortOrder) -> Void
	let toggleSettings: () -> Void

	var body: some View {
		HStack(spacing: 10) {
			if showsSortControl {
				SortOrderControl(sortOrder: sortOrder, setSortOrder: setSortOrder)
			}

			SettingsToggleButton(settingsActive: false) {
				toggleSettings()
			}
		}
		.animation(.snappy, value: showsSortControl)
	}
}

private struct SortOrderControl: View {
	let sortOrder: MemeSortOrder
	let setSortOrder: (MemeSortOrder) -> Void

	var body: some View {
		HStack(spacing: 2) {
			ForEach(MemeSortOrder.allCases) { item in
				Button {
					setSortOrder(item)
				} label: {
					Text(item.title)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(sortOrder == item ? Color.accentColor : Color.primary)
						.frame(width: 62, height: 42)
						.background {
							if sortOrder == item {
								RoundedRectangle(cornerRadius: 14)
									.fill(Color.accentColor.opacity(0.18))
							}
						}
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Sort by \(item.title.lowercased())")
				.accessibilityValue(sortOrder == item ? "Selected" : "Not selected")
				.accessibilityAddTraits(sortOrder == item ? .isSelected : [])
			}
		}
		.padding(3)
		.liquidGlassSurface(cornerRadius: 18, interactive: true)
	}
}

private extension View {
	@ViewBuilder
	func liquidGlassSurface(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
		if #available(iOS 26, *) {
			if interactive {
				glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
			} else {
				glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
			}
		} else {
			background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
				.overlay {
					RoundedRectangle(cornerRadius: cornerRadius)
						.stroke(.white.opacity(0.25), lineWidth: 1)
				}
		}
	}
}

private extension SharedSettings.AppearanceTheme {
	var colorScheme: ColorScheme? {
		switch self {
		case .light:
			.light
		case .dark:
			.dark
		case .auto:
			nil
		}
	}
}

private struct MemeForgeView: View {
	@Bindable var model: MemeForgeModel
	let screenMode: MemeMode
	@State private var pickerItems: [PhotosPickerItem] = []
	@State private var fullScreenPreview: FullScreenPreviewItem?
	@State private var visibleGeneratedResultID: UUID?
	@State private var generatedPromptMode: GeneratedPromptMode = .reroll
	@State private var generationInputFocused = false
	@FocusState private var inputFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			mainContent
			.safeAreaInset(edge: .bottom, spacing: 0) {
				bottomControls
				.padding(.horizontal, 16)
				.padding(.top, 10)
				.padding(.bottom, 8)
			}
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
			model.refreshGenerationHistory()
		}
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
			model.refreshHistoryIfNeeded()
			model.refreshGenerationAssetCollection()
			model.refreshGenerationHistory()
		}
		.onChange(of: model.results.map(\.id)) { _, ids in
			updateVisibleGeneratedResult(for: ids)
		}
		.onChange(of: visibleGeneratedResultID) { _, _ in
			syncGeneratedPromptWithVisibleResult(forceReroll: true)
		}
		.fullScreenCover(item: $fullScreenPreview) { item in
			FullScreenImagePreview(
				item: item,
				selection: previewSelectionAction(for: item),
				rename: previewRenameAction(for: item),
				delete: item.canDelete ? {
					deletePreviewItem(item)
				} : nil,
				close: {
					fullScreenPreview = nil
				}
			) {
				copyPreviewItem(item)
				fullScreenPreview = nil
			}
		}
	}

	@ViewBuilder
	private var mainContent: some View {
		if screenMode == .generate, model.usesGeneratedStage {
			GeneratedResultsStage(
				results: model.results,
				isLoading: model.isLoading,
				requestError: model.requestError,
				currentID: $visibleGeneratedResultID,
				close: {
					closeGeneratedStage()
				},
				copy: {
					if let result = currentGeneratedResult {
						model.copy(result)
						closeGeneratedStage()
					}
				}
			)
		} else if screenMode == .history {
			GenerationHistoryFeed(
				sections: model.generationHistorySections,
				copyPrompt: { step in
					model.copyGenerationHistoryPrompt(step)
				},
				openAsset: { asset in
					openGenerationHistoryAsset(asset)
				}
			)
		} else {
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					if screenMode == .generate, !model.visibleGenerationAssetCollection.isEmpty {
						GenerationAssetCollectionGrid(
							items: model.visibleGenerationAssetCollection,
							selectedCollectionIDs: model.selectedGenerationAssetCollectionIDs,
							select: { item in
								model.toggleGenerationAsset(item)
							},
							preview: { item in
								openGenerationAsset(item)
							}
						)
					}

					if showsActiveModelState, let requestError = model.requestError {
						RequestErrorView(requestError: requestError)
					}

					if showsActiveModelState, model.isLoading, model.results.isEmpty {
						LoadingTilesGrid(mode: screenMode)
					}

					if showsActiveModelState, !model.results.isEmpty {
						MemeResultsGrid(model: model, mode: screenMode) { result in
							fullScreenPreview = .result(result)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, contentHorizontalPadding)
				.padding(.top, floatingSettingsButtonContentTopPadding)
				.padding(.bottom, 16)
			}
			.scrollDismissesKeyboard(.interactively)
		}
	}

	private var contentHorizontalPadding: CGFloat {
		hasTiledContent ? 0 : 16
	}

	private var hasTiledContent: Bool {
		(showsActiveModelState && (!model.results.isEmpty || model.isLoading))
			|| (screenMode == .generate && !model.visibleGenerationAssetCollection.isEmpty)
	}

	private var showsActiveModelState: Bool {
		model.mode == screenMode
	}

	private var bottomControls: some View {
		Group {
			if #available(iOS 26, *) {
				GlassEffectContainer(spacing: 10) {
					bottomControlsContent
				}
			} else {
				bottomControlsContent
			}
		}
	}

	private var bottomControlsContent: some View {
		VStack(alignment: .leading, spacing: 10) {
			if screenMode == .generate, model.usesGeneratedStage {
				GeneratedPromptModeSwitch(mode: generatedPromptMode) { mode in
					setGeneratedPromptMode(mode)
				}
				queryInputArea(showAssetPicker: false)
			} else if screenMode == .history {
				ModeTabs(mode: modeTabSelection)
			} else {
				inputArea
				ModeTabs(mode: modeTabSelection)
			}
		}
	}

	private var modeTabSelection: Binding<MemeMode> {
		Binding(
			get: { screenMode },
			set: { model.mode = $0 }
		)
	}

	private var inputArea: some View {
		VStack(alignment: .leading, spacing: 10) {
			if screenMode == .generate, !model.selectedGenerationAssets.isEmpty {
				SelectedGenerationAssetsStrip(
					assets: model.selectedGenerationAssets,
					open: { asset in
						fullScreenPreview = .selectedAsset(asset)
					},
					remove: { asset in
						model.removeGenerationAsset(asset)
					}
				)
			}
			queryInputArea(showAssetPicker: true)
		}
		.onChange(of: pickerItems) { _, items in
			importPickerItems(items)
			pickerItems = []
		}
	}

	private func queryInputArea(showAssetPicker: Bool) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			ZStack(alignment: .bottomLeading) {
				HStack(alignment: .center, spacing: 10) {
					ZStack(alignment: .trailing) {
						promptInputField(allowsImagePaste: screenMode == .generate && showAssetPicker)

						if !model.query.isEmpty {
							Button {
								model.clearQuery()
								focusPromptInput(allowsImagePaste: screenMode == .generate && showAssetPicker)
							} label: {
								Image(systemName: "xmark.circle.fill")
									.font(.body)
									.foregroundStyle(.secondary)
									.frame(width: 36, height: 36)
							}
							.buttonStyle(.plain)
							.padding(.trailing, 6)
							.accessibilityLabel("Clear")
						}
					}
					.liquidGlassSurface(cornerRadius: 22, interactive: true)

					if screenMode == .generate, showAssetPicker {
						PhotosPicker(selection: $pickerItems, maxSelectionCount: nil, matching: .images) {
							Image(systemName: "photo.stack")
								.font(.title3.weight(.semibold))
								.frame(width: 58, height: 58)
						}
						.buttonStyle(.plain)
						.liquidGlassSurface(cornerRadius: 22, interactive: true)
						.disabled(model.isLoading)
						.accessibilityLabel("Add generation assets")
					}
				}

				assetMentionPopup(allowsImagePaste: screenMode == .generate && showAssetPicker)
			}
		}
	}

	@ViewBuilder
	private func assetMentionPopup(allowsImagePaste: Bool) -> some View {
		if allowsImagePaste, let mentionQuery = activeAssetMentionQuery {
			let options = model.generationAssetMentionOptions(matching: mentionQuery)
			if !options.isEmpty {
				GenerationAssetMentionPopup(
					items: options,
					selectedCollectionIDs: model.selectedGenerationAssetCollectionIDs
				) { item in
					selectAssetMention(item, allowsImagePaste: allowsImagePaste)
				}
				.padding(.trailing, allowsImagePaste ? 68 : 0)
				.padding(.bottom, 68)
				.transition(.move(edge: .bottom).combined(with: .opacity))
				.zIndex(2)
			}
		}
	}

	private var activeAssetMentionQuery: String? {
		guard screenMode == .generate,
			generationInputFocused || inputFocused,
			let mentionQuery = model.query.trailingGenerationAssetMentionQuery
		else {
			return nil
		}
		return mentionQuery
	}

	private func selectAssetMention(_ item: SharedSettings.GenerationAssetItem, allowsImagePaste: Bool) {
		activateScreenModeIfNeeded()
		model.query = model.query.replacingTrailingGenerationAssetMention(with: item.displayName)
		model.insertGenerationAsset(item)
		focusPromptInput(allowsImagePaste: allowsImagePaste)
	}

	@ViewBuilder
	private func promptInputField(allowsImagePaste: Bool) -> some View {
		if allowsImagePaste {
			ZStack(alignment: .topLeading) {
				if model.query.isEmpty {
					Text(screenMode.placeholder)
						.font(.body)
						.foregroundStyle(.secondary)
						.padding(.leading, 16)
						.padding(.trailing, 16)
						.padding(.vertical, 15)
						.frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
						.allowsHitTesting(false)
				}

				GenerationPromptTextView(
					text: $model.query,
					isFocused: generationInputFocusBinding,
					placeholder: screenMode.placeholder,
					onSubmit: submitQuery,
					onPasteImages: importPastedGenerationAssets
				)
				.padding(.leading, 16)
				.padding(.trailing, model.query.isEmpty ? 16 : 46)
				.padding(.vertical, 15)
				.frame(minHeight: 58, alignment: .center)
			}
		} else {
			TextField(screenMode.placeholder, text: $model.query, axis: .vertical)
				.lineLimit(1...5)
				.font(.body)
				.padding(.leading, 16)
				.padding(.trailing, model.query.isEmpty ? 16 : 46)
				.padding(.vertical, 15)
				.frame(minHeight: 58, alignment: .center)
				.textInputAutocapitalization(screenMode == .search ? .never : .sentences)
				.autocorrectionDisabled(screenMode == .search)
				.submitLabel(screenMode == .search ? .search : .done)
				.focused($inputFocused)
				.onSubmit {
					submitQuery()
				}
				.onChange(of: model.query) { _, value in
					submitIfKeyboardInsertedNewline(value)
				}
		}
	}

	private var generationInputFocusBinding: Binding<Bool> {
		Binding(
			get: { generationInputFocused },
			set: { generationInputFocused = $0 }
		)
	}

	private func focusPromptInput(allowsImagePaste: Bool) {
		if allowsImagePaste {
			generationInputFocused = true
		} else {
			inputFocused = true
		}
	}

	private func submitQuery() {
		activateScreenModeIfNeeded()
		if model.usesGeneratedStage {
			model.submitGeneratedStage(mode: generatedPromptMode, sourceResult: currentGeneratedResult)
		} else {
			model.submit()
		}
		inputFocused = false
		generationInputFocused = false
	}

	private func submitIfKeyboardInsertedNewline(_ value: String) {
		guard value.rangeOfCharacter(from: .newlines) != nil else { return }
		model.query = value.components(separatedBy: .newlines).joined(separator: " ")
		submitQuery()
	}

	private var currentGeneratedResult: MemeResult? {
		guard model.mode == .generate else { return nil }
		if let visibleGeneratedResultID,
			let visible = model.results.first(where: { $0.id == visibleGeneratedResultID })
		{
			return visible
		}
		return model.results.last
	}

	private func updateVisibleGeneratedResult(for ids: [UUID]) {
		guard model.mode == .generate else { return }
		visibleGeneratedResultID = ids.last
		syncGeneratedPromptWithVisibleResult(forceReroll: true)
	}

	private func setGeneratedPromptMode(_ mode: GeneratedPromptMode) {
		generatedPromptMode = mode
		syncGeneratedPromptWithVisibleResult(forceReroll: false)
	}

	private func syncGeneratedPromptWithVisibleResult(forceReroll: Bool) {
		guard model.usesGeneratedStage else {
			generatedPromptMode = .reroll
			return
		}
		if forceReroll {
			generatedPromptMode = .reroll
		}

		switch generatedPromptMode {
		case .reroll:
			if let prompt = currentGeneratedResult?.title {
				model.query = prompt
			}
		case .update:
			model.query = ""
		}
	}

	private func closeGeneratedStage() {
		model.closeGeneratedStage()
		visibleGeneratedResultID = nil
		generatedPromptMode = .reroll
	}

	private func importPickerItems(_ items: [PhotosPickerItem]) {
		guard !items.isEmpty else { return }
		inputFocused = false
		generationInputFocused = false
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
				model.insertPickedGenerationAssets(payloads)
			}
		}
	}

	private func importPastedGenerationAssets(_ payloads: [SharedSettings.GenerationAssetPayload]) {
		guard screenMode == .generate else { return }
		activateScreenModeIfNeeded()
		generationInputFocused = false
		model.insertPickedGenerationAssets(payloads)
	}

	private func activateScreenModeIfNeeded() {
		if model.mode != screenMode {
			model.mode = screenMode
		}
	}

	private func openGenerationAsset(_ item: SharedSettings.GenerationAssetItem) {
		guard let data = SharedSettings.generationAssetData(for: item) else { return }
		fullScreenPreview = .collectionAsset(item, imageData: data)
	}

	private func openGenerationHistoryAsset(_ asset: SharedSettings.GenerationHistoryAsset) {
		guard let data = SharedSettings.generationHistoryData(for: asset) else { return }
		fullScreenPreview = .historyAsset(asset, imageData: data)
	}

	private func previewSelectionAction(for item: FullScreenPreviewItem) -> PreviewSelectionAction? {
		guard let collectionID = item.collectionID else { return nil }
		return PreviewSelectionAction(
			isSelected: model.isGenerationAssetSelected(collectionID: collectionID),
			toggle: {
				model.toggleGenerationAsset(collectionID: collectionID)
			}
		)
	}

	private func previewRenameAction(for item: FullScreenPreviewItem) -> ((String) -> String)? {
		guard case .asset(_, let collectionID?, .collectionItem, _, _, _) = item else { return nil }
		return { rawName in
			renamePreviewItem(item, collectionID: collectionID, to: rawName)
		}
	}

	private func renamePreviewItem(_ item: FullScreenPreviewItem, collectionID: UUID, to rawName: String) -> String {
		guard let updatedItem = model.renameCollectionGenerationAsset(id: collectionID, to: rawName) else {
			return item.title
		}
		let name = updatedItem.displayName
		fullScreenPreview = item.renamed(to: name)
		return name
	}

	private func deletePreviewItem(_ item: FullScreenPreviewItem) {
		switch item {
		case .result(let result):
			model.deleteHistoryResult(result)
		case .asset(let id, let collectionID, let deleteTarget, _, _, _):
			switch deleteTarget {
			case .selectedThumbnail:
				model.removeGenerationAsset(id: id)
			case .collectionItem:
				if let collectionID {
					model.deleteCollectionGenerationAsset(id: collectionID)
				}
			}
		case .historyAsset:
			break
		}
	}

	private func copyPreviewItem(_ item: FullScreenPreviewItem) {
		switch item {
		case .result(let result):
			model.copy(result)
		case .asset(_, _, _, _, let imageData, let pasteboardType):
			model.copyImageData(imageData, pasteboardType: pasteboardType)
		case .historyAsset(_, _, let imageData, let pasteboardType):
			model.copyImageData(imageData, pasteboardType: pasteboardType)
		}
	}
}

private struct GenerationPromptTextView: UIViewRepresentable {
	@Binding var text: String
	@Binding var isFocused: Bool

	let placeholder: String
	let onSubmit: () -> Void
	let onPasteImages: ([SharedSettings.GenerationAssetPayload]) -> Void

	func makeUIView(context: Context) -> PasteAwareTextView {
		let textView = PasteAwareTextView()
		textView.backgroundColor = .clear
		textView.font = .preferredFont(forTextStyle: .body)
		textView.adjustsFontForContentSizeCategory = true
		textView.textColor = .label
		textView.tintColor = .tintColor
		textView.textContainerInset = .zero
		textView.textContainer.lineFragmentPadding = 0
		textView.returnKeyType = .done
		textView.autocapitalizationType = .sentences
		textView.autocorrectionType = .default
		textView.delegate = context.coordinator
		textView.imagePasteHandler = { [weak coordinator = context.coordinator] payloads in
			coordinator?.pasteImages(payloads)
		}
		return textView
	}

	func updateUIView(_ textView: PasteAwareTextView, context: Context) {
		context.coordinator.parent = self
		textView.imagePasteEnabled = true
		textView.accessibilityLabel = placeholder
		if textView.text != text {
			textView.text = text
		}
		textView.invalidateIntrinsicContentSize()

		if isFocused, !textView.isFirstResponder {
			DispatchQueue.main.async {
				textView.becomeFirstResponder()
			}
		} else if !isFocused, textView.isFirstResponder {
			DispatchQueue.main.async {
				textView.resignFirstResponder()
			}
		}
	}

	func sizeThatFits(_ proposal: ProposedViewSize, uiView: PasteAwareTextView, context: Context) -> CGSize? {
		let width = proposal.width ?? uiView.bounds.width
		guard width > 0 else { return nil }
		let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
		let lineHeight = uiView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
		let minHeight = ceil(lineHeight)
		let maxHeight = ceil(lineHeight * 5)
		let height = min(max(ceil(fittingSize.height), minHeight), maxHeight)
		uiView.isScrollEnabled = fittingSize.height > maxHeight
		return CGSize(width: width, height: height)
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}

	@MainActor
	final class Coordinator: NSObject, UITextViewDelegate {
		var parent: GenerationPromptTextView

		init(parent: GenerationPromptTextView) {
			self.parent = parent
		}

		func textViewDidChange(_ textView: UITextView) {
			parent.text = textView.text
			textView.invalidateIntrinsicContentSize()
		}

		func textViewDidBeginEditing(_ textView: UITextView) {
			parent.isFocused = true
		}

		func textViewDidEndEditing(_ textView: UITextView) {
			parent.isFocused = false
		}

		func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
			guard text == "\n" else { return true }
			parent.onSubmit()
			return false
		}

		func pasteImages(_ payloads: [SharedSettings.GenerationAssetPayload]) {
			parent.onPasteImages(payloads)
		}
	}
}

@MainActor
private final class PasteAwareTextView: UITextView {
	var imagePasteEnabled = false
	var imagePasteHandler: ([SharedSettings.GenerationAssetPayload]) -> Void = { _ in }

	override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
		if action == #selector(paste(_:)),
			imagePasteEnabled,
			Self.pasteboardContainsImage(.general)
		{
			return true
		}
		return super.canPerformAction(action, withSender: sender)
	}

	override func paste(_ sender: Any?) {
		if imagePasteEnabled {
			let payloads = Self.generationAssetPayloads(from: .general)
			if !payloads.isEmpty {
				imagePasteHandler(payloads)
				return
			}
		}
		super.paste(sender)
	}

	private static func pasteboardContainsImage(_ pasteboard: UIPasteboard) -> Bool {
		pasteboard.hasImages || pasteboard.items.contains { item in
			imagePasteboardTypes.contains { item[$0] != nil }
		}
	}

	private static func generationAssetPayloads(from pasteboard: UIPasteboard) -> [SharedSettings.GenerationAssetPayload] {
		let itemPayloads = pasteboard.items.compactMap(payload)
		if !itemPayloads.isEmpty {
			return itemPayloads
		}
		return pasteboard.images?.compactMap(SharedSettings.normalizedGenerationAssetPayload(from:)) ?? []
	}

	private static func payload(from item: [String: Any]) -> SharedSettings.GenerationAssetPayload? {
		for type in imagePasteboardTypes {
			guard let value = item[type], let payload = payload(from: value) else { continue }
			return payload
		}

		for value in item.values {
			guard let payload = payload(from: value) else { continue }
			return payload
		}

		return nil
	}

	private static func payload(from value: Any) -> SharedSettings.GenerationAssetPayload? {
		if let data = value as? Data {
			return SharedSettings.normalizedGenerationAssetPayload(from: data)
		}
		if let image = value as? UIImage {
			return SharedSettings.normalizedGenerationAssetPayload(from: image)
		}
		if let url = value as? URL, url.isFileURL, let data = try? Data(contentsOf: url) {
			return SharedSettings.normalizedGenerationAssetPayload(from: data)
		}
		return nil
	}

	private static let imagePasteboardTypes = [
		UTType.png.identifier,
		UTType.jpeg.identifier,
		"public.heic",
		"public.heif",
		UTType.tiff.identifier,
		UTType.gif.identifier,
		UTType.image.identifier,
	]
}

private struct ModeTabs: View {
	@Binding var mode: MemeMode

	var body: some View {
		Picker("Mode", selection: $mode) {
			ForEach(MemeMode.allCases) { item in
				Text(item.title)
					.tag(item)
			}
		}
		.pickerStyle(.segmented)
		.padding(2)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
		.liquidGlassSurface(cornerRadius: 14, interactive: true)
	}
}

private struct MemeResultsGrid: View {
	@Bindable var model: MemeForgeModel
	let mode: MemeMode
	let open: (MemeResult) -> Void

	private var columns: [GridItem] {
		resultGridColumns(for: mode)
	}

	var body: some View {
		LazyVGrid(columns: columns, spacing: 0) {
			ForEach(model.visibleResults) { result in
				MemeResultCell(result: result, copied: model.copiedResultID == result.id) {
					open(result)
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
		.frame(maxWidth: .infinity)
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
		LazyVGrid(columns: columns, spacing: 0) {
			ForEach(0..<tileCount, id: \.self) { _ in
				SquareThumbnailTile {
					ProgressView()
						.controlSize(.small)
				}
			}
		}
	}
}

private struct GenerationHistoryFeed: View {
	let sections: [GenerationHistorySection]
	let copyPrompt: (SharedSettings.GenerationHistoryStep) -> Void
	let openAsset: (SharedSettings.GenerationHistoryAsset) -> Void

	var body: some View {
		ScrollView {
			if sections.isEmpty {
				emptyState
					.padding(.horizontal, 20)
					.padding(.top, 96)
			} else {
				LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
					ForEach(sections) { section in
						VStack(alignment: .leading, spacing: 10) {
							Text(section.title)
								.font(.subheadline.weight(.bold))
								.foregroundStyle(.secondary)
								.padding(.horizontal, 2)

							ForEach(section.items) { item in
								GenerationHistoryCard(item: item, copyPrompt: copyPrompt, openAsset: openAsset)
							}
						}
					}
				}
				.padding(.horizontal, 16)
				.padding(.top, floatingSettingsButtonContentTopPadding)
				.padding(.bottom, 16)
			}
		}
		.scrollDismissesKeyboard(.interactively)
	}

	private var emptyState: some View {
		VStack(spacing: 12) {
			Image(systemName: "clock.arrow.circlepath")
				.font(.largeTitle.weight(.semibold))
				.foregroundStyle(Color.accentColor)
				.frame(width: 72, height: 72)
				.liquidGlassSurface(cornerRadius: 36, interactive: false)

			Text("No generations yet")
				.font(.headline.weight(.semibold))
				.foregroundStyle(.primary)
		}
		.frame(maxWidth: .infinity)
		.padding(24)
		.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
	}
}

private struct GenerationHistoryCard: View {
	let item: SharedSettings.GenerationHistoryItem
	let copyPrompt: (SharedSettings.GenerationHistoryStep) -> Void
	let openAsset: (SharedSettings.GenerationHistoryAsset) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .center, spacing: 8) {
				Text(updatedAtText)
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)

				Spacer()

				Label(stepCountText, systemImage: "sparkles")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
			}

			ForEach(Array(item.steps.enumerated()), id: \.element.id) { index, step in
				GenerationHistoryStepView(step: step, copyPrompt: copyPrompt, openAsset: openAsset)

				if index < item.steps.count - 1 {
					Divider()
						.padding(.vertical, 4)
				}
			}
		}
		.padding(12)
		.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
		.overlay {
			RoundedRectangle(cornerRadius: 8)
				.stroke(Color.primary.opacity(0.06), lineWidth: 1)
		}
	}

	private var updatedAtText: String {
		Date(timeIntervalSince1970: item.updatedAt).formatted(date: .omitted, time: .shortened)
	}

	private var stepCountText: String {
		item.steps.count == 1 ? "1 step" : "\(item.steps.count) steps"
	}
}

private struct GenerationHistoryStepView: View {
	let step: SharedSettings.GenerationHistoryStep
	let copyPrompt: (SharedSettings.GenerationHistoryStep) -> Void
	let openAsset: (SharedSettings.GenerationHistoryAsset) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .top, spacing: 10) {
				Button {
					copyPrompt(step)
				} label: {
					Text(step.prompt)
						.font(.headline.weight(.semibold))
						.foregroundStyle(.primary)
						.multilineTextAlignment(.leading)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(12)
						.background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Copy prompt")
				.accessibilityValue(step.prompt)

				if let attachment = step.attachments.only {
					Button {
						openAsset(attachment)
					} label: {
						GenerationHistoryAssetImage(asset: attachment, contentMode: .fill)
							.frame(width: 72, height: 72)
							.clipShape(RoundedRectangle(cornerRadius: 8))
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Preview source image")
				}
			}

			if step.attachments.count > 1 {
				GenerationHistoryAttachmentCarousel(assets: step.attachments, openAsset: openAsset)
			}

			GenerationHistoryResultStack(assets: step.images, openAsset: openAsset)
		}
	}
}

private struct GenerationHistoryAttachmentCarousel: View {
	let assets: [SharedSettings.GenerationHistoryAsset]
	let openAsset: (SharedSettings.GenerationHistoryAsset) -> Void

	var body: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				ForEach(assets) { asset in
					Button {
						openAsset(asset)
					} label: {
						GenerationHistoryAssetImage(asset: asset, contentMode: .fill)
							.frame(width: 76, height: 76)
							.clipShape(RoundedRectangle(cornerRadius: 8))
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Preview source image")
				}
			}
		}
	}
}

private struct GenerationHistoryResultStack: View {
	let assets: [SharedSettings.GenerationHistoryAsset]
	let openAsset: (SharedSettings.GenerationHistoryAsset) -> Void

	var body: some View {
		VStack(spacing: 10) {
			ForEach(assets) { asset in
				Button {
					openAsset(asset)
				} label: {
					GenerationHistoryAssetImage(asset: asset, contentMode: .fit)
						.aspectRatio(1, contentMode: .fit)
						.frame(maxWidth: .infinity)
						.background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
						.clipShape(RoundedRectangle(cornerRadius: 8))
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Preview generated image")
			}
		}
	}
}

private struct GenerationHistoryAssetImage: View {
	let asset: SharedSettings.GenerationHistoryAsset
	let contentMode: ContentMode
	@State private var image: UIImage?

	var body: some View {
		ZStack {
			Color(.tertiarySystemBackground)

			if let image {
				Image(uiImage: image)
					.resizable()
					.aspectRatio(contentMode: contentMode)
			} else {
				Image(systemName: "photo")
					.font(.title3)
					.foregroundStyle(.secondary)
			}
		}
		.clipped()
		.task(id: asset.id) {
			guard let data = SharedSettings.generationHistoryData(for: asset) else { return }
			image = UIImage.animatedGIF(data: data) ?? UIImage(data: data)
		}
	}
}

private struct GeneratedResultsStage: View {
	let results: [MemeResult]
	let isLoading: Bool
	let requestError: RequestError?
	@Binding var currentID: UUID?
	let close: () -> Void
	let copy: () -> Void

	var body: some View {
		ZStack {
			Color.black
				.ignoresSafeArea()

			if results.isEmpty {
				VStack(spacing: 14) {
					ProgressView()
						.tint(.white)
					Text(isLoading ? "Generating" : "No image yet")
						.font(.headline.weight(.semibold))
						.foregroundStyle(.white)
					if let requestError {
						Text(requestError.detail)
							.font(.footnote.weight(.medium))
							.foregroundStyle(.white.opacity(0.72))
							.multilineTextAlignment(.center)
							.padding(.horizontal, 28)
					}
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				TabView(selection: $currentID) {
					ForEach(results) { result in
						GeneratedImagePage(result: result)
							.tag(Optional(result.id))
					}
				}
				.tabViewStyle(.page(indexDisplayMode: results.count > 1 ? .automatic : .never))
				.indexViewStyle(.page(backgroundDisplayMode: .always))

				if let requestError, !isLoading {
					Text(requestError.title)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.white)
						.padding(.horizontal, 14)
						.padding(.vertical, 9)
						.background(.red.opacity(0.82), in: Capsule())
						.padding(.top, 78)
						.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
				}

				if isLoading {
					HStack(spacing: 8) {
						ProgressView()
							.controlSize(.small)
							.tint(.white)
						Text("Generating")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.white)
					}
					.padding(.horizontal, 14)
					.padding(.vertical, 9)
					.background(.black.opacity(0.72), in: Capsule())
					.padding(.top, 78)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
				}
			}

			VStack {
				HStack {
					Button(action: close) {
						Image(systemName: "xmark")
							.font(.title3.weight(.bold))
							.foregroundStyle(.white)
							.frame(width: 56, height: 56)
							.background(.black.opacity(0.62), in: Circle())
							.overlay {
								Circle()
									.stroke(.white.opacity(0.24), lineWidth: 1)
							}
					}
					.buttonStyle(.plain)
					.contentShape(Circle())
					.accessibilityLabel("Close generation")

					Spacer()

					Button(action: copy) {
						Image(systemName: "doc.on.doc.fill")
							.font(.title3.weight(.bold))
							.foregroundStyle(.white)
							.frame(width: 56, height: 56)
							.background(.black.opacity(0.62), in: Circle())
							.overlay {
								Circle()
									.stroke(.white.opacity(0.24), lineWidth: 1)
							}
					}
					.buttonStyle(.plain)
					.contentShape(Circle())
					.disabled(results.isEmpty)
					.opacity(results.isEmpty ? 0 : 1)
					.accessibilityLabel("Copy generated image")
				}
				Spacer()
			}
			.padding(.horizontal, 16)
			.padding(.top, 12)
		}
		.onAppear {
			currentID = currentID ?? results.last?.id
		}
		.onChange(of: results.map(\.id)) { _, ids in
			currentID = ids.last
		}
		.animation(.snappy, value: results.map(\.id))
	}
}

private struct GeneratedPromptModeSwitch: View {
	let mode: GeneratedPromptMode
	let select: (GeneratedPromptMode) -> Void

	var body: some View {
		HStack(spacing: 4) {
			ForEach(GeneratedPromptMode.allCases) { option in
				Button {
					select(option)
				} label: {
					Text(option.title)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(mode == option ? .white : .primary)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 10)
						.background {
							if mode == option {
								Capsule()
									.fill(Color.accentColor)
							}
						}
				}
				.buttonStyle(.plain)
				.accessibilityLabel(option.title)
				.accessibilityAddTraits(mode == option ? .isSelected : [])
			}
		}
		.padding(4)
		.liquidGlassSurface(cornerRadius: 19, interactive: true)
		.animation(.snappy, value: mode)
	}
}

private struct GeneratedImagePage: View {
	let result: MemeResult

	var body: some View {
		ZStack {
			Color.black

			if let image {
				Image(uiImage: image)
					.resizable()
					.scaledToFit()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.padding(.horizontal, 10)
			} else {
				Image(systemName: "photo")
					.font(.largeTitle)
					.foregroundStyle(.white.opacity(0.5))
			}
		}
	}

	private var image: UIImage? {
		guard let data = result.imageData else { return nil }
		return UIImage.animatedGIF(data: data) ?? UIImage(data: data)
	}
}

private func resultGridColumns(for mode: MemeMode) -> [GridItem] {
	guard mode != .generate else {
		return [GridItem(.flexible(), spacing: 0)]
	}
	return [GridItem(.adaptive(minimum: 106), spacing: 0)]
}

private struct SelectedGenerationAssetsStrip: View {
	let assets: [SelectedGenerationAsset]
	let open: (SelectedGenerationAsset) -> Void
	let remove: (SelectedGenerationAsset) -> Void

	var body: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				ForEach(assets) { asset in
					SelectedGenerationAssetThumbnail(asset: asset) {
						open(asset)
					} remove: {
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
	let open: () -> Void
	let remove: () -> Void

	var body: some View {
		ZStack(alignment: .topTrailing) {
			Button(action: open) {
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
				.clipShape(RoundedRectangle(cornerRadius: 8))
				.liquidGlassSurface(cornerRadius: 12, interactive: true)
			}
			.buttonStyle(.plain)
			.accessibilityLabel(asset.name)

			Button(action: remove) {
				Image(systemName: "xmark")
					.font(.caption2.weight(.bold))
					.foregroundStyle(.primary)
					.frame(width: 22, height: 22)
			}
			.buttonStyle(.plain)
			.liquidGlassSurface(cornerRadius: 11, interactive: true)
			.padding(4)
			.accessibilityLabel("Remove generation asset")
		}
	}
}

private struct GenerationAssetMentionPopup: View {
	let items: [SharedSettings.GenerationAssetItem]
	let selectedCollectionIDs: Set<UUID>
	let select: (SharedSettings.GenerationAssetItem) -> Void

	var body: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				ForEach(items) { item in
					Button {
						select(item)
					} label: {
						HStack(spacing: 8) {
							GenerationAssetMentionThumbnail(item: item)

							Text(item.displayName)
								.font(.caption.weight(.semibold))
								.foregroundStyle(.primary)
								.lineLimit(1)
								.frame(maxWidth: 160, alignment: .leading)

							if selectedCollectionIDs.contains(item.id) {
								Image(systemName: "checkmark.circle.fill")
									.font(.caption.weight(.bold))
									.foregroundStyle(Color.accentColor)
							}
						}
						.padding(6)
						.background {
							RoundedRectangle(cornerRadius: 10)
								.fill(selectedCollectionIDs.contains(item.id) ? Color.accentColor.opacity(0.16) : Color.clear)
						}
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Use \(item.displayName)")
				}
			}
			.padding(8)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.frame(height: 58)
		.liquidGlassSurface(cornerRadius: 16, interactive: true)
		.shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
	}
}

private struct GenerationAssetMentionThumbnail: View {
	let item: SharedSettings.GenerationAssetItem
	@State private var image: UIImage?

	var body: some View {
		Group {
			if let image {
				Image(uiImage: image)
					.resizable()
					.scaledToFill()
			} else {
				Image(systemName: "photo")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
			}
		}
		.frame(width: 34, height: 34)
		.background(Color(.secondarySystemBackground))
		.clipShape(RoundedRectangle(cornerRadius: 7))
		.task(id: item.id) {
			image = SharedSettings.generationAssetData(for: item).flatMap(UIImage.init(data:))
		}
	}
}

private struct GenerationAssetCollectionGrid: View {
	let items: [SharedSettings.GenerationAssetItem]
	let selectedCollectionIDs: Set<UUID>
	let select: (SharedSettings.GenerationAssetItem) -> Void
	let preview: (SharedSettings.GenerationAssetItem) -> Void

	private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 2)

	var body: some View {
		LazyVGrid(columns: columns, spacing: 0) {
			ForEach(items) { item in
				GenerationAssetCollectionCell(item: item, isSelected: selectedCollectionIDs.contains(item.id)) {
					select(item)
				} preview: {
					preview(item)
				}
			}
		}
	}
}

private struct GenerationAssetCollectionCell: View {
	let item: SharedSettings.GenerationAssetItem
	let isSelected: Bool
	let select: () -> Void
	let preview: () -> Void

	@State private var image: UIImage?

	var body: some View {
		ZStack(alignment: .topTrailing) {
			SquareThumbnailTile {
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

			if item.useCount > 0 {
				Text(item.useCount > 999 ? "999+" : "\(item.useCount)")
					.font(.caption2.weight(.bold))
					.foregroundStyle(.white)
					.padding(.horizontal, 6)
					.frame(minHeight: 20)
					.background(.black.opacity(0.68), in: Capsule())
					.padding(6)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			}

			if isSelected {
				Rectangle()
					.stroke(Color.accentColor, lineWidth: 4)
					.padding(2)

				Image(systemName: "checkmark.circle.fill")
					.font(.title2.weight(.semibold))
					.foregroundStyle(.white, Color.accentColor)
					.padding(6)
			}
		}
		.contentShape(Rectangle())
		.onTapGesture(perform: select)
		.onLongPressGesture(perform: preview)
		.animation(.snappy, value: isSelected)
		.task(id: item.id) {
			image = SharedSettings.generationAssetData(for: item).flatMap(UIImage.init(data:))
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(item.displayName)
		.accessibilityValue(isSelected ? "Selected" : "Not selected")
		.accessibilityHint("Tap to select. Long press to preview.")
		.accessibilityAddTraits(.isButton)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
		.accessibilityAction {
			select()
		}
		.accessibilityAction(named: "Preview") {
			preview()
		}
	}
}

private struct PreviewSelectionAction {
	let isSelected: Bool
	let toggle: () -> Void
}

private struct PreviewSelectionButton: View {
	let isSelected: Bool
	let toggle: () -> Void

	var body: some View {
		Button(action: toggle) {
			Image(systemName: isSelected ? "checkmark" : "plus")
				.font(.title3.weight(.bold))
				.foregroundStyle(.white)
				.frame(width: 56, height: 56)
				.background(isSelected ? Color.accentColor : .black.opacity(0.62), in: Circle())
				.overlay {
					Circle()
						.stroke(.white.opacity(0.24), lineWidth: 1)
				}
		}
		.buttonStyle(.plain)
		.contentShape(Circle())
		.accessibilityLabel(isSelected ? "Remove from generation assets" : "Add to generation assets")
		.animation(.snappy, value: isSelected)
	}
}

private struct MemeResultCell: View {
	let result: MemeResult
	let copied: Bool
	let open: () -> Void

	var body: some View {
		Button(action: open) {
			ZStack(alignment: .topTrailing) {
				SquareThumbnailTile {
					MemePreview(result: result)
				}

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
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(result.title.isEmpty ? "Meme" : result.title)
		.accessibilityHint("Opens this meme")
	}
}

private enum AssetPreviewDeleteTarget {
	case selectedThumbnail
	case collectionItem
}

private enum FullScreenPreviewItem: Identifiable {
	case result(MemeResult)
	case asset(
		id: UUID,
		collectionID: UUID?,
		deleteTarget: AssetPreviewDeleteTarget,
		title: String,
		imageData: Data,
		pasteboardType: String
	)
	case historyAsset(
		id: UUID,
		title: String,
		imageData: Data,
		pasteboardType: String
	)

	var id: String {
		switch self {
		case .result(let result):
			"result-\(result.id.uuidString)"
		case .asset(let id, _, _, _, _, _):
			"asset-\(id.uuidString)"
		case .historyAsset(let id, _, _, _):
			"history-asset-\(id.uuidString)"
		}
	}

	var title: String {
		switch self {
		case .result(let result):
			result.title.isEmpty ? "Meme" : result.title
		case .asset(_, _, _, let title, _, _):
			title
		case .historyAsset(_, let title, _, _):
			title
		}
	}

	var collectionID: UUID? {
		switch self {
		case .result, .historyAsset:
			nil
		case .asset(_, let collectionID, _, _, _, _):
			collectionID
		}
	}

	var canDelete: Bool {
		switch self {
		case .result(let result):
			result.useCount > 0
		case .asset:
			true
		case .historyAsset:
			false
		}
	}

	var imageData: Data? {
		switch self {
		case .result(let result):
			result.imageData
		case .asset(_, _, _, _, let imageData, _):
			imageData
		case .historyAsset(_, _, let imageData, _):
			imageData
		}
	}

	var imageURL: URL? {
		switch self {
		case .result(let result):
			result.previewURL ?? result.copyURL
		case .asset, .historyAsset:
			nil
		}
	}

	func renamed(to title: String) -> FullScreenPreviewItem {
		switch self {
		case .asset(let id, let collectionID, let deleteTarget, _, let imageData, let pasteboardType):
			.asset(
				id: id,
				collectionID: collectionID,
				deleteTarget: deleteTarget,
				title: title,
				imageData: imageData,
				pasteboardType: pasteboardType
			)
		case .result, .historyAsset:
			self
		}
	}

	static func selectedAsset(_ asset: SelectedGenerationAsset) -> FullScreenPreviewItem {
		.asset(
			id: asset.id,
			collectionID: asset.collectionID,
			deleteTarget: .selectedThumbnail,
			title: asset.name,
			imageData: asset.imageData,
			pasteboardType: UTType(mimeType: asset.mimeType)?.identifier ?? asset.mimeType
		)
	}

	static func collectionAsset(_ item: SharedSettings.GenerationAssetItem, imageData: Data) -> FullScreenPreviewItem {
		.asset(
			id: item.id,
			collectionID: item.id,
			deleteTarget: .collectionItem,
			title: item.displayName,
			imageData: imageData,
			pasteboardType: UTType(mimeType: item.mimeType)?.identifier ?? item.mimeType
		)
	}

	static func historyAsset(_ asset: SharedSettings.GenerationHistoryAsset, imageData: Data) -> FullScreenPreviewItem {
		.historyAsset(
			id: asset.id,
			title: "Generation history image",
			imageData: imageData,
			pasteboardType: UTType(mimeType: asset.mimeType)?.identifier ?? asset.mimeType
		)
	}
}

private struct FullScreenImagePreview: View {
	@Environment(\.dismiss) private var dismiss

	let item: FullScreenPreviewItem
	let selection: PreviewSelectionAction?
	let rename: ((String) -> String)?
	let delete: (() -> Void)?
	let close: () -> Void
	let copy: () -> Void

	@State private var displayName: String
	@State private var draftName: String
	@State private var isRenaming = false
	@FocusState private var renameFocused: Bool

	init(
		item: FullScreenPreviewItem,
		selection: PreviewSelectionAction?,
		rename: ((String) -> String)?,
		delete: (() -> Void)?,
		close: @escaping () -> Void,
		copy: @escaping () -> Void
	) {
		self.item = item
		self.selection = selection
		self.rename = rename
		self.delete = delete
		self.close = close
		self.copy = copy
		_displayName = State(initialValue: item.title)
		_draftName = State(initialValue: item.title)
	}

	var body: some View {
		ZStack {
			Color.black
				.ignoresSafeArea()

			NativePhotoPreview(item: item)
				.ignoresSafeArea()
				.accessibilityLabel(item.title)
				.allowsHitTesting(false)

			VStack {
				topControls
				Spacer()
				controls
			}
			.padding(.horizontal, 24)
			.padding(.top, 12)
			.padding(.bottom, 12)
			.zIndex(1)
		}
		.statusBarHidden()
		.onChange(of: item.title) { _, title in
			displayName = title
			if !isRenaming {
				draftName = title
			}
		}
	}

	private var topControls: some View {
		HStack(alignment: .top, spacing: 12) {
			if let delete {
				controlButton(systemName: "trash.fill", accessibilityLabel: "Delete") {
					delete()
					closePreview()
				}
			}
			Spacer()
			if let selection {
				PreviewSelectionButton(isSelected: selection.isSelected) {
					selection.toggle()
				}
			}
			if let rename {
				nameControl(rename: rename)
			}
		}
	}

	private var controls: some View {
		controlRow
	}

	private var controlRow: some View {
		HStack {
			controlButton(systemName: "xmark", accessibilityLabel: "Close") {
				closePreview()
			}

			Spacer()

			controlButton(systemName: "doc.on.doc.fill", accessibilityLabel: "Copy") {
				copy()
			}
		}
	}

	private func controlButton(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: systemName)
				.font(.title3.weight(.bold))
				.foregroundStyle(.white)
				.frame(width: 56, height: 56)
				.background(.black.opacity(0.62), in: Circle())
				.overlay {
					Circle()
						.stroke(.white.opacity(0.24), lineWidth: 1)
				}
		}
		.buttonStyle(.plain)
		.contentShape(Circle())
		.accessibilityLabel(accessibilityLabel)
	}

	private func nameControl(rename: @escaping (String) -> String) -> some View {
		Group {
			if isRenaming {
				HStack(spacing: 8) {
					TextField("image-name", text: $draftName)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.white)
						.tint(.white)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
						.submitLabel(.done)
						.focused($renameFocused)
						.onSubmit {
							commitRename(rename)
						}

					Button {
						commitRename(rename)
					} label: {
						Image(systemName: "checkmark")
							.font(.subheadline.weight(.bold))
							.foregroundStyle(.white)
							.frame(width: 28, height: 28)
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Save image name")
				}
				.padding(.leading, 12)
				.padding(.trailing, 8)
				.frame(width: 230, height: 44)
				.background(.black.opacity(0.62), in: Capsule())
				.overlay {
					Capsule()
						.stroke(.white.opacity(0.24), lineWidth: 1)
				}
				.onAppear {
					DispatchQueue.main.async {
						renameFocused = true
					}
				}
			} else {
				Button {
					draftName = displayName
					isRenaming = true
				} label: {
					HStack(spacing: 7) {
						Text(displayName)
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.white)
							.lineLimit(1)

						Image(systemName: "pencil")
							.font(.caption.weight(.bold))
							.foregroundStyle(.white.opacity(0.82))
					}
					.padding(.horizontal, 14)
					.frame(maxWidth: 230, minHeight: 44)
					.background(.black.opacity(0.62), in: Capsule())
					.overlay {
						Capsule()
							.stroke(.white.opacity(0.24), lineWidth: 1)
					}
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Rename image")
				.accessibilityValue(displayName)
			}
		}
	}

	private func commitRename(_ rename: (String) -> String) {
		let name = rename(draftName)
		displayName = name
		draftName = name
		isRenaming = false
		renameFocused = false
	}

	private func closePreview() {
		close()
		dismiss()
	}
}

private struct NativePhotoPreview: UIViewRepresentable {
	let item: FullScreenPreviewItem

	func makeUIView(context: Context) -> NativePhotoPreviewUIView {
		NativePhotoPreviewUIView()
	}

	func updateUIView(_ uiView: NativePhotoPreviewUIView, context: Context) {
		uiView.configure(id: item.id, imageData: item.imageData, imageURL: item.imageURL)
	}

	static func dismantleUIView(_ uiView: NativePhotoPreviewUIView, coordinator: ()) {
		uiView.reset()
	}
}

private final class NativePhotoPreviewUIView: UIView {
	private let imageView = UIImageView()
	private var representedID: String?
	private var loadTask: URLSessionDataTask?
	private var analysisTask: Task<Void, Never>?
	private var imageAnalysisInteraction: ImageAnalysisInteraction?

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = .black
		imageView.backgroundColor = .black
		imageView.contentMode = .scaleAspectFit
		imageView.tintColor = .secondaryLabel
		imageView.isUserInteractionEnabled = true
		imageView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(imageView)
		NSLayoutConstraint.activate([
			imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
			imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
			imageView.topAnchor.constraint(equalTo: topAnchor),
			imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(id: String, imageData: Data?, imageURL: URL?) {
		guard representedID != id else { return }
		reset()
		representedID = id

		if let imageData {
			setImageData(imageData, id: id)
			return
		}

		guard let imageURL else {
			imageView.image = UIImage(systemName: "photo")
			return
		}

		let task = URLSession.shared.dataTask(with: imageURL) { [weak self] data, _, _ in
			guard let self, let data else { return }
			DispatchQueue.main.async {
				guard self.representedID == id else { return }
				self.setImageData(data, id: id)
			}
		}
		loadTask = task
		task.resume()
	}

	func reset() {
		loadTask?.cancel()
		loadTask = nil
		analysisTask?.cancel()
		analysisTask = nil
		if let imageAnalysisInteraction {
			imageView.removeInteraction(imageAnalysisInteraction)
			self.imageAnalysisInteraction = nil
		}
		representedID = nil
		imageView.image = nil
	}

	private func setImageData(_ data: Data, id: String) {
		let displayImage = UIImage.animatedGIF(data: data) ?? UIImage(data: data)
		guard let displayImage else {
			imageView.image = UIImage(systemName: "photo")
			return
		}
		imageView.image = displayImage
		imageView.startAnimating()
		prepareImageAnalysis(for: UIImage(data: data) ?? displayImage, id: id)
	}

	private func prepareImageAnalysis(for image: UIImage, id: String) {
		guard ImageAnalyzer.isSupported else { return }

		let interaction = ImageAnalysisInteraction(self)
		interaction.preferredInteractionTypes = [.imageSubject, .visualLookUp, .textSelection, .dataDetectors]
		imageView.addInteraction(interaction)
		imageAnalysisInteraction = interaction

		let analyzer = ImageAnalyzer()
		analysisTask = Task { [weak self] in
			let configuration = ImageAnalyzer.Configuration([.visualLookUp, .text, .machineReadableCode])
			guard let analysis = try? await analyzer.analyze(image, configuration: configuration) else { return }
			await MainActor.run {
				guard self?.representedID == id else { return }
				interaction.analysis = analysis
			}
		}
	}

	private func imageContentRect() -> CGRect {
		guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else {
			return imageView.bounds
		}
		return AVMakeRect(aspectRatio: image.size, insideRect: imageView.bounds)
	}
}

extension NativePhotoPreviewUIView: ImageAnalysisInteractionDelegate {
	func contentsRect(for interaction: ImageAnalysisInteraction) -> CGRect {
		imageContentRect()
	}

	func contentView(for interaction: ImageAnalysisInteraction) -> UIView? {
		imageView
	}

	func presentingViewController(for interaction: ImageAnalysisInteraction) -> UIViewController? {
		sequence(first: self as UIResponder?, next: { $0?.next })
			.first { $0 is UIViewController } as? UIViewController
	}
}

private struct SquareThumbnailTile<Content: View>: View {
	private let content: Content

	init(@ViewBuilder content: () -> Content) {
		self.content = content()
	}

	var body: some View {
		Color(.secondarySystemBackground)
			.aspectRatio(1, contentMode: .fit)
			.overlay {
				GeometryReader { proxy in
					content
						.frame(width: proxy.size.width, height: proxy.size.height)
						.clipped()
				}
			}
		.clipped()
	}
}

private struct MemePreview: UIViewRepresentable {
	let result: MemeResult

	func makeUIView(context: Context) -> MemePreviewUIView {
		MemePreviewUIView()
	}

	func updateUIView(_ uiView: MemePreviewUIView, context: Context) {
		uiView.configure(with: result)
	}

	static func dismantleUIView(_ uiView: MemePreviewUIView, coordinator: ()) {
		uiView.reset()
	}
}

private final class MemePreviewUIView: UIView {
	private let imageView = UIImageView()
	private var representedID: UUID?
	private var loadTask: URLSessionDataTask?
	private var player: AVPlayer?
	private var playerLayer: AVPlayerLayer?
	private var playbackObserver: NSObjectProtocol?

	override init(frame: CGRect) {
		super.init(frame: frame)
		clipsToBounds = true
		backgroundColor = .secondarySystemBackground

		imageView.contentMode = .scaleAspectFill
		imageView.tintColor = .secondaryLabel
		imageView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(imageView)
		NSLayoutConstraint.activate([
			imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
			imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
			imageView.topAnchor.constraint(equalTo: topAnchor),
			imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		playerLayer?.frame = bounds
	}

	func configure(with result: MemeResult) {
		guard representedID != result.id else { return }
		reset()
		representedID = result.id
		imageView.isHidden = false
		imageView.image = UIImage(systemName: "photo")

		if let data = result.imageData {
			imageView.image = UIImage.animatedGIF(data: data) ?? UIImage(data: data)
			imageView.startAnimating()
			return
		}

		if let previewVideoURL = result.previewVideoURL {
			playVideo(previewVideoURL)
			if let previewURL = result.previewURL {
				loadImage(previewURL, id: result.id)
			}
			return
		}

		guard let previewURL = result.previewURL else { return }
		loadImage(previewURL, id: result.id)
	}

	func reset() {
		loadTask?.cancel()
		loadTask = nil
		stopVideo()
		representedID = nil
		imageView.isHidden = false
		imageView.image = nil
	}

	private func loadImage(_ url: URL, id: UUID) {
		let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
			guard let self, let data else { return }
			let image = UIImage.animatedGIF(data: data) ?? UIImage(data: data)
			guard let image else { return }
			DispatchQueue.main.async {
				guard self.representedID == id else { return }
				self.imageView.image = image
				self.imageView.startAnimating()
			}
		}
		loadTask = task
		task.resume()
	}

	private func playVideo(_ url: URL) {
		let player = AVPlayer(url: url)
		player.isMuted = true
		let layer = AVPlayerLayer(player: player)
		layer.videoGravity = .resizeAspectFill
		layer.frame = bounds
		layer.zPosition = 1
		self.layer.addSublayer(layer)
		playbackObserver = NotificationCenter.default.addObserver(
			forName: .AVPlayerItemDidPlayToEndTime,
			object: player.currentItem,
			queue: .main
		) { [weak player] _ in
			player?.seek(to: .zero)
			player?.play()
		}
		player.play()
		self.player = player
		playerLayer = layer
	}

	private func stopVideo() {
		player?.pause()
		player = nil
		playerLayer?.removeFromSuperlayer()
		playerLayer = nil
		if let playbackObserver {
			NotificationCenter.default.removeObserver(playbackObserver)
			self.playbackObserver = nil
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
	@Binding var appearanceTheme: SharedSettings.AppearanceTheme
	@State private var keyboardHasFullAccess = SharedSettings.keyboardHasFullAccess
	@State private var keyboardTest = ""
	@State private var copiedImage: UIImage?
	@State private var copiedPreviewVersion = SharedSettings.copiedMemePreviewVersion
	@State private var keyboardTestFocusRequest = 0

	private let previewTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

	var body: some View {
		Form {
			Section("Theme") {
				Picker("Theme", selection: $appearanceTheme) {
					ForEach(SharedSettings.AppearanceTheme.allCases) { theme in
						Text(theme.title)
							.tag(theme)
					}
				}
				.pickerStyle(.segmented)
			}

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
					KeyboardTestTextField(text: $keyboardTest, focusRequest: keyboardTestFocusRequest)
						.frame(minHeight: 44)

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
				.onTapGesture(perform: focusKeyboardTestInput)
			}

			Section("Generation") {
				LabeledContent("Model", value: SharedSettings.geminiModel)
			}
		}
		.scrollContentBackground(.hidden)
		.background(Color(.systemBackground).ignoresSafeArea())
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
		.onChange(of: appearanceTheme) { _, theme in
			SharedSettings.appearanceTheme = theme
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
		keyboardTestFocusRequest += 1
	}
}

private struct KeyboardTestTextField: UIViewRepresentable {
	@Binding var text: String
	let focusRequest: Int

	func makeCoordinator() -> Coordinator {
		Coordinator(text: $text)
	}

	func makeUIView(context: Context) -> UITextField {
		let textField = UITextField()
		textField.placeholder = "Test keyboard input"
		textField.autocapitalizationType = .none
		textField.autocorrectionType = .no
		textField.textContentType = .none
		textField.returnKeyType = .done
		textField.borderStyle = .none
		textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		textField.addTarget(context.coordinator, action: #selector(Coordinator.requestKeyboard(_:)), for: .touchDown)
		textField.addTarget(context.coordinator, action: #selector(Coordinator.requestKeyboard(_:)), for: .editingDidBegin)
		textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
		return textField
	}

	func updateUIView(_ textField: UITextField, context: Context) {
		if textField.text != text {
			textField.text = text
		}
		guard context.coordinator.focusRequest != focusRequest else { return }
		context.coordinator.focusRequest = focusRequest
		DispatchQueue.main.async {
			textField.reloadInputViews()
			textField.becomeFirstResponder()
		}
	}

	@MainActor
	final class Coordinator: NSObject {
		@Binding var text: String
		var focusRequest = 0

		init(text: Binding<String>) {
			_text = text
		}

		@objc func textDidChange(_ textField: UITextField) {
			text = textField.text ?? ""
		}

		@objc func requestKeyboard(_ textField: UITextField) {
			DispatchQueue.main.async {
				textField.reloadInputViews()
				textField.becomeFirstResponder()
			}
		}
	}
}

@MainActor
@Observable
private final class MemeForgeModel {
	var sortOrder: MemeSortOrder {
		didSet {
			guard oldValue != sortOrder else { return }
			SharedSettings.appMemeSortOrder = sortOrder.rawValue
			refreshHistoryIfNeeded()
		}
	}
	var mode: MemeMode {
		didSet {
			guard oldValue != mode else { return }
			SharedSettings.appMemeMode = mode.rawValue
			resetResults()
			refreshHistoryIfNeeded()
			refreshGenerationAssetCollection()
			refreshGenerationHistory()
		}
	}
	var query = "" {
		didSet {
			guard oldValue != query else { return }
			switch mode {
			case .search:
				resetResults()
				refreshHistoryIfNeeded()
			case .generate:
				requestError = nil
			case .history:
				break
			}
		}
	}
	var results: [MemeResult] = []
	var requestError: RequestError?
	var isLoading = false
	var showingHistory = false
	var selectedGenerationAssets: [SelectedGenerationAsset] = []
	var generationAssetCollection: [SharedSettings.GenerationAssetItem] = []
	var generationHistory: [SharedSettings.GenerationHistoryItem] = []
	var statusMessage: String?
	var copiedResultID: UUID?
	var selectedGenerationAssetCollectionIDs: Set<UUID> {
		Set(selectedGenerationAssets.compactMap(\.collectionID))
	}
	var visibleResults: [MemeResult] {
		guard mode == .search, showingHistory else { return results }
		return sortedSearchResults(results)
	}
	var visibleGenerationAssetCollection: [SharedSettings.GenerationAssetItem] {
		sortedGenerationAssets(generationAssetCollection)
	}
	var generationHistorySections: [GenerationHistorySection] {
		let calendar = Calendar.current
		let grouped = Dictionary(grouping: generationHistory) { item in
			calendar.startOfDay(for: Date(timeIntervalSince1970: item.updatedAt))
		}
		return grouped.keys.sorted(by: >).map { day in
			GenerationHistorySection(
				date: day,
				title: Self.historySectionTitle(for: day),
				items: grouped[day]?.sorted { $0.updatedAt > $1.updatedAt } ?? []
			)
		}
	}
	var usesGeneratedStage: Bool {
		mode == .generate && (isLoading || !results.isEmpty)
	}
	var hasTiledContent: Bool {
		!results.isEmpty || isLoading || (mode == .generate && !generationAssetCollection.isEmpty)
	}

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
	private let generationInstruction = "Create exactly one static meme image. Make it visually clear, funny, and ready to share."

	init() {
		sortOrder = MemeSortOrder(rawValue: SharedSettings.appMemeSortOrder) ?? .date
		mode = MemeMode(rawValue: SharedSettings.appMemeMode) ?? .search
		refreshHistoryIfNeeded()
		refreshGenerationAssetCollection()
		refreshGenerationHistory()
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
		case .history:
			break
		}
	}

	func submitGeneratedStage(mode: GeneratedPromptMode, sourceResult: MemeResult?) {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		requestError = nil
		guard !trimmed.isEmpty else { return }

		switch mode {
		case .reroll:
			generate(
				trimmed,
				assetsOverride: sourceResult?.generationAssets ?? selectedGenerationAssets,
				historyID: sourceResult?.generationHistoryID
			)
		case .update:
			guard let sourceResult, let imageData = sourceResult.imageData else {
				showRequestError(title: "No generated image", detail: "Generate an image before updating it.")
				return
			}
			let mimeType = UTType(sourceResult.pasteboardType)?.preferredMIMEType ?? "image/png"
			let asset = SelectedGenerationAsset(collectionID: nil, imageData: imageData, mimeType: mimeType, useCount: 0)
			generate(trimmed, assetsOverride: [asset], historyID: sourceResult.generationHistoryID)
		}
	}

	func closeGeneratedStage() {
		resetResults()
	}

	func clearQuery() {
		query = ""
	}

	func refreshGenerationAssetCollection() {
		generationAssetCollection = SharedSettings.generationAssetCollection
		for index in selectedGenerationAssets.indices {
			guard let collectionID = selectedGenerationAssets[index].collectionID,
				let item = generationAssetCollection.first(where: { $0.id == collectionID })
			else {
				continue
			}
			selectedGenerationAssets[index].name = item.displayName
		}
	}

	func refreshGenerationHistory() {
		generationHistory = SharedSettings.generationHistory
	}

	func insertPickedGenerationAssets(_ payloads: [SharedSettings.GenerationAssetPayload]) {
		guard !payloads.isEmpty else { return }

		var assets: [SelectedGenerationAsset] = []
		var selectedCollectionIDs = Set(selectedGenerationAssets.compactMap(\.collectionID))
		for payload in payloads {
			guard let item = SharedSettings.addGenerationAsset(payload) else { continue }
			guard selectedCollectionIDs.insert(item.id).inserted else { continue }
			let data = SharedSettings.generationAssetData(for: item) ?? payload.data
			assets.append(SelectedGenerationAsset(collectionItem: item, imageData: data))
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

	func isGenerationAssetSelected(collectionID: UUID) -> Bool {
		selectedGenerationAssets.contains { $0.collectionID == collectionID }
	}

	func toggleGenerationAsset(_ item: SharedSettings.GenerationAssetItem) {
		if isGenerationAssetSelected(collectionID: item.id) {
			removeGenerationAsset(collectionID: item.id)
		} else {
			insertGenerationAsset(item)
		}
	}

	func toggleGenerationAsset(collectionID: UUID) {
		if isGenerationAssetSelected(collectionID: collectionID) {
			removeGenerationAsset(collectionID: collectionID)
			return
		}

		guard let item = generationAssetCollection.first(where: { $0.id == collectionID }) else { return }
		insertGenerationAsset(item)
	}

	func removeGenerationAsset(_ asset: SelectedGenerationAsset) {
		removeGenerationAsset(id: asset.id)
	}

	func removeGenerationAsset(id: UUID) {
		selectedGenerationAssets.removeAll { $0.id == id }
		resetResults()
	}

	func removeGenerationAsset(collectionID: UUID) {
		selectedGenerationAssets.removeAll { $0.collectionID == collectionID }
		resetResults()
	}

	func renameCollectionGenerationAsset(id: UUID, to rawName: String) -> SharedSettings.GenerationAssetItem? {
		guard let item = SharedSettings.renameGenerationAsset(id: id, to: rawName) else { return nil }
		refreshGenerationAssetCollection()
		for index in selectedGenerationAssets.indices where selectedGenerationAssets[index].collectionID == id {
			selectedGenerationAssets[index].name = item.displayName
		}
		return item
	}

	func generationAssetMentionOptions(matching query: String) -> [SharedSettings.GenerationAssetItem] {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		let items = generationAssetCollection.sorted {
			$0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
		}
		guard !trimmed.isEmpty else { return items }
		return items.filter { item in
			item.displayName.lowercased().contains(trimmed)
		}
	}

	func deleteCollectionGenerationAsset(id: UUID) {
		selectedGenerationAssets.removeAll { $0.collectionID == id }
		SharedSettings.deleteGenerationAsset(id: id)
		refreshGenerationAssetCollection()
		resetResults()
		showStatus("Deleted")
	}

	func deleteHistoryResult(_ result: MemeResult) {
		guard let copyURL = result.copyURL else { return }
		guard SharedSettings.deleteGiphyMeme(copyURL: copyURL) else { return }
		historyUseCounts[copyURL.absoluteString] = nil
		if showingHistory {
			results.removeAll { $0.copyURL == copyURL }
			showingHistory = !results.isEmpty
		} else {
			for index in results.indices where results[index].copyURL == copyURL {
				results[index] = results[index].withUseCount(0)
			}
		}
		showStatus("Deleted")
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

	private func sortedSearchResults(_ results: [MemeResult]) -> [MemeResult] {
		switch sortOrder {
		case .date:
			guard showingHistory else { return results }
			return results.enumerated().sorted { lhs, rhs in
				let lhsDate = lhs.element.sortDate ?? 0
				let rhsDate = rhs.element.sortDate ?? 0
				if lhsDate != rhsDate {
					return lhsDate > rhsDate
				}
				return lhs.offset < rhs.offset
			}.map(\.element)
		case .count:
			return results.enumerated().sorted { lhs, rhs in
				if lhs.element.useCount != rhs.element.useCount {
					return lhs.element.useCount > rhs.element.useCount
				}
				let lhsDate = lhs.element.sortDate ?? 0
				let rhsDate = rhs.element.sortDate ?? 0
				if lhsDate != rhsDate {
					return lhsDate > rhsDate
				}
				return lhs.offset < rhs.offset
			}.map(\.element)
		}
	}

	private func sortedGenerationAssets(_ items: [SharedSettings.GenerationAssetItem]) -> [SharedSettings.GenerationAssetItem] {
		items.enumerated().sorted { lhs, rhs in
			switch sortOrder {
			case .date:
				if lhs.element.addedAt != rhs.element.addedAt {
					return lhs.element.addedAt > rhs.element.addedAt
				}
			case .count:
				if lhs.element.useCount != rhs.element.useCount {
					return lhs.element.useCount > rhs.element.useCount
				}
				if lhs.element.addedAt != rhs.element.addedAt {
					return lhs.element.addedAt > rhs.element.addedAt
				}
			}
			return lhs.offset < rhs.offset
		}.map(\.element)
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

	func copyImageData(_ data: Data, pasteboardType: String) {
		let payload = Self.normalizedCopyPayload(data: data, pasteboardType: pasteboardType)
		UIPasteboard.general.setData(payload.data, forPasteboardType: payload.pasteboardType)
		SharedSettings.updateCopiedMemePreview(payload.data)
		showStatus("Copied")
	}

	func copyGenerationHistoryPrompt(_ step: SharedSettings.GenerationHistoryStep) {
		UIPasteboard.general.string = step.prompt
		showStatus("Copied prompt")
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

	private func generate(_ trimmed: String, assetsOverride: [SelectedGenerationAsset]? = nil, historyID: UUID? = nil) {
		guard !SharedSettings.geminiAPIKey.isEmpty else {
			showRequestError(title: "Gemini API key missing", detail: "MemeforgeGeminiAPIKey is empty in this build.")
			return
		}

		currentTask?.cancel()
		let requestID = UUID()
		let historyID = historyID ?? UUID()
		generationID = requestID
		searchQuery = ""
		searchOffset = 0
		canLoadMoreSearchResults = false
		isLoading = true
		showingHistory = false
		pendingGenerationCount = 1
		let assets = assetsOverride ?? selectedGenerationAssets
		recordSelectedGenerationAssetUses(assets)

		currentTask = Task { [weak self] in
			await self?.generateResults(for: trimmed, assets: assets, requestID: requestID, historyID: historyID)
		}
	}

	private func generateResults(for prompt: String, assets: [SelectedGenerationAsset], requestID: UUID, historyID: UUID) async {
		let generated = await Self.geminiResult(
			for: prompt,
			instruction: generationInstruction,
			assets: assets,
			historyID: historyID
		)
		guard generationID == requestID else { return }
		isLoading = false
		pendingGenerationCount = 0

		switch generated {
		case .success(let result):
			results.append(result)
			recordGenerationHistory(historyID: historyID, prompt: prompt, assets: assets, results: [result])
		case .failure(let error):
			requestError = error
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

	private func recordGenerationHistory(historyID: UUID, prompt: String, assets: [SelectedGenerationAsset], results: [MemeResult]) {
		let attachments = assets.map { asset in
			SharedSettings.GenerationAssetPayload(data: asset.imageData, mimeType: asset.mimeType)
		}
		let images = results.compactMap { result -> SharedSettings.GenerationAssetPayload? in
			guard let imageData = result.imageData else { return nil }
			let mimeType = UTType(result.pasteboardType)?.preferredMIMEType ?? "image/png"
			return SharedSettings.GenerationAssetPayload(data: imageData, mimeType: mimeType)
		}
		guard SharedSettings.recordGenerationHistory(id: historyID, prompt: prompt, attachments: attachments, images: images) != nil else { return }
		refreshGenerationHistory()
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

	private static func historySectionTitle(for date: Date) -> String {
		let calendar = Calendar.current
		if calendar.isDateInToday(date) {
			return "Today"
		}
		if calendar.isDateInYesterday(date) {
			return "Yesterday"
		}
		return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
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

	private nonisolated static func geminiResult(
		for prompt: String,
		instruction: String,
		assets: [SelectedGenerationAsset],
		historyID: UUID
	) async -> Result<MemeResult, RequestError> {
		guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(SharedSettings.geminiModel):generateContent") else {
			return .failure(RequestError(title: "Generation failed", detail: "Could not build the Gemini URL."))
		}

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue(SharedSettings.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = geminiRequestBody(for: prompt, instruction: instruction, assets: assets)

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
			return .success(
				MemeResult(
					title: prompt,
					previewURL: nil,
					previewVideoURL: nil,
					copyURL: nil,
					imageData: imageData,
					pasteboardType: pasteboardType,
					generationAssets: assets,
					generationHistoryID: historyID
				)
			)
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

	private nonisolated static func geminiRequestBody(for idea: String, instruction: String, assets: [SelectedGenerationAsset]) -> Data? {
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
					["text": instruction],
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
	case history

	var id: Self { self }

	var title: String {
		switch self {
		case .search:
			"Search"
		case .generate:
			"Generate"
		case .history:
			"History"
		}
	}

	var placeholder: String {
		switch self {
		case .search:
			"type a meme search"
		case .generate:
			"describe a static meme"
		case .history:
			""
		}
	}
}

private enum GeneratedPromptMode: String, CaseIterable, Identifiable, Sendable {
	case reroll
	case update

	var id: Self { self }

	var title: String {
		rawValue
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
	let generationAssets: [SelectedGenerationAsset]
	let generationHistoryID: UUID?
	let sortDate: TimeInterval?
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
		generationAssets: [SelectedGenerationAsset] = [],
		generationHistoryID: UUID? = nil,
		sortDate: TimeInterval? = nil,
		useCount: Int = 0
	) {
		self.title = title
		self.previewURL = previewURL
		self.previewVideoURL = previewVideoURL
		self.copyURL = copyURL
		self.imageData = imageData
		self.pasteboardType = pasteboardType
		self.generationAssets = generationAssets
		self.generationHistoryID = generationHistoryID
		self.sortDate = sortDate
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
			sortDate: item.lastUsedAt,
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
			generationAssets: generationAssets,
			generationHistoryID: generationHistoryID,
			sortDate: sortDate,
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

private struct GenerationHistorySection: Identifiable, Sendable {
	let date: Date
	let title: String
	let items: [SharedSettings.GenerationHistoryItem]

	var id: TimeInterval {
		date.timeIntervalSince1970
	}
}

private extension Collection {
	var only: Element? {
		count == 1 ? first : nil
	}
}

private struct CopyPayload: Sendable {
	let data: Data
	let pasteboardType: String
}

private struct SelectedGenerationAsset: Identifiable, Hashable, Sendable {
	let id: UUID
	let collectionID: UUID?
	var name: String
	let imageData: Data
	let mimeType: String
	var useCount: Int

	init(id: UUID = UUID(), collectionID: UUID?, name: String = "image", imageData: Data, mimeType: String, useCount: Int) {
		self.id = id
		self.collectionID = collectionID
		self.name = name
		self.imageData = imageData
		self.mimeType = mimeType
		self.useCount = useCount
	}

	init(collectionItem: SharedSettings.GenerationAssetItem, imageData: Data) {
		self.init(
			collectionID: collectionItem.id,
			name: collectionItem.displayName,
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
