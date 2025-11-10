//
//  AudioManager.swift
//  BreatheFree
//
//  Audio playback management for breathing exercises
//

import Foundation
import AVFoundation

class AudioManager: ObservableObject {
    @Published var volume: Float = 0.7
    @Published var isMuted: Bool = false

    private var audioPlayer: AVAudioPlayer?
    private var audioSession = AVAudioSession.sharedInstance()

    init() {
        setupAudio()
    }

    private func setupAudio() {
        guard let url = Bundle.main.url(forResource: "breath-chord-loop-icetinespad", withExtension: "mp3") else {
            print("Audio file not found")
            return
        }

        do {
            // Configure audio session
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            // Create audio player
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = volume
            audioPlayer?.numberOfLoops = 0 // Will manually control looping

        } catch {
            print("Error setting up audio: \(error.localizedDescription)")
        }
    }

    func playAudio() {
        guard let player = audioPlayer else { return }

        // Restart from beginning for synchronized playback
        player.currentTime = 0
        player.volume = isMuted ? 0 : volume

        // Adjust playback rate to match 16-second breathing cycle
        if let audioDuration = audioPlayer?.duration {
            let targetDuration: Double = 16.0 // 4+4+4+4 seconds
            let rate = Float(audioDuration / targetDuration)
            player.enableRate = true
            player.rate = rate
        }

        player.play()
    }

    func stopAudio() {
        audioPlayer?.stop()
    }

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        if !isMuted {
            audioPlayer?.volume = newVolume
        }
    }

    func toggleMute() {
        isMuted.toggle()
        audioPlayer?.volume = isMuted ? 0 : volume
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        audioPlayer?.volume = muted ? 0 : volume
    }
}
