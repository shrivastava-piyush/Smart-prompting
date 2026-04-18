import UIKit
import SmartPromptingCore

class KeyboardViewController: UIInputViewController {
    private var searchField: UITextField!
    private var tableView: UITableView!
    private var results: [ScoredPrompt] = []
    private var sp: SmartPrompting?
    private var nextKeyboardButton: UIButton!

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
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        topBar.addSubview(searchField)

        nextKeyboardButton = UIButton(type: .system)
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.tintColor = .secondaryLabel
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        topBar.addSubview(nextKeyboardButton)

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PromptCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        view.addSubview(tableView)

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

            tableView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func searchChanged() {
        let q = searchField.text ?? ""
        if q.isEmpty { loadRecent() }
        else { results = (try? sp?.search.query(q, limit: 10)) ?? [] }
        tableView.reloadData()
    }

    private func loadRecent() {
        results = ((try? sp?.store.all()) ?? []).prefix(10).map {
            ScoredPrompt(prompt: $0, score: 0, ftsScore: 0, vectorScore: 0)
        }
        tableView.reloadData()
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
        textDocumentProxy.insertText(results[indexPath.row].prompt.body)
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
