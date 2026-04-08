//
//  GameOverViewController.swift
//  battaglia
//

import UIKit
import ReplayKit
import AVFoundation

// MARK: - Delegate

protocol GameOverDelegate: AnyObject {
    func gameOverDidTapHome()
    func gameOverDidTapRestart()
}

// MARK: - GameOverViewController

class GameOverViewController: UIViewController {

    // MARK: - Init

    private let winnerIndex: Int
    private let replayPreview: RPPreviewViewController?
    private var audioPlayer: AVAudioPlayer?
    weak var delegate: GameOverDelegate?

    init(winnerIndex: Int, replayPreview: RPPreviewViewController?) {
        self.winnerIndex   = winnerIndex
        self.replayPreview = replayPreview
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        replayPreview?.previewControllerDelegate = self
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    private var backgroundSetup = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !backgroundSetup else { return }
        backgroundSetup = true
        setupBackground()
        setupButtons()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        playGameOverSound()
    }

    // MARK: - Audio

    private func playGameOverSound() {
        let winnerNames = ["CloserToGlory", "Winner_1", "Winner_2", "Winner_3",
                           "Winner_4", "Winner_5", "Winner_6"]
        let loserNames  = ["Lose_1", "Loser_2", "Loser_3"]
        let allNames    = winnerNames + loserNames

        let paths = allNames.compactMap { Bundle.main.path(forResource: $0, ofType: "mp3") }
        guard !paths.isEmpty,
              let chosen = paths.randomElement(),
              let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: chosen)) else { return }
        player.prepareToPlay()
        player.play()
        audioPlayer = player
    }

    // MARK: - Background diagonale

    private func setupBackground() {
        let colorLoser  = UIColor(red: 0.35, green: 0.15, blue: 0.25, alpha: 0.95)
        let colorWinner = UIColor(red: 0.40, green: 0.60, blue: 0.55, alpha: 0.95)

        let colorP1 = winnerIndex == 1 ? colorWinner : colorLoser
        let colorP2 = winnerIndex == 2 ? colorWinner : colorLoser

        let w = view.bounds.width
        let h = view.bounds.height

        // Metà sinistra (P1)
        let pathP1 = UIBezierPath()
        pathP1.move(to: CGPoint(x: 0,        y: 0))
        pathP1.addLine(to: CGPoint(x: w * 0.65, y: 0))
        pathP1.addLine(to: CGPoint(x: w * 0.35, y: h))
        pathP1.addLine(to: CGPoint(x: 0,        y: h))
        pathP1.close()
        let layerP1 = CAShapeLayer()
        layerP1.path      = pathP1.cgPath
        layerP1.fillColor = colorP1.cgColor
        view.layer.addSublayer(layerP1)

        // Metà destra (P2)
        let pathP2 = UIBezierPath()
        pathP2.move(to: CGPoint(x: w * 0.65, y: 0))
        pathP2.addLine(to: CGPoint(x: w,        y: 0))
        pathP2.addLine(to: CGPoint(x: w,        y: h))
        pathP2.addLine(to: CGPoint(x: w * 0.35, y: h))
        pathP2.close()
        let layerP2 = CAShapeLayer()
        layerP2.path      = pathP2.cgPath
        layerP2.fillColor = colorP2.cgColor
        view.layer.addSublayer(layerP2)

        // Angolo della diagonale
        let angle = atan2(h, w * 0.3) - .pi / 2

        // P1 label — sinistra schermo
        let lbl1 = UILabel()
        lbl1.text      = winnerIndex == 1 ? "Winner" : "Loser"
        lbl1.font      = UIFont(name: "MagicSchoolOne", size: 100) ?? .systemFont(ofSize: 80, weight: .bold)
        lbl1.textColor = winnerIndex == 1 ? .white : UIColor(red: 0.3, green: 0.4, blue: 0.8, alpha: 1)
        lbl1.sizeToFit()
        lbl1.center    = CGPoint(x: w * 0.25, y: h / 2)
        lbl1.transform = CGAffineTransform(rotationAngle: angle)
        view.addSubview(lbl1)

        // P2 label — destra schermo
        let lbl2 = UILabel()
        lbl2.text      = winnerIndex == 2 ? "Winner" : "Loser"
        lbl2.font      = UIFont(name: "MagicSchoolOne", size: 100) ?? .systemFont(ofSize: 80, weight: .bold)
        lbl2.textColor = winnerIndex == 2 ? .white : UIColor(red: 0.3, green: 0.4, blue: 0.8, alpha: 1)
        lbl2.sizeToFit()
        lbl2.center    = CGPoint(x: w * 0.75, y: h / 2)
        lbl2.transform = CGAffineTransform(rotationAngle: angle)
        view.addSubview(lbl2)
    }

    // MARK: - Bottoni

    private func setupButtons() {
        let stack = UIStackView()
        stack.axis         = .horizontal
        stack.spacing      = 24
        stack.alignment    = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40)
        ])

        stack.addArrangedSubview(makeButton(title: "🏠 Home",        action: #selector(homeTapped)))
        stack.addArrangedSubview(makeButton(title: "⚔️ Fight Again", action: #selector(restartTapped)))

        if replayPreview != nil {
            stack.addArrangedSubview(makeButton(title: "▶️ Rivedi", action: #selector(replayTapped)))
        }
    }

    private func makeButton(title: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font     = .systemFont(ofSize: 22, weight: .bold)
        btn.backgroundColor      = UIColor.white.withAlphaComponent(0.2)
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius   = 16
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 28, bottom: 16, trailing: 28)
        btn.configuration = config
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    // MARK: - Actions

    @objc private func homeTapped() {
        if RPScreenRecorder.shared().isRecording {
            RPScreenRecorder.shared().discardRecording {}
        }
        dismiss(animated: false) { [weak self] in
            self?.delegate?.gameOverDidTapHome()
        }
    }

    @objc private func restartTapped() {
        dismiss(animated: false) { [weak self] in
            self?.delegate?.gameOverDidTapRestart()
        }
    }

    @objc private func replayTapped() {
        guard let preview = replayPreview else { return }
        preview.modalPresentationStyle = .fullScreen
        present(preview, animated: true)
    }
}

// MARK: - RPPreviewViewControllerDelegate

extension GameOverViewController: RPPreviewViewControllerDelegate {
    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        previewController.dismiss(animated: true)
    }
}
