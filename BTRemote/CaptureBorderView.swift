#if os(macOS)
    import SwiftUI

    /// The SwiftUI content rendered inside each per-screen overlay window while Direct Input
    /// is capturing. Draws a red screen-edge border plus a top-leading badge so the user has a
    /// persistent, unmistakable signal that all local key/mouse input is being forwarded to the
    /// remote host.
    ///
    /// The entire view is hit-test disabled; the hosting window also sets `ignoresMouseEvents`,
    /// so this overlay never intercepts input — it is purely visual.
    struct CaptureBorderView: View {
        /// Display string of the shortcut that exits Direct Input, shown in the badge so the
        /// user always knows how to stop capture. `nil` when no toggle shortcut is configured.
        let exitHotkey: String?

        /// Border stroke width in points. Kept thick enough to be noticeable at a glance.
        private let lineWidth: CGFloat = 6

        /// Opacity of the full-screen gray dimming mask shown beneath the red border.
        private static let maskOpacity: CGFloat = 0.35

        var body: some View {
            ZStack(alignment: .topLeading) {
                // Dimming mask layered under the red border so the capture state is unmistakable.
                Color.gray.opacity(Self.maskOpacity)
                    .ignoresSafeArea()

                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.red, lineWidth: lineWidth)
                    // inset by half the stroke so the border is not clipped at the screen edge
                    .padding(lineWidth / 2)

                badge
                    .padding(.top, 14)
                    .padding(.leading, 18)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }

        private var badge: some View {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                Text(L10n.CaptureIndicator.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                if let exitHotkey {
                    Text(L10n.CaptureIndicator.exitPrefix)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(exitHotkey)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.red.opacity(0.9)))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
    }

    #if DEBUG
        #Preview {
            CaptureBorderView(exitHotkey: "⌃⌥D")
                .frame(width: 480, height: 320)
                .background(Color.gray.opacity(0.3))
        }
    #endif
#endif
