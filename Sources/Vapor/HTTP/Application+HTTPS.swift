extension Application {
    public var https: HTTPS {
        .init(application: self)
    }

    public struct HTTPS {
        public let application: Application

        public var client: Client {
            application.client
        }
    }
}
