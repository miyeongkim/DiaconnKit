import SwiftUI

struct DiaconnBolusSpeedView: View {
    let currentSpeed: UInt8
    let didChange: (UInt8) -> Void

    @State private var selectedSpeed: UInt8

    init(currentSpeed: UInt8, didChange: @escaping (UInt8) -> Void) {
        self.currentSpeed = currentSpeed
        self.didChange = didChange
        _selectedSpeed = State(initialValue: currentSpeed)
    }

    var body: some View {
        List {
            ForEach(1 ... 8, id: \.self) { speed in
                let s = UInt8(speed)
                Button {
                    selectedSpeed = s
                    didChange(s)
                } label: {
                    HStack {
                        Text(LocalizedString("\(speed) U/min", comment: "Bolus speed in units per minute"))
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedSpeed == s {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle(LocalizedString("Bolus Speed", comment: "Bolus speed navigation title"))
    }
}
