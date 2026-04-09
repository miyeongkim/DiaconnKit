import DiaconnKit
import LoopKit
import LoopKitUI
import SwiftUI

struct DiaconnSettingsView: View {
    @ObservedObject var viewModel: DiaconnSettingsViewModel

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        List {
            Section(header: Text("펌프 상태")) {
                HStack {
                    Text("연결 상태")
                    Spacer()
                    Text(viewModel.isConnected ? "연결됨" : "연결 안됨")
                        .foregroundColor(viewModel.isConnected ? .green : .red)
                }

                HStack {
                    Text("리저버")
                    Spacer()
                    Text(String(format: "%.1fU", viewModel.reservoirLevel))
                }

                HStack {
                    Text("배터리")
                    Spacer()
                    Text(String(format: "%.0f%%", viewModel.batteryRemaining * 100))
                }

                if let serial = viewModel.serialNumber {
                    HStack {
                        Text("시리얼 번호")
                        Spacer()
                        Text(serial)
                            .foregroundColor(.secondary)
                    }
                }

                if let firmware = viewModel.firmwareVersion {
                    HStack {
                        Text("펌웨어")
                        Spacer()
                        Text(firmware)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text(LocalizedString("Pump Time", comment: "The title of the pump time row"))
                    Spacer()
                    if let pumpTime = viewModel.pumpTime {
                        Text(Self.timeFormatter.string(from: pumpTime))
                            .foregroundColor(.secondary)
                    } else {
                        Text(LocalizedString("Unknown", comment: "Unknown pump time"))
                            .foregroundColor(.secondary)
                    }
                }

                Button(action: {
                    viewModel.refreshStatus()
                }) {
                    HStack {
                        if viewModel.isRefreshing {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(viewModel.isRefreshing ? "조회 중..." : "상태 새로고침")
                    }
                }
                .disabled(viewModel.isRefreshing)

                if let errorMessage = viewModel.refreshErrorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }

            if viewModel.basalDeliveryState != nil {
                Section(header: Text(LocalizedString("Activity", comment: "Header for activity section"))) {
                    HStack {
                        Button {
                            viewModel.suspendResumeButtonPressed()
                        } label: {
                            HStack {
                                Image(systemName: viewModel.isSuspended ? "play.circle.fill" : "pause.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(viewModel.isSuspended ? .green : .orange)
                                Text(viewModel.suspendResumeButtonLabel)
                                    .foregroundColor(viewModel.isSuspended ? .green : .orange)
                            }
                        }
                        .disabled(viewModel.isSuspending)
                        if viewModel.isSuspending {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
            }

            Section(header: Text("인슐린 전달")) {
                HStack {
                    Text("기저 상태")
                    Spacer()
                    Text(viewModel.basalStateDescription)
                }

                HStack {
                    Text("현재 기저량")
                    Spacer()
                    Text(String(format: "%.2f U/h", viewModel.currentBasalRate))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("오늘 주입 총량")
                    Spacer()
                    Text(String(format: "%.2f U", viewModel.todayTotalAmount))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("최대 기저")
                    Spacer()
                    Text(String(format: "%.2f U/h", viewModel.maxBasalPerHour))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("최대 볼러스")
                    Spacer()
                    Text(String(format: "%.1f U", viewModel.maxBolus))
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("디버그")) {
                HStack {
                    Text("펌프 로그")
                    Spacer()
                    Text("wrap: \(viewModel.pumpWrapCount) / #\(viewModel.pumpLogNum)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("저장된 로그")
                    Spacer()
                    Text("wrap: \(viewModel.storedWrapCount) / #\(viewModel.storedLogNum)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("저장 로그 번호 변경")
                    Spacer()
                    TextField("logNum", text: $viewModel.editStoredLogNum)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Button("적용") {
                        viewModel.applyStoredLogNum()
                    }
                }

                HStack {
                    Text("저장 랩 번호 변경")
                    Spacer()
                    TextField("wrap", text: $viewModel.editStoredWrapCount)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Button("적용") {
                        viewModel.applyStoredWrapCount()
                    }
                }
            }

            Section(header: Text(LocalizedString("Configuration", comment: "Configuration section header"))) {
                NavigationLink(destination: DiaconnBolusSpeedView(
                    currentSpeed: viewModel.bolusSpeed,
                    didChange: viewModel.setBolusSpeed
                )) {
                    HStack {
                        Text(LocalizedString("Bolus Speed", comment: "Bolus speed settings label"))
                        Spacer()
                        Text(LocalizedString("Speed \(viewModel.bolusSpeed)", comment: "Current bolus speed value"))
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink(destination: DiaconnSoundSettingView(
                    currentType: viewModel.beepAndAlarm,
                    currentIntensity: viewModel.alarmIntensity,
                    didChange: { type, intensity in viewModel.setSoundSetting(type: type, intensity: intensity) }
                )) {
                    HStack {
                        Text(LocalizedString("Alert Type", comment: "Alert type settings label"))
                        Spacer()
                        Text(DiaconnAlarmType(rawValue: viewModel.beepAndAlarm)?.title ?? "")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("인슐린 종류")) {
                NavigationLink(destination: InsulinTypeSetting(
                    initialValue: viewModel.insulinType,
                    supportedInsulinTypes: viewModel.allowedInsulinTypes,
                    allowUnsetInsulinType: false,
                    didChange: viewModel.didChangeInsulinType
                ).navigationTitle(LocalizedString("Insulin Type", comment: "Title for insulin type settings"))) {
                    HStack {
                        Text(LocalizedString("Insulin Type", comment: "Insulin type settings label"))
                        Spacer()
                        Text(viewModel.insulinType?.brandName ?? LocalizedString("Unknown", comment: "Unknown insulin type"))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Button(action: {
                    viewModel.deletePump()
                }) {
                    Text("펌프 삭제")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Diaconn G8")
    }
}
