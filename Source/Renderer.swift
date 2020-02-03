import Metal
import MetalKit
import simd

let maxBuffersInFlight = 3

enum RendererError: Error {
    case badVertexDescriptor
}

var gDevice:MTLDevice!
var mtlVertexDescriptor:MTLVertexDescriptor!

var constants: [MTLBuffer] = []
var constantsSize: Int = MemoryLayout<ConstantData>.stride
var constantsIndex: Int = 0
let kInFlightCommandBuffers = 3
var translationAmount = simd_float3(-0.5,-0.5,0.75)

class Renderer: NSObject, MTKViewDelegate {
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState
    var depthState: MTLDepthStencilState
    var texture: MTLTexture
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    var samplerState:MTLSamplerState!
    
    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    
    init?(metalKitView: MTKView) {
        gDevice = metalKitView.device!
        self.commandQueue = gDevice.makeCommandQueue()!
        
        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.sampleCount = 1
        
        mtlVertexDescriptor = Renderer.buildMetalVertexDescriptor()
        
        do { pipelineState = try Renderer.buildRenderPipelineWithDevice(device: gDevice,  metalKitView: metalKitView,  mtlVertexDescriptor: mtlVertexDescriptor)
        } catch {  print("Unable to compile render pipeline state.  Error info: \(error)"); exit(0) }
        
        let depthStateDesciptor = MTLDepthStencilDescriptor()
        depthStateDesciptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDesciptor.isDepthWriteEnabled = true
        depthState = gDevice.makeDepthStencilState(descriptor:depthStateDesciptor)!
        
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter             = MTLSamplerMinMagFilter.nearest
        sampler.magFilter             = MTLSamplerMinMagFilter.nearest
        sampler.mipFilter             = MTLSamplerMipFilter.nearest
        sampler.maxAnisotropy         = 1
        sampler.sAddressMode          = MTLSamplerAddressMode.repeat
        sampler.tAddressMode          = MTLSamplerAddressMode.repeat
        sampler.rAddressMode          = MTLSamplerAddressMode.repeat
        sampler.normalizedCoordinates = true
        sampler.lodMinClamp           = 0
        sampler.lodMaxClamp           = .greatestFiniteMagnitude
        samplerState = gDevice.makeSamplerState(descriptor: sampler)
        
        do { texture = try Renderer.loadTexture("copper")
        } catch { print("Unable to load texture. Error info: \(error)");  exit(0)  }
        
        constants = []
        for _ in 0..<kInFlightCommandBuffers {
            constants.append(gDevice.makeBuffer(length: constantsSize, options: [])!)
        }
        
        super.init()
    }
    
    class func buildMetalVertexDescriptor() -> MTLVertexDescriptor {
        let mtlVertexDescriptor = MTLVertexDescriptor()
        
        mtlVertexDescriptor.attributes[0].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[0].offset = 0
        mtlVertexDescriptor.attributes[0].bufferIndex = 0
        
        mtlVertexDescriptor.attributes[1].format = MTLVertexFormat.float2
        mtlVertexDescriptor.attributes[1].offset = 0
        mtlVertexDescriptor.attributes[1].bufferIndex = 1
        
        mtlVertexDescriptor.layouts[0].stride = 12
        mtlVertexDescriptor.layouts[0].stepRate = 1
        mtlVertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunction.perVertex
        
        mtlVertexDescriptor.layouts[1].stride = 8
        mtlVertexDescriptor.layouts[1].stepRate = 1
        mtlVertexDescriptor.layouts[1].stepFunction = MTLVertexStepFunction.perVertex
        
        return mtlVertexDescriptor
    }
    
    class func buildRenderPipelineWithDevice(device: MTLDevice,
                                             metalKitView: MTKView,
                                             mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()
        
        let vFunction = library?.makeFunction(name: "texturedVertexShader")
        let fFunction = library?.makeFunction(name: "texturedFragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.sampleCount = metalKitView.sampleCount
        pipelineDescriptor.vertexFunction = vFunction
        pipelineDescriptor.fragmentFunction = fFunction
        pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    //MARK: -
    
    func draw(in view: MTKView) {
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        
        let semaphore = inFlightSemaphore
        commandBuffer?.addCompletedHandler { (_ commandBuffer)-> Swift.Void in semaphore.signal() }
        
        let renderPassDescriptor = view.currentRenderPassDescriptor
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor!)
        renderEncoder?.setCullMode(.back)
        renderEncoder?.setFrontFacing(.clockwise)
        renderEncoder?.setRenderPipelineState(pipelineState)
        renderEncoder?.setDepthStencilState(depthState)
        
        renderEncoder?.setFragmentTexture(texture, index:0)
        renderEncoder?.setFragmentSamplerState(samplerState, index: 0)
        
        // -----------------------------
        let cb = constants[constantsIndex].contents().assumingMemoryBound(to: ConstantData.self)
        cb[0].mvp = projectionMatrix * translate(translationAmount)
        cb[0].effectsEnabled = vc.effectsSwitch.isOn ? 1 : 0
        cb[0].bright = vc.bright
        cb[0].contrast = vc.contrast
        cb[0].saturation = vc.saturation
        cb[0].posterize = vc.posterize

        renderEncoder?.setVertexBuffer(constants[constantsIndex], offset:0, index: 1)
        
        // ----------------------------------------------
        vc.mesh.render(renderEncoder!)
        // ----------------------------------------------
        
        renderEncoder?.endEncoding()
        
        if let drawable = view.currentDrawable { commandBuffer?.present(drawable)  }
        commandBuffer?.commit()
        constantsIndex = (constantsIndex + 1) % kInFlightCommandBuffers
        
        vc.mesh.update()
    }
    
    //MARK: -
    
    class func loadTexture(_ textureName: String) throws -> MTLTexture {
        let textureLoader = MTKTextureLoader(device: gDevice)
        return try textureLoader.newTexture(name: textureName, scaleFactor: 1.0, bundle: nil,  options: nil)
    }
    
    func updateTexture(_ rawImg:UIImage) {
        let img = rawImg.scaleAndRotate(toSize: CGSize(width: rawImg.size.width, height:rawImg.size.height))!
        guard let cgImage = img.cgImage else { return }
        
        do {
            let textureLoader = MTKTextureLoader(device: gDevice)
            texture = try textureLoader.newTexture(cgImage:cgImage)
        }
        catch {
            fatalError("Can't load texture")
        }
    }
    
    //MARK: -
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width) / Float(size.height)
        let kFOVY: Float = 65.0
        projectionMatrix = perspective_fov(kFOVY, aspect, 0.1, 300.0)
    }
}

//MARK: -

extension UIImage {
    func rotate(radians: Float) -> UIImage? {
        var newSize = CGRect(origin: CGPoint.zero, size: self.size).applying(CGAffineTransform(rotationAngle: CGFloat(radians))).size
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
        let context = UIGraphicsGetCurrentContext()!
        
        context.translateBy(x: newSize.width/2, y: newSize.height/2) // Move origin to middle
        context.rotate(by: CGFloat(radians)) // Rotate around middle
        self.draw(in: CGRect(x: -self.size.width/2, y: -self.size.height/2, width: self.size.width, height: self.size.height))
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
    
    func scaleAndRotate(toSize newSize:CGSize) -> UIImage? {
        var newImage: UIImage?
        let newRect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height).integral
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        
        if let context = UIGraphicsGetCurrentContext(), let cgImage = self.cgImage {
            context.interpolationQuality = .high
            let flipVertical = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: newSize.height)
            context.concatenate(flipVertical)
            context.draw(cgImage, in: newRect)
            
            if let img = context.makeImage() {
                newImage = UIImage(cgImage: img)
                
                //print(UIDevice.current.orientation.rawValue)
                switch UIDevice.current.orientation.rawValue {
                case 1 : newImage = newImage!.rotate(radians: Float(Double.pi / 2))
                case 2 : newImage = newImage!.rotate(radians: -Float(Double.pi / 2))
                case 4 : newImage = newImage!.rotate(radians: Float(Double.pi))
                default : break
                }
            }
            
            UIGraphicsEndImageContext()
        }
        
        return newImage
    }
}

