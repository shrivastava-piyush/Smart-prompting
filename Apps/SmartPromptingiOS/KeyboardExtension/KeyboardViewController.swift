import UIKit
import SmartPromptingCore

/// Custom keyboard that provides prompt search and one-tap insertion into any
/// text field on iOS. Appears as "Smart Prompting" in Settings → General →
/// Keyboard → Keyboards → Add New Keyboard.
class KeyboardViewController: UIInputViewController {
    private var searchField: UITextField!
    private var tableView: UITableView!
    private var results: [ScoredPrompt] = []
    private var sp: SmartPrompting?
    private var emptyLabel: UILabel!
    private var nextKeyboardButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        sp = try? SmartPrompting()
        setupUI()
        loadRecent()
    }

    // MARK: - Layout

    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground

        // Top bar: search field + globe button
        let topBar = UIView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        searchField = UITextField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = "Search prompts…"
        searchField.borderStyle = .roundedRect
        searchField.font = .systemFont(ofSize: 15)
        searchField.clearButtonMode = .whileEditing
        searchField.autocorrectionType = .no
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        topBar.addSubview(searchField)

        nextKeyboardButton = UIButton(type: .system)
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        topBar.addSubview(nextKeyboardButton)

        // Results table
        tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PromptCell.self, forCellReuseIdentifier: "cell")
        tableView.keyboardDismissMode = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        view.addSubview(tableView)

        // Empty state
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
            topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            topBar.heightAnchor.constraint(equalToConstant: 40),

            nextKeyboardButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            nextKeyboardButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            nextKeyboardButton.widthAnchor.constraint(equalToConstant: 40),

            searchField.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: nextKeyboardButton.leadingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 36),

            tableView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])
    }

    // MARK: - Search

    @objc private func searchChanged() {
        let q = searchField.text ?? ""
        if q.trimmingCharacters(in: .whitespaces).isEmpty {
            loadRecent()
        } else {
            results = (try? sp?.search.query(q, limit: 20)) ?? []
        }
        emptyLabel.isHidden = !results.isEmpty
        tableView.reloadData()
    }

    private func loadRecent() {
        let all = (try? sp?.store.all()) ?? []
        results = all.prefix(20).map {
            ScoredPrompt(prompt: $0, score: 0, ftsScore: 0, vectorScore: 0)
        }
        emptyLabel.isHidden = !results.isEmpty
        tableView.reloadData()
    }

    // MARK: - Insertion

    private func insertPrompt(_ prompt: Prompt) {
        let body = prompt.body
        if prompt.placeholders.isEmpty {
            textDocumentProxy.insertText(body)
            try? sp?.store.recordUse(prompt)
        } else {
            // For prompts with placeholders, insert the raw body with
            // placeholders visible so the user can fill them manually.
            textDocumentProxy.insertText(body)
            try? sp?.store.recordUse(prompt)
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Request a height that fits the search bar + a few results.
        let preferred: CGFloat = 260
        if view.frame.height < preferred {
            let constraint = view.heightAnchor.constraint(equalToConstant: preferred)
            constraint.priority = .defaultHigh
            constraint.isActive = true
        }
    }
}

// MARK: - Table data source & delegate

extension KeyboardViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tv: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! PromptCell
        cell.configure(with: results[indexPath.row].prompt)
        return cell
    }

    func tableView(_ tv: UITableView, didSelectRowAt indexPath: IndexPath) {
        tv.deselectRow(at: indexPath, animated: true)
        insertPrompt(results[indexPath.row].prompt)
    }
}

// MARK: - Cell

private class PromptCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let previewLabel = UILabel()
    private let tagsLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.numberOfLines = 1

        previewLabel.font = .systemFont(ofSize: 12)
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 2

        tagsLabel.font = .systemFont(ofSize: 11)
        tagsLabel.textColor = .systemBlue

        let stack = UIStackView(arrangedSubviews: [titleLabel, previewLabel, tagsLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with p: Prompt) {
        titleLabel.text = p.title
        previewLabel.text = String(p.body.prefix(120))
        tagsLabel.text = p.tags.isEmpty ? nil : p.tags.joined(separator: " · ")
        tagsLabel.isHidden = p.tags.isEmpty
    }
}
