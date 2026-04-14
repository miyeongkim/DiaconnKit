import SwiftUI

enum DiaconnAlarmType: UInt8, CaseIterable {
    case sound = 0
    case vibration = 1
    case silent = 2

    var title: String {
        switch self {
        case .sound: return LocalizedString("Sound", comment: "Sound type: sound")
        case .silent: return LocalizedString("Silent", comment: "Sound type: silent")
        case .vibration: return LocalizedString("Vibration", comment: "Sound type: vibration")
        }
    }

    var systemImage: String {
        switch self {
        case .sound: return "speaker.wave.2.fill"
        case .silent: return "speaker.slash.fill"
        case .vibration: return "iphone.radiowaves.left.and.right"
        }
    }

    var hasIntensity: Bool {
        self != .silent
    }
}

enum DiaconnAlarmIntensity: UInt8, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2

    var title: String {
        switch self {
        case .low: return LocalizedString("Low", comment: "Alarm intensity: low")
        case .medium: return LocalizedString("Medium", comment: "Alarm intensity: medium")
        case .high: return LocalizedString("High", comment: "Alarm intensity: high")
        }
    }
}

struct DiaconnSoundSettingView: View {
    let currentType: UInt8
    let currentIntensity: UInt8
    let didChange: (UInt8, UInt8) -> Void

    @State private var selectedType: UInt8
    @State private var selectedIntensity: UInt8

    init(currentType: UInt8, currentIntensity: UInt8, didChange: @escaping (UInt8, UInt8) -> Void) {
        self.currentType = currentType
        self.currentIntensity = currentIntensity
        self.didChange = didChange
        _selectedType = State(initialValue: currentType)
        _selectedIntensity = State(initialValue: currentIntensity)
    }

    var body: some View {
        List {
            Section(header: Text(LocalizedString("Pump Sound", comment: "Sound type section header"))) {
                ForEach(DiaconnAlarmType.allCases, id: \.rawValue) { type in
                    Button {
                        selectedType = type.rawValue
                        didChange(selectedType, selectedIntensity)
                    } label: {
                        HStack {
                            Image(systemName: type.systemImage)
                                .frame(width: 28)
                                .foregroundColor(.accentColor)
                            Text(type.title)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedType == type.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            if DiaconnAlarmType(rawValue: selectedType)?.hasIntensity == true {
                Section(header: Text(LocalizedString("Intensity", comment: "Alarm intensity section header"))) {
                    ForEach(DiaconnAlarmIntensity.allCases, id: \.rawValue) { intensity in
                        Button {
                            selectedIntensity = intensity.rawValue
                            didChange(selectedType, selectedIntensity)
                        } label: {
                            HStack {
                                Text(intensity.title)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedIntensity == intensity.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(LocalizedString("Pump Sound", comment: "Sound type navigation title"))
    }
}
