import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let reason = statusBarController?.terminationBlockReason() else { return .terminateNow }
        statusBarController?.showAlert(title: "Restore Before Quitting", message: reason)
        return .terminateCancel
    }
}
