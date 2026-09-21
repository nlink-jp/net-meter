import AppKit
import NetMeterUI
import SwiftUI

/// The menu bar item and its panel, as a `MenuBarExtra` window (ADR-0004). The
/// window's placement, material and closing are SwiftUI's; so is keeping the item
/// shown pressed while the panel is open, which a panel of our own could not do
/// through public API (measured on macOS 27.0).
///
/// Nothing here observes `AppDelegate`: the label observes `StatusModel`, which
/// changes every second, and the panel observes `PanelModel`, which is pushed to
/// only while the panel is open.
struct NetMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var app

    var body: some Scene {
        MenuBarExtra {
            PanelHost(
                model: app.panelModel,
                opened: { [app] in app.panelDidOpen() },
                closed: { [app] in app.panelDidClose() }
            )
        } label: {
            StatusLabel(model: app.statusModel)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The item: one image from the one renderer (ADR-0002). The coloured finish takes
/// its foreground from the appearance SwiftUI gives the label. ADR-0002 needs the
/// menu bar's own appearance, which can differ from the system's; whether this is
/// it is one of ADR-0004's checks.
struct StatusLabel: View {
    @ObservedObject var model: StatusModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let finish: StatusFinish = model.coloured ? .coloured(darkMenuBar: colorScheme == .dark) : .template
        Image(nsImage: StatusRenderer.image(content: model.status, finish: finish))
            .accessibilityLabel("net-meter")
            .accessibilityValue(model.spoken)
        #if TRACE
            .onChange(of: colorScheme, initial: true) { _, scheme in
                let bars = NSApp.windows.filter { $0.level == .statusBar }
                    .map { "\(Swift.type(of: $0)):\($0.effectiveAppearance.name.rawValue)" }
                Trace.log("LABEL   colorScheme=\(scheme) statusBarWindows=\(bars) system=\(NSApp.effectiveAppearance.name.rawValue)")
            }
        #endif
    }
}

/// The panel's content. Its appearing and disappearing are how the app learns
/// that the panel opened and closed — whichever way it was closed.
struct PanelHost: View {
    let model: PanelModel
    let opened: () -> Void
    let closed: () -> Void

    var body: some View {
        #if TRACE
        let _ = Trace.log("PANEL   body")
        #endif
        PanelView(model: model)
            .onAppear(perform: opened)
            .onDisappear(perform: closed)
    }
}
