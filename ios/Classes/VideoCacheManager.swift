import Foundation

/// Singleton cache manager for video files
/// Handles headless downloading and file management
class VideoCacheManager: NSObject {
    
    static let shared = VideoCacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    
    // Custom session for downloads
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    // LRU Configuration
    private let maxCacheSize: Int64 = 400 * 1024 * 1024 // 400MB
    
    private override init() {
        // Create a subdirectory in Caches
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("native_video_player_cache")
        
        super.init()
        
        createCacheDirectory()
        cleanCacheIfNeeded() // Clean on startup
    }
    
    private func createCacheDirectory() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            do {
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
                print("[VideoCacheManager] Created cache directory: \(cacheDirectory.path)")
            } catch {
                print("[VideoCacheManager] Failed to create cache directory: \(error)")
            }
        }
    }
    
    /// Enforce LRU Cache Size
    private func cleanCacheIfNeeded() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let resourceKeys: [URLResourceKey] = [.contentAccessDateKey, .fileSizeKey]
                let fileUrls = try self.fileManager.contentsOfDirectory(at: self.cacheDirectory,
                                                                      includingPropertiesForKeys: resourceKeys,
                                                                      options: .skipsHiddenFiles)
                
                var currentSize: Int64 = 0
                var files: [(url: URL, date: Date, size: Int64)] = []
                
                for url in fileUrls {
                    let resources = try url.resourceValues(forKeys: Set(resourceKeys))
                    if let size = resources.fileSize, let date = resources.contentAccessDate {
                        currentSize += Int64(size)
                        files.append((url, date, Int64(size)))
                    }
                }
                
                // If we are within limits, return
                if currentSize <= self.maxCacheSize {
                    return
                }
                
                print("[VideoCacheManager] Cache size (\(currentSize / 1024 / 1024)MB) exceeds limit (\(self.maxCacheSize / 1024 / 1024)MB). Pruning...")
                
                // Sort by last access (oldest first)
                files.sort { $0.date < $1.date }
                
                for file in files {
                    if currentSize <= self.maxCacheSize {
                        break
                    }
                    
                    try self.fileManager.removeItem(at: file.url)
                    currentSize -= file.size
                    print("[VideoCacheManager] Evicted: \(file.url.lastPathComponent)")
                }
                
            } catch {
                print("[VideoCacheManager] Error during cache pruning: \(error)")
            }
        }
    }
    
    /// Get the local file URL for a given remote URL
    /// Returns nil if not cached
    func getCachedFile(for urlString: String) -> URL? {
        let fileUrl = getLocalFileUrl(for: urlString)
        if fileManager.fileExists(atPath: fileUrl.path) {
            // Touch the file to update access time (for LRU)
            // We verify specific file URLs so minimal overhead
            try? (fileUrl as NSURL).setResourceValue(Date(), forKey: .contentAccessDateKey)
            return fileUrl
        }
        return nil
    }
    
    /// Start prefetching a video (Headless)
    /// Downloads the file to the cache directory
    func prefetch(url: String) {
        // Check if already cached
        if getCachedFile(for: url) != nil {
            print("[VideoCacheManager] Already cached: \(url)")
            return
        }
        
        // Check if currently downloading
        if activeDownloads[url] != nil {
            print("[VideoCacheManager] Already downloading: \(url)")
            return
        }
        
        guard let remoteUrl = URL(string: url) else { return }
        
        print("[VideoCacheManager] Start prefetch: \(url)")
        
        let task = session.downloadTask(with: remoteUrl)
        
        // Store task to prevent duplicates
        // Note: In a real app we might want to attach task descriptions or use a proper delegate map
        // For simplicity, we assume one task per URL
        task.taskDescription = url
        activeDownloads[url] = task
        
        task.resume()
    }
    
    /// Cancel a prefetch
    func cancelPrefetch(url: String) {
        if let task = activeDownloads[url] {
            task.cancel()
            activeDownloads.removeValue(forKey: url)
        }
    }
    
    /// Clear all cached videos
    func clearCache() {
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
            print("[VideoCacheManager] Cache cleared")
            
            // Cancel all downloads
            activeDownloads.values.forEach { $0.cancel() }
            activeDownloads.removeAll()
        } catch {
            print("[VideoCacheManager] Failed to clear cache: \(error)")
        }
    }
    
    /// Get total cache size in bytes
    func getCacheSize() -> Int64 {
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            var size: Int64 = 0
            for file in files {
                let resources = try file.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resources.fileSize {
                    size += Int64(fileSize)
                }
            }
            return size
        } catch {
            return 0
        }
    }
    
    // MARK: - Helper Methods
    
    private func getLocalFileUrl(for remoteUrlString: String) -> URL {
        // Use MD5 or Base64 of URL as filename to handle special characters
        // Simple Base64 encoding for filename safety
        let filename = remoteUrlString.data(using: .utf8)?.base64EncodedString() ?? "unknown"
        // Append mp4 extension just in case, though AVPlayer often needs correct mime type or extension
        return cacheDirectory.appendingPathComponent("\(filename).mp4")
    }
}

// MARK: - URLSessionDownloadDelegate

extension VideoCacheManager: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let url = downloadTask.taskDescription else { return }
        
        let destinationUrl = getLocalFileUrl(for: url)
        
        do {
            // Move file from temp location to cache
            if fileManager.fileExists(atPath: destinationUrl.path) {
                try fileManager.removeItem(at: destinationUrl)
            }
            try fileManager.moveItem(at: location, to: destinationUrl)
            
            print("[VideoCacheManager] Prefetch complete: \(url)")
            
            // Trigger cleaning (ensure we stay within limits)
            self?.cleanCacheIfNeeded()
        } catch {
            print("[VideoCacheManager] Failed to save file: \(error)")
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.activeDownloads.removeValue(forKey: url)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let url = task.taskDescription else { return }
        
        if let error = error {
            print("[VideoCacheManager] Prefetch failed for \(url): \(error.localizedDescription)")
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.activeDownloads.removeValue(forKey: url)
        }
    }
}
