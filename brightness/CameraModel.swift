import AVFoundation
import UIKit
import Photos
import ImageIO

class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var session = AVCaptureSession()
    private var output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var completionHandler: ((UIImage, [String: Any]) -> Void)?
    
    override init() {
        super.init()
        setupSession()
    }
    
    func setupSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.session.stopRunning()
            self.session.beginConfiguration()
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                print("Failed to get camera device")
                return
            }
            
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            
            self.device = device
            
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            
            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
                if self.output.isHighResolutionCaptureEnabled {
                    self.output.isHighResolutionCaptureEnabled = true
                }
            }
            
            self.session.commitConfiguration()
            
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupSession()
                    }
                }
            }
        default:
            return
        }
    }
    
    func capturePhoto(completion: @escaping (UIImage, [String: Any]) -> Void) {
        self.completionHandler = completion
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.isHighResolutionPhotoEnabled = output.isHighResolutionCaptureEnabled
        
        settings.photoQualityPrioritization = .balanced
        settings.isDepthDataDeliveryEnabled = output.isDepthDataDeliveryEnabled
        
        output.capturePhoto(with: settings, delegate: self)
    }
    
    func savePhotoToLibrary(image: UIImage, metadata: [String: Any], completion: @escaping (Bool) -> Void) {
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
                    let mutableData = NSMutableData()
                    if let destination = CGImageDestinationCreateWithData(mutableData, 
                                                                        UTType.jpeg.identifier as CFString, 
                                                                        1, 
                                                                        nil) {
                        if let source = CGImageSourceCreateWithData(imageData as CFData, nil) {
                            CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
                            CGImageDestinationFinalize(destination)
                            
                            request.addResource(with: .photo, data: mutableData as Data, options: nil)
                        }
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
        guard let imageData = photo.fileDataRepresentation() else { return }
        
        var metadata: [String: Any] = [:]
        if let source = CGImageSourceCreateWithData(imageData as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            metadata = properties
        }
        
        guard let image = UIImage(data: imageData) else { return }
        
        DispatchQueue.main.async {
            self.completionHandler?(image, metadata)
        }
    }
}
