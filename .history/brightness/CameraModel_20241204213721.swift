import AVFoundation
import UIKit

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
        session.beginConfiguration()
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        
        self.device = device
        
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
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
        
        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
        }
    }
    
    func capturePhoto(completion: @escaping (UIImage, [String: Any]) -> Void) {
        self.completionHandler = completion
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        settings.isHighResolutionPhotoEnabled = output.isHighResolutionCaptureEnabled
        
        output.capturePhoto(with: settings, delegate: self)
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
        }
        
        DispatchQueue.main.async {
            self.completionHandler?(image, metadata)
        }
    }
}