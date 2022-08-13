//
//  VideoTransitionRenderer.swift
//  VideoLab
//
//  Created by Joey Patino on 8/13/22.
//

import Foundation
import MTTransitions
import MetalPetal
import VideoToolbox

public class VideoTransitionRenderer: NSObject {
    
    public let effect: MTTransition.Effect
    
    private let transition: MTTransition
    
    public init(effect: MTTransition.Effect) {
        self.effect = effect
        self.transition = effect.transition
    }
    
    public func renderPixelBuffer(usingForegroundSourceBuffer foregroundImage: MTIImage,
                                  andBackgroundSourceBuffer backgroundImage: MTIImage,
                                  forTweenFactor tween: Float) -> MTIImage? {

        transition.inputImage = foregroundImage.oriented(.downMirrored)
        transition.destImage = backgroundImage.oriented(.downMirrored)
        transition.progress = tween
        
        guard let output = transition.outputImage else {
            return nil
        }
        return output
    }
}
