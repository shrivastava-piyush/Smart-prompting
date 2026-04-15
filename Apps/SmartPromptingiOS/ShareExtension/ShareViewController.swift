import UIKit
import SwiftUI
import UniformTypeIdentifiers
import SmartPromptingCore

/// "Save to Smart Prompting" share extension. Accepts plain text from any app.
class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await handleInput() }
    }

    private func handleInput() async {
        guard let item = (extensionContext?.inputItems.first as? NSExtensionItem),
              let providers = item.attachments else {
            complete()
            return
        }
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    await save(text)
                    break
                }
            }
        }
        complete()
    }

    private func save(_ body: String) async {
        guard let sp = try? SmartPrompting() else { return }
        _ = try? await sp.create(from: body)
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
