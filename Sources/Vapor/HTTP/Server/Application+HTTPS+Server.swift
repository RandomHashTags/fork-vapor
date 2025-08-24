extension Application.Servers.Provider {
    public static var https: Self {
        .init {
            $0.servers.use { $0.http.server.shared }
        }
    }
}

extension Application.HTTPS {
    public var server: Server {
        .init(application: self.application)
    }
    
    public struct Server: Sendable {
        let application: Application

        public var shared: HTTPSServer {
            if let existing = self.application.storage[Key.self] {
                return existing
            } else {
                let new = HTTPSServer.init(
                    application: self.application,
                    responder: self.application.responder.current,
                    configuration: self.configuration,
                    on: self.application.eventLoopGroup
                )
                self.application.storage[Key.self] = new
                return new
            }
        }

        struct Key: StorageKey, Sendable {
            typealias Value = HTTPSServer
        }

        /// The configuration for the HTTP server.
        ///
        /// Although the configuration can be changed after the server has started, a warning will be logged
        /// and the configuration will be discarded if an option will no longer be considered.
        /// 
        /// These include the following properties, which are only read once when the server starts:
        /// - ``HTTPServer/Configuration-swift.struct/address``
        /// - ``HTTPServer/Configuration-swift.struct/hostname``
        /// - ``HTTPServer/Configuration-swift.struct/port``
        /// - ``HTTPServer/Configuration-swift.struct/backlog``
        /// - ``HTTPServer/Configuration-swift.struct/reuseAddress``
        /// - ``HTTPServer/Configuration-swift.struct/tcpNoDelay``
        public var configuration: HTTPSServer.Configuration {
            get {
                self.application.storage[ConfigurationKey.self] ?? .init(
                    logger: self.application.logger
                )
            }
            nonmutating set {
                /// If a server is available, configure it directly, otherwise cache a configuration instance
                /// here to be used until the server is instantiated.
                if let server = self.application.storage[Key.self] {
                    server.configuration = newValue
                } else {
                    self.application.storage[ConfigurationKey.self] = newValue
                }
            }
        }

        package struct ConfigurationKey: StorageKey, Sendable {
            package typealias Value = HTTPSServer.Configuration
        }
    }
}
