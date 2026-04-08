import Vision
import CoreGraphics

enum PlayerAction: String, Equatable {
    case idle   = "😐 In attesa"
    case attack = "⚔️ ATTACCO"
    case block  = "🛡️ PARATA"
}

// MARK: - BodyAnalyzer

class BodyAnalyzer {

    // MARK: Calibrazione
    private var baselineShoulderY: CGFloat?
    private var baselineHipY: CGFloat?
    private var calibrationShoulder: [CGFloat] = []
    private var calibrationHip: [CGFloat] = []
    private let calibrationCount = 60
    var isCalibrated: Bool { baselineShoulderY != nil }
    private var hipsAvailableInCalibration = false

    // Stabilità: aspetta che il corpo sia fermo prima di raccogliere dati
    private var stabilityBuffer: [CGFloat] = []
    private let stabilityWindowSize = 20       // frame da controllare
    private let stabilityThreshold: CGFloat = 0.008  // varianza max spalla Y
    private var isStable = false

    // MARK: Smoothing
    private var recentActions: [PlayerAction] = []
    private let smoothingWindow = 8

    // MARK: Hold — mantiene un'azione visibile per N frame anche se sparisce
    private var heldAction: PlayerAction = .idle
    private var holdCounter: Int = 0
    private let holdFrames = 20   // ~0.66s a 30fps

    // MARK: Storico polsi
    private var leftWristHistory:  [CGPoint] = []
    private var rightWristHistory: [CGPoint] = []
    private let wristHistorySize = 8

    // MARK: Cooldown attacco
    private var attackCooldown = 0
    private let attackCooldownFrames = 25

    // MARK: Soglie
    // Attacco: soglia leggermente alzata per evitare trigger su micro-movimenti
    private let swingSpeedThreshold: CGFloat = 0.018

    // Parata: condizioni più permissive
    private let blockWristAboveShoulderMargin: CGFloat = 0.02   // polsi almeno 2% sopra le spalle
    private let blockCenterRatio: CGFloat = 0.90                // braccia non devono essere perfettamente al centro
    private let blockWristHeightTolerance: CGFloat = 0.18       // più tollerante sull'altezza

    // MARK: - Analisi principale

        func analyze(_ observation: VNHumanBodyPoseObservation, isPlayerOne: Bool) -> PlayerAction {
            let shoulderY = avgY(observation, .leftShoulder, .rightShoulder)
            let hipY      = avgY(observation, .leftHip,      .rightHip)

            guard let sY = shoulderY else { return smoothed(.idle) }

            updateWristHistory(observation)
            if attackCooldown > 0 { attackCooldown -= 1 }

            // Calibrazione (invariata)
            if !isCalibrated {
                stabilityBuffer.append(sY)
                if stabilityBuffer.count > stabilityWindowSize { stabilityBuffer.removeFirst() }

                if !isStable {
                    if stabilityBuffer.count == stabilityWindowSize {
                        let mean = stabilityBuffer.reduce(0, +) / CGFloat(stabilityWindowSize)
                        let variance = stabilityBuffer.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / CGFloat(stabilityWindowSize)
                        if variance < stabilityThreshold {
                            isStable = true
                            print("⏳ Corpo stabile, inizio raccolta dati calibrazione...")
                        }
                    }
                    return .idle
                }

                calibrationShoulder.append(sY)
                if let hY = hipY { calibrationHip.append(hY) }
                if calibrationShoulder.count >= calibrationCount {
                    baselineShoulderY = median(calibrationShoulder)
                    if calibrationHip.count > calibrationCount / 2 {
                        baselineHipY = median(calibrationHip)
                        hipsAvailableInCalibration = true
                        print("✅ Calibrato con fianchi")
                    } else {
                        print("✅ Calibrato senza fianchi")
                    }
                }
                return .idle
            }

            let shoulderBaseline = baselineShoulderY!
            if abs(sY - shoulderBaseline) < 0.024 {
                baselineShoulderY = shoulderBaseline * 0.997 + sY * 0.003
            }

            if isBlockCross(observation) { return held(.block) }

            // ATTACCO: Ora passiamo l'identità del giocatore alla nuova funzione matematica
            if attackCooldown == 0 {
                let lSpeed = leftWristHistory.count >= 4 ? forwardSwingSpeed(history: leftWristHistory, isPlayerOne: isPlayerOne) : 0
                let rSpeed = rightWristHistory.count >= 4 ? forwardSwingSpeed(history: rightWristHistory, isPlayerOne: isPlayerOne) : 0
                if max(lSpeed, rSpeed) > swingSpeedThreshold {
                    attackCooldown = attackCooldownFrames
                    recentActions.removeAll()
                    return held(.attack)
                }
            }

            return held(smoothed(.idle))
        }

    // MARK: - Parata: mani sul viso (almeno un polso vicino alla testa)

    private func isBlockCross(_ obs: VNHumanBodyPoseObservation) -> Bool {
            guard let lW = joint(obs, .leftWrist, minConfidence: 0.15),
                  let rW = joint(obs, .rightWrist, minConfidence: 0.15),
                  let neck = joint(obs, .neck, minConfidence: 0.2) else {
                return false
            }

            // 1. Asse Y: I polsi devono essere sollevati all'altezza del collo o più su.
            let areHandsHigh = lW.y > (neck.y - 0.20) && rW.y > (neck.y - 0.20)

            // 2. Asse X: Le mani devono essere vicine tra loro orizzontalmente.
            let horizontalDist = abs(lW.x - rW.x)
            let areHandsClose = horizontalDist < 0.25

            return areHandsHigh && areHandsClose
        }

    // MARK: - Helpers

    private func avgY(_ obs: VNHumanBodyPoseObservation,
                      _ a: VNHumanBodyPoseObservation.JointName,
                      _ b: VNHumanBodyPoseObservation.JointName) -> CGFloat? {
        let pa = joint(obs, a); let pb = joint(obs, b)
        switch (pa, pb) {
        case let (a?, b?): return (a.y + b.y) / 2.0
        case let (a?, nil): return a.y
        case let (nil, b?): return b.y
        default: return nil
        }
    }

    private func median(_ v: [CGFloat]) -> CGFloat { let s = v.sorted(); return s[s.count/2] }

    // NUOVA FUNZIONE: Calcola solo la velocità in avanti verso l'avversario
    private func forwardSwingSpeed(history: [CGPoint], isPlayerOne: Bool) -> CGFloat {
            guard history.count >= 2 else { return 0 }
            var maxSpeed: CGFloat = 0
            
            for i in 1..<history.count {
                // Misuriamo SOLO lo scatto orizzontale assoluto (asse X).
                // Ignoriamo totalmente la Y, così un movimento in alto o in basso non innesca l'attacco.
                let dx = abs(history[i].x - history[i-1].x)
                maxSpeed = max(maxSpeed, dx)
            }
            return maxSpeed
        }

    private func updateWristHistory(_ obs: VNHumanBodyPoseObservation) {
        // Se il polso non è visibile, svuota la history per evitare
        // falsi attacchi quando riappare in una posizione distante
        if let lw = joint(obs, .leftWrist) {
            leftWristHistory.append(lw)
            if leftWristHistory.count > wristHistorySize { leftWristHistory.removeFirst() }
        } else {
            leftWristHistory.removeAll()
        }
        if let rw = joint(obs, .rightWrist) {
            rightWristHistory.append(rw)
            if rightWristHistory.count > wristHistorySize { rightWristHistory.removeFirst() }
        } else {
            rightWristHistory.removeAll()
        }
    }

    private func held(_ action: PlayerAction) -> PlayerAction {
        if action != .idle {
            heldAction = action
            holdCounter = holdFrames
        } else if holdCounter > 0 {
            holdCounter -= 1
            return heldAction
        } else {
            heldAction = .idle
        }
        return action
    }

    private func smoothed(_ action: PlayerAction) -> PlayerAction {
        recentActions.append(action)
        if recentActions.count > smoothingWindow { recentActions.removeFirst() }
        let counts = Dictionary(grouping: recentActions, by: { $0 }).mapValues { $0.count }
        for a in [PlayerAction.block] {
            if (counts[a] ?? 0) >= 2 { return a }
        }
        return .idle
    }

    private func joint(_ obs: VNHumanBodyPoseObservation,
                       _ name: VNHumanBodyPoseObservation.JointName,
                       minConfidence: Float = 0.3) -> CGPoint? {
        guard let p = try? obs.recognizedPoint(name), p.confidence > minConfidence else { return nil }
        return p.location
    }

    func resetCalibration() {
        baselineShoulderY = nil; baselineHipY = nil
        calibrationShoulder = []; calibrationHip = []
        hipsAvailableInCalibration = false
        recentActions = []; leftWristHistory = []; rightWristHistory = []
        attackCooldown = 0
        heldAction = .idle; holdCounter = 0
        stabilityBuffer = []; isStable = false
    }
}
