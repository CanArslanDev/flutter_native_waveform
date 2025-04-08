package com.example.flutter_native_waveform

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.flutter_native_waveform/audio"
    private val TAG = "AudioProcessor"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "extractPCMFromMP3" -> {
                    try {
                        Log.i(TAG, "extractPCMFromMP3 method called")
                        val mp3Data = call.argument<ByteArray>("mp3Data")
                        
                        if (mp3Data != null) {
                            Log.i(TAG, "MP3 data received, size: ${mp3Data.size} bytes")
                            val pcmData = extractPCMFromMP3(mp3Data)
                            result.success(pcmData)
                        } else {
                            Log.e(TAG, "MP3 data is null")
                            result.error("NULL_DATA", "MP3 data is empty", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "MP3 processing error", e)
                        result.error("EXTRACTION_ERROR", "Error processing MP3 data: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun extractPCMFromMP3(mp3Data: ByteArray): List<Float> {
        val extractor = MediaExtractor()
        val pcmOutput = mutableListOf<Float>()
        
        try {
            val tempFile = File.createTempFile("temp_audio", ".mp3", context.cacheDir)
            tempFile.writeBytes(mp3Data)
            
            extractor.setDataSource(tempFile.path)
            
            tempFile.deleteOnExit()
            
            val audioTrackIndex = selectAudioTrack(extractor)
            if (audioTrackIndex < 0) {
                Log.e(TAG, "Audio track not found")
                return emptyList()
            }
            
            val mediaFormat = extractor.getTrackFormat(audioTrackIndex)
            val mime = mediaFormat.getString(MediaFormat.KEY_MIME)
            val decoder = MediaCodec.createDecoderByType(mime!!)
            decoder.configure(mediaFormat, null, null, 0)
            decoder.start()
            
            val sampleRate = mediaFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channelCount = mediaFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            Log.i(TAG, "Audio properties: Sample rate: $sampleRate, Channel count: $channelCount")
            
            extractor.selectTrack(audioTrackIndex)
            
            val bufferInfo = MediaCodec.BufferInfo()
            
            var sawInputEOS = false
            var sawOutputEOS = false
            
            val samplingFactor = 20
            var sampleCounter = 0
            
            while (!sawOutputEOS) {
                if (!sawInputEOS) {
                    val inputBufferIndex = decoder.dequeueInputBuffer(10000)
                    if (inputBufferIndex >= 0) {
                        val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
                        inputBuffer?.clear()
                        
                        val sampleSize = extractor.readSampleData(inputBuffer!!, 0)
                        if (sampleSize < 0) {
                            sawInputEOS = true
                            decoder.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        } else {
                            decoder.queueInputBuffer(inputBufferIndex, 0, sampleSize, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                
                val outputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, 10000)
                if (outputBufferIndex >= 0) {
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        sawOutputEOS = true
                    }
                    
                    if (bufferInfo.size > 0) {
                        val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
                        
                        val shortArray = ShortArray(bufferInfo.size / 2)
                        outputBuffer?.position(bufferInfo.offset)
                        outputBuffer?.order(ByteOrder.LITTLE_ENDIAN)
                        
                        for (i in shortArray.indices) {
                            shortArray[i] = outputBuffer?.short ?: 0
                            
                            if (sampleCounter % samplingFactor == 0) {
                                val normalizedValue = shortArray[i] / 32768.0f
                                pcmOutput.add(normalizedValue)
                            }
                            sampleCounter++
                        }
                    }
                    
                    decoder.releaseOutputBuffer(outputBufferIndex, false)
                }
            }
            
            decoder.stop()
            decoder.release()
            extractor.release()
            
            return processWaveformData(pcmOutput)
            
        } catch (e: Exception) {
            Log.e(TAG, "Audio conversion error", e)
            extractor.release()
            return emptyList()
        }
    }
    
    private fun selectAudioTrack(extractor: MediaExtractor): Int {
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME)
            if (mime?.startsWith("audio/") == true) {
                return i
            }
        }
        return -1
    }
    
    private fun processWaveformData(pcmData: List<Float>): List<Float> {
        if (pcmData.isEmpty()) return emptyList()
        
        val totalSamples = pcmData.size
        val barsCount = 200
        val samplesPerBar = totalSamples / barsCount
        
        val result = mutableListOf<Float>()
        
        for (i in 0 until barsCount) {
            val startIndex = i * samplesPerBar
            val endIndex = minOf((i + 1) * samplesPerBar, totalSamples)
            
            if (startIndex >= endIndex) continue
            
            var sumOfSquares = 0.0f
            for (j in startIndex until endIndex) {
                val sample = pcmData[j]
                sumOfSquares += sample * sample
            }
            
            val rmsValue = Math.sqrt(sumOfSquares / (endIndex - startIndex).toDouble()).toFloat()
            result.add(rmsValue)
        }
        
        return result
    }
}
