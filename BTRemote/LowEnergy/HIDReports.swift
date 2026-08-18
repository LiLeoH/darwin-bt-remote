import Foundation

struct MouseReport: Equatable {
    var buttons: MouseButtons = []
    var dX: Int8 = 0
    var dY: Int8 = 0
    var wheel: Int8 = 0

    static let zero = MouseReport()

    var data: Data {
        Data([
            buttons.rawValue,
            UInt8(bitPattern: dX),
            UInt8(bitPattern: dY),
            UInt8(bitPattern: wheel)
        ])
    }
}

struct MouseButtons: OptionSet, Equatable {
    let rawValue: UInt8
    static let left = MouseButtons(rawValue: 1 << 0)
    static let right = MouseButtons(rawValue: 1 << 1)
    static let middle = MouseButtons(rawValue: 1 << 2)
}

struct KeyboardReport: Equatable {
    var modifiers: KeyboardModifiers = []
    var keys: [Keycode] = []

    static let zero = KeyboardReport()

    var data: Data {
        var bytes = [UInt8](repeating: 0, count: 8)
        bytes[0] = modifiers.rawValue
        // bytes[1] reserved
        for (i, key) in keys.prefix(6).enumerated() {
            bytes[2 + i] = key.rawValue
        }
        return Data(bytes)
    }
}

struct KeyboardModifiers: OptionSet, Equatable, Codable, Hashable {
    let rawValue: UInt8
    static let leftCtrl = KeyboardModifiers(rawValue: 1 << 0)
    static let leftShift = KeyboardModifiers(rawValue: 1 << 1)
    static let leftAlt = KeyboardModifiers(rawValue: 1 << 2)
    static let leftGUI = KeyboardModifiers(rawValue: 1 << 3)
    static let rightCtrl = KeyboardModifiers(rawValue: 1 << 4)
    static let rightShift = KeyboardModifiers(rawValue: 1 << 5)
    static let rightAlt = KeyboardModifiers(rawValue: 1 << 6)
    static let rightGUI = KeyboardModifiers(rawValue: 1 << 7)
}

struct KeyboardLEDs: OptionSet, Equatable {
    let rawValue: UInt8
    static let numLock = KeyboardLEDs(rawValue: 1 << 0)
    static let capsLock = KeyboardLEDs(rawValue: 1 << 1)
    static let scrollLock = KeyboardLEDs(rawValue: 1 << 2)
    static let compose = KeyboardLEDs(rawValue: 1 << 3)
    static let kana = KeyboardLEDs(rawValue: 1 << 4)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(byte: UInt8) {
        rawValue = byte & 0x1F
    }
}

/// USB HID usage page 0x07
enum Keycode: UInt8, Equatable, Hashable, Codable {
    case a = 0x04, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z
    case digit1 = 0x1E, digit2, digit3, digit4, digit5, digit6, digit7, digit8, digit9, digit0
    case `return` = 0x28
    case escape = 0x29
    case backspace = 0x2A
    case tab = 0x2B
    case space = 0x2C
    case minus = 0x2D
    case equal = 0x2E
    case leftBracket = 0x2F
    case rightBracket = 0x30
    case backslash = 0x31
    case semicolon = 0x33
    case quote = 0x34
    case grave = 0x35
    case comma = 0x36
    case period = 0x37
    case slash = 0x38
    case capsLock = 0x39
    case f1 = 0x3A, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case printScreen = 0x46
    case deleteForward = 0x4C
    case rightArrow = 0x4F
    case leftArrow = 0x50
    case downArrow = 0x51
    case upArrow = 0x52
}

struct SystemControlReport: Equatable {
    var actions: SystemActions = []

    static let zero = SystemControlReport()

    var data: Data {
        Data([actions.rawValue])
    }
}

struct SystemActions: OptionSet, Equatable {
    let rawValue: UInt8
    static let powerDown = SystemActions(rawValue: 1 << 0)
    static let sleep = SystemActions(rawValue: 1 << 1)
    static let coldRestart = SystemActions(rawValue: 1 << 2)
    static let displayToggle = SystemActions(rawValue: 1 << 3)
    static let displayLCDAutoscale = SystemActions(rawValue: 1 << 4)
    static let mainMenu = SystemActions(rawValue: 1 << 5)
    static let appMenu = SystemActions(rawValue: 1 << 6)
    static let displayBrightnessDecrement = SystemActions(rawValue: 1 << 7)
}

/// consumer report (5 bytes)
struct ConsumerReport: Equatable {
    var key: ConsumerKey = .none
    var acUsageA: UInt8 = 0
    var acUsageB: UInt8 = 0
    var sub: UInt8 = 0

    static let zero = ConsumerReport()

    var data: Data {
        let raw = key.rawValue
        return Data([
            UInt8(raw & 0xFF),
            UInt8(raw >> 8),
            acUsageA,
            acUsageB,
            sub
        ])
    }
}

/// USB HID usage page 0x0C
enum ConsumerKey: UInt16, Equatable {
    case none = 0x0000
    case playPause = 0x00CD
    case scanNext = 0x00B5
    case scanPrev = 0x00B6
    case stop = 0x00B7
    case rewind = 0x00B4
    case fastForward = 0x00B3
    case mute = 0x00E2
    case volumeUp = 0x00E9
    case volumeDown = 0x00EA
    case channelUp = 0x009C
    case channelDown = 0x009D
    case closedCaption = 0x0061
    case menu = 0x0040
    case menuPick = 0x0041
    case menuUp = 0x0042
    case menuDown = 0x0043
    case menuLeft = 0x0044
    case menuRight = 0x0045
    case power = 0x0030
}

extension ConsumerReport {
    static let acHome = ConsumerReport(acUsageB: 0x23)
    static let acBack = ConsumerReport(acUsageB: 0x24)
}

extension Keycode {
    /// Display label for UI, e.g. "A", "F1", "←", "Space".
    var displayName: String {
        if (0x04 ... 0x1D).contains(rawValue) {
            let letters = "abcdefghijklmnopqrstuvwxyz"
            let index = letters.index(letters.startIndex, offsetBy: Int(rawValue) - 0x04)
            return String(letters[index])
        }
        if (0x1E ... 0x27).contains(rawValue) {
            let n = Int(rawValue) - 0x1E + 1
            return n == 10 ? "0" : String(n)
        }
        switch self {
        case .space: return "Space"
        case .return: return "↩"
        case .escape: return "Esc"
        case .tab: return "Tab"
        case .backspace: return "⌫"
        case .capsLock: return "⇪"
        case .minus: return "-"
        case .equal: return "="
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .backslash: return "\\"
        case .semicolon: return ";"
        case .quote: return "'"
        case .grave: return "`"
        case .comma: return ","
        case .period: return "."
        case .slash: return "/"
        case .printScreen: return "PrtSc"
        case .deleteForward: return "Del"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .downArrow: return "↓"
        case .upArrow: return "↑"
        default: return "?"
        }
    }

    /// Map a macOS virtual key code to a HID `Keycode`, when representable.
    init?(macVirtualKey key: UInt16) {
        guard let code = Self.macVirtualKeys[key] else { return nil }
        self = code
    }

    /// macOS virtual key code -> HID usage id (subset covering the keys we route).
    static let macVirtualKeys: [UInt16: Keycode] = [
        0x00: .a, 0x0B: .b, 0x08: .c, 0x02: .d, 0x0E: .e, 0x03: .f, 0x05: .g, 0x04: .h,
        0x22: .i, 0x26: .j, 0x28: .k, 0x25: .l, 0x2E: .m, 0x2D: .n, 0x1F: .o, 0x23: .p,
        0x0C: .q, 0x0F: .r, 0x01: .s, 0x11: .t, 0x20: .u, 0x09: .v, 0x0D: .w, 0x07: .x,
        0x10: .y, 0x06: .z,
        0x12: .digit1, 0x13: .digit2, 0x14: .digit3, 0x15: .digit4, 0x17: .digit5,
        0x16: .digit6, 0x1A: .digit7, 0x1C: .digit8, 0x19: .digit9, 0x1D: .digit0,
        0x24: .return, 0x4C: .return,
        0x35: .escape, 0x33: .backspace,
        0x75: .deleteForward, // macOS kVK_ForwardDelete; PC "Del" (HID 0x4C) maps here, not 0x33 (backspace)
        0x30: .tab, 0x31: .space,
        0x1B: .minus, 0x18: .equal, 0x21: .leftBracket, 0x1E: .rightBracket,
        0x2A: .backslash, 0x29: .semicolon, 0x27: .quote, 0x32: .grave,
        0x2B: .comma, 0x2F: .period, 0x2C: .slash, 0x39: .capsLock,
        0x7A: .f1, 0x78: .f2, 0x63: .f3, 0x76: .f4, 0x60: .f5, 0x61: .f6,
        0x62: .f7, 0x64: .f8, 0x65: .f9, 0x6D: .f10, 0x67: .f11, 0x6F: .f12,
        0x7C: .rightArrow, 0x7B: .leftArrow, 0x7D: .downArrow, 0x7E: .upArrow
    ]
}
