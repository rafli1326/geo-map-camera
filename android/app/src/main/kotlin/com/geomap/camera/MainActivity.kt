package com.geomap.camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.OverlaySettings
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.geomap.camera/video_watermark"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "burnWatermark") {
                val inputPath = call.argument<String>("inputPath")
                val outputPath = call.argument<String>("outputPath")
                val overlayPaths = call.argument<List<String>>("overlayPaths") ?: emptyList()
                val rotationDegrees = call.argument<Int>("rotationDegrees") ?: 0

                if (inputPath == null || outputPath == null || overlayPaths.isEmpty()) {
                    result.error("INVALID_ARGS", "Missing inputPath, outputPath or overlayPaths", null)
                    return@setMethodCallHandler
                }

                if (!isPathAllowed(inputPath) || !isPathAllowed(outputPath) || overlayPaths.any { !isPathAllowed(it) }) {
                    result.error("SECURITY_VIOLATION", "Unauthorized or invalid file path detected", null)
                    return@setMethodCallHandler
                }

                val inputFile = File(inputPath)
                if (!inputFile.exists() || !inputFile.isFile) {
                    result.error("FILE_NOT_FOUND", "Input video file does not exist", null)
                    return@setMethodCallHandler
                }

                burnVideoWatermark(inputPath, outputPath, overlayPaths, rotationDegrees, result)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun isPathAllowed(path: String): Boolean {
        if (path.contains("\u0000")) return false
        val file = File(path)
        val canonicalPath = try {
            file.canonicalPath
        } catch (_: Exception) {
            return false
        }

        val allowedRoots = mutableListOf<String>()
        applicationContext.cacheDir?.canonicalPath?.let { allowedRoots.add(it) }
        applicationContext.externalCacheDir?.canonicalPath?.let { allowedRoots.add(it) }
        applicationContext.filesDir?.canonicalPath?.let { allowedRoots.add(it) }
        applicationContext.getExternalFilesDir(null)?.canonicalPath?.let { allowedRoots.add(it) }
        allowedRoots.add("/storage/emulated/0/Pictures")

        return allowedRoots.any { root -> canonicalPath.startsWith(root) }
    }

    private fun readOrientedVideoDimensions(inputPath: String): Pair<Int, Int> {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(inputPath)
            val w = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val h = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rot = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (rot == 90 || rot == 270) Pair(h, w) else Pair(w, h)
        } catch (_: Exception) {
            Pair(0, 0)
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {}
        }
    }

    private fun burnVideoWatermark(
        inputPath: String,
        outputPath: String,
        overlayPaths: List<String>,
        rotationDegrees: Int,
        channelResult: MethodChannel.Result
    ) {
        try {
            val firstBitmap = BitmapFactory.decodeFile(overlayPaths[0])
            if (firstBitmap == null) {
                channelResult.error("BITMAP_DECODE_FAILED", "Failed to decode initial overlay strip", null)
                return
            }

            val videoDimensions = readOrientedVideoDimensions(inputPath)
            val videoWidth = videoDimensions.first
            val videoHeight = videoDimensions.second

            val effectsList = mutableListOf<Effect>()

            // If user recorded in landscape (rotationDegrees == -90 or 90), but raw video
            // metadata is portrait (videoWidth < videoHeight), rotate video to landscape!
            val isRequestedLandscape = rotationDegrees == -90 || rotationDegrees == 90
            val isCurrentlyPortrait = videoWidth in 1..<videoHeight

            val finalVideoWidth: Int
            if (isRequestedLandscape && isCurrentlyPortrait) {
                val extraRotation = if (rotationDegrees == -90) 90f else -90f
                effectsList.add(
                    ScaleAndRotateTransformation.Builder()
                        .setRotationDegrees(extraRotation)
                        .build()
                )
                finalVideoWidth = videoHeight
            } else {
                finalVideoWidth = if (videoWidth > 0) videoWidth else firstBitmap.width
            }

            val scaleFactor = if (finalVideoWidth > 0 && firstBitmap.width > 0) {
                finalVideoWidth.toFloat() / firstBitmap.width.toFloat()
            } else {
                1f
            }

            // Anchor the cropped watermark strip to the bottom-center of the video frame
            val bottomOverlaySettings: OverlaySettings = StaticOverlaySettings.Builder()
                .setBackgroundFrameAnchor(0f, -1f)
                .setOverlayFrameAnchor(0f, -1f)
                .setScale(scaleFactor, scaleFactor)
                .build()

            var currentIndex = 0
            var currentBitmap: Bitmap = firstBitmap
            var previousBitmap: Bitmap? = null

            fun cleanupBitmaps() {
                try {
                    if (!currentBitmap.isRecycled) currentBitmap.recycle()
                } catch (_: Exception) {}
                try {
                    previousBitmap?.let { if (!it.isRecycled) it.recycle() }
                } catch (_: Exception) {}
                previousBitmap = null
            }

            // Lazy O(1) memory BitmapOverlay: decodes only the active second's strip on demand
            val dynamicOverlay = object : BitmapOverlay() {
                override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
                    return bottomOverlaySettings
                }

                override fun getBitmap(presentationTimeUs: Long): Bitmap {
                    val sec = (presentationTimeUs / 1_000_000L).toInt()
                    val idx = sec.coerceIn(0, overlayPaths.size - 1)
                    if (idx != currentIndex) {
                        val decoded = BitmapFactory.decodeFile(overlayPaths[idx])
                        if (decoded != null) {
                            previousBitmap?.let {
                                if (!it.isRecycled && it !== currentBitmap) {
                                    it.recycle()
                                }
                            }
                            previousBitmap = currentBitmap
                            currentBitmap = decoded
                            currentIndex = idx
                        }
                    }
                    return currentBitmap
                }
            }

            val overlayEffect = OverlayEffect(ImmutableList.of<TextureOverlay>(dynamicOverlay))
            effectsList.add(overlayEffect)

            val mediaItem = MediaItem.fromUri(Uri.fromFile(File(inputPath)))
            val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                .setEffects(Effects(listOf(), effectsList))
                .build()

            val listener = object : Transformer.Listener {
                override fun onCompleted(composition: androidx.media3.transformer.Composition, exportResult: ExportResult) {
                    runOnUiThread {
                        cleanupBitmaps()
                        channelResult.success(outputPath)
                    }
                }

                override fun onError(
                    composition: androidx.media3.transformer.Composition,
                    exportResult: ExportResult,
                    exportException: ExportException
                ) {
                    runOnUiThread {
                        cleanupBitmaps()
                        channelResult.error("TRANSFORM_ERROR", exportException.message, exportException.localizedMessage)
                    }
                }
            }

            val transformer = Transformer.Builder(applicationContext)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .addListener(listener)
                .build()

            val outFile = File(outputPath)
            if (outFile.exists()) {
                outFile.delete()
            }

            transformer.start(editedMediaItem, outputPath)
        } catch (e: Exception) {
            channelResult.error("PROCESSING_EXCEPTION", e.message, null)
        }
    }
}
