import Foundation

/// The built renderer copied into this package's bundle.
public enum RendererResources {
    public static var directory: URL {
        guard let url = Bundle.module.url(forResource: "renderer", withExtension: nil) else {
            preconditionFailure("Renderer missing. Run `cd renderer && npm run build`.")
        }
        return url
    }

    public static var indexHTML: URL { directory.appending(path: "index.html") }
    public static var stylesheet: URL { directory.appending(path: "styles.css") }
    public static var fontsDirectory: URL { directory.appending(path: "fonts") }
}
