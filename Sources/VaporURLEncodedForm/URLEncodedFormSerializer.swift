import struct Foundation.CharacterSet

package struct URLEncodedFormSerializer: Sendable {
    package let splitVariablesOn: Character
    package let splitKeyValueOn: Character

    /// Create a new form-urlencoded data parser.
    package init(splitVariablesOn: Character = "&", splitKeyValueOn: Character = "=") {
        self.splitVariablesOn = splitVariablesOn
        self.splitKeyValueOn = splitKeyValueOn
    }

    package struct _CodingKey: CodingKey {
        package var stringValue: String

        package init(stringValue: String) {
            self.stringValue = stringValue
        }

        package var intValue: Int?

        package init?(intValue: Int) {
            self.intValue = intValue
            self.stringValue = intValue.description
        }
    }
}

extension Array where Element == CodingKey {
    package func toURLEncodedKey() throws -> String {
        if count < 1 {
            return ""
        }
        return try self[0].stringValue.urlEncoded(codingPath: self) + self[1...].map { (key: CodingKey) -> String in
            try "[" + key.stringValue.urlEncoded(codingPath: self) + "]"
        }.joined()
    }
}

// MARK: Utilities

extension String {
    /// Prepares a `String` for inclusion in form-urlencoded data.
    package func urlEncoded(codingPath: [CodingKey] = []) throws -> String {
        guard let result = self.addingPercentEncoding(
            withAllowedCharacters: Characters.allowedCharacters
        ) else {
            throw EncodingError.invalidValue(self, EncodingError.Context(
                codingPath: codingPath,
                debugDescription: "Unable to add percent encoding to \(self)"
            ))
        }
        return result
    }
}

/// Characters allowed in form-urlencoded data.
private enum Characters {
    // https://url.spec.whatwg.org/#application-x-www-form-urlencoded-percent-encode-set
    package static let allowedCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "*-._")
        return allowed
    }()
}
