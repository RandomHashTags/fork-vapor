import FoundationEssentials
import VaporPasswords

package struct BcryptHasher: PasswordHasher {
    let cost: Int
    
    package init(cost: Int) {
        self.cost = cost
    }

    package func hash<Password>(
        _ password: Password
    ) throws -> [UInt8]
        where Password: DataProtocol
    {
        let string = String(decoding: password, as: UTF8.self)
        let digest = try Bcrypt.hash(string, cost: self.cost)
        return .init(digest.utf8)
    }

    package func verify<Password, Digest>(
        _ password: Password,
        created digest: Digest
    ) throws -> Bool
        where Password: DataProtocol, Digest: DataProtocol
    {
        try Bcrypt.verify(
            String(decoding: password.copyBytes(), as: UTF8.self),
            created: String(decoding: digest.copyBytes(), as: UTF8.self)
        )
    }
}
