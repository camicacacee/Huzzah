//
//  FairyTrackingViewController.swift
//  battaglia
//

import UIKit
import Vision
import SceneKit
import Speech
import AVFoundation
import ReplayKit

class FairyTrackingViewController: UIViewController {

    // MARK: - Config
    var onGoHome: (() -> Void)?

    // MARK: - Player names
    private static let fairyNames = [
        "Lady Gets Away", "Twinkle the Destroyer", "Countess Ice Cold",
        "Dazzling and Dangerous", "The Beautiful Problem", "Countess Never Tired",
        "Lady Hits Different", "The One You Missed", "Lady Wings Too Small for That Attitude",
        "The Tiny Fury", "The Dangerous One", "Lady Glitter in Your Eyes",
        "Lady Watch Out", "Lady Cute Until Provoked", "Lady Already Won"
    ]

    // MARK: - UI
    private let cameraPreviewView = UIView()
    private lazy var player1Box   = FairyHUDView(
        playerName: FairyTrackingViewController.fairyNames[Int.random(in: 0..<FairyTrackingViewController.fairyNames.count)],
        color: .systemCyan, rightSide: false)
    private lazy var player2Box   = FairyHUDView(
        playerName: FairyTrackingViewController.fairyNames[Int.random(in: 0..<FairyTrackingViewController.fairyNames.count)],
        color: .systemOrange, rightSide: true)
    private let calibrationLabel  = UILabel()
    private let warningLabel      = UILabel()
    private let statusDot         = UIView()
    private let pauseButton       = UIButton(type: .system)
    private let pauseOverlay      = UIView()
    private let startButton        = UIButton(type: .system)
    private let calibrateButton    = UIButton(type: .system)

    // MARK: - SceneKit
    private let scnView  = SCNView()
    private let scnScene = SCNScene()
    private var emitter1:   SCNNode?
    private var emitter2:   SCNNode?
    private var handLight1: SCNNode?
    private var handLight2: SCNNode?
    private var chestNode1: SCNNode?
    private var chestNode2: SCNNode?

    // MARK: - Tracking
    private let cameraManager = CameraManager()

    private var p1HandPos:    SCNVector3 = SCNVector3(-200, 0, 20)
    private var p2HandPos:    SCNVector3 = SCNVector3( 200, 0, 20)
    private var p1BodyPos:    SCNVector3 = SCNVector3( 200, 0, 20)
    private var p2BodyPos:    SCNVector3 = SCNVector3(-200, 0, 20)
    private var p1HandSmooth: SCNVector3 = SCNVector3(-200, 0, 20)
    private var p2HandSmooth: SCNVector3 = SCNVector3( 200, 0, 20)
    private let posAlpha: Float = 0.25

    private var p1WristHistory: [CGPoint] = []
    private var p2WristHistory: [CGPoint] = []
    private let wristHistorySize = 8

    private var p1ElbowDist: [Float] = []
    private var p2ElbowDist: [Float] = []
    private let elbowHistorySize = 6

    private var p1Power:    Float = 0
    private var p2Power:    Float = 0
    private let powerAlpha: Float = 0.25   // reattività salita
    private let powerDecay: Float = 0.75   // cade veloce quando ci si ferma

    // MARK: - Game state
    private var isReady          = false
    private var countdownStarted = false
    private var bothPlayersVisible = false
    private var bothDetectedFrames = 0           // conta frame con entrambi rilevati
    private let framesBeforeCountdown = 30       // ~1s a 30fps

    // MARK: - HP
    private var p1HP          = 100
    private var p2HP          = 100
    private var isGameOver    = false
    private let hitCooldown   = 20
    private var p1HitCooldown = 0
    private var p2HitCooldown = 0
    private let lowHealthThreshold = 30

    // MARK: - Audio
    private var battleMusicPlayer:    AVAudioPlayer?
    private var countdownPlayers:     [AVAudioPlayer] = []   // 321Fight_1/2/3.mp3
    private var lowHealthPlayers:     [AVAudioPlayer] = []
    private var lowHealthBothPlayers: [AVAudioPlayer] = []
    private var lowHealthP1Played     = false
    private var lowHealthP2Played     = false
    private var lowHealthBothPlayed   = false

    // MARK: - Speech (stesso sistema di Knight)
    private let speechRecognizer  = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:    SFSpeechRecognitionTask?
    private let audioEngine        = AVAudioEngine()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCamera()
        setupSceneKit()
        setupPauseOverlay()
        setupAudio()
        requestSpeechAndStart()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        cameraManager.startSession()
        startRecording()
    }

    private func startRecording() {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable, !recorder.isRecording else { return }
        recorder.startRecording { _ in }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cameraManager.stopSession()
        stopSpeech()
        stopBattleMusic()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraManager.previewLayer?.frame = cameraPreviewView.bounds
        cameraManager.previewLayer?.connection?.videoRotationAngle = 180
    }

    // MARK: - Camera

    private func setupCamera() {
        cameraManager.delegate        = self
        cameraManager.expectedPlayers = 2
        cameraManager.dominantHand    = "right"
        cameraManager.setupCamera()
        if let layer = cameraManager.previewLayer {
            cameraPreviewView.layer.insertSublayer(layer, at: 0)
        }
    }

    // MARK: - Audio

    private func setupAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("⚠️ AVAudioSession: \(error)") }

        // Countdown audio: 321Fight.mp3, 321Fight_2.mp3, 321Fight_3.mp3 — scelto random
        let countdownNames = ["321Fight", "321Fight_2", "321Fight_3"]
        for name in countdownNames {
            if let path = Bundle.main.path(forResource: name, ofType: "mp3"),
               let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) {
                p.prepareToPlay(); countdownPlayers.append(p)
            }
        }

        for i in 1...3 {
            if let path = Bundle.main.path(forResource: "LowHealth_\(i)", ofType: "mp3"),
               let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) {
                p.prepareToPlay(); lowHealthPlayers.append(p)
            }
        }
        for i in 1...2 {
            if let path = Bundle.main.path(forResource: "LowHealthBoth_\(i)", ofType: "mp3"),
               let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) {
                p.prepareToPlay(); lowHealthBothPlayers.append(p)
            }
        }
    }

    private func playLowHealthIfNeeded() {
        let anyPlaying = (lowHealthPlayers + lowHealthBothPlayers).contains { $0.isPlaying }
        guard !anyPlaying else { return }
        let p1Low = p1HP <= lowHealthThreshold
        let p2Low = p2HP <= lowHealthThreshold
        if p1Low && p2Low && !lowHealthBothPlayed {
            lowHealthBothPlayed = true
            lowHealthBothPlayers.randomElement().map { $0.currentTime = 0; $0.play() }
        } else if p1Low && !lowHealthP1Played {
            lowHealthP1Played = true
            lowHealthPlayers.randomElement().map { $0.currentTime = 0; $0.play() }
        } else if p2Low && !lowHealthP2Played {
            lowHealthP2Played = true
            lowHealthPlayers.randomElement().map { $0.currentTime = 0; $0.play() }
        }
    }

    private func startBattleMusic() {
        let tracks = ["giostra", "giostra2"]
        guard let name = tracks.randomElement(),
              let path = Bundle.main.path(forResource: name, ofType: "mp3"),
              let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else { return }
        p.numberOfLoops = -1; p.volume = 0.25
        p.prepareToPlay(); p.play()
        battleMusicPlayer = p
    }

    private func stopBattleMusic() {
        battleMusicPlayer?.stop(); battleMusicPlayer = nil
    }

    // MARK: - Speech (stesso sistema Knight — funziona)

    private func requestSpeechAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status == .authorized { self?.startSpeech() }
            }
        }
    }

    private func startSpeech() {
        stopSpeech()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        let inputNode = audioEngine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1024,
                             format: inputNode.outputFormat(forBus: 0)) { buf, _ in
            request.append(buf)
        }
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let text = result?.bestTranscription.formattedString.uppercased() {
                if text.contains("READY") && !self.isReady && !self.countdownStarted {
                    DispatchQueue.main.async {
                        if self.bothPlayersVisible {
                            self.startCountdown()
                        } else {
                            self.flashWarning()
                        }
                    }
                }
            }
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.startSpeech() }
            }
        }
        audioEngine.prepare()
        try? audioEngine.start()
    }

    private func stopSpeech() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil; recognitionTask = nil
    }

    private func flashWarning() {
        warningLabel.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.2, animations: {
            self.warningLabel.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0) {
                self.warningLabel.alpha = 0
            }
        }
    }

    // MARK: - Countdown

    private func startCountdown() {
        guard !countdownStarted else { return }
        countdownStarted = true
        calibrationLabel.isHidden = true

        guard let player = countdownPlayers.randomElement() else {
            activateGame(); return
        }
        player.currentTime = 0
        player.play()

        // Distribuiamo i 4 step proporzionalmente sulla durata dell'audio
        // così FIGHT! compare mentre l'audio lo sta dicendo
        let dur = player.duration
        let steps: [(String, Double)] = [
            ("3",      0),
            ("2",      dur * 0.25),
            ("1",      dur * 0.50),
            ("FIGHT!", dur * 0.75)
        ]
        for (text, delay) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.showCountdownLabel(text)
            }
        }

        // Gioco attivo alla fine esatta dell'audio
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) { [weak self] in
            self?.activateGame()
        }
    }

    private func activateGame() {
        isReady = true
        startBattleMusic()
    }

    private func showCountdownLabel(_ text: String) {
        let isFight = text == "FIGHT!"
        // Pattern Knight: label nuova per ogni step, nessun conflitto di animazione
        let label = UILabel()
        label.text          = text
        label.font          = UIFont(name: "MagicSchoolOne", size: isFight ? 96 : 120)
                              ?? .systemFont(ofSize: isFight ? 96 : 120, weight: .black)
        label.textColor     = isFight ? UIColor(red: 0.8, green: 0.4, blue: 1.0, alpha: 1) : .white
        label.textAlignment = .center
        label.layer.shadowColor   = UIColor.black.cgColor
        label.layer.shadowRadius  = 10
        label.layer.shadowOpacity = 0.9
        label.layer.shadowOffset  = .zero
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alpha     = 0
        label.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(equalTo: view.widthAnchor)
        ])
        UIView.animate(withDuration: 0.15, animations: {
            label.alpha     = 1
            label.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.25, delay: isFight ? 0.8 : 0.55) {
                label.alpha     = 0
                label.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
    }

    // MARK: - SceneKit

    private func setupSceneKit() {
        scnView.scene                    = scnScene
        scnView.backgroundColor          = .clear
        scnView.isUserInteractionEnabled = false
        scnView.translatesAutoresizingMaskIntoConstraints = false
        scnView.allowsCameraControl      = false
        scnView.antialiasingMode         = .multisampling4X
        scnView.isPlaying                = true

        let camNode = SCNNode()
        camNode.camera                             = SCNCamera()
        camNode.camera?.usesOrthographicProjection = false
        camNode.camera?.fieldOfView                = 60
        camNode.camera?.zNear                      = 0.1
        camNode.camera?.zFar                       = 2000
        camNode.position                           = SCNVector3(0, 0, 800)
        scnScene.rootNode.addChildNode(camNode)
        scnView.pointOfView = camNode

        let amb = SCNNode()
        amb.light            = SCNLight()
        amb.light?.type      = .ambient
        amb.light?.intensity = 600
        scnScene.rootNode.addChildNode(amb)

        view.addSubview(scnView)
        NSLayoutConstraint.activate([
            scnView.topAnchor.constraint(equalTo: view.topAnchor),
            scnView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scnView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scnView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        setupEmitters()

        view.bringSubviewToFront(player1Box)
        view.bringSubviewToFront(player2Box)
        view.bringSubviewToFront(calibrationLabel)
        view.bringSubviewToFront(statusDot)
        view.bringSubviewToFront(warningLabel)
        if let sub = view.viewWithTag(9901) { view.bringSubviewToFront(sub) }
        view.bringSubviewToFront(pauseButton)
        view.bringSubviewToFront(startButton)
        view.bringSubviewToFront(calibrateButton)
    }

    // MARK: - Beam

    private func makeParticleSystem(color: UIColor, birthRate: CGFloat, size: CGFloat,
                                     velocity: CGFloat, lifespan: Double,
                                     spread: CGFloat, emitterRadius: CGFloat) -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.birthRate                 = birthRate
        ps.emitterShape              = SCNSphere(radius: emitterRadius)
        ps.spreadingAngle            = spread
        ps.particleLifeSpan          = lifespan
        ps.particleLifeSpanVariation = lifespan * 0.3
        ps.particleVelocity          = velocity
        ps.particleVelocityVariation = velocity * 0.3
        ps.particleSize              = size
        ps.particleSizeVariation     = size * 0.4
        ps.particleColor             = color
        ps.isLightingEnabled         = false
        ps.blendMode                 = .additive
        ps.isAffectedByGravity       = false
        ps.loops                     = true
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values   = [1.0, 0.6, 0.0]
        fade.keyTimes = [0, 0.5, 1.0]
        ps.propertyControllers = [SCNParticleSystem.ParticleProperty.opacity:
                                    SCNParticlePropertyController(animation: fade)]
        return ps
    }

    private func setupEmitters() {
        func makeBeamNode(color: UIColor) -> SCNNode {
            let node = SCNNode()
            // Particelle che scorrono lungo il raggio dalla mano al petto
            let stream = makeParticleSystem(color: color, birthRate: 0,
                                            size: 7, velocity: 500,
                                            lifespan: 0.45, spread: 3, emitterRadius: 3)
            node.addParticleSystem(stream)
            return node
        }

        func makeImpactNode(color: UIColor) -> SCNNode {
            let node = SCNNode()
            // Esplosione sull'impatto — scintille veloci
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: nil)
            let burst = makeParticleSystem(
                color: UIColor(red: min(1, r*1.4), green: min(1, g*1.4), blue: min(1, b*1.4), alpha: 1),
                birthRate: 0, size: 9, velocity: 180, lifespan: 0.3, spread: 70, emitterRadius: 6)
            // Alone più grande e diffuso attorno al punto di impatto
            let halo = makeParticleSystem(color: color, birthRate: 0,
                                          size: 18, velocity: 40,
                                          lifespan: 0.5, spread: 90, emitterRadius: 10)
            node.addParticleSystem(burst)
            node.addParticleSystem(halo)
            // Luce puntuale sull'impatto
            let light = SCNLight()
            light.type      = .omni
            light.color     = color
            light.intensity = 0
            light.attenuationStartDistance = 20
            light.attenuationEndDistance   = 200
            node.light = light
            return node
        }

        let e1 = makeBeamNode(color: UIColor(red: 0.5, green: 0.1, blue: 1.0, alpha: 1))
        scnScene.rootNode.addChildNode(e1); emitter1 = e1

        let e2 = makeBeamNode(color: UIColor(red: 0.9, green: 0.1, blue: 0.8, alpha: 1))
        scnScene.rootNode.addChildNode(e2); emitter2 = e2

        let i1 = makeImpactNode(color: UIColor(red: 0.5, green: 0.1, blue: 1.0, alpha: 1))
        scnScene.rootNode.addChildNode(i1); handLight1 = i1

        let i2 = makeImpactNode(color: UIColor(red: 0.9, green: 0.1, blue: 0.8, alpha: 1))
        scnScene.rootNode.addChildNode(i2); handLight2 = i2

        // Indicatori petto — piccola sfera pulsante sul target
        func makeChestIndicator(color: UIColor) -> SCNNode {
            let sphere = SCNSphere(radius: 8)
            let mat = SCNMaterial()
            mat.diffuse.contents  = UIColor.white
            mat.emission.contents = color
            mat.blendMode         = .add
            sphere.materials      = [mat]
            let node = SCNNode(geometry: sphere)
            // Alone esterno semitrasparente
            let haloSphere = SCNSphere(radius: 18)
            let haloMat    = SCNMaterial()
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: nil)
            haloMat.diffuse.contents  = UIColor(red: r, green: g, blue: b, alpha: 0.25)
            haloMat.emission.contents = UIColor(red: r, green: g, blue: b, alpha: 0.25)
            haloMat.blendMode         = .add
            haloMat.isDoubleSided     = true
            haloSphere.materials      = [haloMat]
            let haloNode = SCNNode(geometry: haloSphere)
            node.addChildNode(haloNode)
            // Animazione pulsazione
            let pulse = CABasicAnimation(keyPath: "scale")
            pulse.fromValue    = SCNVector3(1.0, 1.0, 1.0)
            pulse.toValue      = SCNVector3(1.4, 1.4, 1.4)
            pulse.duration     = 0.6
            pulse.autoreverses = true
            pulse.repeatCount  = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            node.addAnimation(pulse, forKey: "pulse")
            return node
        }
        let c1 = makeChestIndicator(color: UIColor(red: 0.5, green: 0.1, blue: 1.0, alpha: 1))
        c1.isHidden = true
        scnScene.rootNode.addChildNode(c1); chestNode1 = c1

        let c2 = makeChestIndicator(color: UIColor(red: 0.9, green: 0.1, blue: 0.8, alpha: 1))
        c2.isHidden = true
        scnScene.rootNode.addChildNode(c2); chestNode2 = c2
    }

    private func applyRotation(to node: SCNNode, from: simd_float3, to dest: simd_float3) {
        let diff    = dest - from
        let yAxis   = simd_float3(0, 1, 0)
        let dirNorm = simd_normalize(diff)
        let axis    = simd_cross(yAxis, dirNorm)
        let dot     = simd_dot(yAxis, dirNorm)
        let angle   = acos(max(-1, min(1, dot)))
        if simd_length(axis) > 0.001 {
            let na = simd_normalize(axis)
            node.rotation = SCNVector4(na.x, na.y, na.z, angle)
        }
    }

    private func updateBeam(emitter: SCNNode?, light: SCNNode?,
                             handPos: SCNVector3, targetPos: SCNVector3,
                             power: Float, color: UIColor) {
        guard let beamNode = emitter, let impactNode = light else { return }

        let active = isReady && power >= 0.015

        if !active {
            beamNode.particleSystems?.forEach { $0.birthRate = 0 }
            impactNode.particleSystems?.forEach { $0.birthRate = 0 }
            impactNode.light?.intensity = 0
            return
        }

        let from = simd_float3(handPos.x, handPos.y, handPos.z)
        let to   = simd_float3(targetPos.x, targetPos.y, targetPos.z)
        let diff = to - from
        let dist = simd_length(diff)
        guard dist > 1 else { return }

        // Niente cilindri — solo particelle che scorrono dalla mano al petto
        // ── Particelle che scorrono dalla mano al petto ──────────────────────
        beamNode.position = handPos
        applyRotation(to: beamNode, from: from, to: to)
        let stream = beamNode.particleSystems?.first
        let velocity: CGFloat = 500
        stream?.particleLifeSpan          = Double(dist) / Double(velocity)
        stream?.particleLifeSpanVariation = 0.05
        stream?.particleVelocity          = velocity
        stream?.birthRate                 = CGFloat(power * 800 + 200)

        // ── Impatto sul petto ────────────────────────────────────────────────
        impactNode.position = targetPos
        impactNode.particleSystems?.forEach { ps in
            ps.birthRate = CGFloat(power * 400 + 100)
        }
        impactNode.light?.intensity = CGFloat(power * 3000)
    }

    // MARK: - Speed

    private func armSpeed(wristHistory: [CGPoint], elbowDistHistory: [Float]) -> Float {
        // Tutto in coordinate normalizzate (0-1) — distanza indipendente
        var speed2D: Float = 0
        if wristHistory.count >= 3 {
            var total: CGFloat = 0
            for i in 1..<wristHistory.count {
                let dx = wristHistory[i].x - wristHistory[i-1].x
                let dy = wristHistory[i].y - wristHistory[i-1].y
                total += sqrt(dx*dx + dy*dy)
            }
            speed2D = Float(total / CGFloat(wristHistory.count - 1))
        }
        // elbowShoulderDistNorm è già in spazio 0-1 — variazione è piccola, moltiplichiamo per 0.5
        var depthSpeed: Float = 0
        if elbowDistHistory.count >= 3 {
            var total: Float = 0
            for i in 1..<elbowDistHistory.count {
                total += abs(elbowDistHistory[i] - elbowDistHistory[i-1])
            }
            depthSpeed = (total / Float(elbowDistHistory.count - 1)) * 0.5
        }
        return max(speed2D, depthSpeed)
    }

    // MARK: - Helpers

    private func toSceneKit(_ pt: CGPoint) -> SCNVector3 {
        let d = scnView.projectPoint(SCNVector3(0, 0, 20)).z
        return scnView.unprojectPoint(SCNVector3(Float(pt.x), Float(pt.y), d))
    }

    private func smooth(_ cur: SCNVector3, _ tgt: SCNVector3) -> SCNVector3 {
        SCNVector3(posAlpha * tgt.x + (1-posAlpha) * cur.x,
                   posAlpha * tgt.y + (1-posAlpha) * cur.y,
                   posAlpha * tgt.z + (1-posAlpha) * cur.z)
    }

    private func bodyCenter(_ obs: VNHumanBodyPoseObservation, sz: CGSize) -> SCNVector3? {
        // Target = petto: punto a metà tra collo e metà dei fianchi
        guard let neck = try? obs.recognizedPoint(.neck), neck.confidence > 0.3,
              let lS   = try? obs.recognizedPoint(.leftShoulder),  lS.confidence > 0.2,
              let rS   = try? obs.recognizedPoint(.rightShoulder), rS.confidence > 0.2 else { return nil }
        // Petto = sotto il collo, tra le spalle, leggermente in basso
        let cx = ((1-neck.location.x) + (1-lS.location.x) + (1-rS.location.x)) / 3 * sz.width
        let cy = ((1-neck.location.y) + (1-lS.location.y) + (1-rS.location.y)) / 3 * sz.height + sz.height * 0.05
        return toSceneKit(CGPoint(x: cx, y: cy))
    }

    private func elbowShoulderDist(_ obs: VNHumanBodyPoseObservation, sz: CGSize) -> Float? {
        guard let elbow   = try? obs.recognizedPoint(.rightElbow),   elbow.confidence   > 0.3,
              let shoulder = try? obs.recognizedPoint(.rightShoulder), shoulder.confidence > 0.3 else { return nil }
        let dx = (elbow.location.x - shoulder.location.x) * Double(sz.width)
        let dy = (elbow.location.y - shoulder.location.y) * Double(sz.height)
        return Float(sqrt(dx*dx + dy*dy))
    }

    // Versione normalizzata (0-1) — indipendente da distanza camera e risoluzione
    private func elbowShoulderDistNorm(_ obs: VNHumanBodyPoseObservation) -> Float? {
        guard let elbow    = try? obs.recognizedPoint(.rightElbow),    elbow.confidence    > 0.3,
              let shoulder  = try? obs.recognizedPoint(.rightShoulder), shoulder.confidence > 0.3 else { return nil }
        let dx = elbow.location.x - shoulder.location.x
        let dy = elbow.location.y - shoulder.location.y
        return Float(sqrt(dx*dx + dy*dy))
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = .black

        cameraPreviewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraPreviewView)
        NSLayoutConstraint.activate([
            cameraPreviewView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraPreviewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            cameraPreviewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraPreviewView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // HUD container
        let hudContainer = UIView()
        hudContainer.translatesAutoresizingMaskIntoConstraints = false
        hudContainer.backgroundColor = .clear
        view.addSubview(hudContainer)
        NSLayoutConstraint.activate([
            hudContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            hudContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            hudContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            hudContainer.heightAnchor.constraint(equalToConstant: 80)
        ])

        player1Box.translatesAutoresizingMaskIntoConstraints = false
        hudContainer.addSubview(player1Box)
        NSLayoutConstraint.activate([
            player1Box.topAnchor.constraint(equalTo: hudContainer.topAnchor),
            player1Box.bottomAnchor.constraint(equalTo: hudContainer.bottomAnchor),
            player1Box.leadingAnchor.constraint(equalTo: hudContainer.leadingAnchor),
            player1Box.widthAnchor.constraint(equalTo: hudContainer.widthAnchor, multiplier: 0.46)
        ])

        player2Box.translatesAutoresizingMaskIntoConstraints = false
        hudContainer.addSubview(player2Box)
        NSLayoutConstraint.activate([
            player2Box.topAnchor.constraint(equalTo: hudContainer.topAnchor),
            player2Box.bottomAnchor.constraint(equalTo: hudContainer.bottomAnchor),
            player2Box.trailingAnchor.constraint(equalTo: hudContainer.trailingAnchor),
            player2Box.widthAnchor.constraint(equalTo: hudContainer.widthAnchor, multiplier: 0.46)
        ])

        // Pause button — centro HUD tra le due barre
        pauseButton.setTitle("⏸", for: .normal)
        pauseButton.titleLabel?.font = .systemFont(ofSize: 26)
        pauseButton.translatesAutoresizingMaskIntoConstraints = false
        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        hudContainer.addSubview(pauseButton)
        NSLayoutConstraint.activate([
            pauseButton.centerXAnchor.constraint(equalTo: hudContainer.centerXAnchor),
            pauseButton.centerYAnchor.constraint(equalTo: hudContainer.centerYAnchor)
        ])

        // Calibration label — READY? grande
        calibrationLabel.translatesAutoresizingMaskIntoConstraints = false
        calibrationLabel.font               = UIFont(name: "MagicSchoolOne", size: 80) ?? .systemFont(ofSize: 80, weight: .black)
        calibrationLabel.textColor          = .white
        calibrationLabel.textAlignment      = .center
        calibrationLabel.text               = "READY?"
        calibrationLabel.backgroundColor    = .clear
        calibrationLabel.layer.shadowColor  = UIColor.black.cgColor
        calibrationLabel.layer.shadowRadius = 12
        calibrationLabel.layer.shadowOpacity = 0.9
        calibrationLabel.layer.shadowOffset = .zero
        view.addSubview(calibrationLabel)
        NSLayoutConstraint.activate([
            calibrationLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            calibrationLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            calibrationLabel.widthAnchor.constraint(equalTo: view.widthAnchor)
        ])

        // Subtitle sotto READY?
        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font               = UIFont(name: "MagicSchoolOne", size: 22) ?? .systemFont(ofSize: 22, weight: .semibold)
        subtitleLabel.textColor          = UIColor.white.withAlphaComponent(0.75)
        subtitleLabel.textAlignment      = .center
        subtitleLabel.text               = "say ready to begin"
        subtitleLabel.backgroundColor    = .clear
        subtitleLabel.layer.shadowColor  = UIColor.black.cgColor
        subtitleLabel.layer.shadowRadius = 6
        subtitleLabel.layer.shadowOpacity = 0.9
        subtitleLabel.layer.shadowOffset = .zero
        subtitleLabel.tag                = 9901
        view.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: calibrationLabel.bottomAnchor, constant: -8),
            subtitleLabel.widthAnchor.constraint(equalTo: view.widthAnchor)
        ])

        // Warning label — appare se si dice Ready ma non ci sono 2 giocatori
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        warningLabel.font               = UIFont(name: "MagicSchoolOne", size: 26) ?? .systemFont(ofSize: 26, weight: .bold)
        warningLabel.textColor          = .white
        warningLabel.textAlignment      = .center
        warningLabel.text               = "I can't see both fairies!"
        warningLabel.backgroundColor    = UIColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 0.85)
        warningLabel.layer.cornerRadius = 14
        warningLabel.clipsToBounds      = true
        warningLabel.alpha              = 0
        view.addSubview(warningLabel)
        NSLayoutConstraint.activate([
            warningLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            warningLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 80),
            warningLabel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.75),
            warningLabel.heightAnchor.constraint(equalToConstant: 60)
        ])

        // Status dot
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.backgroundColor    = .red
        statusDot.layer.cornerRadius = 8
        view.addSubview(statusDot)
        NSLayoutConstraint.activate([
            statusDot.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusDot.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            statusDot.widthAnchor.constraint(equalToConstant: 16),
            statusDot.heightAnchor.constraint(equalToConstant: 16)
        ])

        // Start button — fallback se il vocale non funziona
        startButton.setTitle("START", for: .normal)
        startButton.titleLabel?.font = UIFont(name: "MagicSchoolOne", size: 28) ?? .systemFont(ofSize: 28, weight: .bold)
        startButton.setTitleColor(.white, for: .normal)
        startButton.backgroundColor = UIColor(red: 0.3, green: 0.0, blue: 0.6, alpha: 0.85)
        startButton.layer.cornerRadius = 18
        startButton.layer.borderWidth  = 2
        startButton.layer.borderColor  = UIColor(red: 0.7, green: 0.3, blue: 1.0, alpha: 1).cgColor
        startButton.layer.shadowColor  = UIColor.black.cgColor
        startButton.layer.shadowRadius = 8
        startButton.layer.shadowOpacity = 0.6
        startButton.layer.shadowOffset = .zero
        var scfg = UIButton.Configuration.plain()
        scfg.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 40, bottom: 16, trailing: 40)
        startButton.configuration = scfg
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        view.addSubview(startButton)
        NSLayoutConstraint.activate([
            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30)
        ])

        // Calibrate button — resetta la calibrazione della camera
        calibrateButton.setTitle("Calibrate", for: .normal)
        calibrateButton.titleLabel?.font = UIFont(name: "MagicSchoolOne", size: 16) ?? .systemFont(ofSize: 16)
        calibrateButton.setTitleColor(UIColor.white.withAlphaComponent(0.8), for: .normal)
        calibrateButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        calibrateButton.layer.cornerRadius = 10
        calibrateButton.layer.borderWidth  = 1
        calibrateButton.layer.borderColor  = UIColor.white.withAlphaComponent(0.3).cgColor
        calibrateButton.translatesAutoresizingMaskIntoConstraints = false
        calibrateButton.addTarget(self, action: #selector(calibrateTapped), for: .touchUpInside)
        view.addSubview(calibrateButton)
        var ccfg = UIButton.Configuration.plain()
        ccfg.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        calibrateButton.configuration = ccfg
        NSLayoutConstraint.activate([
            calibrateButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            calibrateButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

    }

    @objc private func goHomeTapped() { onGoHome?() }

    @objc private func startTapped() {
        guard !countdownStarted && !isReady else { return }
        if bothPlayersVisible {
            startButton.isHidden     = true
            calibrateButton.isHidden = true
            view.viewWithTag(9901)?.isHidden = true
            startCountdown()
        } else {
            flashWarning()
        }
    }

    @objc private func calibrateTapped() {
        cameraManager.resetCalibration()
        p1WristHistory = []; p2WristHistory = []
        p1ElbowDist    = []; p2ElbowDist    = []
        p1Power = 0; p2Power = 0
    }

    @objc private func pauseTapped() {
        guard isReady && !isGameOver else { return }
        isReady = false
        stopBattleMusic()
        emitter1?.childNodes.forEach { $0.removeFromParentNode() }
        emitter2?.childNodes.forEach { $0.removeFromParentNode() }

        pauseOverlay.isHidden = false
        UIView.animate(withDuration: 0.25) { self.pauseOverlay.alpha = 1 }
    }

    private func setupPauseOverlay() {
        pauseOverlay.translatesAutoresizingMaskIntoConstraints = false
        pauseOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        pauseOverlay.alpha = 0
        pauseOverlay.isHidden = true
        view.addSubview(pauseOverlay)
        NSLayoutConstraint.activate([
            pauseOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            pauseOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pauseOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pauseOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let titleLabel = UILabel()
        titleLabel.text = "PAUSED"
        titleLabel.font = UIFont(name: "MagicSchoolOne", size: 60) ?? .systemFont(ofSize: 60, weight: .black)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowRadius = 8; titleLabel.layer.shadowOpacity = 0.9; titleLabel.layer.shadowOffset = .zero
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        pauseOverlay.addSubview(titleLabel)

        let resumeBtn = makePauseMenuButton(title: "▶  Resume")
        resumeBtn.addTarget(self, action: #selector(resumeTapped), for: .touchUpInside)
        let restartBtn = makePauseMenuButton(title: "⚔  Fight Again")
        restartBtn.addTarget(self, action: #selector(pauseRestartTapped), for: .touchUpInside)
        let homeBtn = makePauseMenuButton(title: "🏠  Home")
        homeBtn.addTarget(self, action: #selector(goHomeTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [resumeBtn, restartBtn, homeBtn])
        stack.axis = .vertical; stack.spacing = 16; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        pauseOverlay.addSubview(stack)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: pauseOverlay.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: pauseOverlay.centerYAnchor, constant: -100),

            stack.centerXAnchor.constraint(equalTo: pauseOverlay.centerXAnchor),
            stack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 32)
        ])
    }

    private func makePauseMenuButton(title: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = UIFont(name: "MagicSchoolOne", size: 26) ?? .systemFont(ofSize: 24, weight: .bold)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        btn.layer.cornerRadius = 14
        var cfg = UIButton.Configuration.plain()
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 32, bottom: 14, trailing: 32)
        btn.configuration = cfg
        return btn
    }

    @objc private func resumeTapped() {
        UIView.animate(withDuration: 0.2, animations: { self.pauseOverlay.alpha = 0 }) { _ in
            self.pauseOverlay.isHidden = true
        }
        isReady = true
        startBattleMusic()
    }

    @objc private func pauseRestartTapped() {
        pauseOverlay.alpha = 0; pauseOverlay.isHidden = true
        gameOverDidTapRestart()
    }

    // MARK: - Game Over

    private func triggerGameOver(winnerIndex: Int) {
        isGameOver = true
        stopBattleMusic()
        for e in [emitter1, emitter2] {
            e?.particleSystems?.forEach { $0.birthRate = 0 }
        }
        for i in [handLight1, handLight2] {
            i?.particleSystems?.forEach { $0.birthRate = 0 }
            i?.light?.intensity = 0
        }
        RPScreenRecorder.shared().stopRecording { [weak self] preview, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let vc = GameOverViewController(winnerIndex: winnerIndex, replayPreview: preview)
                vc.delegate = self
                self.present(vc, animated: true)
            }
        }
    }
}

// MARK: - GameOverDelegate

extension FairyTrackingViewController: GameOverDelegate {
    func gameOverDidTapHome() { onGoHome?() }
    func gameOverDidTapRestart() {
        p1HP = 100; p2HP = 100
        isGameOver = false; isReady = false
        countdownStarted = false
        bothDetectedFrames = 0
        bothPlayersVisible = false
        p1Power = 0; p2Power = 0
        lowHealthP1Played = false; lowHealthP2Played = false; lowHealthBothPlayed = false
        for e in [emitter1, emitter2] {
            e?.particleSystems?.forEach { $0.birthRate = 0 }
        }
        for i in [handLight1, handLight2] {
            i?.particleSystems?.forEach { $0.birthRate = 0 }
            i?.light?.intensity = 0
        }
        pauseOverlay.isHidden = true; pauseOverlay.alpha = 0
        stopBattleMusic()
        calibrationLabel.isHidden = false
        startRecording()
    }
}

// MARK: - BodyTrackingDelegate

extension FairyTrackingViewController: BodyTrackingDelegate {

    func didDetectPlayers(_ result: PlayersDetectionResult) {
        guard !isGameOver else { return }

        let p1Present = result.player1 != nil
        let p2Present = result.player2 != nil

        if p1HP <= 0 || p2HP <= 0 {
            triggerGameOver(winnerIndex: p1HP <= 0 ? 2 : 1); return
        }

        statusDot.backgroundColor = (p1Present && p2Present) ? .green : .red
        bothPlayersVisible = (p1Present && p2Present)

        // Auto-countdown quando entrambi rilevati per abbastanza frame
        if p1Present && p2Present && !countdownStarted {
            bothDetectedFrames += 1
            if bothDetectedFrames >= framesBeforeCountdown {
                startCountdown()
            }
        } else if !p1Present || !p2Present {
            bothDetectedFrames = max(0, bothDetectedFrames - 1)
        }

        let sz = view.bounds.size

        // ── P1 ──
        if let obs = result.player1?.observation {
            let rW = try? obs.recognizedPoint(.rightWrist)
            let lW = try? obs.recognizedPoint(.leftWrist)
            let wp = (rW?.confidence ?? 0) >= (lW?.confidence ?? 0) ? rW : lW
            if let w = wp, w.confidence > 0.25 {
                // Coordinate normalizzate Vision (0-1) — indipendenti da distanza e risoluzione
                let normPt = CGPoint(x: 1 - w.location.x, y: 1 - w.location.y)
                p1WristHistory.append(normPt)
                if p1WristHistory.count > wristHistorySize { p1WristHistory.removeFirst() }
                let screenPt = CGPoint(x: normPt.x * sz.width, y: normPt.y * sz.height)
                p1HandSmooth = smooth(p1HandSmooth, toSceneKit(screenPt))
                p1HandPos    = p1HandSmooth
            }
            if let dist = elbowShoulderDistNorm(obs) {
                p1ElbowDist.append(dist)
                if p1ElbowDist.count > elbowHistorySize { p1ElbowDist.removeFirst() }
            }
            if let body = bodyCenter(obs, sz: sz) { p1BodyPos = body }
        }

        // ── P2 ──
        if let obs = result.player2?.observation {
            let rW = try? obs.recognizedPoint(.rightWrist)
            let lW = try? obs.recognizedPoint(.leftWrist)
            let wp = (rW?.confidence ?? 0) >= (lW?.confidence ?? 0) ? rW : lW
            if let w = wp, w.confidence > 0.25 {
                let normPt = CGPoint(x: 1 - w.location.x, y: 1 - w.location.y)
                p2WristHistory.append(normPt)
                if p2WristHistory.count > wristHistorySize { p2WristHistory.removeFirst() }
                let screenPt = CGPoint(x: normPt.x * sz.width, y: normPt.y * sz.height)
                p2HandSmooth = smooth(p2HandSmooth, toSceneKit(screenPt))
                p2HandPos    = p2HandSmooth
            }
            if let dist = elbowShoulderDistNorm(obs) {
                p2ElbowDist.append(dist)
                if p2ElbowDist.count > elbowHistorySize { p2ElbowDist.removeFirst() }
            }
            if let body = bodyCenter(obs, sz: sz) { p2BodyPos = body }
        }

        // ── Velocità → potenza ──
        let s1 = armSpeed(wristHistory: p1WristHistory, elbowDistHistory: p1ElbowDist)
        let s2 = armSpeed(wristHistory: p2WristHistory, elbowDistHistory: p2ElbowDist)
        // Spazio normalizzato 0-1: dead zone 0.005 (tremore), saturazione a 0.05
        // Abbassato per catturare movimenti reali di braccia
        let n1 = Float(min(1.0, max(0, (Double(s1) - 0.005) / 0.045)))
        let n2 = Float(min(1.0, max(0, (Double(s2) - 0.005) / 0.045)))
        p1Power = n1 > p1Power ? powerAlpha*n1 + (1-powerAlpha)*p1Power : p1Power*powerDecay
        p2Power = n2 > p2Power ? powerAlpha*n2 + (1-powerAlpha)*p2Power : p2Power*powerDecay

        // ── Fasci ──
        updateBeam(emitter: emitter1, light: handLight1,
                   handPos: p1HandPos, targetPos: p2BodyPos, power: p1Power,
                   color: UIColor(red: 0.5, green: 0.1, blue: 1.0, alpha: 1))
        updateBeam(emitter: emitter2, light: handLight2,
                   handPos: p2HandPos, targetPos: p1BodyPos, power: p2Power,
                   color: UIColor(red: 0.9, green: 0.1, blue: 0.8, alpha: 1))

        // Indicatori petto — visibili solo durante la partita
        let showChest = isReady && !isGameOver
        chestNode1?.isHidden = !showChest
        chestNode2?.isHidden = !showChest
        if showChest {
            chestNode1?.position = p2BodyPos
            chestNode2?.position = p1BodyPos
        }

        // ── Danno ──
        // Soglia 0.25: qualsiasi movimento deciso fa danno.
        // power 0.25→1HP, 0.5→5HP, 0.75→11HP, 1.0→15HP
        // hitCooldown=20 (~0.65s a 30fps)
        if isReady {
            if p1HitCooldown > 0 { p1HitCooldown -= 1 }
            if p2HitCooldown > 0 { p2HitCooldown -= 1 }
            if p1Power > 0.25 && p2HitCooldown == 0 {
                let dmg = Int(pow(Double(p1Power), 2.0) * 15)
                if dmg > 0 {
                    p2HP = max(0, p2HP - dmg)
                    p2HitCooldown = hitCooldown; player2Box.flashDamage()
                    playLowHealthIfNeeded()
                }
            }
            if p2Power > 0.25 && p1HitCooldown == 0 {
                let dmg = Int(pow(Double(p2Power), 2.0) * 15)
                if dmg > 0 {
                    p1HP = max(0, p1HP - dmg)
                    p1HitCooldown = hitCooldown; player1Box.flashDamage()
                    playLowHealthIfNeeded()
                }
            }
        }

        player1Box.update(hp: p1HP, power: p1Power)
        player2Box.update(hp: p2HP, power: p2Power)
    }

    func didLoseTracking() {
        statusDot.backgroundColor = .red
        p1Power = 0; p2Power = 0
        for e in [emitter1, emitter2] {
            e?.particleSystems?.forEach { $0.birthRate = 0 }
        }
        for i in [handLight1, handLight2] {
            i?.particleSystems?.forEach { $0.birthRate = 0 }
            i?.light?.intensity = 0
        }
    }
}

// MARK: - FairyHUDView

class FairyHUDView: UIView {

    private let isRightSide: Bool
    private let playerColor: UIColor
    private var currentHP: Int = 100
    private var ghostTimer: Timer?

    private let nameLabel  = UILabel()
    private let hpIcon     = UIImageView()
    private let hpBarBg    = ArrowBarView(color: UIColor(red:0.1,green:0.2,blue:0.6,alpha:1))
    private let hpGhostBar = ArrowBarView(color: UIColor(red:0.8,green:0.5,blue:0.0,alpha:0.8))
    private let hpFillBar  = ArrowBarView(color: UIColor(red:0.15,green:0.75,blue:0.25,alpha:1))

    private var hpRatio:   CGFloat = 1.0
    private var ghostRatio: CGFloat = 1.0

    init(playerName: String, color: UIColor, rightSide: Bool = false) {
        self.playerColor = color
        self.isRightSide = rightSide
        super.init(frame: .zero)
        backgroundColor = .clear
        setupLayout(name: playerName)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayout(name: String) {
        nameLabel.text      = name
        nameLabel.font      = UIFont(name: "MagicSchoolOne", size: 28) ?? .systemFont(ofSize: 24, weight: .bold)
        nameLabel.textColor = isRightSide
            ? UIColor(red: 251/255.0, green: 198/255.0, blue: 161/255.0, alpha: 1.0)
            : UIColor(red: 209/255.0, green:  84/255.0, blue: 113/255.0, alpha: 1.0)
        nameLabel.textAlignment           = isRightSide ? .right : .left
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor      = 0.5
        nameLabel.layer.shadowColor       = UIColor.black.cgColor
        nameLabel.layer.shadowOffset      = CGSize(width: 2, height: 2)
        nameLabel.layer.shadowOpacity     = 0.95
        nameLabel.layer.shadowRadius      = 3

        hpIcon.image       = UIImage(named: "heart")
        hpIcon.contentMode = .scaleAspectFit

        for v in [nameLabel, hpIcon, hpBarBg, hpGhostBar, hpFillBar] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        let pad: CGFloat = 6
        var constraints: [NSLayoutConstraint] = [
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            nameLabel.heightAnchor.constraint(equalToConstant: 34),

            hpIcon.centerYAnchor.constraint(equalTo: hpBarBg.centerYAnchor),
            hpIcon.widthAnchor.constraint(equalToConstant: 26),
            hpIcon.heightAnchor.constraint(equalToConstant: 26),

            hpBarBg.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            hpBarBg.heightAnchor.constraint(equalToConstant: 20),
            hpBarBg.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            hpGhostBar.topAnchor.constraint(equalTo: hpBarBg.topAnchor),
            hpGhostBar.leadingAnchor.constraint(equalTo: hpBarBg.leadingAnchor),
            hpGhostBar.heightAnchor.constraint(equalTo: hpBarBg.heightAnchor),
            hpGhostBar.widthAnchor.constraint(equalTo: hpBarBg.widthAnchor),

            hpFillBar.topAnchor.constraint(equalTo: hpBarBg.topAnchor),
            hpFillBar.leadingAnchor.constraint(equalTo: hpBarBg.leadingAnchor),
            hpFillBar.heightAnchor.constraint(equalTo: hpBarBg.heightAnchor),
            hpFillBar.widthAnchor.constraint(equalTo: hpBarBg.widthAnchor),
        ]

        if isRightSide {
            constraints.append(contentsOf: [
                hpIcon.trailingAnchor.constraint(equalTo: trailingAnchor),
                hpBarBg.trailingAnchor.constraint(equalTo: hpIcon.leadingAnchor, constant: -4),
                hpBarBg.leadingAnchor.constraint(equalTo: leadingAnchor),
            ])
            let flip = CGAffineTransform(scaleX: -1, y: 1)
            hpBarBg.transform = flip; hpGhostBar.transform = flip; hpFillBar.transform = flip
        } else {
            constraints.append(contentsOf: [
                hpIcon.leadingAnchor.constraint(equalTo: leadingAnchor),
                hpBarBg.leadingAnchor.constraint(equalTo: hpIcon.trailingAnchor, constant: 4),
                hpBarBg.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
        NSLayoutConstraint.activate(constraints)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hpGhostBar.setFillRatio(ghostRatio)
        hpFillBar.setFillRatio(hpRatio)
    }

    func update(hp: Int, power: Float) {
        let newRatio = CGFloat(max(0, hp)) / 100.0
        if hp < currentHP {
            hpRatio = newRatio
            UIView.animate(withDuration: 0.12) { self.hpFillBar.setFillRatio(self.hpRatio) }
            ghostTimer?.invalidate()
            ghostTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.ghostRatio = newRatio
                UIView.animate(withDuration: 0.5) { self.hpGhostBar.setFillRatio(self.ghostRatio) }
            }
        } else if hp > currentHP {
            hpRatio = 1.0; ghostRatio = 1.0
            hpFillBar.setFillRatio(1.0); hpGhostBar.setFillRatio(1.0)
        }
        currentHP = hp

        let hpColor: UIColor = hp > 50
            ? UIColor(red: 0.15, green: 0.75, blue: 0.25, alpha: 1)
            : (hp > 25 ? UIColor.systemOrange : UIColor.systemRed)
        hpFillBar.fillColor = hpColor
        hpFillBar.setFillRatio(hpRatio)
    }

    func flashDamage() {
        let shake = CAKeyframeAnimation(keyPath: "position.x")
        shake.values   = [0,-9,9,-7,7,-5,5,0].map { $0 + layer.position.x }
        shake.duration = 0.38
        shake.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(shake, forKey: "shake")
    }
}
