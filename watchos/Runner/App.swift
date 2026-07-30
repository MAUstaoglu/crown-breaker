import SwiftUI

#if !arch(arm64_32)
// The Flutter host (frame display, input, native overlays) — compiled by
// flutter-watchos into watchos/Flutter/, like Flutter.framework itself.
//
// This app previously carried its own copy of that glue (a local
// FlutterHostView plus Runner/FlutterRunner.swift). That is "legacy mode": the
// CLI detects Runner/FlutterRunner.swift and skips building the host module,
// because the two would collide. The VM Service bridge lives in the module, so
// legacy apps cannot attach DevTools.
import FlutterWatchOS
#endif

@main
struct CrownBreakerApp: App {
    #if !arch(arm64_32)
    // Remote-notification plumbing (APNs device token, notification payloads)
    // for plugins that need it, e.g. firebase_messaging. Safe to keep even if
    // no plugin uses notifications.
    @WKApplicationDelegateAdaptor(FlutterWatchOSAppDelegate.self)
    private var flutterAppDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            #if arch(arm64_32)
            // 32-bit watches (Series 4–8 / SE) are not supported.
            UnsupportedDeviceView()
            #else
            FlutterHostView()
            #endif
        }
    }
}

// Shown on 32-bit watches (Series 4–8 / SE), which this app does not support.
struct UnsupportedDeviceView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Crown Breaker")
                .font(.headline)
            Text("Requires Apple Watch Series 9 or later.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
