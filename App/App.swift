import SwiftUI
import ARKit
import Network
import WebKit

final class Tracker: NSObject, ObservableObject, ARSessionDelegate {
    @Published var mode = "car"
    @Published var walk = 1
    @Published var zoom = 1.0
    @Published var steady = false
    @Published var recenter = 0
    private let session = ARSession()
    private var conn: NWConnection?

    func start(host: String) {
        conn = NWConnection(host: NWEndpoint.Host(host), port: 5006, using: .udp)
        conn?.start(queue: .main)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        UIApplication.shared.isIdleTimerDisabled = true
        session.delegate = self
        session.run(ARWorldTrackingConfiguration(), options: [.resetTracking])
        recenter += 1
    }

    func stop() {
        session.pause()
        conn?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // ARKit (y arriba) -> BeamNG (z arriba)
    private func g(_ v: SIMD3<Float>) -> [Float] { [v.x, -v.z, v.y] }

    func session(_ s: ARSession, didUpdate frame: ARFrame) {
        let t = frame.camera.transform
        func col(_ i: Int) -> SIMD3<Float> { SIMD3(t[i].x, t[i].y, t[i].z) }
        let flip: Float = UIDevice.current.orientation == .landscapeRight ? -1 : 1
        let msg: [String: Any] = [
            "p": g(col(3)), "f": g(-col(2)), "u": g(col(1) * flip),
            "m": mode, "w": walk, "z": 75 / zoom,
            "s": steady ? 1 : 0, "r": recenter
        ]
        if let d = try? JSONSerialization.data(withJSONObject: msg) {
            conn?.send(content: d, completion: .idempotent)
        }
    }
}

struct MJPEG: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView()
        w.isOpaque = false
        w.backgroundColor = .black
        w.scrollView.isScrollEnabled = false
        let html = """
        <body style='margin:0;background:#000'><img id='i' style='width:100vw;height:100vh;object-fit:contain'>
        <script>
        var u='\(url.absoluteString)',i=document.getElementById('i'),t=0;
        function n(){setTimeout(function(){t=Date.now();var x=new Image();x.onload=function(){i.src=x.src;n()};x.onerror=function(){setTimeout(n,200)};x.src=u+'?'+t},Math.max(0,33-(Date.now()-t)))}
        n()
        </script></body>
        """
        w.loadHTMLString(html, baseURL: nil)
        return w
    }
    func updateUIView(_ v: WKWebView, context: Context) {}
}

extension View {
    func chip(_ on: Bool) -> some View {
        self.buttonStyle(.plain)
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(on ? Color.mint : Color.black.opacity(0.55))
            .foregroundColor(on ? .black : .white)
            .clipShape(Capsule())
    }
}

struct ContentView: View {
    @StateObject var t = Tracker()
    @AppStorage("ip") var ip = ""
    @State var on = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if on, let u = URL(string: "http://\(ip):5007/snap") {
                MJPEG(url: u).ignoresSafeArea()
                controls
            } else {
                VStack(spacing: 14) {
                    Text("PHONE CAM").font(.largeTitle.bold())
                    TextField("IP de tu PC (ej. 192.168.1.20)", text: $ip)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder).frame(width: 320)
                    Button("Conectar") { t.start(host: ip); on = true }
                        .buttonStyle(.borderedProminent).tint(.mint)
                }
            }
        }.preferredColorScheme(.dark)
    }

    var controls: some View {
        VStack {
            HStack(spacing: 6) {
                ForEach(["car", "free", "chase", "drone", "head"], id: \.self) { m in
                    Button(m.uppercased()) { t.mode = m }.chip(t.mode == m)
                }
                Spacer()
                Button("RECENTER") { t.recenter += 1 }.chip(false)
                Button("X") { t.stop(); on = false }.chip(false)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("WALK").font(.caption2)
                ForEach(1...5, id: \.self) { n in
                    Button("x\(n)") { t.walk = n }.chip(t.walk == n)
                }
                Spacer()
                Text("ZOOM").font(.caption2)
                Slider(value: $t.zoom, in: 1...4).frame(width: 140).tint(.mint)
                Button("STEADY") { t.steady.toggle() }.chip(t.steady)
            }
        }.padding()
    }
}

@main
struct PhoneCamApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
