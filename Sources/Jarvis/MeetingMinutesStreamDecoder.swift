import Foundation

/// Reads the minutes JSON while the model is still writing it.
///
/// The point is to stop treating one long answer as a single atomic result: the overview
/// streams out as text, and every point or todo is handed over the moment its closing brace
/// arrives. Whatever this decoder produces is a preview — the finished response is always
/// parsed again in full, and that parse is what gets stored.
struct MeetingMinutesStreamDecoder {
    enum Event: Equatable, Sendable {
        case overviewDelta(String)
        /// Raw JSON text of one finished array element, ready for JSONDecoder.
        case pointCompleted(String)
        case todoCompleted(String)
        /// The model wrote the overview key again. JSON decoding keeps the last one, so the
        /// preview throws away what it showed for the earlier one instead of gluing both.
        case overviewRestarted
    }

    private static let overviewKeys: Set<String> = ["summary", "overview"]
    private static let pointKeys: Set<String> = ["points"]
    private static let todoKeys: Set<String> = ["todos", "actionItems"]

    private var tokenizer = JSONStreamTokenizer()
    private var raw: [Character] = []
    private var stack: [Frame] = []

    private var captureStart: Int?
    private var captureNesting = 0
    private var captureKind: Event?
    /// Set once the first complete object has closed. Anything after it is not the answer.
    private var isClosed = false
    /// An object with no keys at all is prose that happened to contain braces, not the answer.
    private var sawRootKey = false
    private var sawOverviewValue = false

    private struct Frame {
        var isObject: Bool
        /// The key this container hangs under in its parent.
        var key: String?
        /// The last key seen inside this object, cleared once its value is complete.
        var pendingKey: String?
    }

    mutating func feed(_ chunk: String) -> [Event] {
        guard !chunk.isEmpty, !isClosed else { return [] }
        raw.append(contentsOf: chunk)
        var events: [Event] = []
        for token in tokenizer.feed(chunk) where !isClosed {
            append(token, to: &events)
        }
        return events
    }

    private mutating func append(_ token: JSONStreamTokenizer.Token, to events: inout [Event]) {
        switch token.kind {
        case let .key(name):
            if !stack.isEmpty, stack[stack.count - 1].isObject {
                if stack.count == 1 {
                    sawRootKey = true
                }
                stack[stack.count - 1].pendingKey = name
                if stack.count == 1, Self.overviewKeys.contains(name), sawOverviewValue {
                    sawOverviewValue = false
                    events.append(.overviewRestarted)
                }
            }

        case .objectStart, .arrayStart:
            if token.kind == .objectStart, let kind = elementKind() {
                captureStart = token.endOffset - 1
                captureNesting = 0
                captureKind = kind
            } else if captureStart != nil {
                captureNesting += 1
            }
            stack.append(
                Frame(isObject: token.kind == .objectStart, key: stack.last?.pendingKey, pendingKey: nil)
            )

        case .objectEnd, .arrayEnd:
            closeContainer(endOffset: token.endOffset, into: &events)

        case let .stringDelta(text):
            if isStreamingOverview() {
                sawOverviewValue = true
                events.append(.overviewDelta(text))
            }

        case .stringEnd, .scalar:
            clearPendingKey()
        }
    }

    private mutating func closeContainer(endOffset: Int, into events: inout [Event]) {
        if captureStart != nil {
            if captureNesting > 0 {
                captureNesting -= 1
            } else {
                if let start = captureStart, start < endOffset {
                    let slice = String(raw[start ..< endOffset])
                    switch captureKind {
                    case .pointCompleted: events.append(.pointCompleted(slice))
                    case .todoCompleted: events.append(.todoCompleted(slice))
                    default: break
                    }
                }
                captureStart = nil
                captureKind = nil
            }
        }
        _ = stack.popLast()
        if stack.isEmpty {
            // `使用 {} 表示对象：{…}` is prose, not an answer. Only a root object that had
            // keys ends the run.
            isClosed = sawRootKey
            return
        }
        clearPendingKey()
    }

    private mutating func clearPendingKey() {
        guard !stack.isEmpty, stack[stack.count - 1].isObject else { return }
        stack[stack.count - 1].pendingKey = nil
    }

    /// True while reading the value of the overview key directly inside the root object.
    private func isStreamingOverview() -> Bool {
        guard stack.count == 1, stack[0].isObject, let key = stack[0].pendingKey else { return false }
        return Self.overviewKeys.contains(key)
    }

    /// Which list this object belongs to, when it is an element of a known root array.
    private func elementKind() -> Event? {
        guard stack.count == 2, !stack[1].isObject, let key = stack[1].key else { return nil }
        if Self.pointKeys.contains(key) {
            return .pointCompleted("")
        }
        if Self.todoKeys.contains(key) {
            return .todoCompleted("")
        }
        return nil
    }
}

/// Minimal incremental JSON tokenizer: containers, keys, and streamed string content,
/// each token carrying how many characters have been consumed so far so a caller can slice
/// raw element text out of what it fed in.
struct JSONStreamTokenizer {
    struct Token: Equatable {
        enum Kind: Equatable {
            case objectStart
            case objectEnd
            case arrayStart
            case arrayEnd
            case key(String)
            case stringDelta(String)
            case stringEnd
            /// Numbers, booleans and null. Their content is never needed.
            case scalar
        }

        var kind: Kind
        /// Number of characters consumed, counting from the first character ever fed.
        var endOffset: Int = 0
    }

    private enum Container {
        case object
        case array
    }

    private var containers: [Container] = []
    private var offset = 0

    private var inString = false
    private var escaping = false
    private var pendingUnicode: String?
    private var highSurrogate: UInt32?
    private var decoded = ""
    private var stringIsKey = false
    /// A string right after `{` or a comma inside an object is a key; anything else is a value.
    private var expectingKey = false
    private var inScalar = false

    mutating func feed(_ chunk: String) -> [Token] {
        var tokens: [Token] = []
        for character in chunk {
            offset += 1
            step(character, into: &tokens)
        }
        flushDecoded(into: &tokens)
        return tokens
    }

    private mutating func step(_ character: Character, into tokens: inout [Token]) {
        if inString {
            stepInString(character, into: &tokens)
            return
        }
        switch character {
        case "{":
            flushDecoded(into: &tokens)
            inScalar = false
            tokens.append(Token(kind: .objectStart, endOffset: offset))
            containers.append(.object)
            expectingKey = true
        case "[":
            flushDecoded(into: &tokens)
            inScalar = false
            tokens.append(Token(kind: .arrayStart, endOffset: offset))
            containers.append(.array)
            expectingKey = false
        case "}":
            flushDecoded(into: &tokens)
            inScalar = false
            tokens.append(Token(kind: .objectEnd, endOffset: offset))
            close(.object)
        case "]":
            flushDecoded(into: &tokens)
            inScalar = false
            tokens.append(Token(kind: .arrayEnd, endOffset: offset))
            close(.array)
        case "\"":
            flushDecoded(into: &tokens)
            inScalar = false
            inString = true
            escaping = false
            // A surrogate pair cannot span two strings.
            highSurrogate = nil
            stringIsKey = expectingKey
        case ":":
            inScalar = false
            expectingKey = false
        case ",":
            inScalar = false
            expectingKey = containers.last == .object
        case " ", "\n", "\t", "\r":
            break
        default:
            if !inScalar {
                inScalar = true
                tokens.append(Token(kind: .scalar, endOffset: offset))
            }
        }
    }

    private mutating func stepInString(_ character: Character, into tokens: inout [Token]) {
        if let digits = pendingUnicode {
            guard character.isHexDigit else {
                // Not a unicode escape after all. Keep what was read and carry on.
                decoded += "\\u" + digits + String(character)
                pendingUnicode = nil
                return
            }
            let combined = digits + String(character)
            if combined.count < 4 {
                pendingUnicode = combined
                return
            }
            pendingUnicode = nil
            decoded += Self.decodeUnicodeEscape(combined, highSurrogate: &highSurrogate)
            return
        }
        if escaping {
            escaping = false
            switch character {
            case "n": decoded += "\n"
            case "t": decoded += "\t"
            case "r": decoded += "\r"
            case "b": decoded += "\u{8}"
            case "f": decoded += "\u{c}"
            case "u": pendingUnicode = ""
            default: decoded += String(character)
            }
            return
        }
        switch character {
        case "\\":
            escaping = true
        case "\"":
            inString = false
            highSurrogate = nil
            let finished = decoded
            decoded = ""
            if stringIsKey {
                tokens.append(Token(kind: .key(finished), endOffset: offset))
            } else {
                if !finished.isEmpty {
                    tokens.append(Token(kind: .stringDelta(finished), endOffset: offset))
                }
                tokens.append(Token(kind: .stringEnd, endOffset: offset))
            }
            expectingKey = containers.last == .object
        default:
            decoded += String(character)
        }
    }

    /// Emits the text decoded so far so callers see string content while it streams.
    /// Keys are held back: a key is only known to be a key once it is complete.
    private mutating func flushDecoded(into tokens: inout [Token]) {
        guard !decoded.isEmpty, !stringIsKey else { return }
        tokens.append(Token(kind: .stringDelta(decoded), endOffset: offset))
        decoded = ""
    }

    private mutating func close(_ container: Container) {
        if let index = containers.lastIndex(of: container) {
            containers.removeSubrange(index ..< containers.count)
        }
        expectingKey = containers.last == .object
    }

    private static func decodeUnicodeEscape(_ digits: String, highSurrogate: inout UInt32?) -> String {
        guard let value = UInt32(digits, radix: 16) else { return "" }
        if (0xD800 ... 0xDBFF).contains(value) {
            highSurrogate = value
            return ""
        }
        if (0xDC00 ... 0xDFFF).contains(value) {
            guard let high = highSurrogate else { return "" }
            highSurrogate = nil
            let combined = 0x10000 + ((high - 0xD800) << 10) + (value - 0xDC00)
            return UnicodeScalar(combined).map(String.init) ?? ""
        }
        return UnicodeScalar(value).map(String.init) ?? ""
    }
}
