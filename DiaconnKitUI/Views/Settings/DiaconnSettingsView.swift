import LoopKit
import LoopKitUI
import SwiftUI

struct DiaconnSettingsView: View {
    @ObservedObject var viewModel: DiaconnSettingsViewModel
    @State private var showDebug = false
    @State private var isSharePresented = false

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
                    batteryStatus
                    Spacer()
                    reservoirStatus
                }
                .padding(.bottom, 5)

                if viewModel.showPumpTimeSyncWarning {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            LocalizedString(
                                "Time Change Detected",
                                comment: "Title for time change detected notice"
                            )
                        )
                        .font(Font.subheadline.weight(.bold))
                        Text(
                            LocalizedString(
                                "The time on your pump is different from the current time. Scroll down to Pump Time section to review and sync.",
                                comment: "Description for time change detected notice"
                            )
                        )
                        .font(Font.footnote.weight(.semibold))
                    }
                    .padding(.vertical, 8)
                }

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

            // MARK: - Actions

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

                if viewModel.isTempBasal {
                    Button(action: {
                        viewModel.stopTempBasal()
                    }) {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.red)
                            Text(
                                LocalizedString(
                                    "Stop Temp Basal",
                                    comment: "Button to stop temp basal"
                                )
                            )
                            .foregroundColor(.red)
                            if viewModel.isStoppingTempBasal {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.isStoppingTempBasal)
                }

                Button(action: {
                    viewModel.refreshStatus()
                }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
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

                if let errorMessage = viewModel.refreshErrorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }

            // MARK: - Status

            Section(
                header: Text(
                    LocalizedString(
                        "Status", comment: "Status section header"
                    )
                )
            ) {
                HStack {
                    Text(LocalizedString("Connection", comment: "Connection status label"))
                        .foregroundColor(.primary)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(
                            viewModel
                                .isConnected ? LocalizedString("Connected", comment: "") :
                                LocalizedString("Disconnected", comment: "")
                        )
                        .foregroundColor(.secondary)
                        Circle()
                            .fill(viewModel.isConnected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                    }
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
                    if viewModel.showPumpTimeSyncWarning {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                    }
                    if let pumpTime = viewModel.pumpTime {
                        Text(Self.dateTimeFormatter.string(from: pumpTime))
                            .foregroundColor(
                                viewModel.showPumpTimeSyncWarning ? .orange : .secondary
                            )
                    } else {
                        Text(
                            LocalizedString(
                                "Unknown", comment: "Unknown pump time"
                            )
                        )
                        .foregroundColor(.secondary)
                    }
                }

                Button(action: {
                    viewModel.showingTimeSyncConfirmation = true
                }) {
                    Text(
                        LocalizedString(
                            "Manually Sync Pump Time",
                            comment: "Button to manually sync pump time"
                        )
                    )
                    .foregroundColor(.accentColor)
                }
                .disabled(viewModel.isSyncingTime)
                .actionSheet(isPresented: $viewModel.showingTimeSyncConfirmation) {
                    ActionSheet(
                        title: Text(
                            LocalizedString(
                                "Time Change Detected",
                                comment: "Title for pump sync time action sheet"
                            )
                        ),
                        message: Text(
                            LocalizedString(
                                "Do you want to update the time on your pump to the current time?",
                                comment: "Message for pump sync time action sheet"
                            )
                        ),
                        buttons: [
                            .default(
                                Text(
                                    LocalizedString(
                                        "Yes, Sync to Current Time",
                                        comment: "Button to confirm pump time sync"
                                    )
                                )
                            ) {
                                viewModel.syncPumpTime()
                            },
                            .cancel(
                                Text(
                                    LocalizedString(
                                        "No, Keep Pump As Is",
                                        comment: "Button to cancel pump time sync"
                                    )
                                )
                            )
                        ]
                    )
                }
            }

            // MARK: - Component Age

            Section(
                header: Text(
                    LocalizedString(
                        "Component Age", comment: "Component age section header"
                    )
                )
            ) {
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

                HStack {
                    Text(
                        LocalizedString(
                            "Battery Age", comment: "Text for battery age"
                        )
                    )
                    .foregroundColor(.primary)
                    Spacer()
                    Text(viewModel.batteryDateString)
                        .foregroundColor(.secondary)
                }
                .onLongPressGesture { viewModel.markBatteryChanged() }
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

            // MARK: - Insulin Delivery

            Section(
                header: Text(
                    LocalizedString(
                        "Insulin Delivery",
                        comment: "Insulin delivery section header"
                    )
                )
            ) {
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
                    Text(LocalizedString(
                        "Sum of basal, meal bolus, and normal bolus delivered today.",
                        comment: "Today total delivery description"
                    ))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(LocalizedString("Max Basal", comment: "Max basal label"))
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
                        LocalizedString(
                            "Maximum basal insulin amount that can be delivered per hour.",
                            comment: "Max basal description"
                        )
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(LocalizedString("Max Bolus", comment: "Max bolus label"))
                        Spacer()
                        Text(
                            String(format: "%.1f U", viewModel.maxBolus)
                        )
                        .foregroundColor(.secondary)
                    }
                    Text(
                        LocalizedString(
                            "Maximum insulin amount that can be delivered per single bolus.",
                            comment: "Max bolus description"
                        )
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)
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
                    .onLongPressGesture {
                        withAnimation { showDebug.toggle() }
                    }
                }
            }

            // MARK: - Debug (hidden, long-press Firmware to show)

            if showDebug {
                Section(
                    header: Text("Debug"),
                    footer: Text(
                        "Pump Log shows the latest log position on the pump. Stored Log shows the last synced position. Changing stored wrap/log number will re-sync from that position."
                    )
                    .font(.footnote)
                ) {
                    HStack {
                        Text("Incarnation")
                        Spacer()
                        Text("\(viewModel.incarnation)")
                            .foregroundColor(.secondary)
                    }

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
                        Text("Stored Log #")
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
                        Text("Stored Wrap #")
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
            }

            // MARK: - Logs & Delete

            Section {
                Button(
                    LocalizedString(
                        "Share Diaconn Pump Logs",
                        comment: "Button to share pump logs"
                    )
                ) {
                    isSharePresented = true
                }
                .sheet(isPresented: $isSharePresented) {
                    let urls = viewModel.getLogFileURLs()
                    if urls.isEmpty {
                        Text(
                            LocalizedString(
                                "No log files found.",
                                comment: "Text when no log files available"
                            )
                        )
                        .padding()
                    } else {
                        ShareSheet(activityItems: urls)
                    }
                }

                Button(action: {
                    viewModel.showingDeleteConfirmation = true
                }) {
                    Text(
                        LocalizedString(
                            "Delete Pump",
                            comment: "Label for pump deletion button"
                        )
                    )
                    .foregroundColor(.red)
                }
                .actionSheet(isPresented: $viewModel.showingDeleteConfirmation) {
                    ActionSheet(
                        title: Text(
                            LocalizedString(
                                "Remove Pump",
                                comment: "Title for pump removal confirmation"
                            )
                        ),
                        message: Text(
                            LocalizedString(
                                "Are you sure you want to stop using Diaconn G8?",
                                comment: "Message for pump removal confirmation"
                            )
                        ),
                        buttons: [
                            .destructive(
                                Text(
                                    LocalizedString(
                                        "Delete Pump",
                                        comment: "Confirm pump deletion button"
                                    )
                                )
                            ) {
                                viewModel.deletePump()
                            },
                            .cancel()
                        ]
                    )
                }
            }
        }
        .navigationTitle("Diaconn G8")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
            }
        }
    }

    // MARK: - Delivery Status Component

    private var deliveryStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(
                LocalizedString(
                    "Basal",
                    comment: "Header for basal delivery status"
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
                    Text(String(format: "T:%.2f", dose.unitsPerHour))
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

    // MARK: - Battery Status Component

    private var batteryStatus: some View {
        VStack(alignment: .center, spacing: 5) {
            Text(
                LocalizedString(
                    "Battery",
                    comment: "Header for battery status"
                )
            )
            .foregroundColor(Color(UIColor.secondaryLabel))

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(String(format: "%.0f", viewModel.batteryRemaining * 100))
                    .font(.system(size: 28))
                    .fontWeight(.heavy)
                    .fixedSize()
                    .foregroundColor(
                        viewModel.batteryRemaining <= 0.2 ? .red :
                            viewModel.batteryRemaining <= 0.4 ? .orange : .primary
                    )
                Text("%")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Reservoir Status Component

    private var reservoirStatus: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(
                LocalizedString(
                    "Reservoir",
                    comment: "Header for reservoir status"
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

// MARK: - ShareSheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
