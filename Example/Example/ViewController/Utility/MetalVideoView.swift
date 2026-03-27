//
//  MetalVideoView.swift
//  Example
//
//  Created by William.Weng on 2026/3/27.
//

import MetalKit

final class MetalVideoView: MTKView {
    
    private var textureCache: CVMetalTextureCache?
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    
    private var currentTexture: MTLTexture?
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        commonInit()
    }
        
    override func draw(_ rect: CGRect) {
        
        guard let currentDrawable = currentDrawable,
              let texture = currentTexture,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPass = currentRenderPassDescriptor
        else { return }
        
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)!

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}

extension MetalVideoView {
    
    func display(pixelBuffer: CVPixelBuffer) {
        
        guard let textureCache = textureCache else { return }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        
        if (result != kCVReturnSuccess) { return }
        if let cvTexture { currentTexture = CVMetalTextureGetTexture(cvTexture) }
        
        setNeedsDisplay()
    }
}

private extension MetalVideoView {
    
    func commonInit() {
        
        guard let device = device else { fatalError("Metal device is nil") }
        guard let library = device.makeDefaultLibrary() else { fatalError("Failed to create default Metal library") }
        
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        
        commandQueue = device.makeCommandQueue()
        
        let pipelineDesc = MTLRenderPipelineDescriptor()

        pipelineDesc.vertexFunction = library.makeFunction(name: "vertex_passthrough")
        pipelineDesc.fragmentFunction = library.makeFunction(name: "fragment_texture")
        pipelineDesc.colorAttachments[0].pixelFormat = colorPixelFormat
        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDesc)
        
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        
        isPaused = true
        enableSetNeedsDisplay = true
    }
}
