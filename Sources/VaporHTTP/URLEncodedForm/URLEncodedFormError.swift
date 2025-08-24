import NIOHTTP1
import VaporURLEncodedForm

extension URLEncodedFormError: AbortError {
    package var status: HTTPResponseStatus {
        .badRequest
    }

    package var reason: String {
        switch self {
        case .malformedKey(let path):
            return "Malformed form-urlencoded key encountered: \(path)"
        case .reachedNestingLimit:
            return "The data supplied is too nested"
        }
    }
}
