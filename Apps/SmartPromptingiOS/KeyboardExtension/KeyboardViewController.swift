import UIKit
import SmartPromptingCore

class KeyboardViewController: UIInputViewController {
    private var searchField: UITextField!
    private var tableView: UITableView!
    private var triggerHintLabel: UILabel!
    private var emptyLabel: UILabel!
    private var results: [ScoredPrompt] = []
    private var sp: SmartPrompting?
    private var nextKeyboardButton: UIButton!

    private var triggerBuffer: String = ""
    private var trackingTrigger = false

    override func viewDidLoad() {
        super.viewDidLoad()
        sp = try? SmartPrompting()
        setupUI()
        loadRecent()
    }

    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground

        let topBar = UIView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        searchField = UITextField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = "Search Prompts"
        searchField.borderStyle = .none
        searchField.backgroundColor = .secondarySystemGroupedBackground
        searchField.layer.cornerRadius = 10
        searchField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 36))
        searchField.leftViewMode = .always
        searchField.font = .systemFont(ofSize: 16, weight: .medium)
        searchField.autocorrectionType = .no
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        topBar.addSubview(searchField)

        nextKeyboardButton = UIButton(type: .system)
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.tintColor = .secondaryLabel
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        topBar.addSubview(nextKeyboardButton)

        triggerHintLabel = UILabel()
        triggerHintLabel.translatesAutoresizingMaskIntoConstraints = false
        triggerHintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        triggerHintLabel.textColor = .systemOrange
        triggerHintLabel.textAlignment = .center
        triggerHintLabel.isHidden = true
        view.addSubview(triggerHintLabel)

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PromptCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        view.addSubview(tableView)

        emptyLabel = UILabel()
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No prompts yet.\nSave some with the Smart Prompting app."
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            topBar.heightAnchor.constraint(equalToConstant: 44),

            nextKeyboardButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            nextKeyboardButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            nextKeyboardButton.widthAnchor.constraint(equalToConstant: 44),

            searchField.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: nextKeyboardButton.leadingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 38),

            triggerHintLabel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 2),
            triggerHintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            triggerHintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            triggerHintLabel.heightAnchor.constraint(equalToConstant: 24),

            tableView.topAnchor.constraint(equalTo: triggerHintLabel.bottomAnchor, constant: 2),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Keyword trigger detection

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        detectTrigger()
    }

    private func detectTrigger() {
        guard let proxy = textDocumentProxy as? UITextDocumentProxy else { return }
        guard let before = proxy.documentContextBeforeInput else {
            resetTrigger()
            return
        }

        let pattern = #"(?:^|\s)-([a-zA-Z][a-zA-Z0-9_-]*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: before,
                range: NSRange(before.startIndex..<before.endIndex, in: before)
              ),
              match.numberOfRanges >= 2,
              let slugRange = Range(match.range(at: 1), in: before) else {
            resetTrigger()
            return
        }

        let slug = String(before[slugRange])
        trackingTrigger = true
        triggerBuffer = slug

        if let prompt = try? sp?.store.get(slug: slug) {
            triggerHintLabel.text = "Press space to expand: \(prompt.title)"
            triggerHintLabel.isHidden = false
        } else {
            triggerHintLabel.text = "Typing trigger: -\(slug)..."
            triggerHintLabel.isHidden = false
        }
    }

    private func resetTrigger() {
        trackingTrigger = false
        triggerBuffer = ""
        triggerHintLabel.isHidden = true
    }

    private func expandTrigger(_ slug: String) {
        guard let prompt = try? sp?.store.get(slug: slug) else { return }

        let charsToDelete = slug.count + 2
        for _ in 0..<charsToDelete {
            textDocumentProxy.deleteBackward()
        }

        let rendered = (try? TemplateEngine.render(prompt.body, with: [:])) ?? prompt.body
        textDocumentProxy.insertText(rendered)
        try? sp?.store.recordUse(prompt)
        resetTrigger()
    }

    // MARK: - Search

    @objc private func searchChanged() {
        let q = searchField.text ?? ""
        if q.isEmpty { loadRecent() }
        else { results = (try? sp?.search.query(q, limit: 10)) ?? [] }
        emptyLabel.isHidden = !results.isEmpty
        tableView.reloadData()
    }

    private func loadRecent() {
        results = ((try? sp?.store.all()) ?? []).prefix(10).map {
            ScoredPrompt(prompt: $0, score: 0, ftsScore: 0, vectorScore: 0)
        }
        emptyLabel.isHidden = !results.isEmpty
        tableView.reloadData()
    }

    // MARK: - Insertion

    private func insertPrompt(_ prompt: Prompt) {
        let rendered = (try? TemplateEngine.render(prompt.body, with: [:])) ?? prompt.body
        textDocumentProxy.insertText(rendered)
        try? sp?.store.recordUse(prompt)
    }

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let preferred: CGFloat = 300
        if view.frame.height < preferred {
            view.heightAnchor.constraint(equalToConstant: preferred).isActive = true
        }
    }
}

extension KeyboardViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tv: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! PromptCell
        cell.configure(with: results[indexPath.row].prompt)
        return cell
    }

    func tableView(_ tv: UITableView, didSelectRowAt indexPath: IndexPath) {
        tv.deselectRow(at: indexPath, animated: true)
        let prompt = results[indexPath.row].prompt

        if trackingTrigger && triggerBuffer == prompt.slug {
            expandTrigger(prompt.slug)
        } else {
            insertPrompt(prompt)
        }
    }
}

private class PromptCell: UITableViewCell {
    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        cardView.backgroundColor = .secondarySystemGroupedBackground
        cardView.layer.cornerRadius = 12
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(titleLabel)

        bodyLabel.font = .systemFont(ofSize: 15, weight: .regular)
        bodyLabel.numberOfLines = 2
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(bodyLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            bodyLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with p: Prompt) {
        titleLabel.text = p.title.uppercased()
        bodyLabel.text = p.body
    }
}
