import AppKit
import UniformTypeIdentifiers
import TomatoCore

@MainActor
enum NoteTextExportPresenter {
    static func present(note: StickyNote, from window: NSWindow?,
                        completion: @escaping (Result<URL?, Error>) -> Void) {
        let export = NoteTextExport(note: note)
        let panel = NSSavePanel()
        panel.title = "导出便签为 TXT"
        panel.prompt = "导出"
        panel.allowedContentTypes = [.plainText]
        panel.allowsOtherFileTypes = false
        panel.nameFieldStringValue = export.suggestedFilename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            panel.orderOut(nil)
            if response == .cancel {
                completion(.success(nil))
                return
            }
            guard response == .OK, let url = panel.url else {
                completion(.failure(CocoaError(.fileWriteUnknown)))
                return
            }
            do {
                try export.data.write(to: url, options: .atomic)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            panel.begin(completionHandler: handleResponse)
        }
    }
}
