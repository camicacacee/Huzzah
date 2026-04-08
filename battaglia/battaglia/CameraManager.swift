//
//  CameraManager.swift
//  battaglia
//
//  Gestisce la sessione AVFoundation, il rilevamento corpo (VNDetectHumanBodyPoseRequest)
//  e il rilevamento mani (VNDetectHumanHandPoseRequest) in parallelo.
//

import AVFoundation
import Vision
import UIKit

// MARK: - CameraManager

class CameraManager: NSObject {

    // MARK: - Public
    weak var delegate: BodyTrackingDelegate?
    var expectedPlayers: Int = 1
    var dominantHand: String = "right"   // "right" | "left" — quale mano tracciare
    var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Private: AVFoundation
    private let captureSession  = AVCaptureSession()
    private let videoOutput     = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.battaglia.camera", qos: .userInteractive)

    // MARK: - Private: Vision
    private lazy var bodyPoseRequest: VNDetectHumanBodyPoseRequest = {
        let r = VNDetectHumanBodyPoseRequest()
        return r
    }()

    private lazy var handPoseRequest: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()

    // MARK: - Private: analisi giocatori
    private let analyzer1 = BodyAnalyzer()
    private let analyzer2 = BodyAnalyzer()



    // MARK: - Setup

    func setupCamera() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video, position: .front),
              let input  = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            print("Camera non disponibile"); return
        }

        captureSession.addInput(input)
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        guard captureSession.canAddOutput(videoOutput) else { return }
        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 180
        }

        captureSession.commitConfiguration()

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.connection?.videoRotationAngle = 180
    }

    func startSession() {
        processingQueue.async { [weak self] in self?.captureSession.startRunning() }
    }

    func stopSession() { captureSession.stopRunning() }

    // MARK: - Calibrazione

    func resetCalibration() {
        analyzer1.resetCalibration()
        analyzer2.resetCalibration()
    }

    // MARK: - Assegnazione P1/P2 stabile

    private func centerX(of observation: VNHumanBodyPoseObservation) -> CGFloat {
        let joints: [VNHumanBodyPoseObservation.JointName] = [
            .leftShoulder, .rightShoulder, .leftHip, .rightHip,
            .neck, .root, .leftElbow, .rightElbow
        ]
        let points = joints.compactMap { name -> CGFloat? in
            guard let p = try? observation.recognizedPoint(name), p.confidence > 0.3 else { return nil }
            return p.location.x
        }
        guard !points.isEmpty else { return 0.5 }
        return points.reduce(0, +) / CGFloat(points.count)
    }

    private func assignPlayers(_ observations: [VNHumanBodyPoseObservation])
        -> (p1: VNHumanBodyPoseObservation?, p2: VNHumanBodyPoseObservation?) {

        guard !observations.isEmpty else { return (nil, nil) }
        if expectedPlayers == 1 { return (observations[0], nil) }
        if observations.count == 1 { return (observations[0], nil) }

        let obs0 = observations[0]
        let obs1 = observations[1]
        let x0 = centerX(of: obs0)
        let x1 = centerX(of: obs1)

        // In Vision space: x > 0.5 = sinistra schermo = P1, x < 0.5 = destra schermo = P2
        // Non aggiorniamo mai la posizione — P1 è sempre il corpo più a sinistra schermo
        if x0 > x1 {
            return (obs0, obs1)
        } else {
            return (obs1, obs0)
        }
    }

    // MARK: - Assegna la mano giusta al giocatore
    //
    // VNDetectHumanHandPoseRequest non sa a chi appartiene ogni mano.
    // Usiamo la posizione del polso del body pose per trovare la mano piu' vicina.

    private func assignHand(to bodyObs: VNHumanBodyPoseObservation,
                             from hands: [VNHumanHandPoseObservation]) -> VNHumanHandPoseObservation? {
        guard !hands.isEmpty else { return nil }

        // Usa il polso della mano dominante come punto di riferimento
        let rW = try? bodyObs.recognizedPoint(.rightWrist)
        let lW = try? bodyObs.recognizedPoint(.leftWrist)

        let refPoint: CGPoint?
        if dominantHand == "left" {
            if let lw = lW, lw.confidence > 0.2 { refPoint = lw.location }
            else if let rw = rW, rw.confidence > 0.2 { refPoint = rw.location }
            else { return nil }
        } else {
            if let rw = rW, rw.confidence > 0.2 { refPoint = rw.location }
            else if let lw = lW, lw.confidence > 0.2 { refPoint = lw.location }
            else { return nil }
        }

        guard let ref = refPoint else { return nil }

        // Trova la mano con il wrist piu' vicino al punto di riferimento del body.
        // NOTA: body pose e hand pose condividono lo stesso VNImageRequestHandler,
        // quindi le coordinate sono nello stesso spazio normalizzato (0-1, Y-up).
        // Con camera frontale il flip e' gia' gestito da videoRotationAngle=180.
        var bestHand: VNHumanHandPoseObservation? = nil
        var bestDist: CGFloat = .infinity

        for hand in hands {
            guard let wrist = try? hand.recognizedPoint(.wrist),
                  wrist.confidence > 0.1 else { continue }
            let d = hypot(wrist.location.x - ref.x, wrist.location.y - ref.y)
            if d < bestDist {
                bestDist = d
                bestHand = hand
            }
        }

        // Soglia alzata a 0.6 — lo spazio normalizzato e' 0..1,
        // la mano puo' essere lontana dal wrist body se il body pose e' impreciso.
        // Prendiamo sempre la mano piu' vicina purche' sia nella meta' giusta dello schermo.
        return bestDist < 0.6 ? bestHand : nil
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            // Esegui body pose e hand pose in parallelo nello stesso handler
            try handler.perform([bodyPoseRequest, handPoseRequest])

            let bodyObservations = Array((bodyPoseRequest.results ?? []).prefix(expectedPlayers))
            let handObservations = (handPoseRequest.results ?? []) as [VNHumanHandPoseObservation]

            if bodyObservations.isEmpty {
                DispatchQueue.main.async { [weak self] in self?.delegate?.didLoseTracking() }
                return
            }

            let (p1obs, p2obs) = assignPlayers(bodyObservations)

            var result = PlayersDetectionResult()
                        if let obs = p1obs {
                            // Diciamo esplicitamente che questo è P1
                            result.player1 = (analyzer1.analyze(obs, isPlayerOne: true), obs)
                            result.hand1   = assignHand(to: obs, from: handObservations)
                        }
                        if let obs = p2obs {
                            // Diciamo esplicitamente che questo NON è P1 (è P2)
                            result.player2 = (analyzer2.analyze(obs, isPlayerOne: false), obs)
                            var remainingHands = handObservations
                            if let h1 = result.hand1 {
                                remainingHands = remainingHands.filter { $0 !== h1 }
                            }
                            result.hand2 = assignHand(to: obs, from: remainingHands)
                        }

            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didDetectPlayers(result)
            }

        } catch {
            print("Vision error: \(error)")
        }
    }
}
