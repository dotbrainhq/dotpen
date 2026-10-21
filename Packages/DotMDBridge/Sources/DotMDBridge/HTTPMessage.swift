import Foundation

/// An HTTP/1.1 request, as much of it as the bridge reads.
struct HTTPRequest: Equatable, Sendable {
    enum Parse: Equatable {
        case incomplete
        case invalid
        case complete(HTTPRequest)
    }

    var method: String
    var path: String
    /// Header names in lowercase.
    var headers: [String: String]
    var body: Data

    /// The largest request the bridge reads. MCP requests from an agent are a few hundred bytes.
    static let limit = 1 << 20

    static func parse(_ data: Data) -> Parse {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return data.count > limit ? .invalid : .incomplete
        }
        let lines = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard (0...limit).contains(length) else { return .invalid }
        let body = data[end.upperBound...]
        guard body.count >= length else { return .incomplete }
        return .complete(HTTPRequest(method: String(parts[0]), path: String(parts[1]), headers: headers, body: Data(body.prefix(length))))
    }
}

/// An HTTP/1.1 response. The bridge closes the connection after each one.
struct HTTPResponse: Equatable, Sendable {
    var status: Int
    var headers: [(String, String)] = []
    var body = Data()

    static func == (a: HTTPResponse, b: HTTPResponse) -> Bool {
        a.status == b.status && a.body == b.body && a.headers.map { "\($0.0): \($0.1)" } == b.headers.map { "\($0.0): \($0.1)" }
    }

    static func json(_ object: Any) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return HTTPResponse(status: 200, headers: [("Content-Type", "application/json")], body: body)
    }

    var data: Data {
        var head = "HTTP/1.1 \(status) \(Self.reasons[status] ?? "Error")\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    private static let reasons = [
        200: "OK", 202: "Accepted", 400: "Bad Request", 403: "Forbidden",
        404: "Not Found", 405: "Method Not Allowed", 413: "Content Too Large",
    ]
}
