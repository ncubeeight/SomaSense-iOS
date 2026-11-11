import MetalKit
import UIKit

/// Draws the body mesh with Metal, lit as in the prototype. It draws only when asked,
/// and picks up a new body shape the next time it draws.
final class BodyRenderer: NSObject, MTKViewDelegate {
    struct Uniforms {
        var c: Float, s: Float, cp: Float, sp: Float
        var map: SIMD4<Float>
    }

    /// One picture of the body: its angle, where the figure goes in clip space, and which part of the view it fills (0...1).
    struct Shot {
        var yaw: Double
        var map: SIMD4<Float>
        var area = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    static let sampleCount = 4

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let mesh: BodyMesh
    private let positions: MTLBuffer
    private let normals: MTLBuffer
    private let occlusion: MTLBuffer
    private let indices: MTLBuffer
    private let indexCount: Int
    private var uploaded = -1

    var shots: [Shot] = []
    /// When set, works out the shots from the drawable's size each time it draws.
    var shotsFor: ((CGSize) -> [Shot])?

    init?(device: MTLDevice, mesh: BodyMesh) {
        guard let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: BodyShader.source, options: nil) else { return nil }
        self.device = device
        self.queue = queue
        self.mesh = mesh

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "bodyVertex")
        desc.fragmentFunction = library.makeFunction(name: "bodyFragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.depthAttachmentPixelFormat = .depth32Float
        desc.rasterSampleCount = BodyRenderer.sampleCount
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        self.pipeline = pipeline

        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depth) else { return nil }
        self.depthState = depthState

        let n = mesh.positions.count
        guard let positions = device.makeBuffer(length: n * 4),
              let normals = device.makeBuffer(length: n * 4),
              let occlusion = device.makeBuffer(bytes: mesh.occlusion, length: mesh.occlusion.count * 4),
              let indices = device.makeBuffer(bytes: mesh.triangles, length: mesh.triangles.count * 2) else { return nil }
        self.positions = positions
        self.normals = normals
        self.occlusion = occlusion
        self.indices = indices
        indexCount = mesh.triangles.count
        super.init()
        refresh()
    }

    convenience init?(view: MTKView, mesh: BodyMesh) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice() else { return nil }
        self.init(device: device, mesh: mesh)
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = BodyRenderer.sampleCount
        view.clearColor = MTLClearColor(red: 0xF3 / 255.0, green: 0xF6 / 255.0, blue: 0xF6 / 255.0, alpha: 1)
    }

    /// Copies the mesh's current shape into the drawing buffers when it has changed.
    private func refresh() {
        guard uploaded != mesh.shapeVersion else { return }
        let p = positions.contents().bindMemory(to: Float.self, capacity: mesh.positions.count)
        for (i, v) in mesh.positions.enumerated() { p[i] = Float(v) }
        mesh.normals.withUnsafeBytes { normals.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        uploaded = mesh.shapeVersion
    }

    private func encode(_ enc: MTLRenderCommandEncoder, size: CGSize) {
        refresh()
        let pitch = Float(8 * Double.pi / 180)
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(depthState)
        enc.setCullMode(.none)
        enc.setVertexBuffer(positions, offset: 0, index: 0)
        enc.setVertexBuffer(normals, offset: 0, index: 1)
        enc.setVertexBuffer(occlusion, offset: 0, index: 2)
        for shot in shots {
            let a = shot.area
            enc.setViewport(MTLViewport(originX: a.minX * size.width, originY: a.minY * size.height,
                                        width: a.width * size.width, height: a.height * size.height, znear: 0, zfar: 1))
            let t = Float(shot.yaw * .pi / 180)
            var u = Uniforms(c: cos(t), s: sin(t), cp: cos(pitch), sp: sin(pitch), map: shot.map)
            enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 3)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint16, indexBuffer: indices, indexBufferOffset: 0)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        if let shotsFor { shots = shotsFor(view.drawableSize) }
        encode(enc, size: view.drawableSize)
        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    /// Draws one view of the body off screen, on a clear background, for the calendar's small figures.
    func image(width: Int, height: Int, yaw: Double) -> CGImage? {
        func texture(_ format: MTLPixelFormat, samples: Int, usage: MTLTextureUsage, storage: MTLStorageMode) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            d.textureType = samples > 1 ? .type2DMultisample : .type2D
            d.sampleCount = samples
            d.usage = usage
            d.storageMode = storage
            return device.makeTexture(descriptor: d)
        }
        guard let msaa = texture(.bgra8Unorm, samples: BodyRenderer.sampleCount, usage: .renderTarget, storage: .private),
              let resolved = texture(.bgra8Unorm, samples: 1, usage: [.renderTarget, .shaderRead], storage: .shared),
              let depth = texture(.depth32Float, samples: BodyRenderer.sampleCount, usage: .renderTarget, storage: .private),
              let buffer = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaa
        pass.colorAttachments[0].resolveTexture = resolved
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = depth
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        let saved = shots
        shots = [Shot(yaw: yaw, map: SIMD4(2 / 240, -2 / 440, -1, 1))]
        encode(enc, size: CGSize(width: width, height: height))
        shots = saved
        enc.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        resolved.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// The body stage: the Metal view plus the drag, pinch and tap handling from the prototype.
final class BodyStageView: UIView {
    let metal = MTKView()
    var renderer: BodyRenderer?
    weak var camera: BodyCamera?
    var onTap: ((CGPoint) -> Void)?

    private var dragStart: (yaw: Double, pan: CGSize)?
    private var pinchStart: (zoom: CGFloat, mid: CGPoint)?

    init(mesh: BodyMesh?, camera: BodyCamera) {
        self.camera = camera
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0xF3 / 255, green: 0xF6 / 255, blue: 0xF6 / 255, alpha: 1)
        metal.device = MTLCreateSystemDefaultDevice()
        metal.enableSetNeedsDisplay = true
        metal.isPaused = true
        metal.isUserInteractionEnabled = false
        metal.backgroundColor = .clear
        if let mesh { renderer = BodyRenderer(view: metal, mesh: mesh) }
        metal.delegate = renderer
        addSubview(metal)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        for g in [pan, pinch] as [UIGestureRecognizer] { addGestureRecognizer(g) }
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = "Body model. Tap to mark a point. Drag to turn the body. Pinch or use plus and minus to zoom."
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        metal.frame = bounds
        redraw()
    }

    private var lastYaw = 0.0

    func redraw(yaw: Double? = nil) {
        guard let camera, let renderer else { return }
        if let yaw { lastYaw = yaw }
        renderer.shots = [BodyRenderer.Shot(yaw: lastYaw, map: camera.clipMap)]
        metal.setNeedsDisplay()
    }

    // A tap is one finger that lifts without moving more than 6 points, as in the prototype.
    // A drag or pinch cancels the touch, so it never counts.
    private var tapStart: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        let all = event?.allTouches?.count ?? touches.count
        tapStart = all == 1 ? touches.first?.location(in: self) : nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        if let s = tapStart, let p = touches.first?.location(in: self), hypot(p.x - s.x, p.y - s.y) > 6 { tapStart = nil }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let s = tapStart else { return }
        tapStart = nil
        onTap?(s)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        tapStart = nil
    }

    @MainActor @objc private func onPan(_ g: UIPanGestureRecognizer) {
        guard let camera else { return }
        switch g.state {
        case .began:
            camera.stopSnap()
            dragStart = (camera.yaw, camera.pan)
        case .changed:
            guard let s = dragStart else { return }
            let t = g.translation(in: self)
            if camera.zoom > 1 {
                camera.pan = camera.clampedPan(camera.zoom, CGSize(width: s.pan.width + t.x, height: s.pan.height + t.y))
            } else {
                let w = bounds.width > 0 ? bounds.width : 318
                camera.yaw = BodyCamera.normYaw(s.yaw + Double(t.x / w * 318 * 0.7))
            }
        default:
            dragStart = nil
        }
    }

    @MainActor @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        guard let camera else { return }
        let mid = g.location(in: self)
        switch g.state {
        case .began:
            camera.stopSnap()
            pinchStart = (camera.zoom, mid)
        case .changed:
            guard var s = pinchStart else { return }
            camera.zoom(to: s.zoom * g.scale, about: mid)
            camera.pan = camera.clampedPan(camera.zoom, CGSize(width: camera.pan.width + mid.x - s.mid.x, height: camera.pan.height + mid.y - s.mid.y))
            s.mid = mid
            pinchStart = s
        default:
            if camera.zoom < 1.05 { camera.reset() }
            pinchStart = nil
        }
    }
}
