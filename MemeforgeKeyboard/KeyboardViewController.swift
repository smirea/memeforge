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
		let copyURL: URL?
		let imageData: Data?
		let pasteboardType: String
	}

	private var mode = Mode.search
	private var query = ""
	private var results: [MemeResult] = []
	private var currentTask: URLSessionDataTask?
	private var keyRowStacks: [UIStackView] = []
	private var searchQuery = ""
	private var searchOffset = 0
	private var canLoadMoreSearchResults = false
	private var isLoadingSearchResults = false

	private let searchPageSize = 30

	private let modeControl = UISegmentedControl(items: ["Search", "Generate"])
	private let queryLabel = UILabel()
	private let statusLabel = UILabel()
	private let accessBox = UIView()
	private let accessTitleLabel = UILabel()
	private let accessDetailLabel = UILabel()
	private let collectionView: UICollectionView

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
		view.backgroundColor = UIColor.secondarySystemBackground
		view.heightAnchor.constraint(equalToConstant: 390).isActive = true
		buildInterface()
		updatePrompt()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		updatePrompt()
	}

	private func buildInterface() {
		modeControl.selectedSegmentIndex = Mode.search.rawValue
		modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

		queryLabel.font = .systemFont(ofSize: 17, weight: .semibold)
		queryLabel.textColor = .label
		queryLabel.numberOfLines = 1
		queryLabel.lineBreakMode = .byTruncatingHead

		statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
		statusLabel.textColor = .secondaryLabel
		statusLabel.numberOfLines = 1
		statusLabel.isHidden = true

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
		accessBox.heightAnchor.constraint(equalToConstant: 80).isActive = true

		collectionView.backgroundColor = .clear
		collectionView.dataSource = self
		collectionView.delegate = self
		collectionView.register(MemeCell.self, forCellWithReuseIdentifier: MemeCell.reuseIdentifier)
		collectionView.showsHorizontalScrollIndicator = false
		collectionView.showsVerticalScrollIndicator = true
		collectionView.alwaysBounceVertical = true
		collectionView.heightAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
		collectionView.setContentHuggingPriority(.defaultLow, for: .vertical)
		collectionView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

		let root = UIStackView()
		root.axis = .vertical
		root.spacing = 5
		root.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(root)

		NSLayoutConstraint.activate([
			root.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
			root.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
			root.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
			root.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
		])

		let topRow = UIStackView(arrangedSubviews: [smallButton("globe", action: #selector(nextKeyboard)), modeControl, smallButton("xmark", action: #selector(clearQuery))])
		topRow.axis = .horizontal
		topRow.spacing = 8
		topRow.alignment = .center
		root.addArrangedSubview(topRow)

		let queryBox = UIControl()
		queryBox.backgroundColor = .tertiarySystemBackground
		queryBox.layer.cornerRadius = 8
		queryBox.translatesAutoresizingMaskIntoConstraints = false
		queryBox.heightAnchor.constraint(equalToConstant: 34).isActive = true
		queryBox.addTarget(self, action: #selector(focusQuery), for: .touchUpInside)
		queryBox.addSubview(queryLabel)
		queryLabel.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			queryLabel.leadingAnchor.constraint(equalTo: queryBox.leadingAnchor, constant: 12),
			queryLabel.trailingAnchor.constraint(equalTo: queryBox.trailingAnchor, constant: -12),
			queryLabel.centerYAnchor.constraint(equalTo: queryBox.centerYAnchor),
		])
		root.addArrangedSubview(queryBox)

		root.addArrangedSubview(statusLabel)
		root.addArrangedSubview(accessBox)
		root.addArrangedSubview(collectionView)

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

		for row in keyRows {
			let rowStack = keyboardRow(row)
			keyRowStacks.append(rowStack)
			root.addArrangedSubview(rowStack)
		}
	}

	private var keyRows: [[String]] {
		[
			["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
			["a", "s", "d", "f", "g", "h", "j", "k", "l"],
			["z", "x", "c", "v", "b", "n", "m"],
			["space", "delete", "go"],
		]
	}

	private func keyboardRow(_ keys: [String]) -> UIStackView {
		let row = UIStackView()
		row.axis = .horizontal
		row.spacing = 5
		row.distribution = .fillEqually
		for key in keys {
			let button = keyButton(key)
			row.addArrangedSubview(button)
		}
		return row
	}

	private func keyButton(_ key: String) -> UIButton {
		let button = UIButton(type: .system)
		button.backgroundColor = .systemBackground
		button.tintColor = .label
		button.layer.cornerRadius = 7
		button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
		button.heightAnchor.constraint(equalToConstant: 28).isActive = true
		button.accessibilityIdentifier = "key-\(key)"

		switch key {
		case "space":
			button.setTitle("space", for: .normal)
			button.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
		case "delete":
			button.setImage(UIImage(systemName: "delete.left"), for: .normal)
			button.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
		case "go":
			button.setTitle("go", for: .normal)
			button.addTarget(self, action: #selector(goTapped), for: .touchUpInside)
		default:
			button.setTitle(key.uppercased(), for: .normal)
			button.addAction(UIAction { [weak self] _ in self?.append(key) }, for: .touchUpInside)
		}

		return button
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
		setTypingKeysVisible(true)
	}

	@objc private func modeChanged() {
		mode = Mode(rawValue: modeControl.selectedSegmentIndex) ?? .search
		resetResults()
		setTypingKeysVisible(true)
		updatePrompt()
	}

	@objc private func nextKeyboard() {
		advanceToNextInputMode()
	}

	@objc private func openSetupApp() {
		guard let url = URL(string: "memeforge://setup") else { return }
		extensionContext?.open(url) { [weak self] success in
			if !success {
				self?.finish("Open Memeforge, then enable Full Access.")
			}
		}
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
		setTypingKeysVisible(true)
	}

	private func updatePrompt() {
		let placeholder = mode == .search ? "type a meme search" : "describe a static meme"
		queryLabel.text = query.isEmpty ? placeholder : query
		queryLabel.textColor = query.isEmpty ? .secondaryLabel : .label
		SharedSettings.keyboardHasFullAccess = hasFullAccess
		accessBox.isHidden = hasFullAccess
		collectionView.isHidden = !hasFullAccess
		if !hasFullAccess {
			setStatus("Results need Full Access.")
		} else if statusLabel.text == "Results need Full Access." || statusLabel.text == "Open Memeforge for setup steps." {
			setStatus("")
		}
	}

	private func setTypingKeysVisible(_ visible: Bool) {
		keyRowStacks.forEach { $0.isHidden = !visible }
		collectionView.collectionViewLayout.invalidateLayout()
		view.setNeedsLayout()
	}

	private func queryDidChange() {
		resetResults()
		updatePrompt()
		setStatus("")
	}

	private func resetResults() {
		currentTask?.cancel()
		currentTask = nil
		searchQuery = ""
		searchOffset = 0
		canLoadMoreSearchResults = false
		isLoadingSearchResults = false
		results = []
		collectionView.reloadData()
	}

	private func search() {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard hasFullAccess else {
			updatePrompt()
			setStatus("Open Memeforge for setup steps.")
			return
		}
		guard !SharedSettings.giphyAPIKey.isEmpty else {
			setStatus("Missing GIPHY key in local build settings.")
			return
		}
		guard !trimmed.isEmpty else {
			setStatus("Type a search term.")
			return
		}

		currentTask?.cancel()
		searchQuery = trimmed
		searchOffset = 0
		canLoadMoreSearchResults = true
		isLoadingSearchResults = false
		results = []
		collectionView.reloadData()
		setTypingKeysVisible(false)
		setStatus("Searching...")

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
			setStatus("Invalid search URL.")
			return
		}

		currentTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
			guard let self else { return }
			if let error {
				self.finishSearch("Search failed: \(error.localizedDescription)", for: searchQuery)
				return
			}
			guard let data else {
				self.finishSearch("Search returned no data.", for: searchQuery)
				return
			}

			do {
				let response = try JSONDecoder().decode(GiphyResponse.self, from: data)
				let items = response.data.compactMap { item -> MemeResult? in
					guard let preview = item.images.fixedWidthStill?.url ?? item.images.downsizedStill?.url ?? item.images.originalStill?.url else {
						return nil
					}
					let copy = item.images.originalStill?.url ?? item.images.fixedWidthStill?.url ?? preview
					return MemeResult(title: item.title, previewURL: preview, copyURL: copy, imageData: nil, pasteboardType: UTType.png.identifier)
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
					self.setStatus(self.results.isEmpty ? "No static results." : "")
				}
			} catch {
				self.finishSearch("Could not parse GIPHY response.", for: searchQuery)
			}
		}
		currentTask?.resume()
	}

	private func generate() {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard hasFullAccess else {
			updatePrompt()
			setStatus("Open Memeforge for setup steps.")
			return
		}
		guard !SharedSettings.geminiAPIKey.isEmpty else {
			setStatus("Missing Gemini key in local build settings.")
			return
		}
		guard !trimmed.isEmpty else {
			setStatus("Describe the meme.")
			return
		}

		currentTask?.cancel()
		searchQuery = ""
		searchOffset = 0
		canLoadMoreSearchResults = false
		isLoadingSearchResults = false
		results = []
		collectionView.reloadData()
		setStatus("Generating...")

		let url = URL(string: "https://generativelanguage.googleapis.com/v1/models/\(SharedSettings.geminiModel):generateContent")!
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue(SharedSettings.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = geminiRequestBody(for: trimmed)

		currentTask = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
			guard let self else { return }
			if let error {
				self.finish("Generation failed: \(error.localizedDescription)")
				return
			}
			guard let data else {
				self.finish("Generation returned no data.")
				return
			}

			do {
				let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
				if let message = response.error?.message {
					self.finish(message)
					return
				}
				guard let part = response.candidates?.flatMap(\.content.parts).first(where: { $0.inlineData != nil }),
					let inlineData = part.inlineData,
					let imageData = Data(base64Encoded: inlineData.data)
				else {
					self.finish("Gemini did not return an image.")
					return
				}

				let pasteboardType = UTType(mimeType: inlineData.mimeType)?.identifier ?? UTType.png.identifier
				let result = MemeResult(title: trimmed, previewURL: nil, copyURL: nil, imageData: imageData, pasteboardType: pasteboardType)
				DispatchQueue.main.async {
					self.results = [result]
					self.collectionView.reloadData()
					self.setStatus("Tap the generated image to copy it.")
				}
			} catch {
				self.finish("Could not parse Gemini response.")
			}
		}
		currentTask?.resume()
	}

	private func geminiRequestBody(for idea: String) -> Data? {
		let prompt = """
		Create one static square meme image for casual chat.
		Idea: \(idea)
		Make it punchy, readable, visually simple, and safe for broad audiences. If you use text, make it large and legible.
		"""
		let body: [String: Any] = [
			"contents": [
				[
					"parts": [
						["text": prompt],
					],
				],
			],
		]
		return try? JSONSerialization.data(withJSONObject: body)
	}

	private func copy(_ result: MemeResult) {
		guard hasFullAccess else {
			updatePrompt()
			setStatus("Open Memeforge for setup steps.")
			return
		}

		if let imageData = result.imageData {
			copyImageData(imageData, pasteboardType: result.pasteboardType)
			return
		}

		guard let url = result.copyURL else { return }
		setStatus("Copying...")
		URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
			guard let self else { return }
			if let error {
				self.finish("Copy failed: \(error.localizedDescription)")
				return
			}
			guard let data else {
				self.finish("Copy returned no data.")
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
		if let image = UIImage(data: data), let pngData = image.pngData() {
			UIPasteboard.general.setData(pngData, forPasteboardType: UTType.png.identifier)
		} else {
			UIPasteboard.general.setData(data, forPasteboardType: pasteboardType)
		}
		setStatus("Copied. Paste in the current app.")
	}

	private nonisolated func finish(_ message: String) {
		Task { @MainActor [weak self] in
			self?.isLoadingSearchResults = false
			self?.setStatus(message)
		}
	}

	private nonisolated func finishSearch(_ message: String, for searchQuery: String) {
		Task { @MainActor [weak self] in
			guard let self, self.searchQuery == searchQuery else { return }
			self.isLoadingSearchResults = false
			self.canLoadMoreSearchResults = false
			self.setStatus(message)
		}
	}

	@MainActor private func setStatus(_ message: String) {
		statusLabel.text = message
		statusLabel.isHidden = message.isEmpty
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
		let availableWidth = collectionView.bounds.width - inset.left - inset.right - spacing * 2
		let side = floor(availableWidth / 3)
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

	func configure(with result: KeyboardViewController.MemeResult) {
		representedID = result.id
		imageView.image = UIImage(systemName: "photo")

		if let data = result.imageData {
			imageView.image = UIImage(data: data)
			return
		}

		guard let url = result.previewURL else { return }
		let id = result.id
		URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
			guard let self, let data, let image = UIImage(data: data) else { return }
			DispatchQueue.main.async {
				guard self.representedID == id else { return }
				self.imageView.image = image
			}
		}.resume()
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
	let fixedWidthStill: GiphyRendition?
	let downsizedStill: GiphyRendition?
	let originalStill: GiphyRendition?

	enum CodingKeys: String, CodingKey {
		case fixedWidthStill = "fixed_width_still"
		case downsizedStill = "downsized_still"
		case originalStill = "original_still"
	}
}

private struct GiphyRendition: Decodable {
	let url: URL?
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
