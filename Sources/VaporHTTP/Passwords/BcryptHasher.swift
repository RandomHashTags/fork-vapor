import FoundationEssentials
import VaporBcrypt

extension Application.Passwords.Provider {
    public static var bcrypt: Self {
        .bcrypt(cost: 12)
    }
    
    public static func bcrypt(cost: Int) -> Self {
        .init {
            $0.passwords.use { _ in
                BcryptHasher(cost: cost)
            }
        }
    }
}