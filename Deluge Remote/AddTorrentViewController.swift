//
//  AddTorrentViewController.swift
//  Deluge Remote
//
//  Created by Rudy Bermudez on 1/1/19.
//  Copyright © 2019 Rudy Bermudez. All rights reserved.
//

import Eureka
import MBProgressHUD
import UIKit

// swiftlint:disable:next type_body_length
class AddTorrentViewController: FormViewController {

    var defaultConfig: TorrentConfig?
    var onTorrentAdded: ((_ hash: String) -> Void)?

    var preknownIsFileURL: Bool?
    var preknownURL: URL?

    var torrentType: String?

    enum CodingKeys: String {
        case selectionSection
        case torrentType
        case magnetURL
        // Torrent Config
        case addPaused
        case maxDownloadSpeed
        case maxUploadSpeed
        case maxConnections
        case maxUploadSlots
        case prioritizeFirstLastPieces
        case moveCompleted
        case moveCompletedPath
        case downloadLocation
        case compactAllocation

    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Add Torrent"

        // Get the Torrent Config
        getTorrentConfig()

        // Populate Form
        if let isFileURL = preknownIsFileURL, let torrentURL = preknownURL {

            MBProgressHUD.showAdded(to: self.view, animated: true)

            torrentType = isFileURL ? "Torrent File" : "Magnet Link"

            if isFileURL {
                handleFormConfigurationFor(fileURL: torrentURL)
            } else {
                handleFormConfigurationFor(magnetURL: torrentURL)
            }

        } else {
            populateTorrentTypeSelection()
        }

    }

    func handleFormConfigurationFor(fileURL: URL) {
        ClientManager.shared.activeClient?.getTorrentInfo(fileURL: fileURL)
            .always {
                DispatchQueue.main.async {
                    MBProgressHUD.hide(for: self.view, animated: true)
                }
            }
            .then { torrentInfo -> Void in
                DispatchQueue.main.async {
                    self.showTorrentConfig(name: torrentInfo.name, hash: torrentInfo.hash, url: fileURL)
                }
                torrentInfo.files.prettyPrint()
            }.catch { error in
                if let error = error as? ClientError {
                    showAlert(target: self, title: "Connection failure", message: error.domain())
                } else {
                    showAlert(target: self, title: "Connection failure", message: error.localizedDescription)
                }
                if self.preknownIsFileURL != nil {
                    self.populateTorrentTypeSelection()
                }
        }
    }

    func handleFormConfigurationFor(magnetURL: URL) {
        ClientManager.shared.activeClient?.getMagnetInfo(url: magnetURL)
            .always {
                DispatchQueue.main.async {
                    MBProgressHUD.hide(for: self.view, animated: true)
                }
            }
            .then { output -> Void in
                DispatchQueue.main.async {
                    self.showTorrentConfig(name: output.name, hash: output.hash, url: magnetURL)
                }
            }.catch { _ in
                let dismiss = UIAlertAction(title: "Ok", style: .default) { _ in
                    self.navigationController?.popViewController(animated: true)
                }
                DispatchQueue.main.async {

                    showAlert(target: self, title: "Failure to load magnet URL",
                              message: "An error occurred while attempting to load the magnet URL", actionList: [dismiss])
                    // swiftlint:disable:previous line_length

                }
        }
    }

    // swiftlint:disable:next function_body_length
    func populateTorrentTypeSelection() {
        form +++ Section {
            $0.tag = CodingKeys.selectionSection.rawValue
            $0.header?.title = "Select Torrent Source"
            }

            <<< SegmentedRow<String> {
                $0.tag = CodingKeys.torrentType.rawValue
                $0.options = ["Magnet Link", "Torrent File"]
                }.onChange { row in
                    if let value = row.value {
                        self.torrentType = value
                    }
                }

            <<< URLRow {
                $0.title = "URL:"
                $0.tag = CodingKeys.magnetURL.rawValue
                $0.validationOptions = .validatesOnBlur
                $0.hidden = Condition.function([CodingKeys.torrentType.rawValue]) { form in
                    let selection = (form.rowBy(tag: CodingKeys.torrentType.rawValue)
                        as? SegmentedRow<String>)?.value ?? ""
                    return selection != "Magnet Link"
                }
                }.onRowValidationChanged { cell, row in
                    if !row.isValid {
                        cell.titleLabel?.textColor = .red
                    }
            }
            <<< ButtonRow {
                $0.title = "Select a file"
                $0.hidden = Condition.function([CodingKeys.torrentType.rawValue]) { form in

                    let selection = (form.rowBy(tag: CodingKeys.torrentType.rawValue)
                        as? SegmentedRow<String>)?.value ?? ""
                    return selection != "Torrent File"
                }
                }.onCellSelection { [weak self] _, _ in
                    let vc = UIDocumentPickerViewController(
                        documentTypes: ["io.rudybermudez.deluge.torrent"], in: UIDocumentPickerMode.import
                    )
                    vc.delegate = self
                    self?.present(vc, animated: true, completion: nil)
            }

            <<< ButtonRow {
                $0.title = "Parse Magnet Link"
                $0.disabled = Condition.function([CodingKeys.magnetURL.rawValue]) { form in
                    return (form.rowBy(tag: CodingKeys.magnetURL.rawValue) as? ButtonRow)?.isValid ?? false
                }
                $0.hidden = Condition.function([CodingKeys.torrentType.rawValue]) { form in
                    let selection = (form.rowBy(tag: CodingKeys.torrentType.rawValue)
                        as? SegmentedRow<String>)?.value ?? ""
                    return selection != "Magnet Link"
                }
                }.onCellSelection { [weak self] _, _ in
                    guard
                        let url = self?.form.values()[CodingKeys.magnetURL.rawValue] as? URL
                        else { return }
                    DispatchQueue.main.async {
                        if let view = self?.view {
                            MBProgressHUD.showAdded(to: view, animated: true)
                        }
                    }
                    self?.handleFormConfigurationFor(magnetURL: url)
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func showTorrentConfig(name: String, hash: String, url: URL) {
        form.sectionBy(tag: CodingKeys.selectionSection.rawValue)?.hidden = true
        form.sectionBy(tag: CodingKeys.selectionSection.rawValue)?.evaluateHidden()

        form +++ Section("Torrent Info")
            <<< LabelRow {
                $0.title = name
            }
            <<< LabelRow {
                $0.title = hash
        }

        form +++ Section("Torrent Configuration")
            <<< TextRow {
                $0.title = "Download Location:"
                $0.tag = CodingKeys.downloadLocation.rawValue
                $0.add(rule: RuleRequired())
                $0.value = defaultConfig?.downloadLocation
                }.onChange { row in
                    if let value = row.value {
                        self.defaultConfig?.downloadLocation = value
                }
                }.cellUpdate { _, row in
                    row.value = self.defaultConfig?.downloadLocation
                }
            <<< SwitchRow {
                $0.title = "Move Completed:"
                $0.tag = CodingKeys.moveCompleted.rawValue
                $0.value = defaultConfig?.moveCompleted ?? false
                }.onChange { row in
                    if let value = row.value {
                        self.defaultConfig?.moveCompleted = value
                    }
            }

            <<< TextRow {
                $0.title = "Move Completed Path:"
                $0.tag = defaultConfig?.moveCompletedPath
                $0.value = defaultConfig?.moveCompletedPath
                $0.hidden = Condition.function([CodingKeys.moveCompleted.rawValue]) { form in
                    return !((form.rowBy(tag: CodingKeys.moveCompleted.rawValue) as? SwitchRow)?.value ?? false)
                }
                }.onChange { row in
                    if let value = row.value {
                        self.defaultConfig?.moveCompletedPath = value
                    }
            }

            <<< IntRow {
                $0.title = "Max Upload Speed:"
                $0.value = defaultConfig?.maxUploadSpeed ?? -1
                $0.add(rule: RuleRequired())
                }.onChange { row in
                    if let value = row.value {
                        self.defaultConfig?.maxUploadSpeed = value
                    }
            }

            <<< IntRow {
                $0.title = "Max Download Speed:"
                $0.value = defaultConfig?.maxDownloadSpeed ?? -1
                $0.add(rule: RuleRequired())
                }.onChange { row in
                    if let value = row.value {
                        self.defaultConfig?.maxDownloadSpeed = value
                    }
            }

            <<< IntRow {
                $0.title = "Max Connections:"
                $0.value = defaultConfig?.maxConnections ?? -1
                $0.add(rule: RuleRequired())
                }.onChange { row in
                    if let value = row.value {
                        self.defaultConfig?.maxConnections = value
                    }
            }

            <<< IntRow {
                $0.title = "Max Upload Slots:"
                $0.value = defaultConfig?.maxUploadSlots ?? -1
                $0.add(rule: RuleRequired())
                }.onChange { row in
                    if let value = row.value {
                        self.defaultConfig?.maxUploadSlots = value
                    }
            }

            <<< SwitchRow {
                $0.title = "Add Paused:"
                $0.value = defaultConfig?.addPaused ?? false
                $0.add(rule: RuleRequired())
                }.onChange { row in
                    if let value = row.value {
                        self.defaultConfig?.addPaused = value
                    }
            }

            <<< SwitchRow {
                $0.title = "Compact Allocation:"
                $0.value = defaultConfig?.compactAllocation ?? false
                $0.add(rule: RuleRequired())
                }.onChange { row in
                    if let value = row.value {
                        self.defaultConfig?.compactAllocation = value
                    }
            }

            <<< SwitchRow {
                $0.title = "Prioritize First/Last Pieces:"
                $0.value = defaultConfig?.prioritizeFirstLastPieces ?? false
                $0.add(rule: RuleRequired())
                }.onChange { row in
                    if let value = row.value {
                        self.defaultConfig?.prioritizeFirstLastPieces = value
                    }
        }

        form +++ Section()
            <<< ButtonRow {
                $0.title = "Add Torrent"
                }.onCellSelection { [weak self] _, _ in
                    print("Should Add Torrent")

                    guard
                        let torrentType = self?.torrentType,
                        let defaultConfig = self?.defaultConfig
                        else { return }

                    // TODO: Get the form values and convert to Torrent Config
                    DispatchQueue.main.async {
                        if let view = self?.view {
                            MBProgressHUD.showAdded(to: view, animated: true)
                        }
                    }
                    if torrentType == "Magnet Link" {
                        self?.addMagnetLink(url: url, hash: hash, config: defaultConfig)
                    } else {
                        self?.addTorrentFile(fileName: name, hash: hash, url: url, config: defaultConfig)
                    }
        }
    }

    func addTorrentFile(fileName: String, hash: String, url: URL, config: TorrentConfig) {
        ClientManager.shared.activeClient?.addTorrentFile(fileName: fileName, url: url, with: config)
            .always {
                DispatchQueue.main.async {
                    MBProgressHUD.hide(for: self.view, animated: true)
                }
            }
            .then { _ -> Void in
                DispatchQueue.main.async {
                    let hud = MBProgressHUD.showAdded(to: self.view, animated: true)
                    hud.mode = MBProgressHUDMode.customView
                    hud.customView = UIImageView(image: #imageLiteral(resourceName: "icons8-checkmark"))
                    hud.isSquare = false
                    hud.label.text = "Torrent Successfully Added"
                    hud.hide(animated: true, afterDelay: 1.5)
                    hud.completionBlock = {
                        if let onTorrentAdded = self.onTorrentAdded {
                            onTorrentAdded(hash)
                        }
                    }
                }
            }.catch { _ in
                DispatchQueue.main.async {
                    let hud = MBProgressHUD.showAdded(to: self.view, animated: true)
                    hud.mode = MBProgressHUDMode.customView
                    hud.customView = UIImageView(image: #imageLiteral(resourceName: "icons8-cancel"))
                    hud.isSquare = false
                    hud.label.text = "Failed to Add Torrent"
                    hud.hide(animated: true, afterDelay: 3.0)
                }
        }
    }

    func addMagnetLink(url: URL, hash: String, config: TorrentConfig) {
        ClientManager.shared.activeClient?.addTorrentMagnet(url: url, with: config)
            .always {
                DispatchQueue.main.async {
                    MBProgressHUD.hide(for: self.view, animated: true)
                }
            }
            .then { _ -> Void in
                DispatchQueue.main.async {
                    let hud = MBProgressHUD.showAdded(to: self.view, animated: true)
                    hud.mode = MBProgressHUDMode.customView
                    hud.customView = UIImageView(image: #imageLiteral(resourceName: "icons8-checkmark"))
                    hud.isSquare = false
                    hud.label.text = "Torrent Successfully Added"
                    hud.hide(animated: true, afterDelay: 1.5)
                    hud.completionBlock = {
                        if let onTorrentAdded = self.onTorrentAdded {
                            onTorrentAdded(hash)
                        }

                    }
                }
            }.catch { _ in
                DispatchQueue.main.async {
                    let hud = MBProgressHUD.showAdded(to: self.view, animated: true)
                    hud.mode = MBProgressHUDMode.customView
                    hud.customView = UIImageView(image: #imageLiteral(resourceName: "icons8-cancel"))
                    hud.isSquare = false
                    hud.label.text = "Failed to Add Torrent"
                    hud.hide(animated: true, afterDelay: 3.0)
                }
        }
    }

    func getTorrentConfig() {
        ClientManager.shared.activeClient?.getAddTorrentConfig().then { config -> Void in
            self.defaultConfig = config
            self.tableView.reloadData()
            }.catch { _ in
                let dismiss = UIAlertAction(title: "Ok", style: .default) { _ in
                    self.navigationController?.popViewController(animated: true)
                }
                showAlert(target: self, title: "Failure to load config",
                          message: "An error occurred while attempting to load in the default torrent configuration", actionList: [dismiss])
                // swiftlint:disable:previous line_length
        }
    }

}

// MARK: - UIDocumentPickerDelegate
extension AddTorrentViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            DispatchQueue.main.async {
                showAlert(target: self, title: "Error", message: "Unable to open torrent file")
            }
            return
        }
        DispatchQueue.main.async {
            MBProgressHUD.showAdded(to: self.view, animated: true)
        }
        handleFormConfigurationFor(fileURL: url)
    }
}
