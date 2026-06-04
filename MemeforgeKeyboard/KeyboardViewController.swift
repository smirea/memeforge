import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

final class KeyboardViewController: UIInputViewController {
	private enum Mode: Int {
		case search
		case generate
	}

	fileprivate struct MemeResult: Hashable {
		let id = UUID()
		let title: String
		let previewURL: URL?
		let previewVideoURL: URL?
		let copyURL: URL?
		let imageData: Data?
		let pasteboardType: String
	}

	private var mode = Mode.search
	private var query = ""
	private var results: [MemeResult] = []
	private var currentTasks: [URLSessionDataTask] = []
	private var keyRowStacks: [UIStackView] = []
	private var letterKeyButtons: [UIButton] = []
	private var systemKeyButtons: [UIButton] = []
	private var returnKeyButton: UIButton?
	private var typingControlsVisible = true
	private var searchQuery = ""
	private var searchOffset = 0
	private var canLoadMoreSearchResults = false
	private var isLoadingSearchResults = false
	private var generationID = UUID()
	private var pendingGenerationCount = 0

	private let searchPageSize = 30
	private let keyHeight: CGFloat = 46
	private let keySpacing: CGFloat = 6
	private let rootSpacing: CGFloat = 6
	private let topRowHeight: CGFloat = 30
	private let queryBoxHeight: CGFloat = 34
	private let accessBoxHeight: CGFloat = 80
	private let loadingCollectionHeight: CGFloat = 112
	private let maxSearchCollectionHeight: CGFloat = 320
	private let generatedStyles = [
		"Classic photographic meme style.",
		"Bold illustrated meme style.",
	]

	private let modeControl = UISegmentedControl(items: ["Search", "Generate"])
	private let queryLabel = UILabel()
	private let queryBox = UIControl()
	private let accessBox = UIView()
	private let accessTitleLabel = UILabel()
	private let accessDetailLabel = UILabel()
	private let collectionView: UICollectionView
	private let loadingIndicator = UIActivityIndicatorView(style: .large)
	private let rootStack = UIStackView()
	private lazy var keyboardRestoreButton = smallButton("keyboard", action: #selector(focusQuery))
	private lazy var closeButton = smallButton("xmark", action: #selector(clearQuery))
	private var heightConstraint: NSLayoutConstraint?
	private var collectionHeightConstraint: NSLayoutConstraint?

	init() {
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
		heightConstraint = view.heightAnchor.constraint(equalToConstant: 280)
		heightConstraint?.isActive = true
		buildInterface()
		applyKeyboardTheme()
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
			self.applyKeyboardTheme()
		}
		updatePrompt()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		updatePrompt()
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		updateContainerSizing()
	}

	private func buildInterface() {
		modeControl.selectedSegmentIndex = Mode.search.rawValue
		modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
		modeControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		queryLabel.font = .systemFont(ofSize: 17, weight: .semibold)
		queryLabel.textColor = .label
		queryLabel.numberOfLines = 1
		queryLabel.lineBreakMode = .byTruncatingHead

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

		keyboardRestoreButton.isHidden = true
		let topRow = UIStackView(arrangedSubviews: [smallButton("globe", action: #selector(nextKeyboard)), modeControl, keyboardRestoreButton, closeButton])
		topRow.axis = .horizontal
		topRow.spacing = 8
		topRow.alignment = .center
		topRow.heightAnchor.constraint(equalToConstant: topRowHeight).isActive = true
		rootStack.addArrangedSubview(topRow)

		queryBox.backgroundColor = .tertiarySystemBackground
		queryBox.layer.cornerRadius = 8
		queryBox.translatesAutoresizingMaskIntoConstraints = false
		queryBox.heightAnchor.constraint(equalToConstant: queryBoxHeight).isActive = true
		queryBox.addTarget(self, action: #selector(focusQuery), for: .touchUpInside)
		queryBox.addSubview(queryLabel)
		queryLabel.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			queryLabel.leadingAnchor.constraint(equalTo: queryBox.leadingAnchor, constant: 12),
			queryLabel.trailingAnchor.constraint(equalTo: queryBox.trailingAnchor, constant: -12),
			queryLabel.centerYAnchor.constraint(equalTo: queryBox.centerYAnchor),
		])
		rootStack.addArrangedSubview(queryBox)

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

		buildKeyboardRows(in: rootStack)
	}

	private func buildKeyboardRows(in root: UIStackView) {
		let rows = [
			letterRow(["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]),
			letterRow(["a", "s", "d", "f", "g", "h", "j", "k", "l"], sideSpacerMultiplier: 0.5),
			shiftRow(),
			bottomRow(),
		]
		for row in rows {
			keyRowStacks.append(row)
			root.addArrangedSubview(row)
		}
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
		let button = UIButton(type: .system)
		button.layer.cornerRadius = 8
		button.titleLabel?.font = .systemFont(ofSize: 25, weight: .regular)
		button.heightAnchor.constraint(equalToConstant: keyHeight).isActive = true
		button.accessibilityIdentifier = "key-\(key)"

		let role: KeyRole
		switch key {
		case "space":
			button.setTitle("", for: .normal)
			button.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
			role = .letter
		case "delete":
			button.setImage(UIImage(systemName: "delete.left"), for: .normal)
			button.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
			role = .system
		case "shift":
			button.setImage(UIImage(systemName: "shift.fill"), for: .normal)
			role = .system
		case "numbers":
			button.setTitle("123", for: .normal)
			button.titleLabel?.font = .systemFont(ofSize: 21, weight: .regular)
			role = .system
		case "submit":
			button.setImage(UIImage(systemName: "checkmark"), for: .normal)
			button.addTarget(self, action: #selector(goTapped), for: .touchUpInside)
			role = .submit
		default:
			button.setTitle(key.uppercased(), for: .normal)
			button.addAction(UIAction { [weak self] _ in self?.append(key) }, for: .touchUpInside)
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

	private func applyKeyboardTheme() {
		let isDark = traitCollection.userInterfaceStyle == .dark
		view.backgroundColor = isDark ? UIColor(white: 0.08, alpha: 1) : UIColor.systemGray5
		let letterColor = isDark ? UIColor(white: 0.24, alpha: 1) : UIColor.white
		let systemColor = isDark ? UIColor(white: 0.22, alpha: 1) : UIColor.systemGray3
		let textColor = isDark ? UIColor.white : UIColor.label
		queryBox.backgroundColor = isDark ? UIColor(white: 0.16, alpha: 1) : UIColor.tertiarySystemBackground
		accessBox.backgroundColor = isDark ? UIColor(white: 0.16, alpha: 1) : UIColor.systemBackground

		for button in letterKeyButtons {
			styleKey(button, backgroundColor: letterColor, tintColor: textColor, shadow: !isDark)
		}
		for button in systemKeyButtons {
			styleKey(button, backgroundColor: systemColor, tintColor: textColor, shadow: !isDark)
		}
		if let returnKeyButton {
			styleKey(returnKeyButton, backgroundColor: .systemBlue, tintColor: .white, shadow: false)
		}
		keyboardRestoreButton.backgroundColor = isDark ? systemColor : .tertiarySystemBackground
		keyboardRestoreButton.tintColor = textColor
		closeButton.backgroundColor = isDark ? systemColor : .tertiarySystemBackground
		closeButton.tintColor = textColor
		loadingIndicator.color = isDark ? .white : .secondaryLabel
	}

	private func styleKey(_ button: UIButton, backgroundColor: UIColor, tintColor: UIColor, shadow: Bool) {
		button.backgroundColor = backgroundColor
		button.tintColor = tintColor
		button.setTitleColor(tintColor, for: .normal)
		button.layer.shadowColor = UIColor.black.cgColor
		button.layer.shadowOpacity = shadow ? 0.22 : 0
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

	private func append(_ text: String) {
		query.append(text)
		queryDidChange()
	}

	@objc private func spaceTapped() {
		guard !query.hasSuffix(" ") else { return }
		append(" ")
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
		mode = Mode(rawValue: modeControl.selectedSegmentIndex) ?? .search
		resetResults()
		setTypingControlsVisible(true)
		updatePrompt()
	}

	@objc private func nextKeyboard() {
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
		setTypingControlsVisible(true)
	}

	private func updatePrompt() {
		let placeholder = mode == .search ? "type a meme search" : "describe a static meme"
		queryLabel.text = query.isEmpty ? placeholder : query
		queryLabel.textColor = query.isEmpty ? .secondaryLabel : .label
		SharedSettings.keyboardHasFullAccess = hasFullAccess
		accessBox.isHidden = hasFullAccess
		updateContainerSizing()
	}

	private func setTypingControlsVisible(_ visible: Bool) {
		typingControlsVisible = visible
		queryBox.isHidden = !visible
		keyboardRestoreButton.isHidden = visible
		keyRowStacks.forEach { $0.isHidden = !visible }
		collectionView.collectionViewLayout.invalidateLayout()
		updateContainerSizing()
		view.setNeedsLayout()
	}

	private func updateContainerSizing() {
		let collectionHeight = desiredCollectionHeight()
		if abs((collectionHeightConstraint?.constant ?? 0) - collectionHeight) > 0.5 {
			collectionHeightConstraint?.constant = collectionHeight
		}

		let shouldShowCollection = hasFullAccess && collectionHeight > 0
		collectionView.isHidden = !shouldShowCollection
		collectionView.isScrollEnabled = mode == .search && shouldShowCollection
		collectionView.alwaysBounceVertical = collectionView.isScrollEnabled

		var visibleHeights = [topRowHeight]
		if typingControlsVisible {
			visibleHeights.append(queryBoxHeight)
		}
		if !hasFullAccess {
			visibleHeights.append(accessBoxHeight)
		} else if shouldShowCollection {
			visibleHeights.append(collectionHeight)
		}
		if typingControlsVisible {
			visibleHeights.append(contentsOf: Array(repeating: keyHeight, count: keyRowStacks.count))
		}

		let verticalPadding: CGFloat = 10
		let spacing = CGFloat(max(0, visibleHeights.count - 1)) * rootSpacing
		let desiredHeight = ceil(verticalPadding + visibleHeights.reduce(0, +) + spacing)
		let maxHeight: CGFloat = mode == .search && !typingControlsVisible ? 390 : 720
		let height = min(max(desiredHeight, topRowHeight + verticalPadding), maxHeight)

		if abs((heightConstraint?.constant ?? 0) - height) > 0.5 {
			heightConstraint?.constant = height
		}
	}

	private func desiredCollectionHeight() -> CGFloat {
		guard hasFullAccess else { return 0 }
		let columns = mode == .generate ? 2 : 3
		let side = collectionItemSide(columns: CGFloat(columns))
		guard side > 0 else { return 0 }

		switch mode {
		case .generate:
			if results.isEmpty {
				return pendingGenerationCount > 0 ? loadingCollectionHeight : 0
			}
			let rows = ceil(CGFloat(results.count) / 2)
			return collectionContentHeight(rows: rows, side: side)
		case .search:
			guard !results.isEmpty else { return 0 }
			let rows = ceil(CGFloat(results.count) / 3)
			let contentHeight = collectionContentHeight(rows: rows, side: side)
			let visibleRows = typingControlsVisible ? CGFloat(1) : min(rows, CGFloat(3))
			let fittedHeight = collectionContentHeight(rows: visibleRows, side: side)
			return min(contentHeight, min(fittedHeight, maxSearchCollectionHeight))
		}
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
	}

	private func resetResults() {
		cancelCurrentTasks()
		searchQuery = ""
		searchOffset = 0
		canLoadMoreSearchResults = false
		isLoadingSearchResults = false
		generationID = UUID()
		pendingGenerationCount = 0
		setGenerating(false)
		results = []
		collectionView.reloadData()
		updateContainerSizing()
	}

	private func cancelCurrentTasks() {
		currentTasks.forEach { $0.cancel() }
		currentTasks.removeAll()
	}

	private func search() {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard hasFullAccess else {
			updatePrompt()
			return
		}
		guard !SharedSettings.giphyAPIKey.isEmpty else {
			return
		}
		guard !trimmed.isEmpty else {
			return
		}

		cancelCurrentTasks()
		searchQuery = trimmed
		searchOffset = 0
		canLoadMoreSearchResults = true
		isLoadingSearchResults = false
		setGenerating(false)
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
			isLoadingSearchResults = false
			return
		}

		let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
			guard let self else { return }
			if error != nil {
				self.finishSearch(for: searchQuery)
				return
			}
			guard let data else {
				self.finishSearch(for: searchQuery)
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
					self.results = replacingResults ? items : self.results + items
					self.searchOffset = nextOffset
					self.canLoadMoreSearchResults = hasMore && !items.isEmpty
					self.isLoadingSearchResults = false
					self.collectionView.reloadData()
					self.updateContainerSizing()
				}
			} catch {
				self.finishSearch(for: searchQuery)
			}
		}
		currentTasks.append(task)
		task.resume()
	}

	private func generate() {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard hasFullAccess else {
			updatePrompt()
			return
		}
		guard !SharedSettings.geminiAPIKey.isEmpty else {
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

		let url = URL(string: "https://generativelanguage.googleapis.com/v1/models/\(SharedSettings.geminiModel):generateContent")!
		for style in generatedStyles {
			var request = URLRequest(url: url)
			request.httpMethod = "POST"
			request.setValue(SharedSettings.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.httpBody = geminiRequestBody(for: trimmed, style: style)

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

	private func geminiRequestBody(for idea: String, style: String) -> Data? {
		let body: [String: Any] = [
			"systemInstruction": [
				"parts": [
					["text": style],
				],
			],
			"contents": [
				[
					"parts": [
						["text": idea],
					],
				],
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
				self.copyImageData(data, pasteboardType: pasteboardType)
			}
		}.resume()
	}

	private func copyImageData(_ data: Data, pasteboardType: String) {
		if pasteboardType == UTType.gif.identifier || UIImage.isAnimatedGIF(data: data) {
			UIPasteboard.general.setData(data, forPasteboardType: UTType.gif.identifier)
			SharedSettings.updateCopiedMemePreview(data)
			return
		}

		if let image = UIImage(data: data), let pngData = image.pngData() {
			UIPasteboard.general.setData(pngData, forPasteboardType: UTType.png.identifier)
			SharedSettings.updateCopiedMemePreview(pngData)
		} else {
			UIPasteboard.general.setData(data, forPasteboardType: pasteboardType)
			SharedSettings.updateCopiedMemePreview(data)
		}
	}

	private nonisolated func finish() {
		Task { @MainActor [weak self] in
			self?.isLoadingSearchResults = false
			self?.pendingGenerationCount = 0
			self?.setGenerating(false)
			self?.updateContainerSizing()
		}
	}

	private nonisolated func finishSearch(for searchQuery: String) {
		Task { @MainActor [weak self] in
			guard let self, self.searchQuery == searchQuery else { return }
			self.isLoadingSearchResults = false
			self.canLoadMoreSearchResults = false
			self.updateContainerSizing()
		}
	}
}

extension KeyboardViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		results.count
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MemeCell.reuseIdentifier, for: indexPath)
		(cell as? MemeCell)?.configure(with: results[indexPath.item])
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		copy(results[indexPath.item])
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
		let layout = collectionViewLayout as? UICollectionViewFlowLayout
		let inset = layout?.sectionInset ?? .zero
		let spacing = layout?.minimumInteritemSpacing ?? 0
		let columns: CGFloat = mode == .generate ? 2 : 3
		let availableWidth = collectionView.bounds.width - inset.left - inset.right - spacing * (columns - 1)
		let side = floor(availableWidth / columns)
		return CGSize(width: side, height: side)
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		let remaining = scrollView.contentSize.height - scrollView.bounds.height - scrollView.contentOffset.y
		if remaining < 240 {
			loadMoreSearchResultsIfNeeded()
		}
	}
}

private final class MemeCell: UICollectionViewCell {
	static let reuseIdentifier = "MemeCell"

	private let imageView = UIImageView()
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
		NSLayoutConstraint.activate([
			imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
			imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
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
