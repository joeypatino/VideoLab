//
//  VideoCompositor.swift
//  VideoLab
//
//  Created by Bear on 02/19/2020.
//  Copyright (c) 2020 Chocolate. All rights reserved.
//

import AVFoundation
import MTTransitions

class VideoCompositor: NSObject, AVVideoCompositing {
    private var renderingQueue = DispatchQueue(label: "com.studio.VideoLab.renderingqueue")
    private var renderContextQueue = DispatchQueue(label: "com.studio.VideoLab.rendercontextqueue")
    private var renderContext: AVVideoCompositionRenderContext?
    private var shouldCancelAllRequests = false
    
    private let layerCompositor = LayerCompositor()
    
    /// Returns the pixel buffer attributes required by the video compositor for new buffers created for processing.
    var requiredPixelBufferAttributesForRenderContext: [String : Any] =
    [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    
    /// The pixel buffer attributes of pixel buffers that will be vended by the adaptor’s CVPixelBufferPool.
    var sourcePixelBufferAttributes: [String : Any]? =
    [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    
    /// Maintain the state of render context changes.
    private var internalRenderContextDidChange = false
    
    /// Actual state of render context changes.
    private var renderContextDidChange: Bool {
        get { renderContextQueue.sync { internalRenderContextDidChange } }
        set { renderContextQueue.sync { internalRenderContextDidChange = newValue } }
    }
    
    override init() {
        super.init()
    }
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContextQueue.sync {
            renderContext = newRenderContext
        }
        renderContextDidChange = true
    }
    
    enum PixelBufferRequestError: Error {
        case newRenderedPixelBufferForRequestFailure
    }
    
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            renderingQueue.async {
                if self.shouldCancelAllRequests {
                    request.finishCancelledRequest()
                } else {
                    guard let resultPixels = self.newRenderedPixelBufferForRequest(request) else {
                        request.finish(with: PixelBufferRequestError.newRenderedPixelBufferForRequestFailure)
                        return
                    }
                    
                    request.finish(withComposedVideoFrame: resultPixels)
                }
            }
        }
    }
    
    func cancelAllPendingVideoCompositionRequests() {
        renderingQueue.sync {
            shouldCancelAllRequests = true
        }
        renderingQueue.async {
            self.shouldCancelAllRequests = false
        }
    }
    
    // MARK: - Private
    func newRenderedPixelBufferForRequest(_ request: AVAsynchronousVideoCompositionRequest) -> CVPixelBuffer? {
        guard let newPixelBuffer = renderContext?.newPixelBuffer() else {
            return nil
        }
        
        if renderContextDidChange { renderContextDidChange = false }
        
        layerCompositor.renderPixelBuffer(newPixelBuffer, for: request)
        
        return newPixelBuffer
    }
}
