import SwiftUI
import AVFoundation
import Photos

struct CameraView: View {
    @StateObject private var camera = CameraModel()
    @State private var exifData: [String: Any] = [:]
    @State private var showingSaveAlert = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                Button(action: {
                    camera.saveCurrentFrame { success in
                        showingSaveAlert = true
                    }
                }) {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 20)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let brightness = exifData["Brightness"] as? Float {
                            Text("Brightness: \(String(format: "%.2f", brightness))")
                                .foregroundColor(.black)
                        }
                        if let iso = exifData["ISO"] as? Float {
                            Text("ISO: \(String(format: "%.0f", iso))")
                                .foregroundColor(.black)
                        }
                        if let exposureDuration = exifData["ExposureDuration"] as? Double {
                            Text("Exposure Duration: \(String(format: "%.4f", exposureDuration))s")
                                .foregroundColor(.black)
                        }
                        
                        ForEach(Array(exifData.keys.sorted()), id: \.self) { key in
                            if !["Brightness", "ISO", "ExposureDuration"].contains(key) {
                                HStack {
                                    Text(key)
                                        .bold()
                                        .foregroundColor(.black)
                                    Spacer()
                                    Text("\(String(describing: exifData[key] ?? ""))")
                                        .foregroundColor(.black)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 200)
                .background(Color.white)
            }
        }
        .onAppear {
            camera.checkPermissions()
            camera.setupSession()
        }
        .onReceive(timer) { _ in
            camera.capturePhoto { image, metadata in
                self.exifData = metadata
            }
        }
        .alert("照片已保存", isPresented: $showingSaveAlert) {
            Button("确定", role: .cancel) { }
        }
    }
}

// 相机预览视图
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect.zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}