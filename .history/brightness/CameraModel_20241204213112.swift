import AVFoundation
import UIKit

class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var session = AVCaptureSession()
    private var output = AVCapturePhotoOutput()
    private var completionHandler: ((UIImage) -> Void)?
    
    private var device: AVCaptureDevice?
    
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
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        session.commitConfiguration()
        
        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
        }
    }
    
    func setExposureAndISO(exposure: Float, iso: Float) {
        guard let device = device else { return }
        
        do {
            try device.lockForConfiguration()
            
            // 设置曝光补偿
            let minExposure = device.minExposureTargetBias
            let maxExposure = device.maxExposureTargetBias
            let clampedExposure = max(min(exposure, maxExposure), minExposure)
            device.setExposureTargetBias(clampedExposure)
            
            // 设置 ISO
            let minISO = device.activeFormat.minISO
            let maxISO = device.activeFormat.maxISO
            let clampedISO = max(min(iso, maxISO), minISO)
            device.setFocusMode(.locked)
            device.setExposureModeCustom(duration: CMTimeMake(value: 1, timescale: 1000), iso: clampedISO, completionHandler: nil)
            
            device.unlockForConfiguration()
        } catch {
            print("Failed to configure device: \(error)")
        }
    }
    
    func capturePhoto(completion: @escaping (UIImage) -> Void) {
        self.completionHandler = completion
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, 
                    didFinishProcessingPhoto photo: AVCapturePhoto, 
                    error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            return
        }
        DispatchQueue.main.async {
            self.completionHandler?(image)
        }
    }
} 
