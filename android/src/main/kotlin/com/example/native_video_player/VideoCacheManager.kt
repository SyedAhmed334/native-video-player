package com.example.native_video_player

import android.content.Context
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.Cache
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.CacheWriter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap

/**
 * Singleton cache manager for video segments
 * Shared across all player instances for efficient disk usage
 */
@UnstableApi
object VideoCacheManager {
    private const val TAG = "VideoCacheManager"
    
    private var cache: SimpleCache? = null
    private var downloadDirectory: File? = null
    
    // Default cache size: 400MB
    private var maxCacheSizeBytes: Long = 400 * 1024 * 1024
    
    /**
     * Initialize the cache with custom size
     * Should be called once during app startup
     */
    @Synchronized
    fun initialize(context: Context, maxSizeMB: Int = 100) {
        if (cache != null) {
            android.util.Log.d(TAG, "Cache already initialized")
            return
        }
        
        maxCacheSizeBytes = maxSizeMB.toLong() * 1024 * 1024
        
        val dir = File(context.cacheDir, "native_video_player_cache")
        downloadDirectory = dir
        if (!dir.exists()) {
            dir.mkdirs()
        }
        
        val databaseProvider = StandaloneDatabaseProvider(context)
        val evictor = LeastRecentlyUsedCacheEvictor(maxCacheSizeBytes)
        
        cache = SimpleCache(
            dir,
            evictor,
            databaseProvider
        )
        
        android.util.Log.d(TAG, "Cache initialized: ${maxSizeMB}MB at ${dir.absolutePath}")
    }
    
    /**
     * Get the shared cache instance
     * Returns null if not initialized
     */
    @Synchronized
    fun getCache(context: Context): SimpleCache? {
        if (cache == null) {
            // Auto-initialize with defaults if not done
            initialize(context)
        }
        return cache
    }
    
    /**
     * Get current cache size in bytes
     */
    fun getCacheSize(): Long {
        return cache?.cacheSpace ?: 0
    }
    
    /**
     * Clear all cached data
     */
    @Synchronized
    fun clearCache() {
        try {
            cache?.keys?.forEach { key ->
                cache?.removeResource(key)
            }
            android.util.Log.d(TAG, "Cache cleared")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error clearing cache: ${e.message}")
        }
    }
    
    /**
     * Release cache resources
     * Call during app shutdown
     */
    @Synchronized
    fun release() {
        try {
            cache?.release()
            cache = null
            android.util.Log.d(TAG, "Cache released")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error releasing cache: ${e.message}")
        }
    }
    
    private val prefetchJobs = ConcurrentHashMap<String, CacheWriter>()
    private val scope = CoroutineScope(Dispatchers.IO)

    /**
     * Start prefetching a video URL to cache (Headless)
     */
    fun prefetch(context: Context, url: String, length: Long = 5 * 1024 * 1024) { // Default 5MB
        val currentCache = getCache(context) // Ensure cache is initialized
        if (currentCache == null) return
        
        if (prefetchJobs.containsKey(url)) {
            android.util.Log.d(TAG, "Already prefetching: $url")
            return
        }

        val uri = Uri.parse(url)
        val dataSpec = DataSpec.Builder()
            .setUri(uri)
            .setLength(length) // Prefetch first X bytes. If -1, prefetches all.
            .setFlags(DataSpec.FLAG_ALLOW_CACHE_FRAGMENTATION)
            .build()
            
        val upstreamFactory = DefaultDataSource.Factory(context, DefaultHttpDataSource.Factory())
        
        // CacheWriter requires a CacheDataSource, not just a simple DataSource
        val cacheDataSource = CacheDataSource.Factory()
            .setCache(currentCache)
            .setUpstreamDataSourceFactory(upstreamFactory)
            .createDataSource()
        
        val cacheWriter = CacheWriter(
            cacheDataSource,
            dataSpec,
            null, // Temporary storage not needed for read-through
            null // Progress listener
        )
        
        prefetchJobs[url] = cacheWriter
        
        scope.launch {
            try {
                android.util.Log.d(TAG, "Start prefetch: $url ($length bytes)")
                cacheWriter.cache()
                android.util.Log.d(TAG, "Prefetch complete: $url")
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Prefetch failed for $url: ${e.message}")
            } finally {
                prefetchJobs.remove(url)
            }
        }
    }

    /**
     * Cancel a specific prefetch
     */
    fun cancelPrefetch(url: String) {
        prefetchJobs[url]?.cancel()
        prefetchJobs.remove(url)
    }

    /**
     * Check if caching is available
     */
    fun isAvailable(): Boolean = cache != null
}
