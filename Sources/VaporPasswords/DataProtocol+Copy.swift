import FoundationEssentials

extension DataProtocol {
    package func copyBytes() -> [UInt8] {
        Array(self)
    }
}
