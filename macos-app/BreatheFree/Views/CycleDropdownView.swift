//
//  CycleDropdownView.swift
//  BreatheFree
//
//  Cycle selection dropdown component
//

import SwiftUI

struct CycleDropdownView: View {
    @Binding var selectedCycles: Int
    @State private var isExpanded = false

    let cycleOptions = [2, 6, 10, 20, 36, 50]

    var body: some View {
        // Main button
        Button(action: {
            isExpanded.toggle()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Number of cycles")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.42, green: 0.447, blue: 0.502))

                    Text("\(selectedCycles) cycles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.122, green: 0.161, blue: 0.216))
                }

                Spacer()

                Text(formatDuration(cycles: selectedCycles))
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.42, green: 0.447, blue: 0.502))

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.024, green: 0.714, blue: 0.831))
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: $isExpanded, arrowEdge: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(cycleOptions, id: \.self) { option in
                        Button(action: {
                            selectedCycles = option
                            isExpanded = false
                        }) {
                            HStack {
                                Text("\(option) cycles")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(red: 0.122, green: 0.161, blue: 0.216))

                                Spacer()

                                Text(formatDuration(cycles: option))
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(red: 0.42, green: 0.447, blue: 0.502))

                                if option == selectedCycles {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Color(red: 0.024, green: 0.714, blue: 0.831))
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: 280)
                            .background(option == selectedCycles ?
                                       Color(red: 0.941, green: 0.976, blue: 1.0) :
                                       Color.clear)
                        }
                        .buttonStyle(PlainButtonStyle())

                        if option != cycleOptions.last {
                            Divider()
                                .padding(.vertical, 0)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(Color.white)
            }
            .frame(height: 220)
            .frame(maxWidth: 300)
        }
        .frame(maxWidth: 512)
    }

    private func formatDuration(cycles: Int) -> String {
        let seconds = cycles * 16 // Each cycle is 16 seconds (4+4+4+4)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

#if DEBUG
struct CycleDropdownView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            CycleDropdownView(selectedCycles: .constant(10))
        }
        .padding()
        .frame(width: 600, height: 400)
        .background(Color(red: 0.941, green: 0.976, blue: 1.0))
    }
}
#endif
