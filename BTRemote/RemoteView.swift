import SwiftUI

let groupFill = Color.secondary.opacity(0.16)
private let cellGap: CGFloat = 6

private struct ConsumerButton {
    let report: ConsumerReport
    let icon: String
    let label: LocalizedStringKey

    init(_ key: ConsumerKey, _ icon: String, _ label: LocalizedStringKey) {
        report = ConsumerReport(key: key)
        self.icon = icon
        self.label = label
    }

    init(_ report: ConsumerReport, _ icon: String, _ label: LocalizedStringKey) {
        self.report = report
        self.icon = icon
        self.label = label
    }
}

struct RemoteView: View {
    let goToSetup: () -> Void

    @EnvironmentObject private var ble: HIDPeripheral
    @EnvironmentObject private var central: HIDCentral
    @AppStorage(AppSettings.touchpadSensitivityKey) private var touchpadSensitivity = AppSettings.defaultPointerSensitivity
    @AppStorage(AppSettings.scrollSensitivityKey) private var scrollSensitivity = AppSettings.defaultScrollSensitivity
    #if os(macOS)
        @EnvironmentObject private var classic: HIDClassicDevice
        @Environment(\.macTransport) private var macTransport
        @State private var dragOffset: CGSize = .zero
    #endif

    private var hid: HIDInput {
        #if os(macOS)
            return HIDInput.make(ble: ble, central: central, classic: classic, classicMode: macTransport == .classic)
        #else
            return HIDInput.make(ble: ble, central: central)
        #endif
    }

    var body: some View {
        #if os(macOS)
            NavigationStack { titledScreen }
        #else
            NavigationView { titledScreen }
                .navigationViewStyle(.stack)
        #endif
    }

    private var titledScreen: some View {
        screen
            .navigationTitle(L10n.Tab.remote)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var screen: some View {
        if hid.isActive {
            controls
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text(L10n.Remote.notConnectedTitle)
                .font(.title2.weight(.semibold))
            Text(L10n.Remote.notConnectedMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.Remote.openSetup, action: goToSetup)
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        GeometryReader { geo in
            let h = geo.size.height
            VStack(spacing: cellGap) {
                mediaPill.frame(height: h * 0.11)
                grid.frame(maxHeight: .infinity)
                bottomRow.frame(height: h * 0.11)
                touchpadBlock.frame(height: h * 0.42)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // media pill: rewind, play/pause, forward

    private var mediaPill: some View {
        HStack(spacing: 0) {
            consumerMember(.init(.rewind, "backward.fill", L10n.Media.rewind))
            consumerMember(.init(.playPause, "playpause.fill", L10n.Media.playPause))
            consumerMember(.init(.fastForward, "forward.fill", L10n.Media.fastForward))
        }
        .background(RoundedRectangle(cornerRadius: 26).fill(groupFill))
    }

    // grid: volume column, number pad, channel column

    private var grid: some View {
        HStack(spacing: cellGap) {
            sideColumn(
                pill: { verticalPill(
                    .init(.volumeUp, "speaker.wave.3.fill", L10n.Media.volumeUp),
                    .init(.volumeDown, "speaker.wave.1.fill", L10n.Media.volumeDown)
                ) },
                tail: { consumerCircle(.init(.mute, "speaker.slash.fill", L10n.Media.mute)) }
            )
            numberColumn([(1, .digit1), (4, .digit4), (7, .digit7)])
            numberColumn([(2, .digit2), (5, .digit5), (8, .digit8)])
            numberColumn([(3, .digit3), (6, .digit6), (9, .digit9)])
            sideColumn(
                pill: { verticalPill(
                    .init(.channelUp, "plus", L10n.Remote.channelUp),
                    .init(.channelDown, "minus", L10n.Remote.channelDown)
                ) },
                tail: { consumerCircle(.init(.closedCaption, "captions.bubble", L10n.Remote.closedCaptions)) }
            )
        }
    }

    private func numberColumn(_ keys: [(Int, Keycode)]) -> some View {
        VStack(spacing: cellGap) {
            ForEach(keys, id: \.0) { number, key in
                numberCircle(number, key)
            }
        }
    }

    private func sideColumn(
        @ViewBuilder pill: @escaping () -> some View,
        @ViewBuilder tail: @escaping () -> some View
    ) -> some View {
        GeometryReader { g in
            VStack(spacing: cellGap) {
                pill().frame(height: (g.size.height - cellGap) * 2 / 3)
                tail().frame(height: (g.size.height - cellGap) / 3)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }

    private func verticalPill(_ top: ConsumerButton, _ bottom: ConsumerButton) -> some View {
        VStack(spacing: 0) {
            consumerMember(top)
            consumerMember(bottom)
        }
        .background(Capsule().fill(groupFill))
    }

    // bottom row: back, home, 0, menu, power

    private var bottomRow: some View {
        HStack(spacing: cellGap) {
            consumerCircle(.init(.acBack, "arrow.left", L10n.Remote.back))
            consumerCircle(.init(.acHome, "house.fill", L10n.Remote.home))
            numberCircle(0, .digit0)
            consumerCircle(.init(.menu, "list.bullet", L10n.Remote.menu))
            consumerCircle(.init(.power, "power", L10n.Remote.power))
        }
    }

    // touchpad + scroll column + mouse buttons

    private var touchpadBlock: some View {
        VStack(spacing: cellGap) {
            HStack(spacing: cellGap) {
                touchpadSurface
                scrollColumn.frame(width: 46)
            }
            .frame(maxHeight: .infinity)
            mouseButtonsRow.frame(height: 52)
        }
    }

    private var touchpadSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(groupFill)
            #if os(iOS)
                TouchpadView(
                    moveSensitivity: touchpadSensitivity,
                    scrollSensitivity: scrollSensitivity,
                    onMove: { hid.move(dx: $0, dy: $1) },
                    onScroll: { hid.scroll($0) },
                    onLeftClick: { Haptics.tap(); hid.click(.left) },
                    onRightClick: { Haptics.tap(); hid.click(.right) }
                )
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let dx = HIDInput.clamp((value.translation.width - dragOffset.width) * touchpadSensitivity)
                        let dy = HIDInput.clamp((value.translation.height - dragOffset.height) * touchpadSensitivity)
                        dragOffset = value.translation
                        hid.move(dx: dx, dy: dy)
                    }
                    .onEnded { _ in
                        dragOffset = .zero
                        hid.sendMouse(.zero)
                    }
            )
        #endif
    }

    private var scrollAmount: Int8 {
        max(1, HIDInput.clamp(CGFloat(3 * scrollSensitivity)))
    }

    private var scrollColumn: some View {
        VStack(spacing: cellGap) {
            scrollButton("arrow.up", L10n.Mouse.wheelUp, scrollAmount)
            scrollButton("arrow.down", L10n.Mouse.wheelDown, -scrollAmount)
        }
    }

    private var mouseButtonsRow: some View {
        HStack(spacing: cellGap) {
            mouseButton(.left, L10n.Mouse.leftButton)
            mouseButton(.middle, L10n.Mouse.middleButton)
            mouseButton(.right, L10n.Mouse.rightButton)
        }
    }

    // button builders

    private func consumerCircle(_ button: ConsumerButton) -> some View {
        HoldButton(
            onPress: { hid.sendConsumer(button.report) },
            onRelease: { hid.sendConsumer(.zero) },
            background: { Circle().fill(groupFill) },
            label: { Image(systemName: button.icon).font(.title3) }
        )
        .accessibilityLabel(button.label)
    }

    private func consumerMember(_ button: ConsumerButton) -> some View {
        HoldButton(
            onPress: { hid.sendConsumer(button.report) },
            onRelease: { hid.sendConsumer(.zero) },
            background: { Color.clear },
            label: { Image(systemName: button.icon).font(.title3) }
        )
        .accessibilityLabel(button.label)
    }

    private func numberCircle(_ number: Int, _ key: Keycode) -> some View {
        HoldButton(
            onPress: { hid.sendKeyboard(KeyboardReport(keys: [key])) },
            onRelease: { hid.sendKeyboard(.zero) },
            background: { Circle().fill(groupFill) },
            label: { Text(verbatim: "\(number)").font(.title3.weight(.medium)) }
        )
    }

    private func mouseButton(_ button: MouseButtons, _ label: LocalizedStringKey) -> some View {
        HoldButton(
            onPress: { hid.sendMouse(MouseReport(buttons: button)) },
            onRelease: { hid.sendMouse(.zero) },
            background: { RoundedRectangle(cornerRadius: 12).fill(groupFill) },
            label: { Color.clear }
        )
        .accessibilityLabel(label)
    }

    private func scrollButton(_ icon: String, _ label: LocalizedStringKey, _ wheel: Int8) -> some View {
        HoldButton(
            onPress: { hid.scroll(wheel) },
            onRelease: {},
            background: { RoundedRectangle(cornerRadius: 12).fill(groupFill) },
            label: { Image(systemName: icon).font(.body) }
        )
        .accessibilityLabel(label)
    }
}

private struct HoldButton<Background: View, Label: View>: View {
    let onPress: () -> Void
    let onRelease: () -> Void
    @ViewBuilder var background: () -> Background
    @ViewBuilder var label: () -> Label
    @State private var pressed = false

    var body: some View {
        ZStack {
            background()
            label().foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(pressed ? 0.5 : 1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                        Haptics.tap()
                        onPress()
                    }
                }
                .onEnded { _ in
                    pressed = false
                    onRelease()
                }
        )
    }
}

#if DEBUG
    #Preview {
        #if os(iOS)
            RemoteView(goToSetup: {})
                .environmentObject(HIDPeripheral())
                .environmentObject(HIDCentral())
        #else
            RemoteView(goToSetup: {})
                .environmentObject(HIDPeripheral())
                .environmentObject(HIDCentral())
                .environmentObject(HIDClassicDevice())
        #endif
    }
#endif
