import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit
import TomatoCore
import UniformTypeIdentifiers

public enum FocusAssessmentError: LocalizedError {
    case invalid
    public var errorDescription: String? { "AI 未能明确确认页面相关性，本次只提醒，不关闭标签。" }
}

public enum FocusCaptureError: LocalizedError {
    case permission, window, image
    public var errorDescription: String? {
        switch self {
        case .permission: "请先允许屏幕录制。未授权时只提醒，不截图或关闭标签。"
        case .window: "未能确认当前 Chrome 窗口，本次不关闭标签。"
        case .image: "当前页面截图失败，本次只提醒。"
        }
    }
}

public enum FocusPageCapture {
    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }
    @MainActor public static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    public static func image(for page: GuardPage) async throws -> Data {
        guard hasPermission else { throw FocusCaptureError.permission }
        guard page.mayAssess,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else { throw FocusCaptureError.window }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) }
        catch { throw FocusCaptureError.image }
        let windows = content.windows.filter { $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 }
        let id = try matchedWindowID(for: page, candidates: windows.map { WindowCandidate(id: $0.windowID, frame: $0.frame, title: $0.title) })
        guard let window = windows.first(where: { $0.windowID == id }) else { throw FocusCaptureError.window }
        let configuration = SCStreamConfiguration()
        let scale = min(1, 1280 / max(window.frame.width, window.frame.height))
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let image: CGImage
        do { image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration) }
        catch { throw FocusCaptureError.image }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { throw FocusCaptureError.image }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FocusCaptureError.image }
        return bytes as Data
    }
    struct WindowCandidate {
        var id: CGWindowID
        var frame: CGRect
        var title: String?
    }
    static func matchedWindowID(for page: GuardPage, candidates: [WindowCandidate]) throws -> CGWindowID {
        guard page.mayAssess, !page.title.isEmpty else { throw FocusCaptureError.window }
        let expected = CGRect(x: page.bounds.x, y: page.bounds.y, width: page.bounds.width, height: page.bounds.height)
        let matching = candidates.filter {
            distance($0.frame, expected) < 80 && $0.frame.width > 100 && $0.frame.height > 100 &&
                ($0.title == page.title || $0.title == page.title + " - Google Chrome")
        }
        // 同位置叠放多个 Chrome 窗口时，不能只凭尺寸猜测，以免截到另一个窗口。
        guard matching.count == 1, let window = matching.first else { throw FocusCaptureError.window }
        return window.id
    }
    private static func distance(_ first: CGRect, _ second: CGRect) -> CGFloat {
        abs(first.minX - second.minX) + abs(first.minY - second.minY) + abs(first.width - second.width) + abs(first.height - second.height)
    }
}
