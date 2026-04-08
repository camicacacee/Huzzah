//
//  TrackingViewController.swift
//  battaglia
//

import UIKit
import Vision
import AVFoundation
import Speech
import SceneKit
import ReplayKit

class TrackingViewController: UIViewController {

    // MARK: - Config

    private let playerCount: Int = 2
    var onGoHome: (() -> Void)?

    init() { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Player names
    private static let knightNames = [
        "Sir Big Swing", "The Brave Idiot", "Lord No Fear", "Sir Hits First",
        "The Unstoppable Fool", "Sir Takes It Personally", "Sir Born Fighting",
        "Baron Von Almost", "Lord of Second Thoughts", "Sir Stabby McStabberson",
        "The Bleeding Winner", "The Dramatically Falling Knight",
        "The Knight of Overthinking", "The Proud Disaster",
        "The Sworn Protector of Nothing"
    ]



    // MARK: - Tutorial State Machine
    enum TutorialPhase {
        case inactive
        case intro
        case positioning
        case waitingAttack
        case waitingBlock
        case finished
    }
    private var currentTutorialPhase: TutorialPhase = .inactive
    private var p1TutorialDone = false
    private var p2TutorialDone = false
    private let tutorialOverlayView       = UIView()
    private let splitScreenLine           = UIView()
    private let tutorialInstructionLabel  = UILabel()
    private var tutorialAudioPlayers:     [String: AVAudioPlayer] = [:]
    private var currentTutorialPlayer:    AVAudioPlayer?
    private var tutorialAdvanceTimer:     Timer?

    // MARK: - UI
    private let cameraPreviewView  = UIView()
    private let overlayView        = SkeletonOverlayView()
    private lazy var player1Box    = PlayerHUDView(
        playerName: TrackingViewController.knightNames[Int.random(in: 0..<TrackingViewController.knightNames.count)],
        color: .systemCyan, rightSide: false)
    private lazy var player2Box    = PlayerHUDView(
        playerName: TrackingViewController.knightNames[Int.random(in: 0..<TrackingViewController.knightNames.count)],
        color: .systemOrange, rightSide: true)
    private let calibrationLabel   = UILabel()
    private let warningLabel       = UILabel()   // "I can't see both warriors"
    private let statusDot          = UIView()
    private let startButton        = UIButton(type: .system)
    private let calibrateButton    = UIButton(type: .system)

    // MARK: - SceneKit
    private let scnView          = SCNView()
    private let scnScene         = SCNScene()
    private var swordWrappers:   [SCNNode] = []
    private var swordLoaded      = false
    private var swordBaseScale:  Float = 0.003
    private let swordGripFraction: Float = 0.15

    private var shieldWrappers:  [SCNNode] = []
    private var shieldLoaded     = false
    private var shieldBaseScale: Float = 0.003
    private var shieldRawSpanY:  Float = 1.0
    private var chestNode1:      SCNNode?
    private var chestNode2:      SCNNode?

    // MARK: - Smoothing spada
    private var swordSmoothX:     [Float] = [0, 0]
    private var swordSmoothY:     [Float] = [0, 0]
    private let swordAlpha:       Float = 0.35

    // MARK: - Persistenza anchor
    private var lastAnchor:       [CGPoint?] = [nil, nil]
    private var lastElbow:        [CGPoint?] = [nil, nil]
    private var missingFrames:    [Int]      = [0, 0]
    private let maxMissingFrames  = 6

    // MARK: - Logic
    private let cameraManager = CameraManager()

    // MARK: - Stamina
    private let maxStamina:        Float = 150.0
    private let drainPerFrame:     Float = 1.0
    private let rechargePerFrame:  Float = 1.0
    private let penaltyFrames:     Int   = 60

    private var p1Stamina:         Float = 150.0
    private var p2Stamina:         Float = 150.0
    private var p1PenaltyCounter:  Int   = 0
    private var p2PenaltyCounter:  Int   = 0
    private var p1InPenalty:       Bool  = false
    private var p2InPenalty:       Bool  = false

    // MARK: - HP
    private var bothPlayersVisible = false   // aggiornato ogni frame da didDetectPlayers

    private var p1HP           = 100
    private var p2HP           = 100
    private var isGameOver     = false
    private let damagePerHit   = 10
    private let hitCooldown    = 45
    private var p1HitCooldown  = 0
    private var p2HitCooldown  = 0

    // MARK: - Audio

        private var currentSwingPlayer:   AVAudioPlayer?
        private var currentHitPlayer:     AVAudioPlayer?
        private var currentDefensePlayer: AVAudioPlayer?
        private var currentBlockedPlayer: AVAudioPlayer?
        
        // Assicurati che sotto ci sia UNA SOLA riga per la musica:
        private var battleMusicPlayer:     AVAudioPlayer?
        private var welcomePlayer:         AVAudioPlayer?   // forte riferimento per TwoWarriorsOneArena
        private var countdownStarted:       Bool            = false
        private var isFightActive:          Bool            = false   // true solo dopo FIGHT!
        private var isWelcomePlaying       = false
   
    private var hitPlayers:           [AVAudioPlayer] = []
    private var lastHitSoundTime:     TimeInterval    = 0
    private let hitSoundCooldown:     TimeInterval    = 2.0
    
    private var swingPlayers:         [AVAudioPlayer] = []
    private var lastSwingSoundTime:   TimeInterval    = 0
    private let swingSoundCooldown:   TimeInterval    = 0.4
    
    private var defensePlayers:       [AVAudioPlayer] = []
    private var lastDefenseSoundTime: TimeInterval    = 0
    private let defenseSoundCooldown: TimeInterval    = 1.0
    
    private var blockedPlayers:       [AVAudioPlayer] = []
    private var lastBlockedSoundTime: TimeInterval    = 0
    private let blockedSoundCooldown: TimeInterval    = 0.4

    private var lowHealthPlayers:     [AVAudioPlayer] = []
    private var lowHealthBothPlayers: [AVAudioPlayer] = []
    private var lastLowHealthTime:    TimeInterval    = 0
    private let lowHealthCooldown:    TimeInterval    = 6.0
    private let lowHealthThreshold    = 30
    


    private var lowHealthBothPlayed = false
    private var lowHealthP1Played   = false
    private var lowHealthP2Played   = false

    // MARK: - Speech
    private let speechRecognizer   = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:    SFSpeechRecognitionTask?
    private let audioEngine        = AVAudioEngine()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCamera()
        setupSceneKit()
        setupAudio()
        requestSpeechAndStart()
        setupTutorialUI()
        startTutorialFlowIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        cameraManager.startSession()
        startRecording()
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
        cameraManager.expectedPlayers = playerCount
        cameraManager.dominantHand    = "right"
        cameraManager.setupCamera()
        if let layer = cameraManager.previewLayer {
            cameraPreviewView.layer.insertSublayer(layer, at: 0)
        }
    }

    // MARK: - Audio
    private func playWelcomeAudio() {
        guard !countdownStarted else { return }
        countdownStarted = true
        calibrationLabel.isHidden = true
        view.viewWithTag(9901)?.isHidden = true
        startButton.isHidden     = true
        calibrateButton.isHidden = true
        isFightActive = false

        if let path = Bundle.main.path(forResource: "TwoWarriorsOneArena", ofType: "mp3"),
           let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) {
            player.prepareToPlay()
            player.play()
            welcomePlayer = player
            isWelcomePlaying = true
            startCountdown(audioDuration: player.duration)
        } else {
            startCountdown(audioDuration: 4.0)
        }
    }

    private func startCountdown(audioDuration: Double) {
        // L'audio parte insieme al "3". I 4 step distribuiti sulla durata:
        // "3" a t=0, "2" a t=dur*0.25, "1" a t=dur*0.50, "FIGHT!" a t=dur*0.75
        // così FIGHT! compare mentre la voce dice "fight" e la battaglia parte alla fine.
        let steps: [(String, Double)] = [
            ("3",      0),
            ("2",      audioDuration * 0.25),
            ("1",      audioDuration * 0.50),
            ("FIGHT!", audioDuration * 0.75)
        ]
        for (text, delay) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.showCountdownLabel(text)
            }
        }
        // La battaglia inizia alla fine esatta dell'audio
        DispatchQueue.main.asyncAfter(deadline: .now() + audioDuration) { [weak self] in
            self?.isWelcomePlaying = false
            self?.isFightActive = true
            self?.startBattleMusic()
        }
    }

    private func startBattleMusic() {
        let tracks = ["giostra", "giostra2"]
        let name   = tracks[Int.random(in: 0..<tracks.count)]
        guard let path = Bundle.main.path(forResource: name, ofType: "mp3"),
              let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else { return }
        player.numberOfLoops = -1
        player.volume        = 0.25
        player.prepareToPlay()
        player.play()
        battleMusicPlayer = player
    }

    private func stopBattleMusic() {
        battleMusicPlayer?.stop()
        battleMusicPlayer = nil
    }

    private func showCountdownLabel(_ text: String) {
        let isFight = text == "FIGHT!"
        let label = UILabel()
        label.text          = text
        label.font          = UIFont(name: "MagicSchoolOne", size: isFight ? 96 : 120) ?? .systemFont(ofSize: isFight ? 96 : 120, weight: .black)
        label.textColor     = isFight ? .systemYellow : .white
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

    private func setupAudio() {
        // Configura sessione audio per coesistere con AVCaptureSession
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ AVAudioSession error: \(error)")
        }

        // Hit sounds
        for i in 1...14 {
            guard let path = Bundle.main.path(forResource: "Hit_\(i)", ofType: "mp3") else { continue }
            let url = URL(fileURLWithPath: path)
            for _ in 0..<3 {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    hitPlayers.append(player)
                }
            }
        }

        // Swing sounds
        for i in 1...8 {
            let name = "spadina\(i)"
            var finalPath: String? = nil
            for ext in ["mp3", "wav", "m4a", "aac"] {
                if let p = Bundle.main.path(forResource: name, ofType: ext) { finalPath = p; break }
                if let p = Bundle.main.path(forResource: name, ofType: ext, inDirectory: "Sound_Spada") { finalPath = p; break }
            }
            guard let validPath = finalPath else { continue }
            let url = URL(fileURLWithPath: validPath)
            for _ in 0..<2 {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    swingPlayers.append(player)
                }
            }
        }

        // Defense sounds
        for i in 1...8 {
            let name = "difesa\(i)"
            var finalPath: String? = nil
            for ext in ["mp3", "wav", "m4a", "aac"] {
                if let p = Bundle.main.path(forResource: name, ofType: ext) { finalPath = p; break }
                if let p = Bundle.main.path(forResource: name, ofType: ext, inDirectory: "Sound_Spada") { finalPath = p; break }
            }
            guard let validPath = finalPath else { continue }
            let url = URL(fileURLWithPath: validPath)
            for _ in 0..<2 {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    defensePlayers.append(player)
                }
            }
        }
        
        // Blocked sounds
        for i in 1...4 {
            let name = "blocked_\(i)"
            var finalPath: String? = nil
            for ext in ["mp3", "wav", "m4a", "aac"] {
                if let p = Bundle.main.path(forResource: name, ofType: ext) { finalPath = p; break }
                if let p = Bundle.main.path(forResource: name, ofType: ext, inDirectory: "Sound_Spada") { finalPath = p; break }
            }
            guard let validPath = finalPath else { continue }
            let url = URL(fileURLWithPath: validPath)
            for _ in 0..<2 {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    blockedPlayers.append(player)
                }
            }
        }

        // Tutorial sounds
        let tutorialFiles = ["IntroTutorial", "TutorialBegins", "GetInPosition", "RaiseArmStrike", "good", "CrossToDefende", "StartFight"]
        for name in tutorialFiles {
            for ext in ["mp3", "wav", "m4a", "aac"] {
                if let p = Bundle.main.path(forResource: name, ofType: ext),
                   let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: p)) {
                    player.prepareToPlay()
                    tutorialAudioPlayers[name] = player
                    break
                }
            }
        }

        // LowHealth sounds
        for i in 1...3 {
            if let path = Bundle.main.path(forResource: "LowHealth_\(i)", ofType: "mp3"),
               let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) {
                player.prepareToPlay(); lowHealthPlayers.append(player)
            }
        }
        for i in 1...2 {
            if let path = Bundle.main.path(forResource: "LowHealthBoth_\(i)", ofType: "mp3"),
               let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) {
                player.prepareToPlay(); lowHealthBothPlayers.append(player)
            }
        }
        
    }

    private func playLowHealthIfNeeded() {
        guard !isWelcomePlaying else { return }
        let anyPlaying = (hitPlayers + swingPlayers + lowHealthPlayers + lowHealthBothPlayers + defensePlayers + blockedPlayers).contains { $0.isPlaying }
        guard !anyPlaying else { return }

        let p1Low = p1HP <= lowHealthThreshold
        let p2Low = p2HP <= lowHealthThreshold

        if p1Low && p2Low && !lowHealthBothPlayed {
            lowHealthBothPlayed = true
            guard !lowHealthBothPlayers.isEmpty else { return }
            let player = lowHealthBothPlayers[Int.random(in: 0..<lowHealthBothPlayers.count)]
            player.currentTime = 0; player.play()
        } else if p1Low && !lowHealthP1Played {
            lowHealthP1Played = true
            guard !lowHealthPlayers.isEmpty else { return }
            let player = lowHealthPlayers[Int.random(in: 0..<lowHealthPlayers.count)]
            player.currentTime = 0; player.play()
        } else if p2Low && !lowHealthP2Played {
            lowHealthP2Played = true
            guard !lowHealthPlayers.isEmpty else { return }
            let player = lowHealthPlayers[Int.random(in: 0..<lowHealthPlayers.count)]
            player.currentTime = 0; player.play()
        }
    }

    private func playSwingSound() {
        guard !isWelcomePlaying, !swingPlayers.isEmpty else { return }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastSwingSoundTime >= swingSoundCooldown else { return }
        
        // Stop any existing swing sound to prevent overlapping
        currentSwingPlayer?.stop()
        
        lastSwingSoundTime = now
        let player = swingPlayers[Int.random(in: 0..<swingPlayers.count)]
        player.currentTime = 0
        player.play()
        currentSwingPlayer = player
    }

    private func playHitSound() {
        guard !isWelcomePlaying, !hitPlayers.isEmpty else { return }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastHitSoundTime >= hitSoundCooldown else { return }
        
        // Kill the previous hit sound immediately
        currentHitPlayer?.stop()
        
        lastHitSoundTime = now
        let player = hitPlayers[Int.random(in: 0..<hitPlayers.count)]
        player.currentTime = 0
        player.play()
        currentHitPlayer = player
    }

    private func playDefenseSound() {
        guard !isWelcomePlaying, !defensePlayers.isEmpty else { return }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastDefenseSoundTime >= defenseSoundCooldown else { return }
        
        // Ensure only one defense sound plays at a time
        currentDefensePlayer?.stop()
        
        lastDefenseSoundTime = now
        let player = defensePlayers[Int.random(in: 0..<defensePlayers.count)]
        player.currentTime = 0
        player.play()
        currentDefensePlayer = player
    }

    private func playBlockedSound() {
        guard !isWelcomePlaying, !blockedPlayers.isEmpty else { return }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastBlockedSoundTime >= blockedSoundCooldown else { return }
        
        // Avoid audio clutter by stopping the previous block sound
        currentBlockedPlayer?.stop()
        
        lastBlockedSoundTime = now
        let player = blockedPlayers[Int.random(in: 0..<blockedPlayers.count)]
        player.currentTime = 0
        player.play()
        currentBlockedPlayer = player
    }

    // MARK: - ReplayKit
    private func startRecording() {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else { return }
        recorder.startRecording { _ in }
    }

    // MARK: - SceneKit setup
    private func setupSceneKit() {
        scnView.scene                  = scnScene
        scnView.backgroundColor        = .clear
        scnView.isUserInteractionEnabled = false
        scnView.translatesAutoresizingMaskIntoConstraints = false
        scnView.allowsCameraControl    = false
        scnView.antialiasingMode       = .multisampling4X
        scnView.isPlaying              = true

        let camNode = SCNNode()
        camNode.camera                          = SCNCamera()
        camNode.camera?.usesOrthographicProjection = false
        camNode.camera?.fieldOfView             = 60
        camNode.camera?.zNear                   = 0.1
        camNode.camera?.zFar                    = 2000
        camNode.position                        = SCNVector3(0, 0, 800)
        scnScene.rootNode.addChildNode(camNode)
        scnView.pointOfView = camNode

        let ambNode = SCNNode()
        ambNode.light          = SCNLight()
        ambNode.light?.type    = .ambient
        ambNode.light?.intensity = 1000
        scnScene.rootNode.addChildNode(ambNode)

        let dirNode = SCNNode()
        dirNode.light            = SCNLight()
        dirNode.light?.type      = .directional
        dirNode.light?.intensity = 1500
        dirNode.eulerAngles      = SCNVector3(-0.3, 0.3, 0)
        scnScene.rootNode.addChildNode(dirNode)

        view.addSubview(scnView)
        NSLayoutConstraint.activate([
            scnView.topAnchor.constraint(equalTo: view.topAnchor),
            scnView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scnView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scnView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        loadSwordModel()
        loadShieldModel()
        setupChestIndicators()

        view.bringSubviewToFront(player1Box)
        if playerCount == 2 { view.bringSubviewToFront(player2Box) }
        view.bringSubviewToFront(calibrationLabel)
        view.bringSubviewToFront(statusDot)
        view.bringSubviewToFront(startButton)
        view.bringSubviewToFront(calibrateButton)
    }

    private func loadSwordModel() {
        guard let url = Bundle.main.url(forResource: "sword", withExtension: "usdz"),
              let swordScene = try? SCNScene(url: url, options: [.createNormalsIfAbsent: true, .convertToYUp: true]) else { return }

        let modelRoot = swordScene.rootNode
        var minVec = SCNVector3Zero, maxVec = SCNVector3Zero
        modelRoot.__getBoundingBoxMin(&minVec, max: &maxVec)
        let bladeSpan = CGFloat(abs(maxVec.x - minVec.x))
        swordBaseScale = bladeSpan > 0 ? Float(85.0 / bladeSpan) : 0.003

        let swordMat = SCNMaterial()
        swordMat.lightingModel       = .physicallyBased
        swordMat.diffuse.contents    = UIColor(red: 0.047, green: 0.047, blue: 0.047, alpha: 1)
        swordMat.metalness.contents  = NSNumber(value: 0.95)
        swordMat.roughness.contents  = NSNumber(value: 0.15)
        swordMat.emission.contents   = UIColor(white: 0.10, alpha: 1)

        func applyMaterial(to node: SCNNode) {
            if let geo = node.geometry { geo.materials = Array(repeating: swordMat, count: max(1, geo.materials.count)) }
            node.childNodes.forEach { applyMaterial(to: $0) }
        }

        for _ in 0..<2 {
            let wrapper   = SCNNode()
            wrapper.isHidden = true
            let modelNode = modelRoot.clone()
            modelNode.scale = SCNVector3(swordBaseScale, swordBaseScale, swordBaseScale)
            applyMaterial(to: modelNode)
            let span  = Float(maxVec.x - minVec.x)
            let gripX = (Float(minVec.x) + swordGripFraction * span) * swordBaseScale
            let midZ  = Float((maxVec.z + minVec.z) / 2) * swordBaseScale
            modelNode.position = SCNVector3(gripX, 0, -midZ)
            wrapper.addChildNode(modelNode)
            scnScene.rootNode.addChildNode(wrapper)
            swordWrappers.append(wrapper)
        }
        swordLoaded = true
    }

    private func loadShieldModel() {
        guard let url = Bundle.main.url(forResource: "Shield", withExtension: "usdz"),
              let shieldScene = try? SCNScene(url: url, options: [.createNormalsIfAbsent: true, .convertToYUp: true]) else { return }

        let modelRoot = shieldScene.rootNode

        func recursiveBBox(_ node: SCNNode) -> (min: SCNVector3, max: SCNVector3)? {
            var gMin = SCNVector3( Float.infinity,  Float.infinity,  Float.infinity)
            var gMax = SCNVector3(-Float.infinity, -Float.infinity, -Float.infinity)
            var found = false
            node.enumerateChildNodes { child, _ in
                var lo = SCNVector3Zero, hi = SCNVector3Zero
                child.__getBoundingBoxMin(&lo, max: &hi)
                if lo.x == 0 && hi.x == 0 && lo.y == 0 && hi.y == 0 { return }
                let corners: [SCNVector3] = [
                    SCNVector3(lo.x, lo.y, lo.z), SCNVector3(hi.x, lo.y, lo.z),
                    SCNVector3(lo.x, hi.y, lo.z), SCNVector3(hi.x, hi.y, lo.z),
                    SCNVector3(lo.x, lo.y, hi.z), SCNVector3(hi.x, lo.y, hi.z),
                    SCNVector3(lo.x, hi.y, hi.z), SCNVector3(hi.x, hi.y, hi.z)
                ]
                for c in corners {
                    let w = child.convertPosition(c, to: node)
                    gMin = SCNVector3(min(gMin.x, w.x), min(gMin.y, w.y), min(gMin.z, w.z))
                    gMax = SCNVector3(max(gMax.x, w.x), max(gMax.y, w.y), max(gMax.z, w.z))
                    found = true
                }
            }
            return found ? (gMin, gMax) : nil
        }

        var minVec = SCNVector3Zero, maxVec = SCNVector3Zero
        if let bbox = recursiveBBox(modelRoot) { minVec = bbox.min; maxVec = bbox.max }
        else { modelRoot.__getBoundingBoxMin(&minVec, max: &maxVec) }

        let rawSpan    = max(abs(maxVec.x - minVec.x), abs(maxVec.y - minVec.y))
        shieldRawSpanY  = rawSpan > 0 ? rawSpan : 1.0
        shieldBaseScale = rawSpan > 0 ? Float(120.0 / CGFloat(rawSpan)) : 0.003

        let shieldMat = SCNMaterial()
        shieldMat.lightingModel      = .physicallyBased
        shieldMat.diffuse.contents   = UIColor(red: 0.55, green: 0.40, blue: 0.10, alpha: 1)
        shieldMat.metalness.contents = NSNumber(value: 0.3)
        shieldMat.roughness.contents = NSNumber(value: 0.6)

        func applyMaterial(to node: SCNNode) {
            if let geo = node.geometry { geo.materials = Array(repeating: shieldMat, count: max(1, geo.materials.count)) }
            node.childNodes.forEach { applyMaterial(to: $0) }
        }

        for _ in 0..<2 {
            let wrapper   = SCNNode()
            wrapper.isHidden = true
            let modelNode = modelRoot.clone()
            modelNode.scale       = SCNVector3(1, 1, 1)
            modelNode.eulerAngles = SCNVector3(0, 0, 0)
            applyMaterial(to: modelNode)
            modelNode.position = SCNVector3(-(maxVec.x + minVec.x)/2, -(maxVec.y + minVec.y)/2, -(maxVec.z + minVec.z)/2)
            wrapper.addChildNode(modelNode)
            scnScene.rootNode.addChildNode(wrapper)
            shieldWrappers.append(wrapper)
        }
        shieldLoaded = true
    }

    private func updateSword3D(playerIndex: Int, anchor: CGPoint, elbow: CGPoint, facingRight: Bool) {
        guard swordLoaded, playerIndex < swordWrappers.count else { return }
        let wrapper = swordWrappers[playerIndex]
        let projectedDepth = scnView.projectPoint(SCNVector3(0, 0, 20)).z
        let worldPoint     = scnView.unprojectPoint(SCNVector3(Float(anchor.x), Float(anchor.y), projectedDepth))

        swordSmoothX[playerIndex] = swordAlpha * worldPoint.x + (1 - swordAlpha) * swordSmoothX[playerIndex]
        swordSmoothY[playerIndex] = swordAlpha * worldPoint.y + (1 - swordAlpha) * swordSmoothY[playerIndex]

        let angleOffset: Float = facingRight ? -.pi / 2 : .pi / 2

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        wrapper.position    = SCNVector3(swordSmoothX[playerIndex], swordSmoothY[playerIndex], 20)
        wrapper.eulerAngles = SCNVector3(0, 0, angleOffset)
        wrapper.isHidden    = false
        SCNTransaction.commit()
    }

    private func hideSwords() { swordWrappers.forEach { $0.isHidden = true } }

    private func updateShield3D(playerIndex: Int, anchor: CGPoint, facingRight: Bool, bodyObservation: VNHumanBodyPoseObservation?, opponentAnchor: CGPoint?) {
        guard shieldLoaded, playerIndex < shieldWrappers.count else { return }
        let wrapper = shieldWrappers[playerIndex]
        let size    = view.bounds.size

        var torsoAnchor = anchor
        if let obs = bodyObservation,
           let lS = try? obs.recognizedPoint(.leftShoulder),  lS.confidence > 0.3,
           let rS = try? obs.recognizedPoint(.rightShoulder), rS.confidence > 0.3,
           let lH = try? obs.recognizedPoint(.leftHip),       lH.confidence > 0.2,
           let rH = try? obs.recognizedPoint(.rightHip),      rH.confidence > 0.2 {
            let cx = ((1-lS.location.x) + (1-rS.location.x) + (1-lH.location.x) + (1-rH.location.x)) / 4 * size.width
            let cy = ((1-lS.location.y) + (1-rS.location.y) + (1-lH.location.y) + (1-rH.location.y)) / 4 * size.height
            torsoAnchor = CGPoint(x: cx, y: cy)
        }

        let projectedDepth = scnView.projectPoint(SCNVector3(0, 0, 15)).z
        let worldPoint     = scnView.unprojectPoint(SCNVector3(Float(torsoAnchor.x), Float(torsoAnchor.y), projectedDepth))

        swordSmoothX[playerIndex] = swordAlpha * worldPoint.x + (1 - swordAlpha) * swordSmoothX[playerIndex]
        swordSmoothY[playerIndex] = swordAlpha * worldPoint.y + (1 - swordAlpha) * swordSmoothY[playerIndex]

        var dynamicScale = shieldBaseScale * 2.5
        if let obs = bodyObservation,
           let lS = try? obs.recognizedPoint(.leftShoulder), lS.confidence > 0.3,
           let rS = try? obs.recognizedPoint(.rightShoulder), rS.confidence > 0.3 {
            let shoulderWidthPx = abs((1-lS.location.x)*size.width - (1-rS.location.x)*size.width)
            dynamicScale = Float(shoulderWidthPx * 2.0) / shieldRawSpanY
        }

        let shieldPos = SCNVector3(swordSmoothX[playerIndex], swordSmoothY[playerIndex], 15)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        wrapper.position = shieldPos
        wrapper.scale    = SCNVector3(dynamicScale, dynamicScale, dynamicScale)

        // tilt: P1 inclina a destra (+π/6), P2 inclina a sinistra (-π/6) → specchiato
        let tilt: Float = facingRight ? .pi / 6 : -.pi / 6

        if let oppAnchor = opponentAnchor {
            let oppWorld = scnView.unprojectPoint(SCNVector3(Float(oppAnchor.x), Float(oppAnchor.y), projectedDepth))
            let dx = oppWorld.x - shieldPos.x
            let yawToOpp = atan2(dx, 0)
            wrapper.eulerAngles = SCNVector3(-Float.pi / 2, yawToOpp, tilt)
        } else {
            let yaw: Float = facingRight ? -.pi / 2 : .pi / 2
            wrapper.eulerAngles = SCNVector3(-Float.pi / 2, yaw, tilt)
        }

        wrapper.isHidden = false
        SCNTransaction.commit()
    }

    private func hideShields() { shieldWrappers.forEach { $0.isHidden = true } }

    // MARK: - UI setup
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

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = .clear
        view.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let hudContainer = UIView()
        hudContainer.translatesAutoresizingMaskIntoConstraints = false
        hudContainer.backgroundColor = .clear
        view.addSubview(hudContainer)
        NSLayoutConstraint.activate([
            hudContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            hudContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            hudContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            hudContainer.heightAnchor.constraint(equalToConstant: 90)
        ])

        player1Box.translatesAutoresizingMaskIntoConstraints = false
        hudContainer.addSubview(player1Box)
        NSLayoutConstraint.activate([
            player1Box.topAnchor.constraint(equalTo: hudContainer.topAnchor),
            player1Box.bottomAnchor.constraint(equalTo: hudContainer.bottomAnchor),
            player1Box.leadingAnchor.constraint(equalTo: hudContainer.leadingAnchor),
            player1Box.widthAnchor.constraint(equalTo: hudContainer.widthAnchor, multiplier: 0.46)
        ])

        if playerCount == 2 {
            player2Box.translatesAutoresizingMaskIntoConstraints = false
            hudContainer.addSubview(player2Box)
            NSLayoutConstraint.activate([
                player2Box.topAnchor.constraint(equalTo: hudContainer.topAnchor),
                player2Box.bottomAnchor.constraint(equalTo: hudContainer.bottomAnchor),
                player2Box.trailingAnchor.constraint(equalTo: hudContainer.trailingAnchor),
                player2Box.widthAnchor.constraint(equalTo: hudContainer.widthAnchor, multiplier: 0.46)
            ])
        }

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

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.backgroundColor    = .red
        statusDot.layer.cornerRadius = 8
        view.addSubview(statusDot)
        NSLayoutConstraint.activate([
            statusDot.centerYAnchor.constraint(equalTo: player1Box.centerYAnchor),
            statusDot.trailingAnchor.constraint(equalTo: player1Box.leadingAnchor, constant: -6),
            statusDot.widthAnchor.constraint(equalToConstant: 16),
            statusDot.heightAnchor.constraint(equalToConstant: 16)
        ])

        // Warning label — appare solo quando si dice Ready ma non si vedono 2 giocatori
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        warningLabel.font               = UIFont(name: "MagicSchoolOne", size: 26) ?? .systemFont(ofSize: 26, weight: .bold)
        warningLabel.textColor          = .white
        warningLabel.textAlignment      = .center
        warningLabel.text               = "I can't see both warriors!"
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

        // Start button — fallback vocale
        startButton.setTitle("START", for: .normal)
        startButton.titleLabel?.font = UIFont(name: "MagicSchoolOne", size: 28) ?? .systemFont(ofSize: 28, weight: .bold)
        startButton.setTitleColor(.white, for: .normal)
        startButton.backgroundColor = UIColor(red: 0.1, green: 0.25, blue: 0.5, alpha: 0.9)
        startButton.layer.cornerRadius = 18
        startButton.layer.borderWidth  = 2
        startButton.layer.borderColor  = UIColor(red: 0.9, green: 0.75, blue: 0.2, alpha: 1).cgColor
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

        // Calibrate button
        calibrateButton.setTitle("Calibrate", for: .normal)
        calibrateButton.titleLabel?.font = UIFont(name: "MagicSchoolOne", size: 16) ?? .systemFont(ofSize: 16)
        calibrateButton.setTitleColor(UIColor.white.withAlphaComponent(0.8), for: .normal)
        calibrateButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        calibrateButton.layer.cornerRadius = 10
        calibrateButton.layer.borderWidth  = 1
        calibrateButton.layer.borderColor  = UIColor.white.withAlphaComponent(0.3).cgColor
        calibrateButton.translatesAutoresizingMaskIntoConstraints = false
        calibrateButton.addTarget(self, action: #selector(calibrateTapped), for: .touchUpInside)
        var ccfg = UIButton.Configuration.plain()
        ccfg.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        calibrateButton.configuration = ccfg
        view.addSubview(calibrateButton)
        NSLayoutConstraint.activate([
            calibrateButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            calibrateButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

    }




    // MARK: - Chest indicators

    private func setupChestIndicators() {
        func makeChestNode(color: UIColor) -> SCNNode {
            let sphere = SCNSphere(radius: 10)
            let mat    = SCNMaterial()
            mat.diffuse.contents  = UIColor.white
            mat.emission.contents = color
            mat.blendMode         = .add
            sphere.materials      = [mat]
            let node = SCNNode(geometry: sphere)

            let haloSphere = SCNSphere(radius: 22)
            let haloMat    = SCNMaterial()
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: nil)
            haloMat.diffuse.contents  = UIColor(red: r, green: g, blue: b, alpha: 0.22)
            haloMat.emission.contents = UIColor(red: r, green: g, blue: b, alpha: 0.22)
            haloMat.blendMode         = .add
            haloMat.isDoubleSided     = true
            haloSphere.materials      = [haloMat]
            node.addChildNode(SCNNode(geometry: haloSphere))

            let pulse = CABasicAnimation(keyPath: "scale")
            pulse.fromValue      = SCNVector3(1.0, 1.0, 1.0)
            pulse.toValue        = SCNVector3(1.5, 1.5, 1.5)
            pulse.duration       = 0.7
            pulse.autoreverses   = true
            pulse.repeatCount    = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            node.addAnimation(pulse, forKey: "pulse")
            node.isHidden = true
            return node
        }
        let c1 = makeChestNode(color: .systemCyan)
        scnScene.rootNode.addChildNode(c1); chestNode1 = c1
        let c2 = makeChestNode(color: .systemOrange)
        scnScene.rootNode.addChildNode(c2); chestNode2 = c2
    }

        // MARK: - Block detection

    private func isHandsCrossedAtFace(_ obs: VNHumanBodyPoseObservation) -> Bool {
        guard let lW = try? obs.recognizedPoint(.leftWrist),    lW.confidence  > 0.25,
              let rW = try? obs.recognizedPoint(.rightWrist),   rW.confidence  > 0.25,
              let lS = try? obs.recognizedPoint(.leftShoulder), lS.confidence > 0.3,
              let rS = try? obs.recognizedPoint(.rightShoulder), rS.confidence > 0.3
        else { return false }
        let shoulderY = (lS.location.y + rS.location.y) / 2
        // Entrambi i polsi sopra le spalle
        guard lW.location.y > shoulderY + 0.02,
              rW.location.y > shoulderY + 0.02 else { return false }
        // Polsi vicini = mani incrociate (soglia 0.22 — abbastanza permissiva)
        let dx = lW.location.x - rW.location.x
        let dy = lW.location.y - rW.location.y
        return sqrt(dx*dx + dy*dy) < 0.22
    }

    // MARK: - Tutorial

    private func setupTutorialUI() {
        tutorialOverlayView.translatesAutoresizingMaskIntoConstraints = false
        tutorialOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        tutorialOverlayView.isHidden = true
        view.addSubview(tutorialOverlayView)

        splitScreenLine.translatesAutoresizingMaskIntoConstraints = false
        splitScreenLine.backgroundColor = .systemYellow
        splitScreenLine.layer.shadowColor = UIColor.yellow.cgColor
        splitScreenLine.layer.shadowRadius = 15
        splitScreenLine.layer.shadowOpacity = 1.0
        splitScreenLine.isHidden = true
        view.addSubview(splitScreenLine)

        tutorialInstructionLabel.translatesAutoresizingMaskIntoConstraints = false
        tutorialInstructionLabel.font = UIFont(name: "MagicSchoolOne", size: 56) ?? .systemFont(ofSize: 50, weight: .bold)
        tutorialInstructionLabel.textColor = .white
        tutorialInstructionLabel.textAlignment = .center
        tutorialInstructionLabel.numberOfLines = 0
        tutorialInstructionLabel.layer.shadowColor = UIColor.black.cgColor
        tutorialInstructionLabel.layer.shadowRadius = 8
        tutorialInstructionLabel.layer.shadowOpacity = 1.0
        tutorialInstructionLabel.layer.shadowOffset = CGSize(width: 2, height: 2)
        tutorialInstructionLabel.isHidden = true
        view.addSubview(tutorialInstructionLabel)

        NSLayoutConstraint.activate([
            tutorialOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            tutorialOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tutorialOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tutorialOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            splitScreenLine.topAnchor.constraint(equalTo: view.topAnchor),
            splitScreenLine.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            splitScreenLine.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            splitScreenLine.widthAnchor.constraint(equalToConstant: 6),

            tutorialInstructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tutorialInstructionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            tutorialInstructionLabel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.85)
        ])
    }

    private func startTutorialFlowIfNeeded() {
        let hasSeenTutorial = UserDefaults.standard.bool(forKey: "KnightTutorialCompleted")
        if hasSeenTutorial {
            currentTutorialPhase = .finished
            return   // mostrerà READY? e aspetterà voce/tasto
        }
        currentTutorialPhase = .intro
        tutorialOverlayView.isHidden = false
        tutorialInstructionLabel.isHidden = false
        tutorialInstructionLabel.text = "Welcome to the Arena"
        // Nascondi start/calibrate durante il tutorial
        startButton.isHidden     = true
        calibrateButton.isHidden = true
        calibrationLabel.isHidden = true
        view.viewWithTag(9901)?.isHidden = true
        playTutorialAudio("IntroTutorial", fallbackDelay: 3.0)
    }

    private func playTutorialAudio(_ name: String, fallbackDelay: Double = 3.0) {
        tutorialAdvanceTimer?.invalidate()
        currentTutorialPlayer?.stop()
        let duration: Double
        if let p = tutorialAudioPlayers[name] {
            p.currentTime = 0; p.play()
            currentTutorialPlayer = p
            duration = p.duration > 0.5 ? p.duration : fallbackDelay
        } else {
            duration = fallbackDelay
        }
        tutorialAdvanceTimer = Timer.scheduledTimer(withTimeInterval: duration + 0.2, repeats: false) { [weak self] _ in
            self?.tutorialStepFinished()
        }
    }

    private func tutorialStepFinished() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch self.currentTutorialPhase {
            case .intro:
                self.currentTutorialPhase = .positioning
                self.tutorialOverlayView.isHidden = true
                self.tutorialInstructionLabel.isHidden = false
                self.tutorialInstructionLabel.text = "Get in position —\nboth warriors in frame"
                self.playTutorialAudio("GetInPosition", fallbackDelay: 2.5)
            case .positioning:
                self.advanceToAttackTutorial()
            default: break
            }
        }
    }

    private func advanceToAttackTutorial() {
        currentTutorialPhase = .waitingAttack
        p1TutorialDone = false; p2TutorialDone = false
        splitScreenLine.isHidden = false
        tutorialInstructionLabel.isHidden = false
        tutorialInstructionLabel.text = "ATTACK:\nSwing your sword!"
        playTutorialAudio("RaiseArmStrike", fallbackDelay: 3.0)
    }

    private func advanceToBlockTutorial() {
        currentTutorialPhase = .waitingBlock
        p1TutorialDone = false; p2TutorialDone = false
        tutorialInstructionLabel.text = "DEFENSE:\nCross arms in front of your face!"
        playTutorialAudio("CrossToDefende", fallbackDelay: 3.0)
    }

    private func finishTutorial() {
        currentTutorialPhase = .finished
        UserDefaults.standard.set(true, forKey: "KnightTutorialCompleted")
        tutorialAdvanceTimer?.invalidate()
        currentTutorialPlayer?.stop()
        splitScreenLine.isHidden = true
        tutorialInstructionLabel.isHidden = true
        UIView.animate(withDuration: 0.5) { self.tutorialOverlayView.alpha = 0 } completion: { _ in
            self.tutorialOverlayView.isHidden = true
            self.tutorialOverlayView.alpha = 1
        }
        // Mostra READY? dopo il tutorial
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            self.calibrationLabel.isHidden = false
            self.view.viewWithTag(9901)?.isHidden = false
            self.startButton.isHidden     = false
            self.calibrateButton.isHidden = false
        }
    }

    // MARK: - Speech

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
                if text.contains("READY") && !self.isWelcomePlaying && !self.countdownStarted {
                    DispatchQueue.main.async {
                        if self.bothPlayersVisible {
                            self.playWelcomeAudio()
                        } else {
                            self.flashWarning()
                        }
                    }
                }
            }
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.startSpeech() }
            }
        }
        audioEngine.prepare()
        try? audioEngine.start()
        // Forza restart ogni 8 secondi — SFSpeechRecognizer smette di ascoltare silenziosamente
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self = self, !self.countdownStarted else { return }
            self.startSpeech()
        }
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

    // MARK: - Game Over logic
    @discardableResult
    private func updateStamina(isBlocking: Bool, stamina: inout Float, penaltyCounter: inout Int, inPenalty: inout Bool) -> Bool {
        if inPenalty {
            penaltyCounter -= 1
            if penaltyCounter <= 0 { inPenalty = false }
            return false
        }
        if isBlocking && stamina > 0 {
            stamina -= drainPerFrame
            if stamina <= 0 {
                stamina = 0
                inPenalty = true
                penaltyCounter = penaltyFrames
            }
            return stamina > 0
        } else if !isBlocking {
            stamina = min(maxStamina, stamina + rechargePerFrame)
        }
        return false
    }

    func showGameOverScreen(winnerIndex: Int, replayPreview: RPPreviewViewController?) {
        let vc = GameOverViewController(winnerIndex: winnerIndex, replayPreview: replayPreview)
        vc.delegate = self
        present(vc, animated: true)
    }

    @objc private func startTapped() {
        guard !countdownStarted && !isWelcomePlaying else { return }
        if bothPlayersVisible {
            playWelcomeAudio()   // playWelcomeAudio gestisce countdownStarted e nasconde i bottoni
        } else {
            flashWarning()
        }
    }

    @objc private func calibrateTapped() {
        cameraManager.resetCalibration()
        lastAnchor    = [nil, nil]
        lastElbow     = [nil, nil]
        missingFrames = [0, 0]
    }

    @objc private func restartGameTapped() {
        p1HP = 100; p2HP = 100
        p1Stamina = maxStamina; p2Stamina = maxStamina
        p1InPenalty = false; p2InPenalty = false
        p1PenaltyCounter = 0; p2PenaltyCounter = 0
        lowHealthP1Played = false; lowHealthP2Played = false; lowHealthBothPlayed = false
        isGameOver = false
        countdownStarted = false
        isFightActive = false
        isWelcomePlaying = false
        currentTutorialPhase = .finished   // dopo il primo tutorial non lo rifare
        stopBattleMusic()
        startRecording()
        calibrationLabel.isHidden = false
        view.viewWithTag(9901)?.isHidden = false
        startButton.isHidden     = false
        calibrateButton.isHidden = false
    }
}

// MARK: - GameOverDelegate
extension TrackingViewController: GameOverDelegate {
    func gameOverDidTapHome()    { onGoHome?() }
    func gameOverDidTapRestart() { restartGameTapped() }
}

// MARK: - BodyTrackingDelegate
extension TrackingViewController: BodyTrackingDelegate {
    
    func didDetectPlayers(_ result: PlayersDetectionResult) {
        if !isGameOver {
            if p1HP <= 0 || p2HP <= 0 {
                isGameOver = true
                let winner = p1HP <= 0 ? 2 : 1
                hideSwords(); hideShields()
                stopBattleMusic()
                RPScreenRecorder.shared().stopRecording { [weak self] preview, _ in
                    DispatchQueue.main.async { self?.showGameOverScreen(winnerIndex: winner, replayPreview: preview) }
                }
                return
            }
        } else { return }
        
        statusDot.backgroundColor = .green
        bothPlayersVisible = (result.player1 != nil && result.player2 != nil)

        // ── Tutorial intercept ──────────────────────────────────────────────
        if currentTutorialPhase != .finished {
            let p1Present = result.player1 != nil
            let p2Present = result.player2 != nil
            switch currentTutorialPhase {
            case .positioning:
                if p1Present && p2Present { advanceToAttackTutorial() }
            case .waitingAttack:
                // Usa p1Action dal BodyAnalyzer per la fase tutorial
                let p1A = result.player1?.action ?? .idle
                let p2A = result.player2?.action ?? .idle
                if p1A == .attack { p1TutorialDone = true }
                if p2A == .attack { p2TutorialDone = true }
                if p1TutorialDone && p2TutorialDone { advanceToBlockTutorial() }
            case .waitingBlock:
                // Block tutorial: usa la stessa isHandsCrossedAtFace
                let p1B = result.player1.map { isHandsCrossedAtFace($0.observation) } ?? false
                let p2B = result.player2.map { isHandsCrossedAtFace($0.observation) } ?? false
                if p1B { p1TutorialDone = true }
                if p2B { p2TutorialDone = true }
                if p1TutorialDone && p2TutorialDone { finishTutorial() }
            default: break
            }
            return
        }
        // ── Fine tutorial ───────────────────────────────────────────────────

        var observations: [VNHumanBodyPoseObservation] = []
        var actions:      [PlayerAction]               = []
        
        let p1Action = result.player1?.action ?? .idle
        let p2Action = result.player2?.action ?? .idle

        // Block detection: mani incrociate davanti al volto
        let p1IsBlocking = result.player1.map { isHandsCrossedAtFace($0.observation) } ?? false
        let p2IsBlocking = result.player2.map { isHandsCrossedAtFace($0.observation) } ?? false

        // Suono swing: basato sulla velocità della spada (wrist velocity), non su BodyAnalyzer
        if p1Action == .attack || p2Action == .attack { playSwingSound() }
        if p1IsBlocking || p2IsBlocking { playDefenseSound() }

        let p1Blocking = updateStamina(isBlocking: p1IsBlocking, stamina: &p1Stamina, penaltyCounter: &p1PenaltyCounter, inPenalty: &p1InPenalty)
        let p2Blocking = updateStamina(isBlocking: p2IsBlocking, stamina: &p2Stamina, penaltyCounter: &p2PenaltyCounter, inPenalty: &p2InPenalty)

        // Per l'HUD passiamo il blocco calcolato come action
        let p1DisplayAction: PlayerAction = p1IsBlocking ? .block : p1Action
        let p2DisplayAction: PlayerAction = p2IsBlocking ? .block : p2Action
        
        if let p1 = result.player1 {
            player1Box.update(action: p1DisplayAction, isDetected: true, hp: p1HP, stamina: p1Stamina, maxStamina: maxStamina, inPenalty: p1InPenalty)
            observations.append(p1.observation); actions.append(p1DisplayAction)
        } else {
            player1Box.update(action: .idle, isDetected: false, hp: p1HP, stamina: p1Stamina, maxStamina: maxStamina, inPenalty: p1InPenalty)
        }
        
        if playerCount == 2 {
            if let p2 = result.player2 {
                player2Box.update(action: p2DisplayAction, isDetected: true, hp: p2HP, stamina: p2Stamina, maxStamina: maxStamina, inPenalty: p2InPenalty)
                observations.append(p2.observation); actions.append(p2DisplayAction)
            } else {
                player2Box.update(action: .idle, isDetected: false, hp: p2HP, stamina: p2Stamina, maxStamina: maxStamina, inPenalty: p2InPenalty)
            }
        }
        
        overlayView.update(with: observations, actions: actions, hands: [result.hand1, result.hand2], playerColors: [.systemCyan, .systemOrange], in: view.bounds)
        
        let sz = view.bounds.size
        
        for (i, obs) in observations.enumerated() {
            let handObs: VNHumanHandPoseObservation? = i == 0 ? result.hand1 : result.hand2
            let rW = try? obs.recognizedPoint(.rightWrist)
            let lW = try? obs.recognizedPoint(.leftWrist)
            let rE = try? obs.recognizedPoint(.rightElbow)
            let lE = try? obs.recognizedPoint(.leftElbow)
            let handedness = (rW?.confidence ?? 0) >= (lW?.confidence ?? 0) ? "right" : "left"
            let dominantWrist = handedness == "right" ? rW : lW
            let dominantElbow = handedness == "right" ? rE : lE
            
            let swordFacingRight = (i == 0)
            let isBlocking = i == 0 ? p1Blocking : p2Blocking
            
            if isBlocking {
                swordWrappers[i].isHidden = true
                let rValid = rW.map { $0.confidence > 0.3 } ?? false
                let lValid = lW.map { $0.confidence > 0.3 } ?? false
                let shieldAnchor: CGPoint?
                if rValid, lValid, let r = rW, let l = lW {
                    shieldAnchor = CGPoint(x: ((1 - r.location.x) + (1 - l.location.x)) / 2 * sz.width, y: ((1 - r.location.y) + (1 - l.location.y)) / 2 * sz.height)
                } else if rValid, let r = rW {
                    shieldAnchor = CGPoint(x: (1 - r.location.x) * sz.width, y: (1 - r.location.y) * sz.height)
                } else if lValid, let l = lW {
                    shieldAnchor = CGPoint(x: (1 - l.location.x) * sz.width, y: (1 - l.location.y) * sz.height)
                } else { shieldAnchor = nil }
                
                if let anchor = shieldAnchor {
                    let opponentObs = i == 0 ? result.player2?.observation : result.player1?.observation
                    var opponentAnchor: CGPoint? = nil
                    if let oppObs = opponentObs, let neck = try? oppObs.recognizedPoint(.neck), neck.confidence > 0.3 {
                        opponentAnchor = CGPoint(x: (1 - neck.location.x) * sz.width, y: (1 - neck.location.y) * sz.height)
                    }
                    updateShield3D(playerIndex: i, anchor: anchor, facingRight: swordFacingRight, bodyObservation: obs, opponentAnchor: opponentAnchor)
                } else if i < shieldWrappers.count { shieldWrappers[i].isHidden = true }
                continue
            }
            
            if i < shieldWrappers.count { shieldWrappers[i].isHidden = true }
            
            var currentAnchor: CGPoint?
            var currentElbow:  CGPoint?
            
            if let hand = handObs, let wristPt = try? hand.recognizedPoint(.wrist), wristPt.confidence > 0.1,
               let middleMCP = try? hand.recognizedPoint(.middleMCP), middleMCP.confidence > 0.1 {
                currentAnchor = CGPoint(x: (1 - middleMCP.location.x) * sz.width, y: (1 - middleMCP.location.y) * sz.height)
                if let ep = dominantElbow, ep.confidence > 0.3 {
                    currentElbow = CGPoint(x: (1 - ep.location.x) * sz.width, y: (1 - ep.location.y) * sz.height)
                }
            } else if let wp = dominantWrist, wp.confidence > 0.35, let ep = dominantElbow, ep.confidence > 0.35 {
                currentAnchor = CGPoint(x: (1 - wp.location.x) * sz.width, y: (1 - wp.location.y) * sz.height)
                currentElbow  = CGPoint(x: (1 - ep.location.x) * sz.width, y: (1 - ep.location.y) * sz.height)
            }
            
            if let anchor = currentAnchor {
                lastAnchor[i]    = anchor
                lastElbow[i]     = currentElbow ?? lastElbow[i]
                missingFrames[i] = 0
            } else {
                missingFrames[i] += 1
                if missingFrames[i] > maxMissingFrames {
                    if i < swordWrappers.count { swordWrappers[i].isHidden = true }
                    continue
                }
                currentAnchor = lastAnchor[i]
                currentElbow  = lastElbow[i]
            }
            
            guard let anchor = currentAnchor else {
                if i < swordWrappers.count { swordWrappers[i].isHidden = true }
                continue
            }
            
            let elbow = currentElbow ?? CGPoint(x: swordFacingRight ? anchor.x - 100 : anchor.x + 100, y: anchor.y)
            updateSword3D(playerIndex: i, anchor: anchor, elbow: elbow, facingRight: swordFacingRight)
            
            let tipAngle = atan2(anchor.y - elbow.y, anchor.x - elbow.x)
            let tip = CGPoint(x: anchor.x + cos(tipAngle) * 220, y: anchor.y + sin(tipAngle) * 220)
            overlayView.setSwordTip(tip, forPlayer: i)
        }
        
        if observations.count < 2 {
            if swordWrappers.count  > 1 { swordWrappers[1].isHidden  = true }
            if shieldWrappers.count > 1 { shieldWrappers[1].isHidden = true }
        }
        if observations.isEmpty {
            swordWrappers.first?.isHidden  = true
            shieldWrappers.first?.isHidden = true
        }

        // Aggiorna indicatori petto
        let showChest = isFightActive

        func chestPos(_ obs: VNHumanBodyPoseObservation) -> SCNVector3? {
            guard let neck = try? obs.recognizedPoint(.neck), neck.confidence > 0.3,
                  let lS   = try? obs.recognizedPoint(.leftShoulder),  lS.confidence > 0.2,
                  let rS   = try? obs.recognizedPoint(.rightShoulder), rS.confidence > 0.2 else { return nil }
            let cx = ((1-neck.location.x) + (1-lS.location.x) + (1-rS.location.x)) / 3 * sz.width
            let cy = ((1-neck.location.y) + (1-lS.location.y) + (1-rS.location.y)) / 3 * sz.height + sz.height * 0.05
            let d  = scnView.projectPoint(SCNVector3(0, 0, 20)).z
            return scnView.unprojectPoint(SCNVector3(Float(cx), Float(cy), d))
        }

        chestNode1?.isHidden = !showChest
        chestNode2?.isHidden = !showChest
        if showChest {
            if let p1obs = result.player1?.observation, let pos = chestPos(p1obs) { chestNode2?.position = pos }
            if let p2obs = result.player2?.observation, let pos = chestPos(p2obs) { chestNode1?.position = pos }
        }
        
        if p1HitCooldown > 0 { p1HitCooldown -= 1 }
        if p2HitCooldown > 0 { p2HitCooldown -= 1 }

        guard playerCount == 2, let p1obs = result.player1?.observation, let p2obs = result.player2?.observation else { return }
        let bounds = view.bounds

        // --- LOGICA DI COLLISIONE E DANNI ---
        // Nessun danno finché non è apparso FIGHT! sullo schermo
        guard isFightActive else { return }

        if p2HitCooldown == 0,
           let tip = overlayView.swordTip(forPlayer: 0),
           overlayView.bodyRect(for: p2obs, in: bounds).contains(tip) {
            if p2Blocking {
                playBlockedSound()
            } else {
                p2HP = max(0, p2HP - damagePerHit)
                player2Box.flashDamage()
                playHitSound()
                playLowHealthIfNeeded()
            }
            p2HitCooldown = hitCooldown
        }

        if p1HitCooldown == 0,
           let tip = overlayView.swordTip(forPlayer: 1),
           overlayView.bodyRect(for: p1obs, in: bounds).contains(tip) {
            if p1Blocking {
                playBlockedSound()
            } else {
                p1HP = max(0, p1HP - damagePerHit)
                player1Box.flashDamage()
                playHitSound()
                playLowHealthIfNeeded()
            }
            p1HitCooldown = hitCooldown
        }
    }
    
    func didLoseTracking() {
        statusDot.backgroundColor = .red
        hideSwords(); hideShields()
        player1Box.update(action: .idle, isDetected: false, hp: p1HP, stamina: p1Stamina, maxStamina: maxStamina, inPenalty: p1InPenalty)
        if playerCount == 2 { player2Box.update(action: .idle, isDetected: false, hp: p2HP, stamina: p2Stamina, maxStamina: maxStamina, inPenalty: p2InPenalty) }
        overlayView.clear()
    }
    
}
// MARK: - PlayerHUDView
class PlayerHUDView: UIView {
    private let isRightSide: Bool
    private let playerColor: UIColor
    private var currentHP: Int = 100
    private var ghostTimer: Timer?

    private let nameLabel     = UILabel()
    private let hpIcon        = UIImageView()
    private let stamIcon      = UIImageView()
    private let hpBarBg       = ArrowBarView(color: UIColor(red:0.1,green:0.2,blue:0.6,alpha:1))
    private let hpGhostBar    = ArrowBarView(color: UIColor(red:0.8,green:0.5,blue:0.0,alpha:0.8))
    private let hpFillBar     = ArrowBarView(color: UIColor(red:0.85,green:0.1,blue:0.1,alpha:1))
    private let stamBarBg     = ArrowBarView(color: UIColor(red:0.05,green:0.15,blue:0.5,alpha:1))
    private let stamFillBar   = ArrowBarView(color: UIColor(red:0.1,green:0.4,blue:0.9,alpha:1))

    private var hpRatio: CGFloat   = 1.0
    private var ghostRatio: CGFloat = 1.0
    private var stamRatio: CGFloat = 1.0

    init(playerName: String, color: UIColor, rightSide: Bool = false) {
        self.playerColor = color
        self.isRightSide = rightSide
        super.init(frame: .zero)
        backgroundColor = .clear
        setupSubviews(name: playerName)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupSubviews(name: String) {
        nameLabel.text                    = name
        nameLabel.font                    = UIFont(name: "MagicSchoolOne", size: 28) ?? .systemFont(ofSize: 24, weight: .bold)
        
        if isRightSide {
            nameLabel.textColor = UIColor(red: 251/255.0, green: 198/255.0, blue: 161/255.0, alpha: 1.0)
        } else {
            nameLabel.textColor = UIColor(red: 209/255.0, green: 84/255.0, blue: 113/255.0, alpha: 1.0)
        }
        
        nameLabel.textAlignment           = isRightSide ? .right : .left
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor      = 0.5
        nameLabel.layer.shadowColor       = UIColor.black.cgColor
        nameLabel.layer.shadowOffset      = CGSize(width: 2, height: 2)
        nameLabel.layer.shadowOpacity     = 0.95
        nameLabel.layer.shadowRadius      = 3

        hpIcon.image = UIImage(named: "heart")
        hpIcon.contentMode = .scaleAspectFit
        stamIcon.image = UIImage(named: "shield")
        stamIcon.contentMode = .scaleAspectFit

        for v in [nameLabel, hpIcon, stamIcon, hpBarBg, hpGhostBar, hpFillBar, stamBarBg, stamFillBar] {
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

            hpGhostBar.topAnchor.constraint(equalTo: hpBarBg.topAnchor),
            hpGhostBar.leadingAnchor.constraint(equalTo: hpBarBg.leadingAnchor),
            hpGhostBar.heightAnchor.constraint(equalTo: hpBarBg.heightAnchor),
            hpGhostBar.widthAnchor.constraint(equalTo: hpBarBg.widthAnchor),

            hpFillBar.topAnchor.constraint(equalTo: hpBarBg.topAnchor),
            hpFillBar.leadingAnchor.constraint(equalTo: hpBarBg.leadingAnchor),
            hpFillBar.heightAnchor.constraint(equalTo: hpBarBg.heightAnchor),
            hpFillBar.widthAnchor.constraint(equalTo: hpBarBg.widthAnchor),

            stamIcon.centerYAnchor.constraint(equalTo: stamBarBg.centerYAnchor),
            stamIcon.widthAnchor.constraint(equalToConstant: 22),
            stamIcon.heightAnchor.constraint(equalToConstant: 22),

            stamBarBg.topAnchor.constraint(equalTo: hpBarBg.bottomAnchor, constant: 5),
            stamBarBg.heightAnchor.constraint(equalToConstant: 13),
            stamBarBg.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            stamFillBar.topAnchor.constraint(equalTo: stamBarBg.topAnchor),
            stamFillBar.leadingAnchor.constraint(equalTo: stamBarBg.leadingAnchor),
            stamFillBar.heightAnchor.constraint(equalTo: stamBarBg.heightAnchor),
            stamFillBar.widthAnchor.constraint(equalTo: stamBarBg.widthAnchor)
        ]

        if isRightSide {
            constraints.append(contentsOf: [
                hpIcon.trailingAnchor.constraint(equalTo: trailingAnchor),
                hpBarBg.trailingAnchor.constraint(equalTo: hpIcon.leadingAnchor, constant: -4),
                hpBarBg.leadingAnchor.constraint(equalTo: leadingAnchor),

                stamIcon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                stamBarBg.trailingAnchor.constraint(equalTo: stamIcon.leadingAnchor, constant: -4),
                stamBarBg.leadingAnchor.constraint(equalTo: leadingAnchor)
            ])
            let flip = CGAffineTransform(scaleX: -1, y: 1)
            hpBarBg.transform = flip
            hpGhostBar.transform = flip
            hpFillBar.transform = flip
            stamBarBg.transform = flip
            stamFillBar.transform = flip
        } else {
            constraints.append(contentsOf: [
                hpIcon.leadingAnchor.constraint(equalTo: leadingAnchor),
                hpBarBg.leadingAnchor.constraint(equalTo: hpIcon.trailingAnchor, constant: 4),
                hpBarBg.trailingAnchor.constraint(equalTo: trailingAnchor),

                stamIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                stamBarBg.leadingAnchor.constraint(equalTo: stamIcon.trailingAnchor, constant: 4),
                stamBarBg.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }
        NSLayoutConstraint.activate(constraints)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hpGhostBar.setFillRatio(ghostRatio); hpFillBar.setFillRatio(hpRatio); stamFillBar.setFillRatio(stamRatio)
    }

    func update(action: PlayerAction, isDetected: Bool, hp: Int = 100, stamina: Float, maxStamina: Float, inPenalty: Bool) {
        let newHPRatio = CGFloat(max(0, hp)) / 100.0
        if hp < currentHP {
            hpRatio = newHPRatio
            UIView.animate(withDuration: 0.12) { self.hpFillBar.setFillRatio(self.hpRatio) }
            ghostTimer?.invalidate()
            ghostTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.ghostRatio = newHPRatio
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

        stamRatio = CGFloat(stamina / maxStamina)
        let stamColor: UIColor = inPenalty ? UIColor(red:0.8,green:0.1,blue:0.1,alpha:1) : UIColor(red:0.1,green:0.4,blue:0.9,alpha:1)
        stamFillBar.fillColor = stamColor
        UIView.animate(withDuration: 0.2) { self.stamFillBar.setFillRatio(self.stamRatio) }

        if stamina >= maxStamina && !inPenalty {
            UIView.animate(withDuration: 0.4, delay: 0, options: [.autoreverse, .allowUserInteraction],
                           animations: { self.stamFillBar.alpha = 0.6 }) { _ in self.stamFillBar.alpha = 1 }
        }
    }

    func flashDamage() {
        let shake = CAKeyframeAnimation(keyPath: "position.x")
        shake.values   = [0,-9,9,-7,7,-5,5,0].map { $0 + layer.position.x }
        shake.duration = 0.38
        shake.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(shake, forKey: "shake")
    }
}

// MARK: - ArrowBarView
class ArrowBarView: UIView {
    var fillColor: UIColor { didSet { setNeedsDisplay() } }
    private var ratio: CGFloat = 1.0
    init(color: UIColor) { self.fillColor = color; super.init(frame: .zero); backgroundColor = .clear; isOpaque = false }
    required init?(coder: NSCoder) { fatalError() }

    func setFillRatio(_ r: CGFloat) { ratio = max(0, min(1, r)); setNeedsDisplay() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.clear(rect)
        let h = rect.height, w = rect.width, tip = h * 0.55, inset: CGFloat = 2

        func arrowPath(width: CGFloat) -> UIBezierPath {
            let p = UIBezierPath()
            p.move(to: CGPoint(x: inset, y: inset)); p.addLine(to: CGPoint(x: width - tip, y: inset))
            p.addLine(to: CGPoint(x: width, y: h / 2)); p.addLine(to: CGPoint(x: width - tip, y: h - inset))
            p.addLine(to: CGPoint(x: inset, y: h - inset)); p.close()
            return p
        }

        UIColor(red:0.04,green:0.06,blue:0.18,alpha:1).setFill(); arrowPath(width: w).fill()
        UIColor(red:0.2,green:0.5,blue:1.0,alpha:1).setStroke()
        let border = arrowPath(width: w); border.lineWidth = 2.5; border.stroke()

        let shimmer = UIBezierPath()
        shimmer.move(to: CGPoint(x: inset, y: inset + 1)); shimmer.addLine(to: CGPoint(x: w * 0.7, y: inset + 1))
        shimmer.addLine(to: CGPoint(x: w * 0.7, y: inset + h * 0.28)); shimmer.addLine(to: CGPoint(x: inset, y: inset + h * 0.28)); shimmer.close()
        UIColor(white: 1, alpha: 0.08).setFill(); shimmer.fill()

        let fillW = (w - tip - inset) * ratio + (ratio > 0.95 ? tip : 0)
        if fillW > 1 {
            let fill = arrowPath(width: max(inset + 4, fillW))
            ctx.saveGState()
            arrowPath(width: w).addClip()
            fillColor.setFill(); fill.fill()
            let shine = UIBezierPath()
            shine.move(to: CGPoint(x: inset, y: inset + 2)); shine.addLine(to: CGPoint(x: max(inset + 4, fillW) - tip * 0.5, y: inset + 2))
            shine.addLine(to: CGPoint(x: max(inset + 4, fillW) - tip * 0.5, y: h * 0.35)); shine.addLine(to: CGPoint(x: inset, y: h * 0.35)); shine.close()
            UIColor(white: 1, alpha: 0.25).setFill(); shine.fill()
            ctx.restoreGState()
        }
        UIColor(red:0.05,green:0.1,blue:0.35,alpha:1).setStroke()
        let outer = arrowPath(width: w); outer.lineWidth = 1; outer.stroke()
    }
}

// MARK: - SkeletonOverlayView
class SkeletonOverlayView: UIView {
    var showDebugSkeleton = false

    private var jointLayers: [CAShapeLayer] = []
    private var boneLayers:  [CAShapeLayer] = []
    private var labelLayers: [CATextLayer]  = []
    private var swordTips:   [CGPoint?]     = [nil, nil]

    private let bones: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder,.rightElbow), (.rightElbow, .rightWrist), (.leftShoulder, .leftHip),
        (.rightShoulder,.rightHip), (.leftHip, .rightHip), (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.root, .leftHip), (.root, .rightHip), (.neck, .leftShoulder), (.neck, .rightShoulder)
    ]

    func swordTip(forPlayer index: Int) -> CGPoint? { guard index < swordTips.count else { return nil }; return swordTips[index] }
    func setSwordTip(_ point: CGPoint, forPlayer index: Int) { guard index < swordTips.count else { return }; swordTips[index] = point }

    func bodyRect(for obs: VNHumanBodyPoseObservation, in bounds: CGRect) -> CGRect {
        let joints: [VNHumanBodyPoseObservation.JointName] = [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .neck, .leftElbow, .rightElbow, .leftKnee, .rightKnee]
        let points = joints.compactMap { name -> CGPoint? in
            guard let p = try? obs.recognizedPoint(name), p.confidence > 0.2 else { return nil }
            return toScreen(p.location, bounds)
        }
        guard !points.isEmpty else { return .zero }
        let minX = points.map(\.x).min()!; let maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!; let maxY = points.map(\.y).max()!
        let pad: CGFloat = 20
        return CGRect(x: minX - pad, y: minY - pad, width: (maxX - minX) + pad * 2, height: (maxY - minY) + pad * 2)
    }

    func update(with observations: [VNHumanBodyPoseObservation], actions: [PlayerAction], hands: [VNHumanHandPoseObservation?] = [], playerColors: [UIColor], in bounds: CGRect) {
        clear()
        swordTips = [nil, nil]
        for (i, obs) in observations.enumerated() {
            if showDebugSkeleton {
                let color = i < playerColors.count ? playerColors[i] : UIColor.systemCyan
                drawSkeleton(obs, color: color, label: i == 0 ? "P1" : "P2", action: i < actions.count ? actions[i] : .idle, in: bounds, playerIndex: i)
                if i < hands.count, let hand = hands[i] { drawHand(hand, color: color, in: bounds) }
            }
        }
    }

    private func drawHand(_ hand: VNHumanHandPoseObservation, color: UIColor, in bounds: CGRect) {
        let chains: [[VNHumanHandPoseObservation.JointName]] = [
            [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip], [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
            [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip], [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
            [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip], [.indexMCP, .middleMCP, .ringMCP, .littleMCP]
        ]
        for chain in chains {
            var prev: CGPoint? = nil
            for jName in chain {
                guard let pt = try? hand.recognizedPoint(jName), pt.confidence > 0.3 else { prev = nil; continue }
                let s = toScreen(pt.location, bounds)
                if let p = prev {
                    let path = UIBezierPath(); path.move(to: p); path.addLine(to: s)
                    let bl = CAShapeLayer(); bl.path = path.cgPath; bl.strokeColor = color.withAlphaComponent(0.9).cgColor; bl.lineWidth = 3; bl.lineCap = .round
                    layer.addSublayer(bl); boneLayers.append(bl)
                }
                let r: CGFloat  = jName == .wrist ? 8 : 4
                let dl = CAShapeLayer(); dl.path = UIBezierPath(arcCenter: s, radius: r, startAngle: 0, endAngle: .pi*2, clockwise: true).cgPath
                dl.fillColor  = color.withAlphaComponent(0.85).cgColor; dl.strokeColor = UIColor.white.cgColor; dl.lineWidth = 1.5
                layer.addSublayer(dl); jointLayers.append(dl)
                prev = s
            }
        }
    }

    private func drawSkeleton(_ obs: VNHumanBodyPoseObservation, color: UIColor, label: String, action: PlayerAction, in bounds: CGRect, playerIndex: Int = 0) {
        for (jA, jB) in bones {
            guard let pA = try? obs.recognizedPoint(jA), pA.confidence > 0.3, let pB = try? obs.recognizedPoint(jB), pB.confidence > 0.3 else { continue }
            let path = UIBezierPath(); path.move(to: toScreen(pA.location, bounds)); path.addLine(to: toScreen(pB.location, bounds))
            let bl = CAShapeLayer(); bl.path = path.cgPath; bl.strokeColor = color.withAlphaComponent(0.85).cgColor; bl.lineWidth = 4; bl.lineCap = .round
            layer.addSublayer(bl); boneLayers.append(bl)
        }

        let joints: [VNHumanBodyPoseObservation.JointName] = [.leftWrist, .rightWrist, .leftElbow, .rightElbow, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .root, .neck]
        for j in joints {
            guard let p = try? obs.recognizedPoint(j), p.confidence > 0.3 else { continue }
            let s = toScreen(p.location, bounds)
            let isWrist = (j == .leftWrist || j == .rightWrist)
            let dl = CAShapeLayer(); dl.path = UIBezierPath(arcCenter: s, radius: isWrist ? 13 : 6, startAngle: 0, endAngle: .pi*2, clockwise: true).cgPath
            if isWrist {
                dl.fillColor  = UIColor.white.cgColor; dl.strokeColor = color.cgColor; dl.lineWidth = 3
                let inner = CAShapeLayer(); inner.path = UIBezierPath(arcCenter: s, radius: 5, startAngle: 0, endAngle: .pi*2, clockwise: true).cgPath
                inner.fillColor = color.cgColor
                layer.addSublayer(inner); jointLayers.append(inner)
            } else { dl.fillColor  = color.cgColor; dl.strokeColor = UIColor.white.cgColor; dl.lineWidth = 2 }
            layer.addSublayer(dl); jointLayers.append(dl)
        }
        if let neck = try? obs.recognizedPoint(.neck), neck.confidence > 0.3 {
            let pos = toScreen(neck.location, bounds)
            let tl  = CATextLayer(); tl.string = label; tl.fontSize = 24; tl.foregroundColor = color.cgColor; tl.backgroundColor = UIColor.black.withAlphaComponent(0.5).cgColor; tl.cornerRadius = 6; tl.alignmentMode = .center
            tl.frame = CGRect(x: pos.x - 25, y: pos.y - 50, width: 50, height: 32)
            layer.addSublayer(tl); labelLayers.append(tl)
        }
    }

    func clear() {
        (jointLayers + boneLayers).forEach { $0.removeFromSuperlayer() }; labelLayers.forEach { $0.removeFromSuperlayer() }
        jointLayers = []; boneLayers = []; labelLayers = []
    }

    private func toScreen(_ point: CGPoint, _ bounds: CGRect) -> CGPoint { CGPoint(x: (1 - point.x) * bounds.width, y: (1 - point.y) * bounds.height) }
}
