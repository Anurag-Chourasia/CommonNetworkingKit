import Foundation

/// A domain-agnostic protocol for caching raw image data.
/// Decoupled from UI frameworks (handles raw `Data`, not `UIImage`/`NSImage`).
public protocol ImageDataCaching: Sendable {
    func data(for url: URL) async -> Data?
    func store(_ data: Data, for url: URL) async
    func removeData(for url: URL) async
    func clear() async
}

/// A thread-safe, two-tier (memory + disk) image data cache.
public actor PersistentImageDataCache: ImageDataCaching {
    private let memoryCache: NSCache<NSURL, NSData>
    private let fileManager: FileManager
    private let diskDirectory: URL?

    public init(
        memoryCapacityBytes: Int = 50 * 1024 * 1024,
        diskDirectoryName: String = "CommonNetworkingKit.ImageCache",
        fileManager: FileManager = .default
    ) {
        let cache = NSCache<NSURL, NSData>()
        cache.totalCostLimit = memoryCapacityBytes
        self.memoryCache = cache
        self.fileManager = fileManager

        if let baseCaches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = baseCaches.appendingPathComponent(diskDirectoryName, isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            self.diskDirectory = dir
        } else {
            self.diskDirectory = nil
        }
    }

    public init(
        memoryCapacityBytes: Int = 50 * 1024 * 1024,
        diskDirectory: URL,
        fileManager: FileManager = .default
    ) {
        let cache = NSCache<NSURL, NSData>()
        cache.totalCostLimit = memoryCapacityBytes
        self.memoryCache = cache
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        self.diskDirectory = diskDirectory
    }

    public func data(for url: URL) async -> Data? {
        let nsURL = url as NSURL
        if let memoryData = memoryCache.object(forKey: nsURL) {
            return memoryData as Data
        }

        guard let diskURL = diskFileURL(for: url),
              let diskData = try? Data(contentsOf: diskURL) else {
            return nil
        }

        memoryCache.setObject(diskData as NSData, forKey: nsURL, cost: diskData.count)
        return diskData
    }

    public func store(_ data: Data, for url: URL) async {
        let nsURL = url as NSURL
        memoryCache.setObject(data as NSData, forKey: nsURL, cost: data.count)

        guard let diskURL = diskFileURL(for: url) else { return }
        try? data.write(to: diskURL, options: .atomic)
    }

    public func removeData(for url: URL) async {
        let nsURL = url as NSURL
        memoryCache.removeObject(forKey: nsURL)

        guard let diskURL = diskFileURL(for: url) else { return }
        try? fileManager.removeItem(at: diskURL)
    }

    public func clear() async {
        memoryCache.removeAllObjects()

        guard let diskDirectory else { return }
        if let contents = try? fileManager.contentsOfDirectory(at: diskDirectory, includingPropertiesForKeys: nil) {
            for file in contents {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func diskFileURL(for url: URL) -> URL? {
        guard let diskDirectory else { return nil }
        let safeName = Data(url.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        let trimmedName = String(safeName.prefix(200))
        return diskDirectory.appendingPathComponent(trimmedName, isDirectory: false)
    }
}
