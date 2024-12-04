import SwiftUI
import AVFoundation
import Photos

struct CameraView: View {
    @StateObject private var camera = CameraModel()
    @State private var exifData: [String: Any] = [:]
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // 相机预览层
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                // EXIF 数据显示
                ScrollView {
                    ForEach(Array(exifData.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(key)
                                .bold()
                            Spacer()
                            Text("\(String(describing: exifData[key] ?? ""))")
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(height: 200)
                .background(Color.black.opacity(0.7))
            }
        }
        .onAppear {
            camera.checkPermissions()
            camera.setupSession()
        }
        .onReceive(timer) { _ in
            camera.capturePhoto { image, metadata in
                exifData = metadata
            }
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