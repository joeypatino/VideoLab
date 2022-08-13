//
//  CMTime.swift
//  VideoLab
//
//  Created by Joey Patino on 8/13/22.
//

import AVFoundation

extension CMTimeRange: CustomDebugStringConvertible, CustomStringConvertible {
    public var description: String {
        debugDescription
    }
    
    public var debugDescription: String {
        "\(start.seconds) - \(end.seconds)  (\(duration.seconds)s)"
    }
}

extension CMTime: CustomDebugStringConvertible, CustomStringConvertible {
    public var description: String {
        debugDescription
    }
    
    public var debugDescription: String {
        "\(seconds)s"
    }
}
