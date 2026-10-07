//
//  ContentView.swift
//  BreatheFree
//
//  The window: the sky behind, and home, session or finish in front.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = SessionModel()

    var body: some View {
        // The sky follows the time of day; looking every 20 seconds is plenty.
        TimelineView(.periodic(from: .now, by: 20)) { timeline in
            let look = DaySky.look(at: timeline.date)
            ZStack {
                SkyView(model: model, sky: look.sky)
                switch model.screen {
                case .home:
                    HomeView(model: model)
                        .transition(.opacity)
                case .session:
                    if let session = model.session {
                        SessionView(model: model, session: session)
                            .transition(.opacity)
                    }
                case .done:
                    DoneView(model: model)
                        .transition(.opacity)
                }
            }
            // Text and controls turn light when the sky turns dark, easing across.
            .environment(\.ink, Ink.matching(look))
            .animation(.easeInOut(duration: 1.2), value: look.dark)
            .animation(.easeInOut(duration: 0.6), value: model.screen)
        }
        .frame(minWidth: 640, minHeight: 600)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 900, height: 720)
    }
}
#endif
