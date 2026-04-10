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

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        List {
            // MARK: - Header: Pump Image + Status Dashboard

            Section {
                HStack {
                    Spacer()
                    Image(
                        uiImage: UIImage(
                            named: "diacong8",
                            in: Bundle(for: DiaconnSettingsViewModel.self),
                            compatibleWith: nil
                        ) ?? UIImage()
                    )
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal)
                    .frame(height: 150)
                    Spacer()
                }

                HStack(alignment: .top) {
                    deliveryStatus
                    Spacer()
                    reservoirStatus
                }
                .padding(.bottom, 5)

                if let alert = viewModel.activeAlert {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.contentTitle)
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Text(alert.contentBody)
                                .font(.footnote)
                        }
                    }
                    .padding(.vertical, 4)

                    Button(action: {
                        viewModel.acknowledgeAlert()
                    }) {
                        Text(LocalizedString("Acknowledge", comment: "Button to acknowledge alert"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }

            // MARK: - Pump Control Actions

            Section {
                if viewModel.basalDeliveryState != nil {
                    Button(action: {
                        viewModel.suspendResumeButtonPressed()
                    }) {
                        HStack {
                            Image(
                                systemName: viewModel.isSuspended
                                    ? "play.circle.fill" : "pause.circle.fill"
                            )
                            .font(.system(size: 22))
                            .foregroundColor(viewModel.isSuspended ? .green : .orange)
                            Text(viewModel.suspendResumeButtonLabel)
                                .foregroundColor(viewModel.isSuspended ? .green : .orange)
                            if viewModel.isSuspending {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.isSuspending)
                }

                Button(action: {
                    viewModel.refreshStatus()
                }) {
                    HStack {
                        Text(
                            LocalizedString(
                                "Sync Pump Data", comment: "Button to sync pump data"
                            )
                        )
                        Spacer()
                        if viewModel.isRefreshing {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isRefreshing)

                HStack {
                    Text(LocalizedString("Status", comment: "Connection status label"))
                        .foregroundColor(.primary)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(viewModel.isConnected ? "Connected" : "Disconnected")
                            .foregroundColor(.secondary)
                        Circle()
                            .fill(viewModel.isConnected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                    }
                }

                if let errorMessage = viewModel.refreshErrorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }

                HStack {
                    Text(
                        LocalizedString(
                            "Last Sync", comment: "Text for last sync time"
                        )
                    )
                    .foregroundColor(.primary)
                    Spacer()
                    Text(
                        viewModel.pumpTime.map { Self.dateTimeFormatter.string(from: $0) }
                            ?? LocalizedString("Unknown", comment: "Unknown time")
                    )
                    .foregroundColor(.secondary)
                }

                // Component age tracking
                HStack {
                    Text(
                        LocalizedString(
                            "Cannula Age", comment: "Text for cannula age"
                        )
                    )
                    .foregroundColor(.primary)
                    Spacer()
                    Text(viewModel.cannulaDateString)
                        .foregroundColor(.secondary)
                }
                .onLongPressGesture { viewModel.markCannulaChanged() }

                HStack {
                    Text(
                        LocalizedString(
                            "Reservoir Age", comment: "Text for reservoir age"
                        )
                    )
                    .foregroundColor(.primary)
                    Spacer()
                    Text(viewModel.reservoirDateString)
                        .foregroundColor(.secondary)
                }
                .onLongPressGesture { viewModel.markReservoirChanged() }
            }

            // MARK: - Configuration

            Section(
                header: Text(
                    LocalizedString(
                        "Configuration", comment: "Configuration section header"
                    )
                )
            ) {
                NavigationLink(
                    destination: InsulinTypeSetting(
                        initialValue: viewModel.insulinType,
                        supportedInsulinTypes: viewModel.allowedInsulinTypes,
                        allowUnsetInsulinType: false,
                        didChange: viewModel.didChangeInsulinType
                    ).navigationTitle(
                        LocalizedString(
                            "Insulin Type",
                            comment: "Title for insulin type settings"
                        )
                    )
                ) {
                    HStack {
                        Text(
                            LocalizedString(
                                "Insulin Type",
                                comment: "Insulin type settings label"
                            )
                        )
                        Spacer()
                        Text(
                            viewModel.insulinType?.brandName
                                ?? LocalizedString(
                                    "Unknown", comment: "Unknown insulin type"
                                )
                        )
                        .foregroundColor(.secondary)
                    }
                }

                NavigationLink(
                    destination: DiaconnBolusSpeedView(
                        currentSpeed: viewModel.bolusSpeed,
                        didChange: viewModel.setBolusSpeed
                    )
                ) {
                    HStack {
                        Text(
                            LocalizedString(
                                "Bolus Speed",
                                comment: "Bolus speed settings label"
                            )
                        )
                        Spacer()
                        Text(
                            LocalizedString(
                                "Speed \(viewModel.bolusSpeed)",
                                comment: "Current bolus speed value"
                            )
                        )
                        .foregroundColor(.secondary)
                    }
                }

                NavigationLink(
                    destination: DiaconnSoundSettingView(
                        currentType: viewModel.beepAndAlarm,
                        currentIntensity: viewModel.alarmIntensity,
                        didChange: { type, intensity in
                            viewModel.setSoundSetting(
                                type: type, intensity: intensity
                            )
                        }
                    )
                ) {
                    HStack {
                        Text(
                            LocalizedString(
                                "Pump Sound",
                                comment: "Pump sound settings label"
                            )
                        )
                        Spacer()
                        Text(
                            DiaconnAlarmType(rawValue: viewModel.beepAndAlarm)?
                                .title ?? ""
                        )
                        .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: - Pump Information

            Section(
                header: Text(
                    LocalizedString(
                        "Pump Information",
                        comment: "Pump information section header"
                    )
                )
            ) {
                if let serial = viewModel.serialNumber {
                    HStack {
                        Text(
                            LocalizedString(
                                "Serial Number",
                                comment: "Serial number label"
                            )
                        )
                        .foregroundColor(.primary)
                        Spacer()
                        Text(serial)
                            .foregroundColor(.secondary)
                    }
                }

                if let firmware = viewModel.firmwareVersion {
                    HStack {
                        Text(
                            LocalizedString(
                                "Firmware", comment: "Firmware version label"
                            )
                        )
                        .foregroundColor(.primary)
                        Spacer()
                        Text(firmware)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text(
                        LocalizedString(
                            "Battery", comment: "Battery level label"
                        )
                    )
                    .foregroundColor(.primary)
                    Spacer()
                    Text(
                        String(
                            format: "%.0f%%",
                            viewModel.batteryRemaining * 100
                        )
                    )
                    .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Max Basal")
                        Spacer()
                        Text(
                            String(
                                format: "%.2f U/h",
                                viewModel.maxBasalPerHour
                            )
                        )
                        .foregroundColor(.secondary)
                    }
                    Text(
                        "Maximum basal insulin amount that can be delivered per hour."
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Max Bolus")
                        Spacer()
                        Text(
                            String(format: "%.1f U", viewModel.maxBolus)
                        )
                        .foregroundColor(.secondary)
                    }
                    Text(
                        "Maximum insulin amount that can be delivered per single bolus."
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
            }

            // MARK: - Pump Time

            Section(
                header: Text(
                    LocalizedString(
                        "Pump Time", comment: "Pump time section header"
                    )
                )
            ) {
                HStack {
                    Text(
                        LocalizedString(
                            "Pump Time", comment: "Pump time label"
                        )
                    )
                    .foregroundColor(.primary)
                    Spacer()
                    if let pumpTime = viewModel.pumpTime {
                        Text(Self.dateTimeFormatter.string(from: pumpTime))
                            .foregroundColor(.secondary)
                    } else {
                        Text(
                            LocalizedString(
                                "Unknown", comment: "Unknown pump time"
                            )
                        )
                        .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text(
                        LocalizedString(
                            "Current Basal Rate",
                            comment: "Current basal rate label"
                        )
                    )
                    .foregroundColor(.primary)
                    Spacer()
                    Text(
                        String(
                            format: "%.2f U/h",
                            viewModel.currentBasalRate
                        )
                    )
                    .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(
                            LocalizedString(
                                "Today Total Delivery",
                                comment: "Today total delivery label"
                            )
                        )
                        .foregroundColor(.primary)
                        Spacer()
                        Text(
                            String(
                                format: "%.2f U",
                                viewModel.todayTotalAmount
                            )
                        )
                        .foregroundColor(.secondary)
                    }
                    Text("Sum of basal, meal bolus, and normal bolus delivered today.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - Debug

            Section(header: Text("Debug")) {
                HStack {
                    Text("Pump Log")
                    Spacer()
                    Text(
                        "wrap: \(viewModel.pumpWrapCount) / #\(viewModel.pumpLogNum)"
                    )
                    .foregroundColor(.secondary)
                }

                HStack {
                    Text("Stored Log")
                    Spacer()
                    Text(
                        "wrap: \(viewModel.storedWrapCount) / #\(viewModel.storedLogNum)"
                    )
                    .foregroundColor(.secondary)
                }

                HStack {
                    Text("Change Stored Log Number")
                    Spacer()
                    TextField("logNum", text: $viewModel.editStoredLogNum)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Button("Apply") {
                        viewModel.applyStoredLogNum()
                    }
                }

                HStack {
                    Text("Change Stored Wrap Number")
                    Spacer()
                    TextField(
                        "wrap", text: $viewModel.editStoredWrapCount
                    )
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    Button("Apply") {
                        viewModel.applyStoredWrapCount()
                    }
                }

                Button(
                    LocalizedString(
                        "Test Communication",
                        comment: "Button to test pump communication"
                    )
                ) {
                    viewModel.testCommunication()
                }
            }

            // MARK: - Delete Pump

            Section {
                Button(action: {
                    viewModel.deletePump()
                }) {
                    Text(
                        LocalizedString(
                            "Delete Pump",
                            comment: "Label for pump deletion button"
                        )
                    )
                    .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Diaconn G8")
    }

    // MARK: - Delivery Status Component

    private var deliveryStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(
                LocalizedString(
                    "Insulin Delivery",
                    comment: "Header for insulin delivery status"
                )
            )
            .foregroundColor(Color(UIColor.secondaryLabel))

            if viewModel.basalDeliveryState == nil {
                HStack(alignment: .center) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(.secondary)
                    Text(
                        LocalizedString(
                            "Unknown",
                            comment: "Text shown when delivery status unknown"
                        )
                    )
                    .fontWeight(.bold)
                    .fixedSize()
                    .foregroundColor(.secondary)
                }
            } else if viewModel.isSuspended {
                HStack(alignment: .center) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(.orange)
                    Text(
                        LocalizedString(
                            "Insulin\nSuspended",
                            comment: "Text shown when insulin suspended"
                        )
                    )
                    .fontWeight(.bold)
                    .fixedSize()
                }
            } else if case let .tempBasal(dose) = viewModel.basalDeliveryState {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(String(format: "T:%.1f", dose.unitsPerHour))
                        .font(.system(size: 28))
                        .fontWeight(.heavy)
                        .fixedSize()
                        .foregroundColor(.blue)
                    Text(
                        LocalizedString(
                            "U/hr",
                            comment: "Units for showing temp basal rate"
                        )
                    )
                    .foregroundColor(.blue)
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(String(format: "%.2f", viewModel.currentBasalRate))
                        .font(.system(size: 28))
                        .fontWeight(.heavy)
                        .fixedSize()
                    Text(
                        LocalizedString(
                            "U/hr",
                            comment: "Units for showing basal rate"
                        )
                    )
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Reservoir Status Component

    private var reservoirStatus: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(
                LocalizedString(
                    "Insulin Remaining",
                    comment: "Header for insulin remaining"
                )
            )
            .foregroundColor(Color(UIColor.secondaryLabel))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(String(format: "%.0f", viewModel.reservoirLevel))
                    .font(.system(size: 28))
                    .fontWeight(.heavy)
                    .fixedSize()
                Text(
                    LocalizedString(
                        "U", comment: "Insulin unit"
                    )
                )
                .foregroundColor(.secondary)
            }
        }
    }
}
