import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let audioChannel = FlutterMethodChannel(name: "com.example.flutter_native_waveform/audio", 
                                            binaryMessenger: controller.binaryMessenger)
    
    audioChannel.setMethodCallHandler { (call, result) in
      if call.method == "extractPCMFromMP3" {
        print("extractPCMFromMP3 method called")
        
        guard let mp3Data = call.arguments as? [String: Any],
              let flutterData = mp3Data["mp3Data"] as? FlutterStandardTypedData else {
          print("MP3 data could not be retrieved or invalid format")
          result(FlutterError(code: "INVALID_ARGUMENT", 
                            message: "Invalid MP3 data", 
                            details: nil))
          return
        }
        
        print("MP3 data retrieved, size: \(flutterData.data.count) byte")
        self.extractPCMFromMP3(flutterData.data) { pcmValues, error in
          if let error = error {
            result(FlutterError(code: "PROCESSING_ERROR", 
                              message: "MP3 processing error: \(error.localizedDescription)", 
                              details: nil))
          } else if let pcmValues = pcmValues {
            result(pcmValues)
          } else {
            result(FlutterError(code: "UNKNOWN_ERROR", 
                              message: "Unknown error occurred", 
                              details: nil))
          }
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func extractPCMFromMP3(_ mp3Data: Data, completion: @escaping ([Float]?, Error?) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let tempDir = NSTemporaryDirectory()
        let tempFilePath = (tempDir as NSString).appendingPathComponent("temp_audio.mp3")
        let tempFileURL = URL(fileURLWithPath: tempFilePath)
        
        try mp3Data.write(to: tempFileURL)
        
        let asset = AVAsset(url: tempFileURL)
        
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
          throw NSError(domain: "AudioProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio track not found"])
        }
        
        let outputSettings: [String: Any] = [
          AVFormatIDKey: kAudioFormatLinearPCM,
          AVLinearPCMBitDepthKey: 16,
          AVLinearPCMIsFloatKey: false,
          AVLinearPCMIsBigEndianKey: false,
          AVLinearPCMIsNonInterleaved: false
        ]
        
        let assetReader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        assetReader.add(trackOutput)
        
        assetReader.startReading()
        
        var pcmSamples = [Float]()
        let barsCount = 200
        var sampleGroups = [[Int16]]()
        
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
          guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            continue
          }
          
          var length: Int = 0
          var dataPointer: UnsafeMutablePointer<Int8>?
          CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
          
          let int16Pointer = UnsafeRawPointer(dataPointer!).bindMemory(to: Int16.self, capacity: length / 2)
          let int16Buffer = UnsafeBufferPointer(start: int16Pointer, count: length / 2)
          
          var group = [Int16]()
          for i in 0..<int16Buffer.count {
            group.append(int16Buffer[i])
            
            if group.count >= 1000 {
              sampleGroups.append(group)
              group = []
            }
          }
          
          if !group.isEmpty {
            sampleGroups.append(group)
          }
        }
        
        if assetReader.status != .completed {
          throw NSError(domain: "AudioProcessing", code: 4, userInfo: [NSLocalizedDescriptionKey: "Audio file could not be fully read: \(assetReader.status.rawValue)"])
        }
        
        if sampleGroups.isEmpty {
          throw NSError(domain: "AudioProcessing", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not obtain audio samples"])
        }
        
        let totalSampleGroups = sampleGroups.count
        let groupsPerBar = max(1, totalSampleGroups / barsCount)
        
        for i in 0..<barsCount {
          let startGroupIndex = i * groupsPerBar
          let endGroupIndex = min(startGroupIndex + groupsPerBar, totalSampleGroups)
          
          if startGroupIndex >= endGroupIndex {
            pcmSamples.append(0.0)
            continue
          }
          
          var sumOfSquares: Float = 0.0
          var totalSamples = 0
          
          for groupIndex in startGroupIndex..<endGroupIndex {
            if groupIndex < sampleGroups.count {
              let group = sampleGroups[groupIndex]
              
              for sample in group {
                let normalizedSample = Float(sample) / 32768.0
                sumOfSquares += normalizedSample * normalizedSample
                totalSamples += 1
              }
            }
          }
          
          let rmsValue = totalSamples > 0 ? sqrt(sumOfSquares / Float(totalSamples)) : 0.0
          pcmSamples.append(rmsValue)
        }
        
        try FileManager.default.removeItem(at: tempFileURL)
        
        DispatchQueue.main.async {
          completion(pcmSamples, nil)
        }
        
      } catch {
        DispatchQueue.main.async {
          print("Audio processing error: \(error.localizedDescription)")
          completion(nil, error)
        }
      }
    }
  }
}
