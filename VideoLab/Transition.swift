//
//  Transition.swift
//  VideoLab
//
//  Created by Joey Patino on 8/13/22.
//

import Foundation
import MTTransitions

public final class Transition {
    public static let none = Transition(.none)
    public let effect: MTTransition.Effect
    public var duration: Double = 1.5
    public var isAnimated: Bool { effect != .none && duration != 0 }

    public init(_ effect: Transition.Effect) {
        self.effect = effect
    }
}

extension Transition {
    public static func == (lhs: Transition, rhs: Transition) -> Bool {
        lhs.effect == rhs.effect
    }
    
    public static func != (lhs: Transition, rhs: Transition) -> Bool {
        lhs.effect != rhs.effect
    }
}

extension Transition {
    public typealias Effect = MTTransition.Effect
}
