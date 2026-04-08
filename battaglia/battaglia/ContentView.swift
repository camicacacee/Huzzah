import SwiftUI
import AVFoundation

// MARK: - Splash Audio

private class SplashAudio {
    static let shared = SplashAudio()
    var player: AVAudioPlayer?

    func play() {
            // 1. Se il player esiste già (sta suonando), non fare nulla e non stampare errori falsi.
            guard player == nil else { return }

            // 2. Cerca il file. SE non lo trova, ALLORA stampa il vero errore.
            guard let path = Bundle.main.path(forResource: "Arcane_Arena_Clash", ofType: "mp3"),
                  let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else {
                print("⚠️ ERRORE REALE: Arcane_Arena_Clash.mp3 non trovato nel bundle")
                return
            }
            
            p.numberOfLoops = -1  // loop infinito
            p.volume = 0.7
            p.prepareToPlay()
            p.play()
            player = p
        }

    func stop() {
        player?.stop()
        player = nil
    }
}

// MARK: - Root

struct ContentView: View {
    @State private var screen: Screen = .splash

    enum Screen { case splash, home, game, fairy }

    var body: some View {
        switch screen {
        case .splash:
            SplashView(onTap: { screen = .home })
        case .home:
            Group {
                HomeView(onStart: { selected in
                    screen = selected == "Fairy" ? .fairy : .game
                })
            }
            .onAppear { SplashAudio.shared.play() }
        case .game:
            TrackingView(onGoHome: { screen = .home })
                .ignoresSafeArea()
        case .fairy:
            FairyView(onGoHome: { screen = .home })
                .ignoresSafeArea()
        }
    }
}

// MARK: - SplashView

struct SplashView: View {
    let onTap: () -> Void
    @State private var showTapLabel = false
    @State private var titleScale: CGFloat = 0.7
    @State private var titleOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            Image("background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 40) {
                Text("Huzzah")
                    .font(.custom("MagicSchoolOne", size: 110))
                    .foregroundColor(.yellow)
                    .shadow(color: .black, radius: 12, x: 0, y: 6)
                    .scaleEffect(titleScale)
                    .opacity(titleOpacity)

                if showTapLabel {
                    Text("Tap to begin")
                        .font(.custom("MagicSchoolOne", size: 28))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(color: .black, radius: 6)
                        .modifier(PulseModifier())
                }
            }
        }
        .onTapGesture { if showTapLabel { onTap() } }
        .onAppear {
            SplashAudio.shared.play()
            // Titolo entra con scala
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                titleScale   = 1.0
                titleOpacity = 1.0
            }
            // "Tap to begin" appare dopo 2 secondi
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeIn(duration: 0.5)) { showTapLabel = true }
            }
        }
    }
}

// Effetto pulsante per "Tap to begin"
struct PulseModifier: ViewModifier {
    @State private var opacity: CGFloat = 1.0
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    opacity = 0.3
                }
            }
    }
}

// MARK: - HomeView

struct HomeView: View {
    let onStart: (String) -> Void
    @State private var selected: String? = nil

    private let cards: [(name: String, image: String, rotation: Double, offset: CGFloat)] = [
        (name: "Knight", image: "knight", rotation: -12, offset: 20),
        (name: "Wizard", image: "wizard", rotation:   0, offset:  0),
        (name: "Fairy",  image: "fairy",  rotation:  12, offset: 20)
    ]

    var body: some View {
        ZStack {
            Image("background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 48) {
                Text("Choose Your card")
                    .font(.custom("MagicSchoolOne", size: 36))
                    .foregroundColor(.yellow)
                    .shadow(color: .black, radius: 6)
                    .padding(.top, 40)

                HStack(spacing: 32) {
                    ForEach(cards, id: \.name) { card in
                        let isSelected = selected == card.name
                        let isEnabled  = card.name == "Knight" || card.name == "Fairy"

                        Image(card.image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 190, height: 250)
                            .opacity(isSelected ? 1.0 : (isEnabled ? 0.55 : 0.35))
                            .rotationEffect(.degrees(isSelected ? 0 : card.rotation))
                            .offset(y: isSelected ? -24 : card.offset)
                            .shadow(
                                color: isSelected ? .yellow.opacity(0.7) : .black.opacity(0.4),
                                radius: isSelected ? 20 : 6
                            )
                            .scaleEffect(isSelected ? 1.08 : 1.0)
                            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: selected)
                            .onTapGesture { if isEnabled { selected = card.name } }
                            .zIndex(isSelected ? 1 : 0)
                    }
                }

                Button(action: {
                    if let sel = selected {
                        SplashAudio.shared.stop()
                        onStart(sel)
                    }
                }) {
                    Text("Start")
                        .font(.custom("MagicSchoolOne", size: 36))
                        .foregroundColor(.white)
                        .frame(width: 220, height: 60)
                        .background(selected != nil ? Color.blue.opacity(0.85) : Color.gray.opacity(0.4))
                        .cornerRadius(30)
                        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                }
                .disabled(selected == nil)
                .animation(.easeInOut(duration: 0.2), value: selected)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - FairyView wrapper

struct FairyView: UIViewControllerRepresentable {
    let onGoHome: () -> Void

    func makeUIViewController(context: Context) -> FairyTrackingViewController {
        let vc = FairyTrackingViewController()
        vc.onGoHome = onGoHome
        return vc
    }
    func updateUIViewController(_ uiViewController: FairyTrackingViewController, context: Context) {}
}

struct TrackingView: UIViewControllerRepresentable {
    let onGoHome: () -> Void

    func makeUIViewController(context: Context) -> TrackingViewController {
        let vc = TrackingViewController()
        vc.onGoHome = onGoHome
        return vc
    }
    func updateUIViewController(_ uiViewController: TrackingViewController, context: Context) {}
}
