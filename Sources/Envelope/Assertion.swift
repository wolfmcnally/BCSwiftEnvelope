import Foundation
import SecureComponents

public extension Envelope {
    /// Represents an assertion in an envelope.
    ///
    /// This structure is public but opaque, and the APIs on ``Envelope`` itself should be used to manipulate it.
    struct Assertion {
        let predicate: Envelope
        let object: Envelope
        let digest: Digest
        
        /// Creates an ``Assertion`` and calculates its digest.
        init(predicate: Any, object: Any) {
            let p: Envelope
            if let predicate = predicate as? Envelope {
                p = predicate
            } else {
                p = Envelope(predicate)
            }
            let o: Envelope
            if let object = object as? Envelope {
                o = object
            } else {
                o = Envelope(object)
            }
            self.predicate = p
            self.object = o
            self.digest = Digest(p.digest + o.digest)
        }
    }
}

extension Envelope.Assertion {
    var untaggedCBOR: CBOR {
        [predicate.cbor, object.cbor]
    }
    
    var taggedCBOR: CBOR {
        CBOR.tagged(.assertion, untaggedCBOR)
    }
    
    init(untaggedCBOR: CBOR) throws {
        guard
            case CBOR.array(let array) = untaggedCBOR,
            array.count == 2
        else {
            throw CBORError.invalidFormat
        }
        let predicate = try Envelope.cborDecode(array[0])
        let object = try Envelope.cborDecode(array[1])
        self.init(predicate: predicate, object: object)
    }
}

extension Envelope.Assertion: Equatable {
    public static func ==(lhs: Envelope.Assertion, rhs: Envelope.Assertion) -> Bool {
        lhs.digest == rhs.digest
    }
}
