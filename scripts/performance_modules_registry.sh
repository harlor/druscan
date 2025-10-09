#!/bin/bash
# Registry of performance optimization modules for Drupal 8/9/10/11
# Used by analyze_performance_backend.sh

# Cache Performance Modules
CACHE_MODULES=(
    "redis|Redis cache backend for improved performance"
    "memcache|Memcache cache backend integration"
    "memcache_storage|Memcache storage backend"
    "varnish_purger|Varnish cache purging integration"
    "purge|Cache invalidation framework"
    "cache_warmer|Automatically warm cache for better performance"
)

# CSS/JS Aggregation Modules
# Note: AdvAgg removed - not needed in Drupal 10+, core aggregation is sufficient
AGGREGATION_MODULES=(
    # No additional aggregation modules needed for Drupal 10+
)

# Image Optimization Modules
IMAGE_OPTIMIZATION_MODULES=(
    "webp|WebP image format support for smaller file sizes"
    "imageapi_optimize|Image optimization API"
    "imageapi_optimize_binaries|Image optimization with binaries"
    "imageapi_optimize_resmushit|Image optimization via reSmush.it"
    "image_optimize|Image optimization wrapper"
    "blazy|Lazy loading for images and iframes"
    "lazy|Lazy loading images"
    "lazyloader|Progressive image lazy loading"
)

# CDN and Asset Delivery Modules
CDN_MODULES=(
    "cdn|Content Delivery Network integration"
    "s3fs|Amazon S3 File System for static assets"
    "s3fs_cors|S3 File System CORS support"
)

# Database Optimization Modules
DATABASE_MODULES=(
    "ultimate_cron|Advanced cron job management"
    "node_revision_delete|Automatic deletion of old node revisions"
    "field_purge|Delete unused field data"
    "database_sanitize|Database cleanup and optimization"
)

# Mobile and Rendering Optimization Modules
MOBILE_MODULES=(
    "amp|Accelerated Mobile Pages support"
    "big_pipe|Progressive rendering (Drupal core)"
)

# Additional Performance Modules
ADDITIONAL_MODULES=(
    "fast_404|Fast 404 page delivery"
    "site_audit|Performance audit and recommendations"
    "entitycache|Entity caching for improved database performance"
    "views_cache_bully|Aggressive Views caching"
    "httprl|Parallel HTTP requests"
)

# All modules combined (for easy iteration)
ALL_PERFORMANCE_MODULES=(
    "${CACHE_MODULES[@]}"
    "${AGGREGATION_MODULES[@]}"
    "${IMAGE_OPTIMIZATION_MODULES[@]}"
    "${CDN_MODULES[@]}"
    "${DATABASE_MODULES[@]}"
    "${MOBILE_MODULES[@]}"
    "${ADDITIONAL_MODULES[@]}"
)

