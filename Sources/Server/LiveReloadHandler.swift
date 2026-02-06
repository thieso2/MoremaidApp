import Foundation
import FlyingFox

/// Tracks connected WebSocket clients and broadcasts reload messages.
actor ClientRegistry {
    static let shared = ClientRegistry()

    private var continuations: [UUID: AsyncStream<WSMessage>.Continuation] = [:]

    func register(id: UUID, continuation: AsyncStream<WSMessage>.Continuation) {
        continuations[id] = continuation
    }

    func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    func broadcast(_ message: WSMessage) {
        for (_, continuation) in continuations {
            continuation.yield(message)
        }
    }

    var clientCount: Int {
        continuations.count
    }
}

/// FlyingFox WebSocket handler for live reload.
struct LiveReloadHandler: WSMessageHandler {
    func makeMessages(for client: AsyncStream<WSMessage>) async throws -> AsyncStream<WSMessage> {
        let clientID = UUID()
        let registry = ClientRegistry.shared

        let (outgoing, continuation) = AsyncStream<WSMessage>.makeStream()
        await registry.register(id: clientID, continuation: continuation)

        // Process incoming messages from the client in background
        Task {
            for await message in client {
                switch message {
                case .text(let text):
                    if text == "ping" {
                        // Client keepalive — respond with pong
                        continuation.yield(.text("pong"))
                    }
                case .close:
                    break
                default:
                    break
                }
            }
            // Client disconnected
            await registry.unregister(id: clientID)
            continuation.finish()
        }

        return outgoing
    }
}
