import AVFoundation
import ImageIO
import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class KeyboardViewController: UIInputViewController {
	private enum Mode: Int, CaseIterable {
		case search
		case generate
	}

	private enum KeyboardLayoutMode {
		case alphabet
		case numeric
		case symbols
	}

	private enum ShiftState {
		case lowercase
		case uppercase
		case capsLock
	}

	private enum ScreenSlideDirection {
		case left
		case right
	}

	fileprivate struct MemeResult: Hashable {
		let id = UUID()
		let title: String
		let previewURL: URL?
		let previewVideoURL: URL?
		let copyURL: URL?
		let imageData: Data?
		let pasteboardType: String
		let useCount: Int

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

		var historyKey: String? {
			copyURL?.absoluteString
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

	fileprivate struct SelectedGenerationAsset: Hashable {
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

	private struct RequestError: Equatable, Sendable {
		let title: String
		let detail: String
	}

	private var mode = Mode.search
	private var query = ""
	private var results: [MemeResult] = []
	private var requestError: RequestError?
	private var currentTasks: [URLSessionDataTask] = []
	private var keyRowStacks: [UIStackView] = []
	private var letterKeyButtons: [UIButton] = []
	private var systemKeyButtons: [UIButton] = []
	private var returnKeyButton: UIButton?
	private var alphabetKeyButtons: [(button: UIButton, letter: String)] = []
	private var shiftKeyButton: UIButton?
	private var typingControlsVisible = true
	private var queryInputFocused = true
	private var keyboardLayoutMode = KeyboardLayoutMode.alphabet
	private var shiftState = ShiftState.lowercase
	private var lastShiftTapDate = Date.distantPast
	private var searchQuery = ""
	private var searchOffset = 0
	private var canLoadMoreSearchResults = false
	private var isLoadingSearchResults = false
	private var generationID = UUID()
	private var pendingGenerationCount = 0
	private var historyUseCounts: [String: Int] = [:]
	private var showingHistory = false
	private var assetPickerVisible = false
	private var assetMentionVisible = false
	private var selectedGenerationAssets: [SelectedGenerationAsset] = []
	private var generationAssetCollection: [SharedSettings.GenerationAssetItem] = []
	private var assetMentionItems: [SelectedGenerationAsset] = []
	private var screenSwipeGestureRecognizers: [UISwipeGestureRecognizer] = []
	private let keyFeedback = UIImpactFeedbackGenerator(style: .light)

	private let searchPageSize = 30
	private let keyHeight: CGFloat = 46
	private let keySpacing: CGFloat = 6
	private let rootSpacing: CGFloat = 6
	private let topRowHeight: CGFloat = 30
	private let minQueryBoxHeight: CGFloat = 34
	private let maxQueryBoxLines: CGFloat = 5
	private let queryBoxHorizontalPadding: CGFloat = 12
	private let queryBoxVerticalPadding: CGFloat = 7
	private let queryClearButtonSize: CGFloat = 22
	private let queryClearButtonSpacing: CGFloat = 4
	private var queryClearButtonTopOffset: CGFloat {
		queryBoxVerticalPadding + (queryLabel.font.lineHeight - queryClearButtonSize) / 2
	}
	private let accessBoxHeight: CGFloat = 80
	private let requestErrorHeight: CGFloat = 132
	private let maxSearchCollectionHeight: CGFloat = 320
	private let maxAssetPickerKeyboardHeight: CGFloat = 720
	private let containerVerticalPadding: CGFloat = 10
	private let assetPickerControlsHeight: CGFloat = 34
	private let assetMentionHeight: CGFloat = 44
	private let selectedAssetsHeight: CGFloat = 66
	private let selectedAssetSide: CGFloat = 58
	private let generatedStyles = [
		"Classic photographic meme style. When the prompt references @image-name, use the attachment labeled with that exact name.",
		"Bold illustrated meme style. When the prompt references @image-name, use the attachment labeled with that exact name.",
	]

	private let modeControl = UISegmentedControl(items: ["Search", "Generate"])
	private let queryLabel = UILabel()
	private let queryRow = UIStackView()
	private let queryBox = UIControl()
	private let queryCaret = UIView()
	private let queryClearButton = UIButton(type: .system)
	private lazy var assetToggleButton = smallButton("photo.stack", action: #selector(showAssetPicker))
	private let assetMentionScrollView = UIScrollView()
	private let assetMentionStack = UIStackView()
	private let assetPickerControls = UIStackView()
	private lazy var addAssetButton = assetPickerButton(title: "Add", systemName: "plus", action: #selector(addAssetsTapped))
	private let accessBox = UIView()
	private let accessTitleLabel = UILabel()
	private let accessDetailLabel = UILabel()
	private let selectedAssetsCollectionView: UICollectionView
	private let collectionView: UICollectionView
	private let loadingIndicator = UIActivityIndicatorView(style: .large)
	private let requestErrorView = UIView()
	private let requestErrorTitleLabel = UILabel()
	private let requestErrorDetailLabel = UILabel()
	private let rootStack = UIStackView()
	private lazy var keyboardRestoreButton = smallButton("keyboard", action: #selector(focusQuery))
	private lazy var closeButton = smallButton("xmark", action: #selector(closeKeyboard))
	private var heightConstraint: NSLayoutConstraint?
	private var collectionHeightConstraint: NSLayoutConstraint?
	private var selectedAssetsHeightConstraint: NSLayoutConstraint?
	private var queryBoxHeightConstraint: NSLayoutConstraint?
	private var queryCaretLeadingConstraint: NSLayoutConstraint?
	private var queryCaretTopConstraint: NSLayoutConstraint?
	private var queryCaretHeightConstraint: NSLayoutConstraint?

	init() {
		let selectedLayout = UICollectionViewFlowLayout()
		selectedLayout.scrollDirection = .horizontal
		selectedLayout.minimumLineSpacing = 6
		selectedLayout.minimumInteritemSpacing = 6
		selectedLayout.sectionInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
		selectedAssetsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: selectedLayout)

		let layout = UICollectionViewFlowLayout()
		layout.scrollDirection = .vertical
		layout.minimumLineSpacing = 6
		layout.minimumInteritemSpacing = 6
		layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 4, right: 0)
		collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		syncAppearanceOverride()
		heightConstraint = view.heightAnchor.constraint(equalToConstant: 280)
		heightConstraint?.isActive = true
		buildInterface()
		applyKeyboardTheme()
		keyFeedback.prepare()
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
			self.applyKeyboardTheme()
		}
		updatePrompt()
		showHistoryIfNeeded()
		refreshGenerationAssetCollection()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		syncAppearanceOverride()
		applyKeyboardTheme()
		updatePrompt()
		showHistoryIfNeeded()
		refreshGenerationAssetCollection()
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		updateQueryBoxHeight()
		updateCaretPosition()
		updateContainerSizing()
	}

	private func buildInterface() {
		modeControl.selectedSegmentIndex = Mode.search.rawValue
		modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
		modeControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		queryLabel.font = .systemFont(ofSize: 17, weight: .semibold)
		queryLabel.textColor = .label
		queryLabel.numberOfLines = Int(maxQueryBoxLines)
		queryLabel.lineBreakMode = .byWordWrapping
		queryLabel.setContentCompressionResistancePriority(.required, for: .vertical)

		accessTitleLabel.font = .systemFont(ofSize: 14, weight: .bold)
		accessTitleLabel.textColor = .label
		accessTitleLabel.text = "Full Access is off"

		accessDetailLabel.font = .systemFont(ofSize: 11, weight: .medium)
		accessDetailLabel.textColor = .secondaryLabel
		accessDetailLabel.numberOfLines = 2
		accessDetailLabel.text = "Open Memeforge, then enable Allow Full Access in Keyboard settings."

		accessBox.backgroundColor = .systemBackground
		accessBox.layer.cornerRadius = 8
		accessBox.translatesAutoresizingMaskIntoConstraints = false
		accessBox.heightAnchor.constraint(equalToConstant: accessBoxHeight).isActive = true

		collectionView.backgroundColor = .clear
		collectionView.dataSource = self
		collectionView.delegate = self
		collectionView.register(MemeCell.self, forCellWithReuseIdentifier: MemeCell.reuseIdentifier)
		collectionView.showsHorizontalScrollIndicator = false
		collectionView.showsVerticalScrollIndicator = true
		collectionView.alwaysBounceVertical = false
		collectionHeightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 0)
		collectionHeightConstraint?.isActive = true
		collectionView.setContentHuggingPriority(.defaultLow, for: .vertical)
		collectionView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

		selectedAssetsCollectionView.backgroundColor = .clear
		selectedAssetsCollectionView.dataSource = self
		selectedAssetsCollectionView.delegate = self
		selectedAssetsCollectionView.register(SelectedAssetCell.self, forCellWithReuseIdentifier: SelectedAssetCell.reuseIdentifier)
		selectedAssetsCollectionView.showsHorizontalScrollIndicator = false
		selectedAssetsCollectionView.showsVerticalScrollIndicator = false
		selectedAssetsCollectionView.alwaysBounceHorizontal = true
		selectedAssetsHeightConstraint = selectedAssetsCollectionView.heightAnchor.constraint(equalToConstant: 0)
		selectedAssetsHeightConstraint?.isActive = true
		selectedAssetsCollectionView.isHidden = true

		requestErrorTitleLabel.font = .systemFont(ofSize: 13, weight: .bold)
		requestErrorTitleLabel.textColor = .systemRed
		requestErrorTitleLabel.numberOfLines = 1

		requestErrorDetailLabel.font = .systemFont(ofSize: 11, weight: .medium)
		requestErrorDetailLabel.textColor = .secondaryLabel
		requestErrorDetailLabel.numberOfLines = 4
		requestErrorDetailLabel.lineBreakMode = .byTruncatingTail

		requestErrorView.backgroundColor = .systemBackground
		requestErrorView.layer.cornerRadius = 8
		requestErrorView.clipsToBounds = true
		let requestErrorStack = UIStackView(arrangedSubviews: [requestErrorTitleLabel, requestErrorDetailLabel])
		requestErrorStack.axis = .vertical
		requestErrorStack.spacing = 5
		requestErrorStack.alignment = .fill
		requestErrorStack.translatesAutoresizingMaskIntoConstraints = false
		requestErrorView.addSubview(requestErrorStack)
		NSLayoutConstraint.activate([
			requestErrorStack.leadingAnchor.constraint(equalTo: requestErrorView.leadingAnchor, constant: 12),
			requestErrorStack.trailingAnchor.constraint(equalTo: requestErrorView.trailingAnchor, constant: -12),
			requestErrorStack.centerYAnchor.constraint(equalTo: requestErrorView.centerYAnchor),
			requestErrorStack.topAnchor.constraint(greaterThanOrEqualTo: requestErrorView.topAnchor, constant: 10),
			requestErrorStack.bottomAnchor.constraint(lessThanOrEqualTo: requestErrorView.bottomAnchor, constant: -10),
		])

		rootStack.axis = .vertical
		rootStack.spacing = rootSpacing
		rootStack.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(rootStack)

		NSLayoutConstraint.activate([
			rootStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
			rootStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
			rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
			rootStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
		])
		installScreenSwipeGestures()

		keyboardRestoreButton.isHidden = true
		let topRow = UIStackView(arrangedSubviews: [modeControl, keyboardRestoreButton, closeButton])
		topRow.axis = .horizontal
		topRow.spacing = 8
		topRow.alignment = .center
		topRow.heightAnchor.constraint(equalToConstant: topRowHeight).isActive = true
		rootStack.addArrangedSubview(topRow)

		queryBox.backgroundColor = .tertiarySystemBackground
		queryBox.layer.cornerRadius = 8
		queryBox.layer.borderWidth = 2
		queryBox.translatesAutoresizingMaskIntoConstraints = false
		queryBox.setContentHuggingPriority(.defaultLow, for: .horizontal)
		queryBoxHeightConstraint = queryBox.heightAnchor.constraint(equalToConstant: minQueryBoxHeight)
		queryBoxHeightConstraint?.isActive = true
		queryBox.addTarget(self, action: #selector(focusQuery), for: .touchUpInside)
		queryBox.addSubview(queryLabel)
		queryCaret.backgroundColor = .systemBlue
		queryCaret.layer.cornerRadius = 1
		queryCaret.isHidden = true
		queryCaret.isUserInteractionEnabled = false
		queryBox.addSubview(queryCaret)
		queryClearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
		queryClearButton.accessibilityLabel = "Clear input"
		queryClearButton.isHidden = true
		queryClearButton.addTarget(self, action: #selector(clearQuery), for: .touchUpInside)
		queryBox.addSubview(queryClearButton)
		queryLabel.translatesAutoresizingMaskIntoConstraints = false
		queryCaret.translatesAutoresizingMaskIntoConstraints = false
		queryClearButton.translatesAutoresizingMaskIntoConstraints = false
		let caretLeadingConstraint = queryCaret.leadingAnchor.constraint(equalTo: queryBox.leadingAnchor, constant: queryBoxHorizontalPadding)
		let caretTopConstraint = queryCaret.topAnchor.constraint(equalTo: queryBox.topAnchor, constant: queryBoxVerticalPadding)
		let caretHeightConstraint = queryCaret.heightAnchor.constraint(equalToConstant: queryLabel.font.lineHeight)
		queryCaretLeadingConstraint = caretLeadingConstraint
		queryCaretTopConstraint = caretTopConstraint
		queryCaretHeightConstraint = caretHeightConstraint
		NSLayoutConstraint.activate([
			queryLabel.leadingAnchor.constraint(equalTo: queryBox.leadingAnchor, constant: queryBoxHorizontalPadding),
			queryLabel.trailingAnchor.constraint(equalTo: queryClearButton.leadingAnchor, constant: -queryClearButtonSpacing),
			queryLabel.topAnchor.constraint(equalTo: queryBox.topAnchor, constant: queryBoxVerticalPadding),
			queryLabel.bottomAnchor.constraint(equalTo: queryBox.bottomAnchor, constant: -queryBoxVerticalPadding),
			caretLeadingConstraint,
			caretTopConstraint,
			queryCaret.widthAnchor.constraint(equalToConstant: 2),
			caretHeightConstraint,
			queryClearButton.trailingAnchor.constraint(equalTo: queryBox.trailingAnchor, constant: -queryClearButtonSpacing),
			queryClearButton.topAnchor.constraint(equalTo: queryBox.topAnchor, constant: queryClearButtonTopOffset),
			queryClearButton.widthAnchor.constraint(equalToConstant: queryClearButtonSize),
			queryClearButton.heightAnchor.constraint(equalToConstant: queryClearButtonSize),
		])
		assetToggleButton.accessibilityLabel = "Choose generation assets"
		assetToggleButton.isHidden = true
		queryRow.axis = .horizontal
		queryRow.spacing = 6
		queryRow.alignment = .top
		queryRow.addArrangedSubview(queryBox)
		queryRow.addArrangedSubview(assetToggleButton)
		rootStack.addArrangedSubview(queryRow)

		assetMentionScrollView.showsHorizontalScrollIndicator = false
		assetMentionScrollView.showsVerticalScrollIndicator = false
		assetMentionScrollView.alwaysBounceHorizontal = true
		assetMentionScrollView.isHidden = true
		assetMentionScrollView.heightAnchor.constraint(equalToConstant: assetMentionHeight).isActive = true
		assetMentionStack.axis = .horizontal
		assetMentionStack.spacing = 6
		assetMentionStack.alignment = .center
		assetMentionStack.translatesAutoresizingMaskIntoConstraints = false
		assetMentionScrollView.addSubview(assetMentionStack)
		NSLayoutConstraint.activate([
			assetMentionStack.leadingAnchor.constraint(equalTo: assetMentionScrollView.contentLayoutGuide.leadingAnchor),
			assetMentionStack.trailingAnchor.constraint(equalTo: assetMentionScrollView.contentLayoutGuide.trailingAnchor),
			assetMentionStack.topAnchor.constraint(equalTo: assetMentionScrollView.contentLayoutGuide.topAnchor, constant: 4),
			assetMentionStack.bottomAnchor.constraint(equalTo: assetMentionScrollView.contentLayoutGuide.bottomAnchor, constant: -4),
			assetMentionStack.heightAnchor.constraint(equalTo: assetMentionScrollView.frameLayoutGuide.heightAnchor, constant: -8),
		])
		rootStack.addArrangedSubview(assetMentionScrollView)

		assetPickerControls.axis = .horizontal
		assetPickerControls.spacing = 8
		assetPickerControls.alignment = .fill
		assetPickerControls.distribution = .fillEqually
		assetPickerControls.isHidden = true
		assetPickerControls.addArrangedSubview(addAssetButton)
		addAssetButton.heightAnchor.constraint(equalToConstant: assetPickerControlsHeight).isActive = true
		rootStack.addArrangedSubview(assetPickerControls)
		rootStack.addArrangedSubview(selectedAssetsCollectionView)

		rootStack.addArrangedSubview(accessBox)
		rootStack.addArrangedSubview(collectionView)
		loadingIndicator.hidesWhenStopped = true
		loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(loadingIndicator)
		NSLayoutConstraint.activate([
			loadingIndicator.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
			loadingIndicator.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
		])

		let accessButton = UIButton(type: .system)
		accessButton.setTitle("Open App", for: .normal)
		accessButton.backgroundColor = .tertiarySystemBackground
		accessButton.tintColor = .label
		accessButton.layer.cornerRadius = 8
		accessButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
		accessButton.widthAnchor.constraint(equalToConstant: 88).isActive = true
		accessButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
		accessButton.addTarget(self, action: #selector(openSetupApp), for: .touchUpInside)

		let accessTextStack = UIStackView(arrangedSubviews: [accessTitleLabel, accessDetailLabel])
		accessTextStack.axis = .vertical
		accessTextStack.spacing = 2

		let accessRow = UIStackView(arrangedSubviews: [accessTextStack, accessButton])
		accessRow.axis = .horizontal
		accessRow.spacing = 8
		accessRow.alignment = .center
		accessRow.translatesAutoresizingMaskIntoConstraints = false
		accessBox.addSubview(accessRow)
		NSLayoutConstraint.activate([
			accessRow.leadingAnchor.constraint(equalTo: accessBox.leadingAnchor, constant: 12),
			accessRow.trailingAnchor.constraint(equalTo: accessBox.trailingAnchor, constant: -12),
			accessRow.topAnchor.constraint(equalTo: accessBox.topAnchor, constant: 8),
			accessRow.bottomAnchor.constraint(equalTo: accessBox.bottomAnchor, constant: -8),
		])

		rebuildKeyboardRows()
	}

	private func rebuildKeyboardRows() {
		keyRowStacks.forEach { $0.removeFromSuperview() }
		keyRowStacks.removeAll()
		letterKeyButtons.removeAll()
		systemKeyButtons.removeAll()
		returnKeyButton = nil
		alphabetKeyButtons.removeAll()
		shiftKeyButton = nil

		let rows: [UIStackView]
		switch keyboardLayoutMode {
		case .alphabet:
			rows = [
				letterRow(["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]),
				letterRow(["a", "s", "d", "f", "g", "h", "j", "k", "l"], sideSpacerMultiplier: 0.5),
				shiftRow(),
				bottomRow(),
			]
		case .numeric:
			rows = [
				letterRow(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]),
				letterRow(["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]),
				numericSymbolRow(toggleKey: "symbols"),
				numericBottomRow(toggleKey: "letters"),
			]
		case .symbols:
			rows = [
				letterRow(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]),
				letterRow(["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"]),
				numericSymbolRow(toggleKey: "numbers"),
				numericBottomRow(toggleKey: "letters"),
			]
		}
		for row in rows {
			keyRowStacks.append(row)
			rootStack.addArrangedSubview(row)
		}
		applyKeyboardTheme()
		updateAlphabetKeyTitles()
		updateContainerSizing()
	}

	private func letterRow(_ letters: [String], sideSpacerMultiplier: CGFloat = 0) -> UIStackView {
		let row = UIStackView()
		row.axis = .horizontal
		row.spacing = keySpacing
		row.distribution = .fill
		let buttons = letters.map { keyButton($0) }

		if sideSpacerMultiplier > 0, let first = buttons.first {
			let leadingSpacer = UIView()
			let trailingSpacer = UIView()
			row.addArrangedSubview(leadingSpacer)
			buttons.forEach(row.addArrangedSubview)
			row.addArrangedSubview(trailingSpacer)
			NSLayoutConstraint.activate([
				leadingSpacer.widthAnchor.constraint(equalTo: first.widthAnchor, multiplier: sideSpacerMultiplier),
				trailingSpacer.widthAnchor.constraint(equalTo: leadingSpacer.widthAnchor),
			])
		} else {
			buttons.forEach(row.addArrangedSubview)
		}
		equalizeWidths(buttons)
		return row
	}

	private func shiftRow() -> UIStackView {
		let row = UIStackView()
		row.axis = .horizontal
		row.spacing = keySpacing
		row.distribution = .fill

		let shift = keyButton("shift")
		let letters = ["z", "x", "c", "v", "b", "n", "m"].map { keyButton($0) }
		let delete = keyButton("delete")
		let leadingSpacer = UIView()
		let trailingSpacer = UIView()
		([shift, leadingSpacer] + letters + [trailingSpacer, delete]).forEach(row.addArrangedSubview)
		equalizeWidths(letters)
		if let first = letters.first {
			NSLayoutConstraint.activate([
				shift.widthAnchor.constraint(equalTo: first.widthAnchor, multiplier: 1.35),
				delete.widthAnchor.constraint(equalTo: shift.widthAnchor),
				leadingSpacer.widthAnchor.constraint(equalTo: first.widthAnchor, multiplier: 0.25),
				trailingSpacer.widthAnchor.constraint(equalTo: leadingSpacer.widthAnchor),
			])
		}
		return row
	}

	private func bottomRow() -> UIStackView {
		let row = UIStackView()
		row.axis = .horizontal
		row.spacing = keySpacing
		row.distribution = .fill

		let numbers = keyButton("numbers")
		let space = keyButton("space")
		let submit = keyButton("submit")
		[numbers, space, submit].forEach(row.addArrangedSubview)
		NSLayoutConstraint.activate([
			submit.widthAnchor.constraint(equalTo: numbers.widthAnchor),
			space.widthAnchor.constraint(equalTo: numbers.widthAnchor, multiplier: 2.05),
		])
		return row
	}

	private func numericSymbolRow(toggleKey: String) -> UIStackView {
		let row = UIStackView()
		row.axis = .horizontal
		row.spacing = keySpacing
		row.distribution = .fill

		let toggle = keyButton(toggleKey)
		let characters = [".", ",", "?", "!", "'"].map { keyButton($0) }
		let delete = keyButton("delete")
		let leadingSpacer = UIView()
		let trailingSpacer = UIView()
		([toggle, leadingSpacer] + characters + [trailingSpacer, delete]).forEach(row.addArrangedSubview)
		equalizeWidths(characters)
		if let first = characters.first {
			NSLayoutConstraint.activate([
				toggle.widthAnchor.constraint(equalTo: first.widthAnchor, multiplier: 1.35),
				delete.widthAnchor.constraint(equalTo: toggle.widthAnchor),
				leadingSpacer.widthAnchor.constraint(equalTo: first.widthAnchor, multiplier: 0.25),
				trailingSpacer.widthAnchor.constraint(equalTo: leadingSpacer.widthAnchor),
			])
		}
		return row
	}

	private func numericBottomRow(toggleKey: String) -> UIStackView {
		let row = UIStackView()
		row.axis = .horizontal
		row.spacing = keySpacing
		row.distribution = .fill

		let letters = keyButton(toggleKey)
		let space = keyButton("space")
		let submit = keyButton("return")
		[letters, space, submit].forEach(row.addArrangedSubview)
		NSLayoutConstraint.activate([
			submit.widthAnchor.constraint(equalTo: letters.widthAnchor),
			space.widthAnchor.constraint(equalTo: letters.widthAnchor, multiplier: 2.05),
		])
		return row
	}

	private func equalizeWidths(_ buttons: [UIButton]) {
		guard let first = buttons.first else { return }
		for button in buttons.dropFirst() {
			button.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true
		}
	}

	private enum KeyRole {
		case letter
		case system
		case submit
	}

	private func keyButton(_ key: String) -> UIButton {
		let button = KeyboardKeyButton(type: .system)
		button.layer.cornerRadius = 8
		button.titleLabel?.font = .systemFont(ofSize: 25, weight: .regular)
		button.heightAnchor.constraint(equalToConstant: keyHeight).isActive = true
		button.accessibilityIdentifier = "key-\(key)"
		button.addTarget(self, action: #selector(keyTouchDown), for: .touchDown)

		let role: KeyRole
		switch key {
		case "space":
			button.setTitle(keyboardLayoutMode == .alphabet ? "" : "space", for: .normal)
			button.titleLabel?.font = .systemFont(ofSize: 21, weight: .regular)
			button.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
			role = .letter
		case "delete":
			button.setImage(UIImage(systemName: "delete.left"), for: .normal)
			button.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
			role = .system
		case "shift":
			button.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
			shiftKeyButton = button
			role = .system
		case "numbers":
			button.setTitle("123", for: .normal)
			button.titleLabel?.font = .systemFont(ofSize: 21, weight: .regular)
			button.addTarget(self, action: #selector(showNumericKeyboard), for: .touchUpInside)
			role = .system
		case "symbols":
			button.setTitle("#+=", for: .normal)
			button.titleLabel?.font = .systemFont(ofSize: 20, weight: .regular)
			button.addTarget(self, action: #selector(showSymbolKeyboard), for: .touchUpInside)
			role = .system
		case "letters":
			button.setTitle("ABC", for: .normal)
			button.titleLabel?.font = .systemFont(ofSize: 21, weight: .regular)
			button.addTarget(self, action: #selector(showAlphabetKeyboard), for: .touchUpInside)
			role = .system
		case "submit":
			button.setImage(UIImage(systemName: "checkmark"), for: .normal)
			button.addTarget(self, action: #selector(goTapped), for: .touchUpInside)
			role = .submit
		case "return":
			button.setTitle("return", for: .normal)
			button.titleLabel?.font = .systemFont(ofSize: 21, weight: .regular)
			button.addTarget(self, action: #selector(goTapped), for: .touchUpInside)
			role = .system
		default:
			if key.count == 1, let character = key.first, character.isLetter {
				alphabetKeyButtons.append((button, key.lowercased()))
				button.addAction(UIAction { [weak self] _ in self?.appendLetter(key) }, for: .touchUpInside)
			} else {
				button.setTitle(key, for: .normal)
				button.addAction(UIAction { [weak self] _ in self?.append(key) }, for: .touchUpInside)
			}
			role = .letter
		}

		register(button, role: role)
		return button
	}

	private func register(_ button: UIButton, role: KeyRole) {
		switch role {
		case .letter:
			letterKeyButtons.append(button)
		case .system:
			systemKeyButtons.append(button)
		case .submit:
			returnKeyButton = button
		}
	}

	private func updateAlphabetKeyTitles() {
		let usesUppercase = shiftState != .lowercase
		for key in alphabetKeyButtons {
			key.button.setTitle(usesUppercase ? key.letter.uppercased() : key.letter, for: .normal)
		}

		guard let shiftKeyButton else { return }
		let imageName: String
		switch shiftState {
		case .lowercase:
			imageName = "shift"
			shiftKeyButton.accessibilityLabel = "shift"
		case .uppercase:
			imageName = "shift.fill"
			shiftKeyButton.accessibilityLabel = "shift on"
		case .capsLock:
			imageName = "capslock.fill"
			shiftKeyButton.accessibilityLabel = "caps lock"
		}
		shiftKeyButton.setImage(UIImage(systemName: imageName), for: .normal)

		let isDark = usesDarkAppearance
		let active = shiftState != .lowercase
		let backgroundColor = active ? (isDark ? UIColor(white: 0.36, alpha: 1) : UIColor.white) : (isDark ? UIColor(white: 0.22, alpha: 1) : UIColor.systemGray3)
		let tintColor = isDark ? UIColor.white : UIColor.label
		styleKey(shiftKeyButton, backgroundColor: backgroundColor, tintColor: tintColor, shadow: !isDark && active)
	}

	private func syncAppearanceOverride() {
		let style = SharedSettings.appearanceTheme.userInterfaceStyle
		if overrideUserInterfaceStyle != style {
			overrideUserInterfaceStyle = style
		}
	}

	private var usesDarkAppearance: Bool {
		switch SharedSettings.appearanceTheme {
		case .light:
			false
		case .dark:
			true
		case .auto:
			traitCollection.userInterfaceStyle == .dark
		}
	}

	private func applyKeyboardTheme() {
		syncAppearanceOverride()
		let isDark = usesDarkAppearance
		view.backgroundColor = isDark ? UIColor(white: 0.08, alpha: 1) : UIColor.systemGray5
		let letterColor = isDark ? UIColor(white: 0.24, alpha: 1) : UIColor.white
		let systemColor = isDark ? UIColor(white: 0.22, alpha: 1) : UIColor.systemGray3
		let textColor = isDark ? UIColor.white : UIColor.label
		queryBox.backgroundColor = isDark ? UIColor(white: 0.16, alpha: 1) : UIColor.tertiarySystemBackground
		accessBox.backgroundColor = isDark ? UIColor(white: 0.16, alpha: 1) : UIColor.systemBackground
		requestErrorView.backgroundColor = isDark ? UIColor(white: 0.16, alpha: 1) : UIColor.systemBackground
		requestErrorDetailLabel.textColor = isDark ? UIColor(white: 0.72, alpha: 1) : UIColor.secondaryLabel

		for button in letterKeyButtons {
			styleKey(button, backgroundColor: letterColor, tintColor: textColor, shadow: !isDark)
		}
		for button in systemKeyButtons {
			styleKey(button, backgroundColor: systemColor, tintColor: textColor, shadow: !isDark)
		}
		if let returnKeyButton {
			styleKey(returnKeyButton, backgroundColor: .systemBlue, tintColor: .white, shadow: false)
		}
		assetToggleButton.backgroundColor = isDark ? systemColor : .tertiarySystemBackground
		assetToggleButton.tintColor = textColor
		keyboardRestoreButton.backgroundColor = isDark ? systemColor : .tertiarySystemBackground
		keyboardRestoreButton.tintColor = textColor
		closeButton.backgroundColor = isDark ? systemColor : .tertiarySystemBackground
		closeButton.tintColor = textColor
		styleAssetPickerButton(addAssetButton, filled: true, isDark: isDark)
		queryCaret.backgroundColor = .systemBlue
		queryClearButton.tintColor = isDark ? UIColor(white: 0.75, alpha: 1) : UIColor.secondaryLabel
		loadingIndicator.color = isDark ? .white : .secondaryLabel
		applyQueryInputFocus(animated: false)
		updateAssetMentionSuggestions()
		updateAlphabetKeyTitles()
	}

	private func styleKey(_ button: UIButton, backgroundColor: UIColor, tintColor: UIColor, shadow: Bool) {
		if let keyButton = button as? KeyboardKeyButton {
			keyButton.setKeyStyle(backgroundColor: backgroundColor, shadowOpacity: shadow ? 0.22 : 0)
		} else {
			button.backgroundColor = backgroundColor
			button.layer.shadowOpacity = shadow ? 0.22 : 0
		}
		button.tintColor = tintColor
		button.setTitleColor(tintColor, for: .normal)
		button.layer.shadowColor = UIColor.black.cgColor
		button.layer.shadowRadius = 0
		button.layer.shadowOffset = CGSize(width: 0, height: 1)
	}

	private func smallButton(_ systemName: String, action: Selector) -> UIButton {
		let button = UIButton(type: .system)
		button.setImage(UIImage(systemName: systemName), for: .normal)
		button.backgroundColor = .tertiarySystemBackground
		button.tintColor = .label
		button.layer.cornerRadius = 8
		button.widthAnchor.constraint(equalToConstant: 38).isActive = true
		button.heightAnchor.constraint(equalToConstant: 30).isActive = true
		button.addTarget(self, action: action, for: .touchUpInside)
		return button
	}

	private func assetPickerButton(title: String, systemName: String, action: Selector) -> UIButton {
		let button = UIButton(type: .system)
		var configuration = UIButton.Configuration.filled()
		configuration.title = title
		configuration.image = UIImage(systemName: systemName)
		configuration.imagePadding = 6
		configuration.cornerStyle = .medium
		button.configuration = configuration
		button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
		button.addTarget(self, action: action, for: .touchUpInside)
		return button
	}

	private func styleAssetPickerButton(_ button: UIButton, filled: Bool, isDark: Bool) {
		var configuration = button.configuration ?? .filled()
		if filled {
			configuration.baseBackgroundColor = .systemBlue
			configuration.baseForegroundColor = .white
		} else {
			configuration.baseBackgroundColor = isDark ? UIColor(white: 0.22, alpha: 1) : .tertiarySystemBackground
			configuration.baseForegroundColor = isDark ? .white : .label
		}
		button.configuration = configuration
	}

	private func append(_ text: String) {
		query.append(text)
		queryDidChange()
	}

	@objc private func keyTouchDown() {
		keyFeedback.impactOccurred(intensity: 0.35)
		keyFeedback.prepare()
	}

	private func appendLetter(_ letter: String) {
		let shouldUppercase = shiftState != .lowercase
		append(shouldUppercase ? letter.uppercased() : letter.lowercased())
		if shiftState == .uppercase {
			shiftState = .lowercase
			updateAlphabetKeyTitles()
		}
	}

	@objc private func spaceTapped() {
		guard !query.hasSuffix(" ") else { return }
		append(" ")
	}

	@objc private func shiftTapped() {
		let now = Date()
		if shiftState == .uppercase, now.timeIntervalSince(lastShiftTapDate) < 0.45 {
			shiftState = .capsLock
		} else {
			switch shiftState {
			case .lowercase:
				shiftState = .uppercase
			case .uppercase, .capsLock:
				shiftState = .lowercase
			}
		}
		lastShiftTapDate = now
		updateAlphabetKeyTitles()
	}

	@objc private func deleteTapped() {
		guard !query.isEmpty else { return }
		query.removeLast()
		queryDidChange()
	}

	@objc private func clearQuery() {
		query = ""
		queryDidChange()
		setTypingControlsVisible(true)
	}

	@objc private func modeChanged() {
		setMode(Mode(rawValue: modeControl.selectedSegmentIndex) ?? .search)
	}

	@objc private func screenSwiped(_ recognizer: UISwipeGestureRecognizer) {
		switch recognizer.direction {
		case .left:
			moveMode(by: 1, slideDirection: .left)
		case .right:
			moveMode(by: -1, slideDirection: .right)
		default:
			break
		}
	}

	private func installScreenSwipeGestures() {
		let leftSwipe = UISwipeGestureRecognizer(target: self, action: #selector(screenSwiped(_:)))
		leftSwipe.direction = .left
		let rightSwipe = UISwipeGestureRecognizer(target: self, action: #selector(screenSwiped(_:)))
		rightSwipe.direction = .right
		screenSwipeGestureRecognizers = [leftSwipe, rightSwipe]

		for recognizer in screenSwipeGestureRecognizers {
			recognizer.cancelsTouchesInView = false
			recognizer.delegate = self
			view.addGestureRecognizer(recognizer)
		}
	}

	private func moveMode(by offset: Int, slideDirection: ScreenSlideDirection? = nil) {
		let modes = Mode.allCases
		guard let index = modes.firstIndex(of: mode) else { return }
		let nextIndex = (index + offset + modes.count) % modes.count
		setMode(modes[nextIndex], slideDirection: slideDirection)
	}

	private func setMode(_ newMode: Mode, slideDirection: ScreenSlideDirection? = nil) {
		guard mode != newMode else { return }
		if let slideDirection {
			let transition = CATransition()
			transition.type = .push
			transition.subtype = slideDirection == .left ? .fromRight : .fromLeft
			transition.duration = 0.28
			transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
			rootStack.layer.add(transition, forKey: "screenModePush")
		}

		mode = newMode
		modeControl.selectedSegmentIndex = newMode.rawValue
		assetPickerVisible = false
		resetResults()
		setTypingControlsVisible(true)
		updatePrompt()
		showHistoryIfNeeded()
		view.layoutIfNeeded()
	}

	@objc private func showAlphabetKeyboard() {
		keyboardLayoutMode = .alphabet
		shiftState = .lowercase
		rebuildKeyboardRows()
	}

	@objc private func showNumericKeyboard() {
		keyboardLayoutMode = .numeric
		rebuildKeyboardRows()
	}

	@objc private func showSymbolKeyboard() {
		keyboardLayoutMode = .symbols
		rebuildKeyboardRows()
	}

	@objc private func closeKeyboard() {
		advanceToNextInputMode()
	}

	@objc private func openSetupApp() {
		guard let url = URL(string: "memeforge://setup") else { return }
		extensionContext?.open(url)
	}

	@objc private func goTapped() {
		switch mode {
		case .search:
			search()
		case .generate:
			generate()
		}
	}

	@objc private func focusQuery() {
		assetPickerVisible = false
		setTypingControlsVisible(true)
	}

	@objc private func showAssetPicker() {
		guard mode == .generate else { return }
		guard hasFullAccess else {
			updatePrompt()
			return
		}
		clearRequestError()
		assetPickerVisible = true
		refreshGenerationAssetCollection()
		setTypingControlsVisible(false)
	}

	@objc private func addAssetsTapped() {
		presentMediaPicker()
	}

	private func updatePrompt() {
		let placeholder = mode == .search ? "type a meme search" : "describe a static meme"
		queryLabel.text = query.isEmpty ? placeholder : query
		queryLabel.textColor = query.isEmpty ? .secondaryLabel : .label
		queryClearButton.isHidden = query.isEmpty
		SharedSettings.keyboardHasFullAccess = hasFullAccess
		if !hasFullAccess {
			assetPickerVisible = false
		}
		assetToggleButton.isHidden = mode != .generate
		accessBox.isHidden = hasFullAccess
		updateAssetMentionSuggestions()
		updateQueryBoxHeight()
		updateCaretPosition()
		updateContainerSizing()
	}

	private func updateAssetMentionSuggestions() {
		guard mode == .generate,
			typingControlsVisible,
			hasFullAccess,
			!assetPickerVisible,
			let mentionQuery = query.trailingGenerationAssetMentionQuery
		else {
			assetMentionVisible = false
			assetMentionItems = []
			rebuildAssetMentionButtons()
			return
		}

		assetMentionItems = assetMentionOptions(matching: mentionQuery)
		assetMentionVisible = !assetMentionItems.isEmpty
		rebuildAssetMentionButtons()
	}

	private func assetMentionOptions(matching query: String) -> [SelectedGenerationAsset] {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		let items = selectedGenerationAssets.sorted {
			$0.name.localizedStandardCompare($1.name) == .orderedAscending
		}
		guard !trimmed.isEmpty else { return items }
		return items.filter { asset in
			asset.name.lowercased().contains(trimmed)
		}
	}

	private func rebuildAssetMentionButtons() {
		for view in assetMentionStack.arrangedSubviews {
			assetMentionStack.removeArrangedSubview(view)
			view.removeFromSuperview()
		}

		guard assetMentionVisible else {
			assetMentionScrollView.isHidden = true
			return
		}

		for asset in assetMentionItems {
			let button = UIButton(type: .system)
			var configuration = UIButton.Configuration.filled()
			configuration.title = asset.name
			configuration.image = UIImage(systemName: "checkmark.circle.fill")
			configuration.imagePadding = 6
			configuration.cornerStyle = .capsule
			configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 12)
			configuration.baseBackgroundColor = .systemBlue
			configuration.baseForegroundColor = .white
			button.configuration = configuration
			button.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
			button.heightAnchor.constraint(equalToConstant: 36).isActive = true
			button.addAction(UIAction { [weak self] _ in
				self?.selectAssetMention(asset)
			}, for: .touchUpInside)
			assetMentionStack.addArrangedSubview(button)
		}
		assetMentionScrollView.isHidden = false
	}

	private func selectAssetMention(_ asset: SelectedGenerationAsset) {
		query = query.replacingTrailingGenerationAssetMention(with: asset.name)
		queryDidChange()
	}

	private func clearRequestError() {
		guard requestError != nil else { return }
		requestError = nil
		updateRequestErrorView()
		updateContainerSizing()
	}

	private func showRequestError(title: String, detail: String) {
		requestError = RequestError(title: title, detail: detail)
		results = []
		showingHistory = false
		isLoadingSearchResults = false
		canLoadMoreSearchResults = false
		collectionView.reloadData()
		updateRequestErrorView()
		updateContainerSizing()
	}

	private func updateRequestErrorView() {
		guard let requestError, results.isEmpty else {
			collectionView.backgroundView = nil
			return
		}

		requestErrorTitleLabel.text = requestError.title
		requestErrorDetailLabel.text = requestError.detail
		collectionView.backgroundView = requestErrorView
	}

	private func setTypingControlsVisible(_ visible: Bool) {
		if visible {
			assetPickerVisible = false
		}
		typingControlsVisible = visible
		setQueryInputFocused(visible, animated: true)
		queryRow.isHidden = !visible
		assetPickerControls.isHidden = !assetPickerVisible
		selectedAssetsCollectionView.isHidden = !assetPickerVisible || selectedGenerationAssets.isEmpty
		keyboardRestoreButton.isHidden = visible
		keyRowStacks.forEach { $0.isHidden = !visible }
		updateAssetMentionSuggestions()
		selectedAssetsCollectionView.reloadData()
		collectionView.collectionViewLayout.invalidateLayout()
		collectionView.reloadData()
		updateCaretVisibility()
		updateContainerSizing()
		view.setNeedsLayout()
	}

	private func setQueryInputFocused(_ focused: Bool, animated: Bool) {
		guard queryInputFocused != focused else { return }
		queryInputFocused = focused
		applyQueryInputFocus(animated: animated)
	}

	private func applyQueryInputFocus(animated: Bool) {
		let borderColor = queryInputFocused ? UIColor.systemBlue.cgColor : UIColor.clear.cgColor
		let borderWidth: CGFloat = queryInputFocused ? 2 : 0

		if animated {
			let colorAnimation = CABasicAnimation(keyPath: "borderColor")
			colorAnimation.fromValue = queryBox.layer.presentation()?.borderColor ?? queryBox.layer.borderColor
			colorAnimation.toValue = borderColor
			colorAnimation.duration = 0.22
			colorAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

			let widthAnimation = CABasicAnimation(keyPath: "borderWidth")
			widthAnimation.fromValue = queryBox.layer.presentation()?.borderWidth ?? queryBox.layer.borderWidth
			widthAnimation.toValue = borderWidth
			widthAnimation.duration = 0.22
			widthAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

			queryBox.layer.add(colorAnimation, forKey: "queryFocusBorderColor")
			queryBox.layer.add(widthAnimation, forKey: "queryFocusBorderWidth")
		}

		queryBox.layer.borderColor = borderColor
		queryBox.layer.borderWidth = borderWidth
		updateCaretVisibility()
	}

	private func updateQueryBoxHeight() {
		let fallbackWidth = view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right - 16
		let boxWidth = queryBox.bounds.width > 0 ? queryBox.bounds.width : fallbackWidth
		let textWidth = max(0, boxWidth - queryBoxHorizontalPadding - queryClearButtonSize - queryClearButtonSpacing * 2)
		let measuredHeight = queryLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
		let maxHeight = queryLabel.font.lineHeight * maxQueryBoxLines + queryBoxVerticalPadding * 2
		let height = ceil(min(max(measuredHeight + queryBoxVerticalPadding * 2, minQueryBoxHeight), maxHeight))

		if abs((queryBoxHeightConstraint?.constant ?? 0) - height) > 0.5 {
			queryBoxHeightConstraint?.constant = height
		}
	}

	private func updateCaretPosition() {
		queryBox.layoutIfNeeded()
		queryCaretHeightConstraint?.constant = queryLabel.font.lineHeight
		let labelFrame = queryLabel.frame

		guard !query.isEmpty else {
			queryCaretLeadingConstraint?.constant = labelFrame.minX
			queryCaretTopConstraint?.constant = labelFrame.minY
			updateCaretVisibility()
			return
		}

		let textWidth = max(0, labelFrame.width)
		let font = queryLabel.font ?? .systemFont(ofSize: 17, weight: .semibold)
		let textStorage = NSTextStorage(string: query, attributes: [.font: font])
		let layoutManager = NSLayoutManager()
		let textContainer = NSTextContainer(size: CGSize(width: textWidth, height: .greatestFiniteMagnitude))
		textContainer.lineBreakMode = .byWordWrapping
		textContainer.lineFragmentPadding = 0
		textContainer.maximumNumberOfLines = Int(maxQueryBoxLines)
		layoutManager.addTextContainer(textContainer)
		textStorage.addLayoutManager(layoutManager)
		layoutManager.ensureLayout(for: textContainer)

		let glyphRange = layoutManager.glyphRange(for: textContainer)
		guard glyphRange.length > 0 else {
			updateCaretVisibility()
			return
		}

		let glyphIndex = NSMaxRange(glyphRange) - 1
		let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
		let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
		let caretX = min(textWidth, max(0, glyphRect.maxX))
		let caretY = lineRect.minY + max(0, (lineRect.height - font.lineHeight) / 2)
		queryCaretLeadingConstraint?.constant = labelFrame.minX + caretX
		queryCaretTopConstraint?.constant = labelFrame.minY + caretY
		updateCaretVisibility()
	}

	private func updateCaretVisibility() {
		let shouldShowCaret = typingControlsVisible && queryInputFocused
		queryCaret.isHidden = !shouldShowCaret
		if shouldShowCaret {
			queryCaret.alpha = 1
			if queryCaret.layer.animation(forKey: "queryCaretBlink") == nil {
				let animation = CABasicAnimation(keyPath: "opacity")
				animation.fromValue = 1
				animation.toValue = 0
				animation.duration = 0.55
				animation.autoreverses = true
				animation.repeatCount = .infinity
				queryCaret.layer.add(animation, forKey: "queryCaretBlink")
			}
		} else {
			queryCaret.layer.removeAnimation(forKey: "queryCaretBlink")
			queryCaret.alpha = 0
		}
	}

	private func updateContainerSizing() {
		let selectedHeight = assetPickerVisible && !selectedGenerationAssets.isEmpty ? selectedAssetsHeight : 0
		let collectionHeight = assetPickerVisible
			? desiredAssetPickerCollectionHeight(selectedHeight: selectedHeight)
			: desiredCollectionHeight()
		if abs((collectionHeightConstraint?.constant ?? 0) - collectionHeight) > 0.5 {
			collectionHeightConstraint?.constant = collectionHeight
		}
		if abs((selectedAssetsHeightConstraint?.constant ?? 0) - selectedHeight) > 0.5 {
			selectedAssetsHeightConstraint?.constant = selectedHeight
		}

		updateRequestErrorView()
		let shouldShowCollection = hasFullAccess && collectionHeight > 0
		collectionView.isHidden = !shouldShowCollection
		selectedAssetsCollectionView.isHidden = selectedHeight <= 0
		assetPickerControls.isHidden = !assetPickerVisible
		queryRow.isHidden = !typingControlsVisible
		collectionView.isScrollEnabled = (assetPickerVisible || mode == .search) && shouldShowCollection
		collectionView.alwaysBounceVertical = collectionView.isScrollEnabled
		assetMentionScrollView.isHidden = !assetMentionVisible

		var visibleHeights = [topRowHeight]
		if typingControlsVisible {
			visibleHeights.append(queryBoxHeightConstraint?.constant ?? minQueryBoxHeight)
		}
		if assetMentionVisible {
			visibleHeights.append(assetMentionHeight)
		}
		if assetPickerVisible {
			visibleHeights.append(assetPickerControlsHeight)
			if selectedHeight > 0 {
				visibleHeights.append(selectedHeight)
			}
		}
		if !hasFullAccess {
			visibleHeights.append(accessBoxHeight)
		} else if shouldShowCollection {
			visibleHeights.append(collectionHeight)
		}
		if typingControlsVisible {
			visibleHeights.append(contentsOf: Array(repeating: keyHeight, count: keyRowStacks.count))
		}

		let spacing = CGFloat(max(0, visibleHeights.count - 1)) * rootSpacing
		let desiredHeight = ceil(containerVerticalPadding + visibleHeights.reduce(0, +) + spacing)
		let maxHeight: CGFloat
		if assetPickerVisible {
			maxHeight = maxAssetPickerKeyboardHeight
		} else if mode == .search && !typingControlsVisible {
			maxHeight = 390
		} else {
			maxHeight = 720
		}
		let height = min(max(desiredHeight, topRowHeight + containerVerticalPadding), maxHeight)

		if abs((heightConstraint?.constant ?? 0) - height) > 0.5 {
			heightConstraint?.constant = height
		}
	}

	private func desiredCollectionHeight() -> CGFloat {
		guard hasFullAccess else { return 0 }
		if requestError != nil, results.isEmpty {
			return requestErrorHeight
		}

		let columns = mode == .generate ? 2 : 3
		let side = collectionItemSide(columns: CGFloat(columns))
		guard side > 0 else { return 0 }

		switch mode {
		case .generate:
			if results.isEmpty {
				return pendingGenerationCount > 0 ? collectionContentHeight(rows: 1, side: side) : 0
			}
			let rows = ceil(CGFloat(results.count) / 2)
			return collectionContentHeight(rows: rows, side: side)
		case .search:
			if isLoadingSearchResults, results.isEmpty, !typingControlsVisible {
				return maxSearchCollectionHeight
			}
			guard !results.isEmpty else { return 0 }
			let rows = ceil(CGFloat(results.count) / 3)
			let contentHeight = collectionContentHeight(rows: rows, side: side)
			let visibleRows = typingControlsVisible && !showingHistory ? CGFloat(1) : min(rows, CGFloat(3))
			let fittedHeight = collectionContentHeight(rows: visibleRows, side: side)
			return min(contentHeight, min(fittedHeight, maxSearchCollectionHeight))
		}
	}

	private func desiredAssetPickerCollectionHeight(selectedHeight: CGFloat) -> CGFloat {
		guard hasFullAccess else { return 0 }
		let visibleChromeHeights = [topRowHeight, assetPickerControlsHeight] + (selectedHeight > 0 ? [selectedHeight] : [])
		let visibleItemCount = visibleChromeHeights.count + 1
		let spacing = CGFloat(max(0, visibleItemCount - 1)) * rootSpacing
		let availableHeight = maxAssetPickerKeyboardHeight - containerVerticalPadding - visibleChromeHeights.reduce(0, +) - spacing
		return max(0, floor(availableHeight))
	}

	private func collectionItemSide(columns: CGFloat) -> CGFloat {
		let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
		let inset = layout?.sectionInset ?? .zero
		let spacing = layout?.minimumInteritemSpacing ?? 0
		let viewWidth = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
		let contentWidth = viewWidth - view.safeAreaInsets.left - view.safeAreaInsets.right - 16
		let availableWidth = contentWidth - inset.left - inset.right - spacing * (columns - 1)
		return floor(max(0, availableWidth / columns))
	}

	private func collectionContentHeight(rows: CGFloat, side: CGFloat) -> CGFloat {
		guard rows > 0 else { return 0 }
		let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
		let inset = layout?.sectionInset ?? .zero
		let spacing = layout?.minimumLineSpacing ?? 0
		return inset.top + inset.bottom + rows * side + max(0, rows - 1) * spacing
	}

	private func queryDidChange() {
		resetResults()
		updatePrompt()
		showHistoryIfNeeded()
	}

	private func resetResults() {
		cancelCurrentTasks()
		searchQuery = ""
		searchOffset = 0
		canLoadMoreSearchResults = false
		isLoadingSearchResults = false
		requestError = nil
		generationID = UUID()
		pendingGenerationCount = 0
		setGenerating(false)
		showingHistory = false
		results = []
		collectionView.reloadData()
		updateContainerSizing()
	}

	private func showHistoryIfNeeded() {
		guard mode == .search, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
		cancelCurrentTasks()
		searchQuery = ""
		searchOffset = 0
		canLoadMoreSearchResults = false
		isLoadingSearchResults = false
		requestError = nil
		setGenerating(false)

		let history = SharedSettings.giphyMemeHistory
		historyUseCounts = history.reduce(into: [:]) { counts, item in
			counts[item.copyURL.absoluteString] = item.useCount
		}
		results = history.map { historyResult(from: $0) }
		showingHistory = !results.isEmpty
		collectionView.reloadData()
		updateContainerSizing()
	}

	private func historyResult(from item: SharedSettings.GiphyMemeHistoryItem) -> MemeResult {
		MemeResult(
			title: item.title,
			previewURL: item.previewURL,
			previewVideoURL: item.previewVideoURL,
			copyURL: item.copyURL,
			imageData: nil,
			pasteboardType: item.pasteboardType,
			useCount: item.useCount
		)
	}

	private func refreshGenerationAssetCollection() {
		generationAssetCollection = SharedSettings.generationAssetCollection
		for index in selectedGenerationAssets.indices {
			guard let collectionID = selectedGenerationAssets[index].collectionID,
				let item = generationAssetCollection.first(where: { $0.id == collectionID })
			else {
				continue
			}
			selectedGenerationAssets[index].name = item.displayName
		}
		if assetPickerVisible {
			collectionView.reloadData()
			updateContainerSizing()
		}
		updateAssetMentionSuggestions()
	}

	private func insertPickedGenerationAssets(_ payloads: [SharedSettings.GenerationAssetPayload]) {
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
		selectedAssetsCollectionView.reloadData()
		updateContainerSizing()
	}

	private func insertGenerationAsset(_ item: SharedSettings.GenerationAssetItem) {
		guard !selectedGenerationAssets.contains(where: { $0.collectionID == item.id }),
			let data = SharedSettings.generationAssetData(for: item)
		else {
			return
		}
		selectedGenerationAssets.append(SelectedGenerationAsset(collectionItem: item, imageData: data))
		resetResults()
		selectedAssetsCollectionView.reloadData()
		updateContainerSizing()
	}

	private func removeGenerationAsset(_ asset: SelectedGenerationAsset) {
		selectedGenerationAssets.removeAll { $0.id == asset.id }
		resetResults()
		selectedAssetsCollectionView.reloadData()
		updateContainerSizing()
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
		selectedAssetsCollectionView.reloadData()
		collectionView.reloadData()
	}

	private func resultWithHistoryCount(_ result: MemeResult) -> MemeResult {
		guard let key = result.historyKey, let useCount = historyUseCounts[key] else { return result }
		return result.withUseCount(useCount)
	}

	private func cancelCurrentTasks() {
		currentTasks.forEach { $0.cancel() }
		currentTasks.removeAll()
	}

	private func search() {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		clearRequestError()
		guard hasFullAccess else {
			updatePrompt()
			return
		}
		guard !SharedSettings.giphyAPIKey.isEmpty else {
			setTypingControlsVisible(false)
			showRequestError(
				title: "GIPHY API key missing",
				detail: "MemeforgeGIPHYAPIKey is empty in this build."
			)
			return
		}
		guard !trimmed.isEmpty else {
			return
		}

		cancelCurrentTasks()
		searchQuery = trimmed
		searchOffset = 0
		canLoadMoreSearchResults = true
		isLoadingSearchResults = true
		setGenerating(false)
		showingHistory = false
		results = []
		collectionView.reloadData()
		setTypingControlsVisible(false)

		fetchSearchResults(for: trimmed, offset: 0, replacingResults: true)
	}

	private func loadMoreSearchResultsIfNeeded() {
		guard mode == .search, hasFullAccess, canLoadMoreSearchResults, !isLoadingSearchResults, !searchQuery.isEmpty else { return }
		fetchSearchResults(for: searchQuery, offset: searchOffset, replacingResults: false)
	}

	private func fetchSearchResults(for searchQuery: String, offset: Int, replacingResults: Bool) {
		isLoadingSearchResults = true
		updateContainerSizing()

		var components = URLComponents(string: "https://api.giphy.com/v1/gifs/search")
		components?.queryItems = [
			URLQueryItem(name: "api_key", value: SharedSettings.giphyAPIKey),
			URLQueryItem(name: "q", value: searchQuery),
			URLQueryItem(name: "limit", value: "\(searchPageSize)"),
			URLQueryItem(name: "offset", value: "\(offset)"),
			URLQueryItem(name: "rating", value: "pg-13"),
			URLQueryItem(name: "lang", value: "en"),
		]

		guard let url = components?.url else {
			finishSearch(
				for: searchQuery,
				requestError: RequestError(title: "GIPHY request failed", detail: "Could not build the search URL.")
			)
			return
		}

		let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
			guard let self else { return }
			if let error {
				if (error as? URLError)?.code == .cancelled {
					self.finishSearch(for: searchQuery)
					return
				}
				self.finishSearch(
					for: searchQuery,
					requestError: RequestError(title: "GIPHY request failed", detail: error.localizedDescription)
				)
				return
			}
			if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
				self.finishSearch(
					for: searchQuery,
					requestError: Self.giphyHTTPError(statusCode: httpResponse.statusCode, data: data)
				)
				return
			}
			guard let data else {
				self.finishSearch(
					for: searchQuery,
					requestError: RequestError(title: "GIPHY request failed", detail: "The response did not include data.")
				)
				return
			}

			do {
				let response = try JSONDecoder().decode(GiphyResponse.self, from: data)
				let items = response.data.compactMap { item -> MemeResult? in
					let preview = item.images.fixedWidthStill?.url ?? item.images.downsizedStill?.url ?? item.images.originalStill?.url
					let previewVideo = item.images.fixedWidthSmall?.mp4 ?? item.images.fixedWidth?.mp4 ?? item.images.downsizedSmall?.mp4
					let previewImage = item.images.fixedWidth?.url ?? item.images.downsized?.url ?? preview
					guard previewVideo != nil || previewImage != nil else {
						return nil
					}
					let copy = item.images.downsized?.url ?? item.images.original?.url ?? previewImage ?? preview
					return MemeResult(
						title: item.title,
						previewURL: previewImage ?? preview,
						previewVideoURL: previewVideo,
						copyURL: copy,
						imageData: nil,
						pasteboardType: Self.pasteboardType(for: copy)
					)
				}
				let loadedCount = response.pagination?.count ?? items.count
				let nextOffset = offset + loadedCount
				let totalCount = response.pagination?.totalCount
				let hasMore = totalCount.map { nextOffset < $0 } ?? (items.count == self.searchPageSize)
				DispatchQueue.main.async {
					guard self.searchQuery == searchQuery else { return }
					let countedItems = items.map(self.resultWithHistoryCount)
					self.results = replacingResults ? countedItems : self.results + countedItems
					self.requestError = nil
					self.searchOffset = nextOffset
					self.canLoadMoreSearchResults = hasMore && !items.isEmpty
					self.isLoadingSearchResults = false
					self.showingHistory = false
					self.collectionView.reloadData()
					self.updateContainerSizing()
			}
			} catch {
				self.finishSearch(
					for: searchQuery,
					requestError: RequestError(title: "Could not read GIPHY response", detail: Self.responseDetail(error: error, data: data))
				)
			}
		}
		currentTasks.append(task)
		task.resume()
	}

	private func generate() {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		clearRequestError()
		guard hasFullAccess else {
			updatePrompt()
			return
		}
		guard !SharedSettings.geminiAPIKey.isEmpty else {
			setTypingControlsVisible(false)
			showRequestError(
				title: "Gemini API key missing",
				detail: "MemeforgeGeminiAPIKey is empty in this build."
			)
			return
		}
		guard !trimmed.isEmpty else {
			return
		}

		cancelCurrentTasks()
		searchQuery = ""
		searchOffset = 0
		canLoadMoreSearchResults = false
		isLoadingSearchResults = false
		let generationID = UUID()
		self.generationID = generationID
		pendingGenerationCount = generatedStyles.count
		results = []
		collectionView.reloadData()
		setTypingControlsVisible(false)
		setGenerating(true)
		let assets = selectedGenerationAssets
		recordSelectedGenerationAssetUses(assets)

		let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(SharedSettings.geminiModel):generateContent")!
		for style in generatedStyles {
			var request = URLRequest(url: url)
			request.httpMethod = "POST"
			request.setValue(SharedSettings.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.httpBody = geminiRequestBody(for: trimmed, style: style, assets: assets)

			let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
				let result = (error == nil && data != nil) ? Self.geminiResult(from: data!, title: trimmed) : nil
				DispatchQueue.main.async {
					guard let self, self.generationID == generationID else { return }
					if let result {
						self.results.append(result)
						self.collectionView.reloadData()
						self.updateContainerSizing()
					}
					self.pendingGenerationCount -= 1
					if self.pendingGenerationCount <= 0 {
						self.setGenerating(false)
					}
				}
			}
			currentTasks.append(task)
		}
		currentTasks.forEach { $0.resume() }
	}

	private func geminiRequestBody(for idea: String, style: String, assets: [SelectedGenerationAsset]) -> Data? {
		var parts: [[String: Any]] = [
			["text": idea],
		]
		for asset in assets {
			parts.append(["text": "Attachment @\(asset.name):"])
			parts.append(
				[
					"inlineData": [
						"mimeType": asset.mimeType,
						"data": asset.imageData.base64EncodedString(),
					],
				]
			)
		}

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

	private nonisolated static func geminiResult(from data: Data, title: String) -> MemeResult? {
		guard let response = try? JSONDecoder().decode(GeminiResponse.self, from: data),
			response.error?.message == nil,
			let part = response.candidates?.flatMap(\.content.parts).first(where: { $0.inlineData != nil }),
			let inlineData = part.inlineData,
			let imageData = Data(base64Encoded: inlineData.data)
		else {
			return nil
		}

		let pasteboardType = UTType(mimeType: inlineData.mimeType)?.identifier ?? UTType.png.identifier
		return MemeResult(title: title, previewURL: nil, previewVideoURL: nil, copyURL: nil, imageData: imageData, pasteboardType: pasteboardType)
	}

	private nonisolated static func pasteboardType(for url: URL?) -> String {
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

	private func setGenerating(_ generating: Bool) {
		if generating {
			loadingIndicator.startAnimating()
		} else {
			loadingIndicator.stopAnimating()
		}
		updateContainerSizing()
	}

	private func copy(_ result: MemeResult) {
		guard hasFullAccess else {
			updatePrompt()
			return
		}

		if let imageData = result.imageData {
			copyImageData(imageData, pasteboardType: result.pasteboardType)
			return
		}

		guard let url = result.copyURL else { return }
		URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
			guard let self else { return }
			if error != nil {
				self.finish()
				return
			}
			guard let data else {
				self.finish()
				return
			}
			let mimeType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
			let pasteboardType = mimeType.flatMap { UTType(mimeType: $0)?.identifier } ?? result.pasteboardType
			DispatchQueue.main.async {
				self.copyImageData(data, pasteboardType: pasteboardType, historyResult: result)
			}
		}.resume()
	}

	private func copyImageData(_ data: Data, pasteboardType: String, historyResult: MemeResult? = nil) {
		if pasteboardType == UTType.gif.identifier || UIImage.isAnimatedGIF(data: data) {
			UIPasteboard.general.setData(data, forPasteboardType: UTType.gif.identifier)
			SharedSettings.updateCopiedMemePreview(data)
			recordHistoryUse(for: historyResult, pasteboardType: UTType.gif.identifier)
			closeKeyboard()
			return
		}

		if let image = UIImage(data: data), let pngData = image.pngData() {
			UIPasteboard.general.setData(pngData, forPasteboardType: UTType.png.identifier)
			SharedSettings.updateCopiedMemePreview(pngData)
			recordHistoryUse(for: historyResult, pasteboardType: UTType.png.identifier)
		} else {
			UIPasteboard.general.setData(data, forPasteboardType: pasteboardType)
			SharedSettings.updateCopiedMemePreview(data)
			recordHistoryUse(for: historyResult, pasteboardType: pasteboardType)
		}
		closeKeyboard()
	}

	private func recordHistoryUse(for result: MemeResult?, pasteboardType: String) {
		guard let result, let copyURL = result.copyURL else { return }
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
		collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
	}

	private nonisolated func finish() {
		Task { @MainActor [weak self] in
			self?.isLoadingSearchResults = false
			self?.pendingGenerationCount = 0
			self?.setGenerating(false)
			self?.updateContainerSizing()
		}
	}

	private nonisolated func finishSearch(for searchQuery: String, requestError: RequestError? = nil) {
		Task { @MainActor [weak self] in
			guard let self, self.searchQuery == searchQuery else { return }
			self.isLoadingSearchResults = false
			self.canLoadMoreSearchResults = false
			if let requestError, self.results.isEmpty {
				self.requestError = requestError
				self.collectionView.reloadData()
			}
			self.updateContainerSizing()
		}
	}
}

private final class KeyboardKeyButton: UIButton {
	private var normalBackgroundColor: UIColor?
	private var normalShadowOpacity: Float = 0

	override var isHighlighted: Bool {
		didSet {
			applyPressedState(animated: true)
		}
	}

	func setKeyStyle(backgroundColor: UIColor, shadowOpacity: Float) {
		normalBackgroundColor = backgroundColor
		normalShadowOpacity = shadowOpacity
		applyPressedState(animated: false)
	}

	private func applyPressedState(animated: Bool) {
		let changes = {
			self.backgroundColor = self.normalBackgroundColor
			self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
			self.layer.shadowOpacity = self.isHighlighted ? 0 : self.normalShadowOpacity
		}

		if animated {
			UIView.animate(
				withDuration: isHighlighted ? 0.045 : 0.12,
				delay: 0,
				options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
				animations: changes
			)
		} else {
			changes()
		}
	}
}

private final class SelectedAssetCell: UICollectionViewCell {
	static let reuseIdentifier = "SelectedAssetCell"

	private let imageView = UIImageView()
	private let removeButton = UIButton(type: .system)
	private var removeAction: (() -> Void)?

	override init(frame: CGRect) {
		super.init(frame: frame)
		contentView.backgroundColor = .systemBackground
		contentView.layer.cornerRadius = 8
		contentView.clipsToBounds = true

		imageView.contentMode = .scaleAspectFill
		imageView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(imageView)

		removeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
		removeButton.tintColor = .white
		removeButton.backgroundColor = UIColor.black.withAlphaComponent(0.72)
		removeButton.layer.cornerRadius = 10
		removeButton.translatesAutoresizingMaskIntoConstraints = false
		removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
		contentView.addSubview(removeButton)

		NSLayoutConstraint.activate([
			imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
			imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			removeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
			removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
			removeButton.widthAnchor.constraint(equalToConstant: 20),
			removeButton.heightAnchor.constraint(equalToConstant: 20),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		imageView.image = UIImage(systemName: "photo")
		removeAction = nil
	}

	func configure(with asset: KeyboardViewController.SelectedGenerationAsset, remove: @escaping () -> Void) {
		imageView.image = UIImage(data: asset.imageData) ?? UIImage(systemName: "photo")
		removeAction = remove
	}

	@objc private func removeTapped() {
		removeAction?()
	}
}

private final class GenerationAssetPayloadCollector: @unchecked Sendable {
	private let lock = NSLock()
	private var payloads: [SharedSettings.GenerationAssetPayload] = []

	func append(_ payload: SharedSettings.GenerationAssetPayload) {
		lock.lock()
		payloads.append(payload)
		lock.unlock()
	}

	var values: [SharedSettings.GenerationAssetPayload] {
		lock.lock()
		defer { lock.unlock() }
		return payloads
	}
}

extension KeyboardViewController: PHPickerViewControllerDelegate {
	private func presentMediaPicker() {
		var configuration = PHPickerConfiguration()
		configuration.filter = .images
		configuration.selectionLimit = 0

		let picker = PHPickerViewController(configuration: configuration)
		picker.delegate = self
		present(picker, animated: true)
	}

	func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
		picker.dismiss(animated: true) { [weak self] in
			self?.importPickerResults(results)
		}
	}

	private func importPickerResults(_ results: [PHPickerResult]) {
		guard !results.isEmpty else { return }

		let group = DispatchGroup()
		let payloads = GenerationAssetPayloadCollector()

		for result in results {
			let provider = result.itemProvider
			guard let typeIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in
				UTType(identifier)?.conforms(to: .image) == true
			}) else {
				continue
			}

			group.enter()
			provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
				defer { group.leave() }
				guard let data,
					let payload = SharedSettings.normalizedGenerationAssetPayload(from: data)
				else {
					return
				}
				payloads.append(payload)
			}
		}

		group.notify(queue: .main) { [weak self] in
			self?.insertPickedGenerationAssets(payloads.values)
		}
	}
}

extension KeyboardViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		if collectionView == selectedAssetsCollectionView {
			return selectedGenerationAssets.count
		}
		if assetPickerVisible {
			return generationAssetCollection.count
		}
		return results.count
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		if collectionView == selectedAssetsCollectionView {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SelectedAssetCell.reuseIdentifier, for: indexPath)
			let asset = selectedGenerationAssets[indexPath.item]
			(cell as? SelectedAssetCell)?.configure(with: asset) { [weak self] in
				self?.removeGenerationAsset(asset)
			}
			return cell
		}

		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MemeCell.reuseIdentifier, for: indexPath)
		if assetPickerVisible {
			let item = generationAssetCollection[indexPath.item]
			let result = MemeResult(
				title: item.displayName,
				previewURL: nil,
				previewVideoURL: nil,
				copyURL: nil,
				imageData: SharedSettings.generationAssetData(for: item),
				pasteboardType: item.mimeType,
				useCount: item.useCount
			)
			(cell as? MemeCell)?.configure(with: result)
		} else {
			(cell as? MemeCell)?.configure(with: results[indexPath.item])
		}
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		if collectionView == selectedAssetsCollectionView {
			return
		}
		if assetPickerVisible {
			insertGenerationAsset(generationAssetCollection[indexPath.item])
			return
		}
		copy(results[indexPath.item])
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
		if collectionView == selectedAssetsCollectionView {
			return CGSize(width: selectedAssetSide, height: selectedAssetSide)
		}
		let layout = collectionViewLayout as? UICollectionViewFlowLayout
		let inset = layout?.sectionInset ?? .zero
		let spacing = layout?.minimumInteritemSpacing ?? 0
		let columns: CGFloat = assetPickerVisible ? 2 : (mode == .generate ? 2 : 3)
		let availableWidth = collectionView.bounds.width - inset.left - inset.right - spacing * (columns - 1)
		let side = floor(availableWidth / columns)
		return CGSize(width: side, height: side)
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		guard scrollView == collectionView, !assetPickerVisible else { return }
		guard !showingHistory else { return }
		let remaining = scrollView.contentSize.height - scrollView.bounds.height - scrollView.contentOffset.y
		if remaining < 240 {
			loadMoreSearchResultsIfNeeded()
		}
	}
}

extension KeyboardViewController: UIGestureRecognizerDelegate {
	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		guard screenSwipeGestureRecognizers.contains(where: { $0 === gestureRecognizer }) else { return true }
		return !assetPickerVisible
	}

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		screenSwipeGestureRecognizers.contains { $0 === gestureRecognizer }
	}
}

private final class MemeCell: UICollectionViewCell {
	static let reuseIdentifier = "MemeCell"

	private let imageView = UIImageView()
	private let countLabel = UILabel()
	private var representedID: UUID?
	private var player: AVPlayer?
	private var playerLayer: AVPlayerLayer?
	private var playbackObserver: NSObjectProtocol?

	override init(frame: CGRect) {
		super.init(frame: frame)
		contentView.backgroundColor = .systemBackground
		contentView.layer.cornerRadius = 8
		contentView.clipsToBounds = true

		imageView.contentMode = .scaleAspectFill
		imageView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(imageView)

		countLabel.backgroundColor = UIColor.black.withAlphaComponent(0.68)
		countLabel.textColor = .white
		countLabel.font = .systemFont(ofSize: 11, weight: .bold)
		countLabel.textAlignment = .center
		countLabel.layer.cornerRadius = 9
		countLabel.layer.zPosition = 2
		countLabel.clipsToBounds = true
		countLabel.isHidden = true
		countLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(countLabel)
		NSLayoutConstraint.activate([
			imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
			imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			countLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
			countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
			countLabel.heightAnchor.constraint(equalToConstant: 18),
			countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		playerLayer?.frame = contentView.bounds
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		stopVideo()
		representedID = nil
		imageView.isHidden = false
		imageView.image = UIImage(systemName: "photo")
		countLabel.isHidden = true
		countLabel.text = nil
	}

	deinit {
		MainActor.assumeIsolated {
			stopVideo()
		}
	}

	func configure(with result: KeyboardViewController.MemeResult) {
		stopVideo()
		representedID = result.id
		imageView.isHidden = false
		imageView.image = UIImage(systemName: "photo")
		updateUseCount(result.useCount)

		if let data = result.imageData {
			imageView.image = UIImage.animatedGIF(data: data) ?? UIImage(data: data)
			return
		}

		if let previewVideoURL = result.previewVideoURL {
			playVideo(previewVideoURL)
			if let url = result.previewURL {
				loadImage(url, id: result.id)
			}
			return
		}

		guard let url = result.previewURL else { return }
		loadImage(url, id: result.id)
	}

	private func loadImage(_ url: URL, id: UUID) {
		URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
			guard let self, let data else { return }
			let image = UIImage.animatedGIF(data: data) ?? UIImage(data: data)
			guard let image else { return }
			DispatchQueue.main.async {
				guard self.representedID == id else { return }
				self.imageView.image = image
			}
		}.resume()
	}

	private func playVideo(_ url: URL) {
		let player = AVPlayer(url: url)
		player.isMuted = true
		let layer = AVPlayerLayer(player: player)
		layer.videoGravity = .resizeAspectFill
		layer.frame = contentView.bounds
		layer.zPosition = 1
		contentView.layer.addSublayer(layer)
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

	private func updateUseCount(_ count: Int) {
		countLabel.isHidden = count <= 0
		countLabel.text = count > 999 ? "999+" : "\(count)"
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
		let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
		let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
		let unclampedDelay = gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
		let delay = unclampedDelay ?? gifProperties?[kCGImagePropertyGIFDelayTime] as? TimeInterval ?? 0.1
		return delay < 0.02 ? 0.1 : delay
	}
}
