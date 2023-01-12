import Foundation
import WolfBase
import SecureComponents

/// Support for the various text output formats for ``Envelope``.

public extension Envelope {
    /// Returns the envelope notation for this envelope.
    ///
    /// See <doc:Notation> for a description of envelope notation.
    var format: String {
        formatItem.format.trim()
    }

    /// Returns the CBOR diagnostic notation for this envelope.
    ///
    /// See [RFC-8949 §8](https://www.rfc-editor.org/rfc/rfc8949.html#name-diagnostic-notation)
    /// for information on CBOR diagnostic notation.
    var diag: String {
        taggedCBOR.diag
    }

    /// Returns the annotated CBOR diagnostic notation for this envelope.
    ///
    /// See [RFC-8949 §8](https://www.rfc-editor.org/rfc/rfc8949.html#name-diagnostic-notation)
    /// for information on CBOR diagnostic notation.
    ///
    /// Includes comments for tags in the known tags registry. See `SecureComponents.CBOR.setKnownTag(_:)`.
    var diagAnnotated: String {
        taggedCBOR.diagAnnotated
    }

    /// Returns the CBOR hex dump of this envelope.
    ///
    /// See [RFC-8949](https://www.rfc-editor.org/rfc/rfc8949.html) for information on
    /// the CBOR binary format.
    var dump: String {
        taggedCBOR.dump
    }
}

protocol EnvelopeFormat {
    var formatItem: EnvelopeFormatItem { get }
}

extension Digest: EnvelopeFormat {
    var formatItem: EnvelopeFormatItem {
        return .item(data.prefix(8).hex)
    }
}

extension CID: EnvelopeFormat {
    var formatItem: EnvelopeFormatItem {
        return .item(data.hex)
    }
}

extension Envelope.Assertion: EnvelopeFormat {
    var formatItem: EnvelopeFormatItem {
        .list([predicate.formatItem, ": ", object.formatItem])
    }
}

extension Envelope.KnownValue: EnvelopeFormat {
    var formatItem: EnvelopeFormatItem {
        .item(name)
    }
}

extension CBOR {
    func envelopeSummary(maxLength: Int = .max) -> String {
        do {
            switch self {
            case .boolean(let b):
                return b.description
            case .unsignedInt(let n):
                return String(n)
            case .negativeInt(let n):
                return String(-Int(n) - 1)
            case .float(let n):
                return String(n)
            case .double(let n):
                return String(n)
            case .utf8String(let string):
                return (string.count > maxLength ? string.prefix(count: maxLength).trim() + "…" : string).flanked(.quote)
            case .date(let date):
                var s = date.ISO8601Format()
                if s.count == 20 && s.hasSuffix("T00:00:00Z") {
                    s = s.prefix(count: 10)
                }
                return s
            case .data(let data):
                return "Data(\(data.count))"
            case CBOR.tagged(.envelope, _):
                return "Envelope"
            case CBOR.tagged(.knownValue, let cbor):
                guard
                    case let CBOR.unsignedInt(rawValue) = cbor,
                    case let predicate = Envelope.KnownValue(rawValue: rawValue)
                else {
                    return "<not a known value>"
                }
                return predicate†
            case CBOR.tagged(.signature, _):
                return "Signature"
            case CBOR.tagged(.nonce, _):
                return "Nonce"
            case CBOR.tagged(.salt, _):
                return "Salt"
            case CBOR.tagged(.sealedMessage, _):
                return "SealedMessage"
            case CBOR.tagged(.sskrShare, _):
                return "SSKRShare"
            case CBOR.tagged(.publicKeyBase, _):
                return "PublicKeyBase"
            case CBOR.tagged(.cid, _):
                return try CID(taggedCBOR: self).shortDescription.flanked("CID(", ")")
            case CBOR.tagged(.uri, _):
                return try URL(taggedCBOR: self)†.flanked("URI(", ")")
            case CBOR.tagged(.uuid, _):
                return try UUID(taggedCBOR: self)†.flanked("UUID(", ")")
            case CBOR.tagged(.digest, _):
                return try Digest(taggedCBOR: self).shortDescription.flanked("Digest(", ")")
            case CBOR.tagged(.cid, _):
                return try CID(taggedCBOR: self)†
            case CBOR.tagged(CBOR.Tag.function, _):
                return try Envelope.FunctionIdentifier(taggedCBOR: self)†.flanked("«", "»")
            case CBOR.tagged(CBOR.Tag.parameter, _):
                return try Envelope.ParameterIdentifier(taggedCBOR: self)†.flanked("❰", "❱")
            case CBOR.tagged(CBOR.Tag.request, let cbor):
                return Envelope(cbor).format.flanked("request(", ")")
            case CBOR.tagged(CBOR.Tag.response, let cbor):
                return Envelope(cbor).format.flanked("response(", ")")
            case CBOR.tagged(let tag, let innerCBOR):
                let name = CBOR.Tag.knownTag(for: tag.rawValue)?.name ?? tag.name ?? String(tag.rawValue)
                return "\(name)(\(innerCBOR.envelopeSummary(maxLength: maxLength)))"
            case CBOR.array(let elements):
                return elements.map { $0.envelopeSummary(maxLength: maxLength) }.joined(separator: ", ").flanked("[", "]")
            default:
                return "CBOR"
            }
        } catch {
            return "<error>"
        }
    }
}

extension CBOR: EnvelopeFormat {
    var formatItem: EnvelopeFormatItem {
        do {
            switch self {
            case CBOR.tagged(.envelope, _):
                return try Envelope(taggedCBOR: cbor).formatItem
            default:
                return .item(envelopeSummary())
            }
        } catch {
            return "<error>"
        }
    }
}

extension Envelope: EnvelopeFormat {
    var formatItem: EnvelopeFormatItem {
        switch self {
        case .leaf(let cbor, _):
            return cbor.formatItem
        case .knownValue(let predicate, _):
            return predicate.formatItem
        case .wrapped(let envelope, _):
            return .list([.begin("{"), envelope.formatItem, .end("}")])
        case .assertion(let assertion):
            return assertion.formatItem
        case .encrypted(_):
            return .item("ENCRYPTED")
        case .node(subject: let subject, assertions: let assertions, digest: _):
            var items: [EnvelopeFormatItem] = []

            let subjectItem = subject.formatItem
            var elidedCount = 0
            var encryptedCount = 0
            var assertionsItems: [[EnvelopeFormatItem]] = []
            assertions.forEach {
                if $0.isElided {
                    elidedCount += 1
                } else if $0.isEncrypted {
                    encryptedCount += 1
                } else {
                    assertionsItems.append([$0.formatItem])
                }
            }
            assertionsItems.sort { $0.lexicographicallyPrecedes($1) }
            if elidedCount > 1 {
                assertionsItems.append([.item("ELIDED (\(elidedCount))")])
            } else if elidedCount > 0 {
                assertionsItems.append([.item("ELIDED")])
            }
            if encryptedCount > 1 {
                assertionsItems.append([.item("ENCRYPTED (\(encryptedCount))")])
            } else if encryptedCount > 0 {
                assertionsItems.append([.item("ENCRYPTED")])
            }
            let joinedAssertionsItems = Array(assertionsItems.joined(separator: [.separator]))

            let needsBraces: Bool = subject.isSubjectAssertion
            
            if needsBraces {
                items.append(.begin("{"))
            }
            items.append(subjectItem)
            if needsBraces {
                items.append(.end("}"))
            }
            items.append(.begin("["))
            items.append(.list(joinedAssertionsItems))
            items.append(.end("]"))

            return .list(items)
        case .elided:
            return .item("ELIDED")
        }
    }
}

enum EnvelopeFormatItem {
    case begin(String)
    case end(String)
    case item(String)
    case separator
    case list([EnvelopeFormatItem])
}

extension EnvelopeFormatItem: ExpressibleByStringLiteral {
    init(stringLiteral value: StringLiteralType) {
        self = .item(value)
    }
}

extension EnvelopeFormatItem: CustomStringConvertible {
    var description: String {
        switch self {
        case .begin(let string):
            return ".begin(\(string))"
        case .end(let string):
            return ".end(\(string))"
        case .item(let string):
            return ".item(\(string))"
        case .separator:
            return ".separator"
        case .list(let list):
            return ".list(\(list))"
        }
    }
}

extension EnvelopeFormatItem {
    var flatten: [EnvelopeFormatItem] {
        if case let .list(items) = self {
            return items.map { $0.flatten }.flatMap { $0 }
        } else {
            return [self]
        }
    }
    
    func nicen(_ items: [EnvelopeFormatItem]) -> [EnvelopeFormatItem] {
        var input = items
        var result: [EnvelopeFormatItem] = []
        
        while !input.isEmpty {
            let current = input.removeFirst()
            if input.isEmpty {
                result.append(current)
                break
            }
            if case .end(let endString) = current {
                if case .begin(let beginString) = input.first! {
                    result.append(.end("\(endString) \(beginString)"))
                    result.append(.begin(""))
                    input.removeFirst()
                } else {
                    result.append(current)
                }
            } else {
                result.append(current)
            }
        }
        
        return result
    }
    
    func indent(_ level: Int) -> String {
        String(repeating: " ", count: level * 4)
    }
    
    private func addSpaceAtEndIfNeeded(_ s: String) -> String {
        guard !s.isEmpty else {
            return " "
        }
        if s.last! == " " {
            return s
        } else {
            return s + " "
        }
    }
    
    var format: String {
        var lines: [String] = []
        var level = 0
        var currentLine = ""
        let items = nicen(flatten)
        for item in items {
            switch item {
            case .begin(let string):
                if !string.isEmpty {
                    let c = currentLine.isEmpty ? string : addSpaceAtEndIfNeeded(currentLine) + string
                    lines.append(indent(level) + c + .newline)
                }
                level += 1
                currentLine = ""
            case .end(let string):
                if !currentLine.isEmpty {
                    lines.append(indent(level) + currentLine + .newline)
                    currentLine = ""
                }
                level -= 1
                lines.append(indent(level) + string + .newline)
            case .item(let string):
                currentLine += string
            case .separator:
                if !currentLine.isEmpty {
                    lines.append(indent(level) + currentLine + .newline)
                    currentLine = ""
                }
            case .list:
                lines.append("<list>")
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        return lines.joined()
    }
}

extension EnvelopeFormatItem: Equatable {
    static func ==(lhs: EnvelopeFormatItem, rhs: EnvelopeFormatItem) -> Bool {
        if case let .begin(l) = lhs, case let .begin(r) = rhs, l == r { return true }
        if case let .end(l) = lhs, case let .end(r) = rhs, l == r { return true }
        if case let .item(l) = lhs, case let .item(r) = rhs, l == r { return true }
        if case .separator = lhs, case .separator = rhs { return true }
        if case let .list(l) = lhs, case let .list(r) = rhs, l == r { return true }
        return false
    }
}

extension EnvelopeFormatItem {
    var index: Int {
        switch self {
        case .begin:
            return 1
        case .end:
            return 2
        case .item:
            return 3
        case .separator:
            return 4
        case .list:
            return 5
        }
    }
}

extension EnvelopeFormatItem: Comparable {
    static func <(lhs: EnvelopeFormatItem, rhs: EnvelopeFormatItem) -> Bool {
        let lIndex = lhs.index
        let rIndex = rhs.index
        if lIndex < rIndex {
            return true
        } else if rIndex < lIndex {
            return false
        }
        if case let .begin(l) = lhs, case let .begin(r) = rhs, l < r { return true }
        if case let .end(l) = lhs, case let .end(r) = rhs, l < r { return true }
        if case let .item(l) = lhs, case let .item(r) = rhs, l < r { return true }
        if case .separator = lhs, case .separator = rhs { return false }
        if case let .list(l) = lhs, case let .list(r) = rhs, l.lexicographicallyPrecedes(r) { return true }
        return false
    }
}