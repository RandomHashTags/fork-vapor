
/// Errors thrown while encoding/decoding `application/x-www-form-urlencoded` data.
package enum URLEncodedFormError: Error {
    case malformedKey(key: Substring)
    case reachedNestingLimit
}