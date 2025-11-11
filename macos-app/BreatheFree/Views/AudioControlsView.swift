//
//  AudioControlsView.swift
//  BreatheFree
//
//  Audio controls with mute button and volume slider modal
//

import SwiftUI

struct AudioControlsView: View {
    @ObservedObject var audioManager: AudioManager
    @State private var showVolumeModal = false

    var body: some View {
        HStack(spacing: 12) {
            // Mute button
            Button(action: {
                audioManager.toggleMute()
            }) {
                Image(systemName: audioManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())

            // Volume button
            Button(action: {
                showVolumeModal = true
            }) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .sheet(isPresented: $showVolumeModal) {
            VolumeModalView(audioManager: audioManager, isPresented: $showVolumeModal)
        }
    }
}

struct VolumeModalView: View {
    @ObservedObject var audioManager: AudioManager
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Modal content
            VStack(spacing: 24) {
                HStack {
                    Text("Volume")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(red: 0.122, green: 0.161, blue: 0.216))

                    Spacer()

                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(red: 0.42, green: 0.447, blue: 0.502))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 0.024, green: 0.714, blue: 0.831))

                        Slider(value: Binding(
                            get: { Double(audioManager.volume) },
                            set: { newValue in
                                audioManager.setVolume(Float(newValue))
                                if audioManager.isMuted && newValue > 0 {
                                    audioManager.setMuted(false)
                                }
                            }
                        ), in: 0...1)
                        .accentColor(Color(red: 0.024, green: 0.714, blue: 0.831))

                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 0.024, green: 0.714, blue: 0.831))
                    }

                    Text("\(Int(audioManager.volume * 100))%")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.122, green: 0.161, blue: 0.216))
                }
            }
            .padding(24)
            .frame(width: 400)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
        }
    }
}

#Preview {
    ZStack {
        Color(red: 0.024, green: 0.714, blue: 0.831)
            .ignoresSafeArea()

        AudioControlsView(audioManager: AudioManager())
    }
    .frame(width: 600, height: 400)
}
