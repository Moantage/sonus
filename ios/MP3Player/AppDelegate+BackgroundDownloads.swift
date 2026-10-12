import UIKit

extension AppDelegate {
    /// iOS relaunches the app (or wakes it) when background downloads finish. Reconnecting to the
    /// session delivers their results; the completion handler runs once they're all handled.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundDownloadSession.shared.handleEvents(for: identifier, completionHandler: completionHandler)
    }
}
