package com.example.native_video_player

import android.content.Context
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.Cache
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File

/**
 * Singleton cache manager for video segments
 * Shared across all player instances for efficient disk usage
 */
@UnstableApi
object VideoCacheManager {
    private const val TAG = "VideoCacheManager"
    
    private var cache: SimpleCache? = null
    private var downloadDirectory: File? = null
    
    // Default cache size: 100MB
    private var maxCacheSizeBytes: Long = 100 * 1024 * 1024
    
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
        
        downloadDirectory = File(context.cacheDir, "native_video_player_cache")
        if (!downloadDirectory!!.exists()) {
            downloadDirectory!!.mkdirs()
        }
        
        val databaseProvider = StandaloneDatabaseProvider(context)
        val evictor = LeastRecentlyUsedCacheEvictor(maxCacheSizeBytes)
        
        cache = SimpleCache(
            downloadDirectory!!,
            evictor,
            databaseProvider
        )
        
        android.util.Log.d(TAG, "Cache initialized: ${maxSizeMB}MB at ${downloadDirectory!!.absolutePath}")
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
    
    /**
     * Check if caching is available
     */
    fun isAvailable(): Boolean = cache != null
}
