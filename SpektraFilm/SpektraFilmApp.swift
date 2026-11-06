import SwiftUI
import UIKit

@main
struct SpektraFilmApp: App {
    @UIApplicationDelegateAdaptor(SpektraFilmLaunchDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            LaunchRootView()
                .preferredColorScheme(.dark)
        }
    }
}

/// Keeps the window under the first SwiftUI frame the same charcoal as the
/// launch storyboard. Without this, UIKit can flash white before the plate draws.
final class SpektraFilmLaunchDelegate: NSObject, UIApplicationDelegate {
    override init() {
        super.init()
        Self.prepareLaunchWindow()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.prepareLaunchWindow()
        return true
    }

    /// Decode the plate into the named-image cache before the first frame so the
    /// storyboard and LaunchSplashView show the same pixels without a blank gap.
    private static func prepareLaunchWindow() {
        let canvas = UIColor(red: 6.0 / 255.0, green: 6.0 / 255.0, blue: 6.0 / 255.0, alpha: 1)
        UIWindow.appearance().backgroundColor = canvas
        guard let plate = UIImage(named: "LaunchBackground") else { return }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        _ = renderer.image { _ in
            plate.draw(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}
