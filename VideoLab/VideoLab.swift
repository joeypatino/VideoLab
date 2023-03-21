//
//  VideoLab.swift
//  VideoLab
//
//  Created by Bear on 2020/8/22.
//  Copyright (c) 2020 Chocolate. All rights reserved.
//

import AVFoundation

public class VideoLab {
    public private(set) var renderComposition: RenderComposition
    
    private var videoRenderLayers: [VideoRenderLayer] = []
    private var audioRenderLayersInTimeline: [AudioRenderLayer] = []
    private var audioMix: AVAudioMix?
    
    // MARK: - Public
    public init(renderComposition: RenderComposition) {
        self.renderComposition = renderComposition
    }
    
    public func makePlayerItem() -> AVPlayerItem {
        let result = makeComposition()
        let playerItem = AVPlayerItem(asset: result.0)
        playerItem.videoComposition = makeVideoComposition(result)
        playerItem.audioMix = makeAudioMix()
        return playerItem
    }
    
    public func makeImageGenerator() -> AVAssetImageGenerator {
        let result = makeComposition()
        let imageGenerator = AVAssetImageGenerator(asset: result.0)
        imageGenerator.videoComposition = makeVideoComposition(result)
        return imageGenerator
    }
    
    public func makeExportSession(presetName: String, outputURL: URL) -> AVAssetExportSession? {
        let result = makeComposition()
        let exportSession = AVAssetExportSession(asset: result.0, presetName: presetName)
        let videoComposition = makeVideoComposition(result)
        videoComposition.animationTool = makeAnimationTool()
        exportSession?.videoComposition = videoComposition
        exportSession?.audioMix = makeAudioMix()
        exportSession?.outputURL = outputURL
        exportSession?.outputFileType = AVFileType.mov
        return exportSession
    }
    
    // MARK: - Private
    
    private func makeComposition() -> (AVMutableComposition, CompositionLayout, [AVMutableCompositionTrack], [AVMutableCompositionTrack]) {
        // TODO: optimize make performance, like return when exist
        let composition = AVMutableComposition()
                
        // Increase track ID
        var increasementTrackID: CMPersistentTrackID = 0
        func increaseTrackID() -> Int32 {
            let trackID = increasementTrackID + 1
            increasementTrackID = trackID
            return trackID
        }
        
        // Step 1: Add video tracks
        
        // Substep 1: Generate videoRenderLayers sorted by start time.
        // A videoRenderLayer can contain video tracks or the source of the layer is ImageSource.
        videoRenderLayers = renderComposition.layers.filter {
            $0.canBeConvertedToVideoRenderLayer()
        }.sorted {
            CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0
        }.compactMap {
            VideoRenderLayer.makeVideoRenderLayer(renderLayer: $0)
        }
        
        // Generate video track ID. This inline method is used in substep 2.
        // You can reuse the track ID if there is no intersection with some of the previous, otherwise increase an ID.
        var videoTrackIDInfo: [CMPersistentTrackID: CMTimeRange] = [:]
        func videoTrackID(for layer: VideoRenderLayer) -> CMPersistentTrackID {
            var videoTrackID: CMPersistentTrackID?
            for (trackID, timeRange) in videoTrackIDInfo {
                if layer.timeRangeInTimeline.start > timeRange.end {
                    videoTrackID = trackID
                    videoTrackIDInfo[trackID] = layer.timeRangeInTimeline
                    break
                }
            }
            
            if let videoTrackID = videoTrackID {
                return videoTrackID
            } else {
                let videoTrackID = increaseTrackID()
                videoTrackIDInfo[videoTrackID] = layer.timeRangeInTimeline
                return videoTrackID
            }
        }
        
        // Substep 2: Add all VideoRenderLayer tracks from the timeline to the composition.
        // Calculate minimum start time and maximum end time for substep 3.
        var videoRenderLayersInTimeline: [VideoRenderLayer] = []
        videoRenderLayers.forEach { videoRenderLayer in
            if let videoRenderLayerGroup = videoRenderLayer as? VideoRenderLayerGroup {
                videoRenderLayersInTimeline += videoRenderLayerGroup.recursiveVideoRenderLayers()
            } else {
                videoRenderLayersInTimeline.append(videoRenderLayer)
            }
        }
        
        var transitionVideoTracks: [AVMutableCompositionTrack] = composition.tracks(withMediaType: .video)
        var transitionAudioTracks: [AVMutableCompositionTrack] = composition.tracks(withMediaType: .audio)
        let layout = generateCompositionTracks(forComposition: composition,
                                               videoLayers: videoRenderLayersInTimeline,
                                               transitionVideoTracks: &transitionVideoTracks,
                                               transitionAudioTracks: &transitionAudioTracks)
        
        let minimumStartTime = videoRenderLayersInTimeline.first?.timeRangeInTimeline.start
        var maximumEndTime = videoRenderLayersInTimeline.first?.timeRangeInTimeline.end
        videoRenderLayersInTimeline.forEach { videoRenderLayer in
            if videoRenderLayer.renderLayer.source?.tracks(for: .video).first != nil {
                let trackID = videoTrackID(for: videoRenderLayer)
                videoRenderLayer.addVideoTrack(to: composition, preferredTrackID: trackID)
            }
            
            if maximumEndTime! < videoRenderLayer.timeRangeInTimeline.end {
                maximumEndTime = videoRenderLayer.timeRangeInTimeline.end
            }
        }
        
        // Substep 3: Add a blank video track for image or effect layers.
        // The track's duration is the same as timeline's duration.
        if let minimumStartTime = minimumStartTime, let maximumEndTime = maximumEndTime {
            let timeRange = CMTimeRange(start: minimumStartTime, end: maximumEndTime)
            let videoTrackID = increaseTrackID()
            VideoRenderLayer.addBlankVideoTrack(to: composition, in: timeRange, preferredTrackID: videoTrackID)
        }
        
        // Step 2: Add audio tracks
        
        // Substep 1: Generate audioRenderLayers sorted by start time.
        // A audioRenderLayer must contain audio tracks.
        let audioRenderLayers = renderComposition.layers.filter {
            $0.canBeConvertedToAudioRenderLayer()
        }.sorted {
            CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0
        }.compactMap {
            AudioRenderLayer.makeAudioRenderLayer(renderLayer: $0)
        }
        
        // Substep 2: Add tracks from the timeline to the composition.
        // Since AVAudioMixInputParameters only corresponds to one track ID, the audio track ID is not reused. One audio layer corresponds to one track ID.
        audioRenderLayersInTimeline = []
        audioRenderLayers.forEach { audioRenderLayer in
            if let audioRenderLayerGroup = audioRenderLayer as? AudioRenderLayerGroup {
                audioRenderLayersInTimeline += audioRenderLayerGroup.recursiveAudioRenderLayers()
            } else {
                audioRenderLayersInTimeline.append(audioRenderLayer)
            }
        }
        audioRenderLayersInTimeline.forEach { audioRenderLayer in
            if audioRenderLayer.renderLayer.source?.tracks(for: .audio).first != nil {
                let trackID = increaseTrackID()
                audioRenderLayer.trackID = trackID
                audioRenderLayer.addAudioTrack(to: composition, preferredTrackID: trackID)
            }
        }
        composition.tracks(withMediaType: .audio)
            .filter({ $0.timeRange == .invalid })
            .forEach {
                composition.removeTrack($0)
            }
        
        debugVideoLayers(videoRenderLayers)
        debugVideoLayers(videoRenderLayersInTimeline)
        debugCompositionTracks(composition: composition)
        return (composition, layout, transitionVideoTracks, transitionAudioTracks)
    }
    
    private func generateCompositionTracks(forComposition composition: AVMutableComposition,
                                           videoLayers: [VideoRenderLayer],
                                           transitionVideoTracks: inout [AVMutableCompositionTrack],
                                           transitionAudioTracks: inout [AVMutableCompositionTrack]) -> CompositionLayout {
        var compositionTimes: [CMTime] = [CMTime.zero]
        var passthroughRanges: [CMTimeRange] = []
        var transitionRanges: [CMTimeRange] = []
        var nextStartTime: CMTime = .zero
        var isPreviousLayerTransitionLayer = false

        while transitionVideoTracks.count < 2 {
            transitionVideoTracks.append(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!)
        }
        while transitionAudioTracks.count < 2 {
            transitionAudioTracks.append(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!)
        }
        
        for (idx, videoLayer) in videoLayers.enumerated() {
            let isTransitionLayer = videoLayer.transition.isAnimated
            let transitionDuration = CMTime(seconds: videoLayer.transition.duration, preferredTimescale: 600)
            let layerTimeRangeInTimeline = CMTimeRange(start: nextStartTime, duration: videoLayer.timeRangeInTimeline.duration)
            
            /// close range from last iteration and store the filterTimeRangeMap information
            if let endTime = compositionTimes.last, isPreviousLayerTransitionLayer  {
                let start = layerTimeRangeInTimeline.start
                transitionRanges.append(CMTimeRange(start: start, end: endTime))
            }
            
            // store the passThroughTimeRangeMap information
            if isTransitionLayer {
                var passThroughTimeRange: CMTimeRange
                if isPreviousLayerTransitionLayer {
                    passThroughTimeRange = CMTimeRange(start: CMTimeAdd(layerTimeRangeInTimeline.start, transitionDuration), end: CMTimeSubtract(layerTimeRangeInTimeline.end, transitionDuration))
                } else {
                    passThroughTimeRange = CMTimeRange(start: layerTimeRangeInTimeline.start, end: CMTimeSubtract(layerTimeRangeInTimeline.end, transitionDuration))
                }
                if idx == videoLayers.count-1 {
                    passThroughTimeRange = CMTimeRange(start: passThroughTimeRange.start, end: CMTimeAdd(passThroughTimeRange.end, transitionDuration))
                }
                //passThroughTimeRangeMap[videoRenderLayer.trackID] = passThroughTime
                passthroughRanges.append(passThroughTimeRange)
            }
            else {
                var passThroughTimeRange: CMTimeRange
                if isPreviousLayerTransitionLayer {
                    passThroughTimeRange = CMTimeRange(start: CMTimeAdd(layerTimeRangeInTimeline.start, transitionDuration), end: layerTimeRangeInTimeline.end)
                } else {
                    passThroughTimeRange = CMTimeRange(start: layerTimeRangeInTimeline.start, end: layerTimeRangeInTimeline.end)
                }
                if idx == videoLayers.count-1 {
                    passThroughTimeRange = CMTimeRange(start: passThroughTimeRange.start, end: passThroughTimeRange.end)
                }
                //passThroughTimeRangeMap[videoRenderLayer.trackID] = passThroughTime
                passthroughRanges.append(passThroughTimeRange)
            }
                        
            // store the times
            if !compositionTimes.contains(layerTimeRangeInTimeline.start) {
                compositionTimes.append(layerTimeRangeInTimeline.start)
            }
            if !compositionTimes.contains(layerTimeRangeInTimeline.end) {
                compositionTimes.append(layerTimeRangeInTimeline.end)
            }
            
            if videoLayer.renderGroup != nil {
                print("[VideoRenderLayerGroup]")
            } else {
                // MARK: this breaks VideoRenderGroups?
                // it offsets teh VideoLayers by the incorrect amout..
                // Do i instead need to offset by again by the groups offset... How?
                videoLayer.timeRangeInTimeline = layerTimeRangeInTimeline
            }
            
            // update offset for the next layer start time
            nextStartTime = CMTimeAdd(nextStartTime, layerTimeRangeInTimeline.duration)
            // if this layer is a transition, then offset the next start layer
            if isTransitionLayer { nextStartTime = CMTimeSubtract(nextStartTime, transitionDuration) }
            isPreviousLayerTransitionLayer = isTransitionLayer
        }
        compositionTimes.sort { $0 < $1 }
        
        debugTimeRanges(transitionRanges, title: "Transitions")
        debugTimeRanges(passthroughRanges, title: "Passthrough")
        return CompositionLayout(times: compositionTimes, passthroughRanges: passthroughRanges, transitionRanges: transitionRanges)
    }
    
    private func generateCompositionInstructions(forVideoLayers videoLayers: [VideoRenderLayer],
                                                 compositionLayout: CompositionLayout,
                                                 transitionVideoTracks: [AVMutableCompositionTrack],
                                                 transitionAudioTracks: [AVMutableCompositionTrack]) -> [VideoCompositionInstruction] {
        let times = compositionLayout.times
        let transitionRanges = compositionLayout.transitionRanges
        var instructions: [VideoCompositionInstruction] = []
        for index in 0..<times.count - 1 {
            let alternatingIndex = index % 2
            let startTime = times[index]
            let endTime = times[index + 1]
            let timeRange = CMTimeRange(start: startTime, end: endTime)
            let isTransition = transitionRanges.contains(where: { timeRange == $0 })
            
            func layers(_ layers: [VideoRenderLayer], intersecting: CMTimeRange) -> [VideoRenderLayer] {
                return layers.filter {
                    return !$0.timeRangeInTimeline.intersection(timeRange).isEmpty
                }
            }
            var intersectingVideoRenderLayers = layers(videoLayers, intersecting: timeRange)
            let transitionLayers = intersectingVideoRenderLayers
                .filter({ videoRenderLayer in
                transitionRanges.contains(where: {
                    !videoRenderLayer.timeRangeInTimeline.intersection($0).isEmpty
                })
            })
            intersectingVideoRenderLayers.sort { $0.renderLayer.layerLevel > $1.renderLayer.layerLevel }
            let transition = transitionLayers.compactMap { $0.transition }.first ?? .none
            let trackIDs = [ NSNumber(value: transitionVideoTracks[0].trackID), NSNumber(value: transitionVideoTracks[1].trackID) ]
            let instruction: VideoCompositionInstruction
            if isTransition {
                instruction = VideoCompositionInstruction(videoRenderLayers: intersectingVideoRenderLayers, theSourceTrackIDs: trackIDs, transition: transition, forTimeRange: timeRange)
                instruction.foregroundTrackID = transitionVideoTracks[1 - alternatingIndex].trackID
                instruction.backgroundTrackID = transitionVideoTracks[alternatingIndex].trackID
            } else {
                instruction = VideoCompositionInstruction(videoRenderLayers: intersectingVideoRenderLayers, forTimeRange: timeRange)
            }
            instructions.append(instruction)
        }
        debugInstructions(instructions)
        return instructions
    }
    
    
    private func makeVideoComposition(_ result: (composition: AVMutableComposition, layout: CompositionLayout, videoTracks: [AVMutableCompositionTrack], audioTracks: [AVMutableCompositionTrack])) -> AVMutableVideoComposition {
        // Create videoComposition. Specify frameDuration, renderSize, instructions, and customVideoCompositorClass.
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = renderComposition.frameDuration
        videoComposition.renderSize = renderComposition.renderSize
        videoComposition.customVideoCompositorClass = VideoCompositor.self
        videoComposition.instructions = generateCompositionInstructions(forVideoLayers: videoRenderLayers, compositionLayout: result.layout, transitionVideoTracks: result.videoTracks, transitionAudioTracks: result.audioTracks)
        return videoComposition
    }

    private func makeAudioMix() -> AVAudioMix? {
        // TODO: optimize make performance, like return when exist
        
        // Convert audioRenderLayers to inputParameters
        var inputParameters: [AVMutableAudioMixInputParameters] = []
        audioRenderLayersInTimeline.forEach { audioRenderLayer in
            let audioMixInputParameters = AVMutableAudioMixInputParameters()
            audioMixInputParameters.trackID = audioRenderLayer.trackID
            audioMixInputParameters.audioTimePitchAlgorithm = audioRenderLayer.pitchAlgorithm
            audioMixInputParameters.audioTapProcessor = audioRenderLayer.makeAudioTapProcessor()
            inputParameters.append(audioMixInputParameters)
        }
        
        // Create audioMix. Specify inputParameters.
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParameters
        self.audioMix = audioMix
        
        return audioMix
    }
    
    private func makeAnimationTool() -> AVVideoCompositionCoreAnimationTool? {
        guard let animationLayer = renderComposition.animationLayer else {
            return nil
        }
        
        let parentLayer = CALayer()
        parentLayer.isGeometryFlipped = true
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: CGPoint.zero, size: renderComposition.renderSize)
        videoLayer.frame = CGRect(origin: CGPoint.zero, size: renderComposition.renderSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(animationLayer)
        
        let animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
        return animationTool
    }
    
    // debug helpers
    
    private func debugVideoLayers(_ videoRenderLayers: [VideoRenderLayer], title: String = "VideoLayers", isTransition: Bool = false) {
        print()
        print("[\(title)]")
        videoRenderLayers.forEach { print(" [\($0.trackID)]: \($0.timeRangeInTimeline) \($0.transition.isAnimated && isTransition ? "(Transition: \($0.transition.effect))" : "")") }
        print()
    }
    
    private func debugCompositionTracks(composition: AVMutableComposition) {
        print()
        print("[Composition]")
        composition.tracks.forEach { print(" (\($0.trackID)) \($0.mediaType.rawValue) \($0.timeRange)") }
        print()
    }
    
    private func debugTimeRanges(_ timeRanges: [CMTimeRange], title: String) {
        print()
        print("[\(title)]")
        timeRanges.forEach { print(" \($0)") }
        print()
    }
    
    private func debugInstructions(_ instructions: [VideoCompositionInstruction]) {
        print()
        print("[Instruction]")
        instructions.forEach { print(" \($0.debugDescription)") }
        print()
    }
}

struct CompositionLayout {
    let times: [CMTime]
    let passthroughRanges: [CMTimeRange]
    let transitionRanges: [CMTimeRange]
}
