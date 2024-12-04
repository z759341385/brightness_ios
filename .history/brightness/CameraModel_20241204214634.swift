import AVFoundation
import UIKit
import Photos

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
                if let imageData = image.jpegData(compressionQuality: 1.0) {
                    request.addResource(with: .photo, data: imageData, options: nil)
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