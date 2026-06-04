import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

final class KeyboardViewController: UIInputViewController {
	private enum Mode: Int {
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
	private let maxSearchCollectionHeight: CGFloat = 320
	private let generatedStyles = [
		"Classic photographic meme style.",
		"Bold illustrated meme style.",
	]

	private let modeControl = UISegmentedControl(items: ["Search", "Generate"])
	private let queryLabel = UILabel()
	private let queryBox = UIControl()
	private let queryCaret = UIView()
	private let queryClearButton = UIButton(type: .system)
	private let accessBox = UIView()
	private let accessTitleLabel = UILabel()
	private let accessDetailLabel = UILabel()
	private let collectionView: UICollectionView
	private let loadingIndicator = UIActivityIndicatorView(style: .large)
	private let rootStack = UIStackView()
	private lazy var keyboardRestoreButton = smallButton("keyboard", action: #selector(focusQuery))
	private lazy var closeButton = smallButton("xmark", action: #selector(closeKeyboard))
	private var heightConstraint: NSLayoutConstraint?
	private var collectionHeightConstraint: NSLayoutConstraint?
	private var queryBoxHeightConstraint: NSLayoutConstraint?
	private var queryCaretLeadingConstraint: NSLayoutConstraint?
	private var queryCaretTopConstraint: NSLayoutConstraint?
	private var queryCaretHeightConstraint: NSLayoutConstraint?

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
		keyFeedback.prepare()
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

		let isDark = traitCollection.userInterfaceStyle == .dark
		let active = shiftState != .lowercase
		let backgroundColor = active ? (isDark ? UIColor(white: 0.36, alpha: 1) : UIColor.white) : (isDark ? UIColor(white: 0.22, alpha: 1) : UIColor.systemGray3)
		let tintColor = isDark ? UIColor.white : UIColor.label
		styleKey(shiftKeyButton, backgroundColor: backgroundColor, tintColor: tintColor, shadow: !isDark && active)
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
		queryCaret.backgroundColor = .systemBlue
		queryClearButton.tintColor = isDark ? UIColor(white: 0.75, alpha: 1) : UIColor.secondaryLabel
		loadingIndicator.color = isDark ? .white : .secondaryLabel
		applyQueryInputFocus(animated: false)
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
		mode = Mode(rawValue: modeControl.selectedSegmentIndex) ?? .search
		resetResults()
		setTypingControlsVisible(true)
		updatePrompt()
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
		setTypingControlsVisible(true)
	}

	private func updatePrompt() {
		let placeholder = mode == .search ? "type a meme search" : "describe a static meme"
		queryLabel.text = query.isEmpty ? placeholder : query
		queryLabel.textColor = query.isEmpty ? .secondaryLabel : .label
		queryClearButton.isHidden = query.isEmpty
		SharedSettings.keyboardHasFullAccess = hasFullAccess
		accessBox.isHidden = hasFullAccess
		updateQueryBoxHeight()
		updateCaretPosition()
		updateContainerSizing()
	}

	private func setTypingControlsVisible(_ visible: Bool) {
		typingControlsVisible = visible
		setQueryInputFocused(visible, animated: true)
		queryBox.isHidden = !visible
		keyboardRestoreButton.isHidden = visible
		keyRowStacks.forEach { $0.isHidden = !visible }
		collectionView.collectionViewLayout.invalidateLayout()
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
			visibleHeights.append(queryBoxHeightConstraint?.constant ?? minQueryBoxHeight)
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
		isLoadingSearchResults = true
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

		let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(SharedSettings.geminiModel):generateContent")!
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
			closeKeyboard()
			return
		}

		if let image = UIImage(data: data), let pngData = image.pngData() {
			UIPasteboard.general.setData(pngData, forPasteboardType: UTType.png.identifier)
			SharedSettings.updateCopiedMemePreview(pngData)
		} else {
			UIPasteboard.general.setData(data, forPasteboardType: pasteboardType)
			SharedSettings.updateCopiedMemePreview(data)
		}
		closeKeyboard()
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
