import FoundationEssentials

public protocol RoutesBuilder {
    func add(_ route: Route)
}

extension FoundationEssentials.UUID: Swift.LosslessStringConvertible {
    public init?(_ description: String) {
        self.init(uuidString: description)
    }
}
