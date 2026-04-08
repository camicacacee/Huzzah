//
//  BodyTracking.swift
//  battaglia
//

import Vision

// MARK: - PlayersDetectionResult

struct PlayersDetectionResult {
    var player1: (action: PlayerAction, observation: VNHumanBodyPoseObservation)?
    var player2: (action: PlayerAction, observation: VNHumanBodyPoseObservation)?

    // Hand pose observations per player (nil se non rilevata)
    var hand1: VNHumanHandPoseObservation?
    var hand2: VNHumanHandPoseObservation?
}

// MARK: - BodyTrackingDelegate

protocol BodyTrackingDelegate: AnyObject {
    func didDetectPlayers(_ result: PlayersDetectionResult)
    func didLoseTracking()
}
