//
//  RenderLayerGroup.swift
//  VideoLab
//
//  Created by Bear on 2020/8/19.
//  Copyright © 2020 Chocolate. All rights reserved.
//

import AVFoundation

public class RenderLayerGroup: RenderLayer {
    public var layers: [RenderLayer] = [] {
        didSet { layers.forEach { $0.renderGroup = self } }
    }
}
