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

	private let modeControl = UISegmentedControl(items: ["Search", "Generate"])
	private let queryLabel = UILabel()
	private let statusLabel = UILabel()
	private let collectionView: UICollectionView

	init() {
		let layout = UICollectionViewFlowLayout()
		layout.scrollDirection = .horizontal
		layout.minimumLineSpacing = 8
		layout.minimumInteritemSpacing = 8
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

		collectionView.backgroundColor = .clear
		collectionView.dataSource = self
		collectionView.delegate = self
		collectionView.register(MemeCell.self, forCellWithReuseIdentifier: MemeCell.reuseIdentifier)
		collectionView.showsHorizontalScrollIndicator = false
		collectionView.heightAnchor.constraint(equalToConstant: 116).isActive = true

		let root = UIStackView()
		root.axis = .vertical
		root.spacing = 8
		root.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(root)

		NSLayoutConstraint.activate([
			root.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
			root.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
			root.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
			root.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
		])

		let topRow = UIStackView(arrangedSubviews: [smallButton("globe", action: #selector(nextKeyboard)), modeControl, smallButton("xmark", action: #selector(clearQuery))])
		topRow.axis = .horizontal
		topRow.spacing = 8
		topRow.alignment = .center
		root.addArrangedSubview(topRow)

		let queryBox = UIView()
		queryBox.backgroundColor = .tertiarySystemBackground
		queryBox.layer.cornerRadius = 8
		queryBox.translatesAutoresizingMaskIntoConstraints = false
		queryBox.heightAnchor.constraint(equalToConstant: 40).isActive = true
		queryBox.addSubview(queryLabel)
		queryLabel.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			queryLabel.leadingAnchor.constraint(equalTo: queryBox.leadingAnchor, constant: 12),
			queryLabel.trailingAnchor.constraint(equalTo: queryBox.trailingAnchor, constant: -12),
			queryLabel.centerYAnchor.constraint(equalTo: queryBox.centerYAnchor),
		])
		root.addArrangedSubview(queryBox)

		root.addArrangedSubview(statusLabel)
		root.addArrangedSubview(collectionView)

		let actionRow = UIStackView(arrangedSubviews: [
			actionButton("Search", action: #selector(runSearch)),
			actionButton("Generate", action: #selector(runGenerate)),
		])
		actionRow.axis = .horizontal
		actionRow.spacing = 8
		actionRow.distribution = .fillEqually
		root.addArrangedSubview(actionRow)

		for row in keyRows {
			root.addArrangedSubview(keyboardRow(row))
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
		button.heightAnchor.constraint(equalToConstant: 34).isActive = true
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
		button.widthAnchor.constraint(equalToConstant: 42).isActive = true
		button.heightAnchor.constraint(equalToConstant: 32).isActive = true
		button.addTarget(self, action: action, for: .touchUpInside)
		return button
	}

	private func actionButton(_ title: String, action: Selector) -> UIButton {
		let button = UIButton(type: .system)
		button.setTitle(title, for: .normal)
		button.backgroundColor = .systemOrange
		button.tintColor = .white
		button.layer.cornerRadius = 8
		button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
		button.heightAnchor.constraint(equalToConstant: 36).isActive = true
		button.addTarget(self, action: action, for: .touchUpInside)
		return button
	}

	private func append(_ text: String) {
		query.append(text)
		updatePrompt()
	}

	@objc private func spaceTapped() {
		guard !query.hasSuffix(" ") else { return }
		append(" ")
	}

	@objc private func deleteTapped() {
		guard !query.isEmpty else { return }
		query.removeLast()
		updatePrompt()
	}

	@objc private func clearQuery() {
		query = ""
		results = []
		collectionView.reloadData()
		updatePrompt()
	}

	@objc private func modeChanged() {
		mode = Mode(rawValue: modeControl.selectedSegmentIndex) ?? .search
		updatePrompt()
	}

	@objc private func nextKeyboard() {
		advanceToNextInputMode()
	}

	@objc private func goTapped() {
		switch mode {
		case .search:
			search()
		case .generate:
			generate()
		}
	}

	@objc private func runSearch() {
		modeControl.selectedSegmentIndex = Mode.search.rawValue
		modeChanged()
		search()
	}

	@objc private func runGenerate() {
		modeControl.selectedSegmentIndex = Mode.generate.rawValue
		modeChanged()
		generate()
	}

	private func updatePrompt() {
		let placeholder = mode == .search ? "type a meme search" : "describe a static meme"
		queryLabel.text = query.isEmpty ? placeholder : query
		if !hasFullAccess {
			statusLabel.text = "Allow Full Access is required for network calls."
		} else if statusLabel.text?.isEmpty != false {
			statusLabel.text = mode == .search ? "Search copies static GIPHY stills." : "Generated images copy as PNG."
		}
	}

	private func search() {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard hasFullAccess else {
			statusLabel.text = "Enable Allow Full Access first."
			return
		}
		guard !SharedSettings.giphyAPIKey.isEmpty else {
			statusLabel.text = "Add a GIPHY key in Memeforge."
			return
		}
		guard !trimmed.isEmpty else {
			statusLabel.text = "Type a search term."
			return
		}

		currentTask?.cancel()
		statusLabel.text = "Searching..."

		var components = URLComponents(string: "https://api.giphy.com/v1/gifs/search")
		components?.queryItems = [
			URLQueryItem(name: "api_key", value: SharedSettings.giphyAPIKey),
			URLQueryItem(name: "q", value: trimmed),
			URLQueryItem(name: "limit", value: "24"),
			URLQueryItem(name: "rating", value: "pg-13"),
			URLQueryItem(name: "lang", value: "en"),
			URLQueryItem(name: "bundle", value: "messaging_non_clips"),
		]

		guard let url = components?.url else {
			statusLabel.text = "Invalid search URL."
			return
		}

		currentTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
			guard let self else { return }
			if let error {
				self.finish("Search failed: \(error.localizedDescription)")
				return
			}
			guard let data else {
				self.finish("Search returned no data.")
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
				DispatchQueue.main.async {
					self.results = items
					self.collectionView.reloadData()
					self.statusLabel.text = items.isEmpty ? "No static results." : "Tap a result to copy it."
				}
			} catch {
				self.finish("Could not parse GIPHY response.")
			}
		}
		currentTask?.resume()
	}

	private func generate() {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard hasFullAccess else {
			statusLabel.text = "Enable Allow Full Access first."
			return
		}
		guard !SharedSettings.geminiAPIKey.isEmpty else {
			statusLabel.text = "Add a Gemini key in Memeforge."
			return
		}
		guard !trimmed.isEmpty else {
			statusLabel.text = "Describe the meme."
			return
		}

		currentTask?.cancel()
		statusLabel.text = "Generating..."

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
					self.statusLabel.text = "Tap the generated image to copy it."
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
			"generationConfig": [
				"responseModalities": ["TEXT", "IMAGE"],
				"responseFormat": [
					"image": [
						"aspectRatio": "1:1",
						"imageSize": "1K",
					],
				],
			],
		]
		return try? JSONSerialization.data(withJSONObject: body)
	}

	private func copy(_ result: MemeResult) {
		guard hasFullAccess else {
			statusLabel.text = "Enable Allow Full Access first."
			return
		}

		if let imageData = result.imageData {
			copyImageData(imageData, pasteboardType: result.pasteboardType)
			return
		}

		guard let url = result.copyURL else { return }
		statusLabel.text = "Copying..."
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
		statusLabel.text = "Copied. Paste in the current app."
	}

	private nonisolated func finish(_ message: String) {
		Task { @MainActor [weak self] in
			self?.statusLabel.text = message
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
		CGSize(width: 104, height: 104)
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
