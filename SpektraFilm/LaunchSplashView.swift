import SwiftUI

/// Matches the compact system launch composition without delaying access to the library.
struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            LaunchColor.canvas.ignoresSafeArea()
            VStack(spacing: 18) {
                Image("BrandIcon").resizable().scaledToFit().frame(width: 88, height: 88)
                Text("LiteFilm")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Ink.ivory)
            }
            .frame(height: 135)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LiteFilm")
    }
}

enum LaunchColor {
    /// Matches LaunchCanvas.colorset.
    static let canvas = Ink.void
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: showLab)
        .task {
            guard !showLab else { return }
            // Yield one frame for a seamless system-launch handoff, without an artificial wait.
            await Task.yield()
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
        return args.contains("--text-self-test") || args.contains("--self-test") || args.contains("--frame-self-test")
            || args.contains("--preview-transition-probe") || args.contains("--editing-suite-self-test")
    }
}
