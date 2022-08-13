//
//  VideoCompositionInstruction.swift
//  VideoLab
//
//  Created by Bear on 2020/8/29.
//  Copyright © 2020 Chocolate. All rights reserved.
//

import AVFoundation

class VideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    /// ID used to identify the foreground frame.
    var foregroundTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    
    /// ID used to identify the background frame.
    var backgroundTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    
    /// Effect applied to video transition
    var transition: Transition
    
    var timeRange: CMTimeRange {
        get { return self.overrideTimeRange }
        set { self.overrideTimeRange = newValue }
    }
    
    var enablePostProcessing: Bool {
        get { return self.overrideEnablePostProcessing }
        set { self.overrideEnablePostProcessing = newValue }
    }
    
    var containsTweening: Bool {
        get { return self.overrideContainsTweening }
        set { self.overrideContainsTweening = newValue }
    }
    
    var requiredSourceTrackIDs: [NSValue]? {
        get { return self.overrideRequiredSourceTrackIDs }
        set { self.overrideRequiredSourceTrackIDs = newValue }
    }
    
    var passthroughTrackID: CMPersistentTrackID {
        get { return self.overridePassthroughTrackID }
        set { self.overridePassthroughTrackID = newValue }
    }
    
    /// The timeRange during which instructions will be effective.
    private var overrideTimeRange: CMTimeRange = CMTimeRange()
    
    /// Indicates whether post-processing should be skipped for the duration of the instruction.
    private var overrideEnablePostProcessing = false
    
    /// Indicates whether to avoid some duplicate processing when rendering a frame from the same source and destinatin at different times.
    private var overrideContainsTweening = false
    
    /// The track IDs required to compose frames for the instruction.
    private var overrideRequiredSourceTrackIDs: [NSValue]?
    
    /// Track ID of the source frame when passthrough is in effect.
    private var overridePassthroughTrackID: CMPersistentTrackID = 0
    
    public var videoRenderLayers: [VideoRenderLayer]
    
    init(videoRenderLayers: [VideoRenderLayer], forTimeRange theTimeRange: CMTimeRange) {
        self.transition = Transition.none
        self.videoRenderLayers = videoRenderLayers
        super.init()
        overrideRequiredSourceTrackIDs = [NSValue]()
//        overrideRequiredSourceTrackIDs = videoRenderLayers.reduce(into: Set<CMPersistentTrackID>()) { result, layer in
//            if let videoRenderLayerGroup = layer as? VideoRenderLayerGroup {
//                let recursiveTrackIDs = videoRenderLayerGroup.recursiveTrackIDs()
//                result = result.union(Set(recursiveTrackIDs))
//            } else {
//                result.insert(layer.trackID)
//            }
//        }.compactMap { $0 }
//            .filter { $0 != kCMPersistentTrackID_Invalid }
//            .compactMap { $0 as NSValue }
        overrideTimeRange = theTimeRange
        overridePassthroughTrackID = videoRenderLayers.compactMap({ $0.trackID }).last ?? kCMPersistentTrackID_Invalid
        overrideContainsTweening = false
        overrideEnablePostProcessing = false
    }
    
    init(videoRenderLayers: [VideoRenderLayer], theSourceTrackIDs: [NSValue], transition: Transition, forTimeRange theTimeRange: CMTimeRange) {
        self.transition = transition
        self.videoRenderLayers = videoRenderLayers
        super.init()
        overrideRequiredSourceTrackIDs = theSourceTrackIDs
//        overrideRequiredSourceTrackIDs = videoRenderLayers.reduce(into: Set<CMPersistentTrackID>()) { result, layer in
//            if let videoRenderLayerGroup = layer as? VideoRenderLayerGroup {
//                let recursiveTrackIDs = videoRenderLayerGroup.recursiveTrackIDs()
//                result = result.union(Set(recursiveTrackIDs))
//            } else {
//                result.insert(layer.trackID)
//            }
//        }.compactMap { $0 }
//            .filter { $0 != kCMPersistentTrackID_Invalid }
//            .compactMap { $0 as NSValue }
        overrideTimeRange = theTimeRange
        overridePassthroughTrackID = kCMPersistentTrackID_Invalid
        overrideContainsTweening = true
        overrideEnablePostProcessing = false
    }
}

extension VideoCompositionInstruction {
    override var debugDescription: String {
        var desc = """
[VideoCompositionInstruction] (\(passthroughTrackID)) \(requiredSourceTrackIDs ?? [])
    ForegroundTrackId: [\(foregroundTrackID)] BackgroundTrackId: [\(backgroundTrackID)]
    TimeRange: \(timeRange)
"""
        if transition.isAnimated { desc += "\n    Transition: \(transition.effect)" }
        desc += "\n"
        return desc
    }
}
