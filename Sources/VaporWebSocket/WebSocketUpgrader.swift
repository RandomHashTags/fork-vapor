import NIOCore
import NIOHTTP1
import NIOWebSocket
import VaporHTTP
import WebSocketKit

/// Handles upgrading an HTTP connection to a WebSocket
public struct WebSocketUpgrader: Upgrader, Sendable {
    var maxFrameSize: WebSocketMaxFrameSize
    var shouldUpgrade: (@Sendable () -> EventLoopFuture<HTTPHeaders?>)
    var onUpgrade: @Sendable (WebSocket) -> ()
    
    @preconcurrency public init(maxFrameSize: WebSocketMaxFrameSize, shouldUpgrade: @escaping (@Sendable () -> EventLoopFuture<HTTPHeaders?>), onUpgrade: @Sendable @escaping (WebSocket) -> ()) {
        self.maxFrameSize = maxFrameSize
        self.shouldUpgrade = shouldUpgrade
        self.onUpgrade = onUpgrade
    }
    
    public func applyUpgrade(req: Request, res: Response) -> HTTPServerProtocolUpgrader {
        let webSocketUpgrader = NIOWebSocketServerUpgrader(maxFrameSize: self.maxFrameSize.value, automaticErrorHandling: false, shouldUpgrade: { _, _ in
            return self.shouldUpgrade()
        }, upgradePipelineHandler: { channel, req in
            return WebSocket.server(on: channel, onUpgrade: self.onUpgrade)
        })
        
        return webSocketUpgrader
    }
}