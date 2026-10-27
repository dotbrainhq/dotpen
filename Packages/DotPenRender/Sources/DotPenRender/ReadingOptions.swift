import Foundation

/// The Aa settings. Stored as JSON so it works with @AppStorage.
public struct ReadingOptions: Codable, Equatable, Sendable {
    public enum Size: String, Codable, CaseIterable, Sendable { case small, medium, large, extraLarge }
    public enum Font: String, Codable, CaseIterable, Sendable { case serif, sans, mono }
    public enum Width: String, Codable, CaseIterable, Sendable { case narrow, medium, wide }
    public enum Paper: String, Codable, CaseIterable, Sendable { case auto, white, paper, night }

    public var size: Size
    public var font: Font
    public var width: Width
    public var paper: Paper
    /// Long code lines wrap inside their block instead of scrolling sideways.
    public var wrapCode: Bool

    public init(size: Size = .medium, font: Font = .serif, width: Width = .medium, paper: Paper = .auto, wrapCode: Bool = false) {
        self.size = size
        self.font = font
        self.width = width
        self.paper = paper
        self.wrapCode = wrapCode
    }

    // Written out on purpose: with RawRepresentable below, Swift's built-in Codable would encode through
    // rawValue, which encodes through Codable again, and recurse until the stack overflows.
    private enum CodingKeys: String, CodingKey { case size, font, width, paper, wrapCode }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(Size.self, forKey: .size) ?? .medium
        font = try container.decodeIfPresent(Font.self, forKey: .font) ?? .serif
        width = try container.decodeIfPresent(Width.self, forKey: .width) ?? .medium
        paper = try container.decodeIfPresent(Paper.self, forKey: .paper) ?? .auto
        wrapCode = try container.decodeIfPresent(Bool.self, forKey: .wrapCode) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(size, forKey: .size)
        try container.encode(font, forKey: .font)
        try container.encode(width, forKey: .width)
        try container.encode(paper, forKey: .paper)
        try container.encode(wrapCode, forKey: .wrapCode)
    }
}

extension ReadingOptions: RawRepresentable {
    public init?(rawValue: String) {
        guard let value = try? JSONDecoder().decode(ReadingOptions.self, from: Data(rawValue.utf8)) else { return nil }
        self = value
    }

    public var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? String(decoding: encoder.encode(self), as: UTF8.self)) ?? "{}"
    }
}
