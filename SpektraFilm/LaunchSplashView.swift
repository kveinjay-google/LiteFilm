import SwiftUI

/// Darkroom plate shown on the first frame. Same bitmap and canvas as
/// LaunchScreen.storyboard, so the system launch image does not flash white
/// or jump when SwiftUI takes over.
struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            LaunchColor.canvas.ignoresSafeArea()
            Image("LaunchBackground")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LiteFilm")
    }
}

enum LaunchColor {
    /// Matches LaunchCanvas.colorset and the padded edge of the launch plate.
    static let canvas = Color(red: 6.0 / 255.0, green: 6.0 / 255.0, blue: 6.0 / 255.0)
}

struct LaunchRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showLab = LaunchRootView.skipsSplash

    var body: some View {
        ZStack {
            LaunchColor.canvas.ignoresSafeArea()
            labContent
                .opacity(showLab ? 1 : 0)
                .allowsHitTesting(showLab)
                .accessibilityHidden(!showLab)
            if !showLab {
                LaunchSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: showLab)
        .task {
            guard !showLab else { return }
            let hold: UInt64 = reduceMotion ? 450_000_000 : 1_150_000_000
            try? await Task.sleep(nanoseconds: hold)
            guard !Task.isCancelled else { return }
            showLab = true
        }
    }

    @ViewBuilder private var labContent: some View {
        #if DEBUG
        if CommandLine.arguments.contains("--preview-transition-probe") {
            PreviewTransitionProbe()
        } else {
            ContentView()
        }
        #else
        ContentView()
        #endif
    }

    /// Self-tests exit from ContentView and should not wait on the brand plate.
    private static var skipsSplash: Bool {
        let args = CommandLine.arguments
        return args.contains("--self-test") || args.contains("--frame-self-test")
            || args.contains("--preview-transition-probe")
    }
}
