/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Lists saved scans and opens a floor plan review.
*/

import UIKit

final class SavedScansViewController: UITableViewController {
    private var scans: [SavedScanRecord] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Saved Scans"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissSelf)
        )

        tableView.register(SavedScanCell.self, forCellReuseIdentifier: SavedScanCell.reuseIdentifier)
        tableView.rowHeight = 72
        tableView.separatorStyle = .singleLine
        tableView.backgroundColor = .systemBackground
        reloadScans()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadScans()
    }

    private func reloadScans() {
        scans = SavedScansStore().loadIndex()
        tableView.reloadData()
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
}

// MARK: - UITableViewDataSource

extension SavedScansViewController {
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        scans.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SavedScanCell.reuseIdentifier,
            for: indexPath
        ) as? SavedScanCell else {
            return UITableViewCell()
        }

        cell.configure(with: scans[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate

extension SavedScansViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = scans[indexPath.row]
        guard let exportData = SavedScansStore().loadFloorPlanExport(for: record.id) else {
            return
        }

        let viewController = FloorPlanViewController(exportData: exportData)
        navigationController?.pushViewController(viewController, animated: true)
    }
}

// MARK: - Cell

final class SavedScanCell: UITableViewCell {
    static let reuseIdentifier = "SavedScanCell"

    private let thumbnailView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        selectionStyle = .default

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.layer.cornerRadius = 8
        thumbnailView.clipsToBounds = true
        thumbnailView.backgroundColor = UIColor.secondarySystemBackground

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .label

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel

        contentView.addSubview(thumbnailView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 56),
            thumbnailView.heightAnchor.constraint(equalToConstant: 56),

            titleLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: thumbnailView.topAnchor, constant: 4),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        ])
    }

    func configure(with record: SavedScanRecord) {
        titleLabel.text = record.title
        subtitleLabel.text = record.subtitle
        thumbnailView.image = SavedScansStore().loadThumbnail(for: record.id)
    }
}
