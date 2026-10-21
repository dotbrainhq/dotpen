import Foundation
import Network

/// The agent bridge: an MCP server over HTTP on 127.0.0.1. Claude Code, Codex and other agents connect to
/// http://127.0.0.1:<port>/mcp, list the open comments and resolve them once they're done.
public final class BridgeServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 47319

    private let tools: MCPTools
    private let queue = DispatchQueue(label: "app.dotmd.bridge")
    /// Touched only on the queue.
    private var listener: NWListener?

    public init(tools: MCPTools) {
        self.tools = tools
    }

    /// Listens on 127.0.0.1 only, so nothing off this Mac can reach it. Returns the port, which is a free one when
    /// port is 0.
    public func start(port: UInt16 = defaultPort) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.listener?.cancel()
                self.listener = listener
                let waiter = Waiter(continuation)
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        waiter.finish(.success(listener.port?.rawValue ?? port))
                    case let .failed(error), let .waiting(error):
                        listener.cancel()
                        waiter.finish(.failure(error))
                    default:
                        break
                    }
                }
                listener.start(queue: self.queue)
            }
        }
    }

    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequest.parse(buffer) {
            case .incomplete:
                guard !isComplete, error == nil else { return connection.cancel() }
                receive(on: connection, buffer: buffer)
            case .invalid:
                send(HTTPResponse(status: 400), on: connection)
            case let .complete(request):
                Task {
                    let response = await respond(to: request)
                    send(response, on: connection)
                }
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.data, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// One MCP message over Streamable HTTP. There is no event stream: every answer is a plain JSON response.
    func respond(to request: HTTPRequest) async -> HTTPResponse {
        // A web page can't reach the bridge by renaming a host to 127.0.0.1, or by posting from another origin.
        guard Self.isLocal(host: request.headers["host"]),
              request.headers["origin"].map({ Self.isLocal(host: URL(string: $0)?.host) }) ?? true else {
            return HTTPResponse(status: 403)
        }
        guard request.path.split(separator: "?").first == "/mcp" else { return HTTPResponse(status: 404) }
        guard request.method == "POST" else { return HTTPResponse(status: 405, headers: [("Allow", "POST")]) }
        guard let message = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            var response = HTTPResponse.json(MCPTools.error(id: nil, code: -32700, message: "Parse error"))
            response.status = 400
            return response
        }
        guard let reply = await tools.respond(to: message) else { return HTTPResponse(status: 202) }
        return .json(reply)
    }

    /// The start call waiting for the listener, resumed once. Touched only on the queue.
    private final class Waiter: @unchecked Sendable {
        private var continuation: CheckedContinuation<UInt16, Error>?

        init(_ continuation: CheckedContinuation<UInt16, Error>) {
            self.continuation = continuation
        }

        func finish(_ result: Result<UInt16, Error>) {
            continuation?.resume(with: result)
            continuation = nil
        }
    }

    static func isLocal(host: String?) -> Bool {
        guard var host else { return false }
        if host.hasPrefix("["), let close = host.firstIndex(of: "]") {
            host = String(host[host.index(after: host.startIndex)..<close])
        } else if let colon = host.lastIndex(of: ":"), host.firstIndex(of: ":") == colon {
            host = String(host[..<colon])
        }
        return ["127.0.0.1", "localhost", "::1"].contains(host.lowercased())
    }
}
