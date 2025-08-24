import Logging
import VaporURLEncodedForm

extension URLQueryFragment {

    /// Returns the URL Encoded version
    func asUrlEncoded() throws -> String {
        switch self {
        case .urlEncoded(let encoded):
            return encoded
        case .urlDecoded(let decoded):
            return try decoded.urlEncoded()
        }
    }
    
    func hash(into: inout Hasher) {
        do {
            try self.asUrlDecoded().hash(into: &into)
        } catch {
            Logger(label: "codes.vapor.url").report(error: error)
        }
    }
}
