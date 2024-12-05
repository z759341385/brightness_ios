import AVFoundation
import UIKit
import Photos
import ImageIO

class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var session = AVCaptureSession()
    private var output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var completionHandler: ((UIImage, [String: Any]) -> Void)?
    

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.setupSession()
                    }
                }
            }
        default:
            return
        }
    }
    
    func setupSession() {
        session.stopRunning()
        session.beginConfiguration()
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        
        self.device = device
        
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            device.isSubjectAreaChangeMonitoringEnabled = true
            
            let centerPoint = CGPoint(x: 0.5, y: 0.5)
            device.exposurePointOfInterest = centerPoint
            
            if device.exposureDuration.seconds != device.activeFormat.minExposureDuration.seconds {
                device.setExposureModeCustom(
                    duration: device.activeFormat.minExposureDuration,
                    iso: device.activeFormat.minISO,
                    completionHandler: nil
                )
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error configuring device: \(error)")
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        if session.canAddOutput(output) {
            session.addOutput(output)
            if output.isHighResolutionCaptureEnabled {
                output.isHighResolutionCaptureEnabled = true
            }
        }
        
        session.commitConfiguration()
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }
    
    func capturePhoto(completion: @escaping (UIImage, [String: Any]) -> Void) {
        self.completionHandler = completion
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.isHighResolutionPhotoEnabled = output.isHighResolutionCaptureEnabled
        
        output.capturePhoto(with: settings, delegate: self)
    }
    
    func savePhotoToLibrary(image: UIImage, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                
                if let imageData = image.jpegData(compressionQuality: 1.0),
                   let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                   let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                    
                    var finalMetadata = metadata
                    var exifDict = (finalMetadata[kCGImagePropertyExifDictionary as String] as? [String: Any]) ?? [:]
                    
                    if let device = self.device {
                        // 基本相机参数
                        exifDict[kCGImagePropertyExifISOSpeedRatings as String] = [device.iso]
                        exifDict[kCGImagePropertyExifExposureTime as String] = CMTimeGetSeconds(device.exposureDuration)
                        exifDict[kCGImagePropertyExifFNumber as String] = device.lensAperture
                        
                        // 焦距相关
                        let focalLength = device.activeFormat.videoZoomFactorUpscaleThreshold
                        exifDict[kCGImagePropertyExifFocalLength as String] = focalLength
                        exifDict["FocalLengthIn35mmFilm"] = Int(focalLength * 35.0) // 35mm等效焦距
                        
                        // 曝光相关
                        exifDict[kCGImagePropertyExifBrightnessValue as String] = device.exposureTargetBias
                        exifDict[kCGImagePropertyExifExposureBiasValue as String] = device.exposureTargetBias
                        exifDict[kCGImagePropertyExifShutterSpeedValue as String] = log2(CMTimeGetSeconds(device.exposureDuration))
                        exifDict[kCGImagePropertyExifApertureValue as String] = log2(pow(device.lensAperture, 2))
                        
                        // 曝光程序
                        exifDict["ExposureProgram"] = 2 // 通常程序模式
                        
                        // 场景类型
                        exifDict["SceneCaptureType"] = 0 // 标准
                        
                        // 曝光模式
                        exifDict[kCGImagePropertyExifExposureMode as String] = device.exposureMode == .custom ? 1 : 0
                        
                        // 白平衡
                        exifDict[kCGImagePropertyExifWhiteBalance as String] = device.whiteBalanceMode == .locked ? 1 : 0
                        
                        // 测光模式
                        exifDict["MeteringMode"] = 5 // 评价测光
                        
                        // 时间信息
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                        let currentDate = dateFormatter.string(from: Date())
                        exifDict[kCGImagePropertyExifDateTimeOriginal as String] = currentDate
                        exifDict[kCGImagePropertyExifDateTimeDigitized as String] = currentDate
                        
                        // 设备信息
                        var tiffDict = (finalMetadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any]) ?? [:]
                        tiffDict[kCGImagePropertyTIFFMake as String] = "Apple"
                        tiffDict[kCGImagePropertyTIFFModel as String] = UIDevice.current.model
                        tiffDict[kCGImagePropertyTIFFSoftware as String] = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
                        tiffDict[kCGImagePropertyTIFFDateTime as String] = currentDate
                        
                        finalMetadata[kCGImagePropertyTIFFDictionary as String] = tiffDict
                        finalMetadata[kCGImagePropertyExifDictionary as String] = exifDict
                    }
                    
                    let mutableData = NSMutableData()
                    if let destination = CGImageDestinationCreateWithData(mutableData, 
                                                                        UTType.jpeg.identifier as CFString, 
                                                                        1, 
                                                                        nil) {
                        CGImageDestinationAddImageFromSource(destination, source, 0, finalMetadata as CFDictionary)
                        CGImageDestinationFinalize(destination)
                        
                        request.addResource(with: .photo, data: mutableData as Data, options: nil)
                    }
                }
            }) { success, error in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, 
                    didFinishProcessingPhoto photo: AVCapturePhoto, 
                    error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            return
        }
        
        var metadata: [String: Any] = [:]
        
        if let source = CGImageSourceCreateWithData(imageData as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            metadata = properties
        }
        
        if let device = self.device {
            metadata["Brightness"] = device.exposureTargetBias
            metadata["ISO"] = device.iso
            metadata["ExposureDuration"] = CMTimeGetSeconds(device.exposureDuration)
            metadata["LensPosition"] = device.lensPosition
            metadata["ExposureMode"] = device.exposureMode.rawValue
            metadata["MinExposureDuration"] = CMTimeGetSeconds(device.activeFormat.minExposureDuration)
            metadata["MaxExposureDuration"] = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
            metadata["MinISO"] = device.activeFormat.minISO
            metadata["MaxISO"] = device.activeFormat.maxISO
            metadata["ExposurePointOfInterest"] = "\(device.exposurePointOfInterest)"
        }
        
        DispatchQueue.main.async {
            self.completionHandler?(image, metadata)
        }
    }
}
