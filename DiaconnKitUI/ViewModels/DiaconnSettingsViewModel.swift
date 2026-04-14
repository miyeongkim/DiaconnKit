import Combine
import Foundation
import LoopKit

class DiaconnSettingsViewModel: ObservableObject, DiaconnStateObserver {
    @Published var isConnected: Bool = false
    @Published var reservoirLevel: Double = 0
    @Published var batteryRemaining: Double = 0
    @Published var firmwareVersion: String?
    @Published var basalStateDescription: String = "Unknown"
    @Published var isRefreshing: Bool = false
    @Published var refreshErrorMessage: String?
    @Published var insulinType: InsulinType?
    @Published var basalDeliveryState: PumpManagerStatus.BasalDeliveryState?
    @Published var isSuspending: Bool = false
    @Published var pumpTime: Date?
    @Published var bolusSpeed: UInt8 = 4
    @Published var beepAndAlarm: UInt8 = 0
    @Published var alarmIntensity: UInt8 = 0
    @Published var serialNumber: String?
    @Published var maxBasalPerHour: Double = 0
    @Published var maxBolus: Double = 0
    @Published var todayTotalAmount: Double = 0
    @Published var currentBasalRate: Double = 0
    @Published var pumpLogNum: UInt16 = 0
    @Published var pumpWrapCount: UInt8 = 0
    @Published var storedLogNum: UInt16 = 0
    @Published var storedWrapCount: UInt8 = 0
    @Published var editStoredLogNum: String = ""
    @Published var editStoredWrapCount: String = ""
    @Published var incarnation: UInt16 = 0
    @Published var cannulaDate: Date?
    @Published var reservoirDate: Date?
    @Published var batteryDate: Date?
    @Published var activeAlert: DiaconnPumpManagerAlert?
    @Published var pumpTimeSyncedAt: Date?
    @Published var showPumpTimeSyncWarning: Bool = false
    @Published var isSyncingTime: Bool = false
    @Published var isTempBasal: Bool = false
    @Published var isStoppingTempBasal: Bool = false
    @Published var showingDeleteConfirmation: Bool = false
    @Published var showingTimeSyncConfirmation: Bool = false

    let allowedInsulinTypes: [InsulinType]

    private weak var pumpManager: DiaconnPumpManager?
    private var onFinish: () -> Void

    init(pumpManager: DiaconnPumpManager?, allowedInsulinTypes: [InsulinType], onFinish: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.allowedInsulinTypes = allowedInsulinTypes
        self.onFinish = onFinish
        pumpManager?.addStateObserver(self, queue: .main)
        updateFromState()
    }

    func updateFromState() {
        guard let state = pumpManager?.state else { return }
        updateFromNewState(state)
    }

    private func updateFromNewState(_ state: DiaconnPumpManagerState) {
        isConnected = pumpManager?.isBluetoothConnected ?? state.isConnected
        reservoirLevel = state.reservoirLevel
        batteryRemaining = state.batteryRemaining
        firmwareVersion = state.firmwareVersion
        insulinType = state.insulinType
        basalDeliveryState = state.basalDeliveryState
        pumpTime = state.pumpTime
        bolusSpeed = state.bolusSpeed
        beepAndAlarm = state.beepAndAlarm
        alarmIntensity = state.alarmIntensity
        serialNumber = state.serialNumber
        maxBasalPerHour = state.maxBasalPerHour
        maxBolus = state.maxBolus
        todayTotalAmount = state.todayBasalAmount + state.todayMealAmount + state.todaySnackAmount
        currentBasalRate = state.currentBasalRate
        pumpLogNum = state.pumpLastLogNum
        pumpWrapCount = state.pumpWrappingCount
        storedLogNum = state.storedLastLogNum
        storedWrapCount = state.storedWrappingCount
        incarnation = state.syncedIncarnation
        cannulaDate = state.cannulaDate
        reservoirDate = state.reservoirDate
        batteryDate = state.batteryDate
        activeAlert = pumpManager?.activeAlert
        pumpTimeSyncedAt = state.pumpTimeSyncedAt
        isTempBasal = state.isTempBasalInProgress

        // Pump time sync warning: warn if pump clock and system clock differed by more than 2 minutes at sync time
        if let pt = state.pumpTime, let syncedAt = state.pumpTimeSyncedAt {
            showPumpTimeSyncWarning = abs(pt.timeIntervalSince(syncedAt)) > 120
        } else {
            showPumpTimeSyncWarning = false
        }

        switch state.basalDeliveryOrdinal {
        case .active: basalStateDescription = "Active"
        case .suspended: basalStateDescription = "Suspended"
        case .tempBasal:
            basalStateDescription = state.tempBasalUnits.map { String(format: "Temp Basal %.2fU/hr", $0) } ?? "Temp Basal"
        }
    }

    var suspendResumeButtonLabel: String {
        switch basalDeliveryState {
        case .active,
             .cancelingTempBasal,
             .initiatingTempBasal,
             .tempBasal:
            return LocalizedString("Suspend Delivery", comment: "Title text for button to suspend insulin delivery")
        case .suspending:
            return LocalizedString(
                "Suspending",
                comment: "Title text for button when insulin delivery is in the process of being stopped"
            )
        case .suspended:
            return LocalizedString("Resume Delivery", comment: "Title text for button to resume insulin delivery")
        case .resuming:
            return LocalizedString(
                "Resuming",
                comment: "Title text for button when insulin delivery is in the process of being resumed"
            )
        case .none:
            return LocalizedString("Suspend Delivery", comment: "Title text for button to suspend insulin delivery")
        }
    }

    var isSuspended: Bool {
        if case .suspended = basalDeliveryState { return true }
        return false
    }

    func suspendResumeButtonPressed() {
        isSuspending = true
        if isSuspended {
            pumpManager?.resumeDelivery { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isSuspending = false
                    self?.updateFromState()
                }
            }
        } else {
            pumpManager?.suspendDelivery { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isSuspending = false
                    self?.updateFromState()
                }
            }
        }
    }

    func setBolusSpeed(_ speed: UInt8) {
        pumpManager?.setBolusSpeed(speed) { [weak self] _ in
            DispatchQueue.main.async { self?.updateFromState() }
        }
    }

    func setSoundSetting(type: UInt8, intensity: UInt8) {
        pumpManager?.setSoundSetting(beepAndAlarm: type, alarmIntensity: intensity) { [weak self] _ in
            DispatchQueue.main.async { self?.updateFromState() }
        }
    }

    func didChangeInsulinType(_ newType: InsulinType?) {
        pumpManager?.state.insulinType = newType
        insulinType = newType
    }

    // MARK: - Device Lifecycle

    private static let lifecycleDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var cannulaDateString: String {
        cannulaDate.map { Self.lifecycleDateFormatter.string(from: $0) }
            ?? LocalizedString("Unknown", comment: "Unknown date")
    }

    var reservoirDateString: String {
        reservoirDate.map { Self.lifecycleDateFormatter.string(from: $0) }
            ?? LocalizedString("Unknown", comment: "Unknown date")
    }

    var batteryDateString: String {
        batteryDate.map { Self.lifecycleDateFormatter.string(from: $0) }
            ?? LocalizedString("Unknown", comment: "Unknown date")
    }

    func markCannulaChanged() {
        pumpManager?.state.cannulaDate = Date()
        pumpManager?.notifyStateDidChange()
        updateFromState()
    }

    func markReservoirChanged() {
        pumpManager?.state.reservoirDate = Date()
        pumpManager?.notifyStateDidChange()
        updateFromState()
    }

    func markBatteryChanged() {
        pumpManager?.state.batteryDate = Date()
        pumpManager?.notifyStateDidChange()
        updateFromState()
    }

    // MARK: - Stop Temp Basal

    func stopTempBasal() {
        isStoppingTempBasal = true
        pumpManager?.enactTempBasal(unitsPerHour: 0, for: 0) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isStoppingTempBasal = false
                self?.updateFromState()
            }
        }
    }

    // MARK: - Pump Time Sync

    func syncPumpTime() {
        isSyncingTime = true
        pumpManager?.syncTime { [weak self] _ in
            DispatchQueue.main.async {
                self?.isSyncingTime = false
                self?.updateFromState()
            }
        }
    }

    // MARK: - Log Sharing

    private let log = DiaconnLogger(category: "DiaconnSettings")

    func getLogFileURLs() -> [URL] {
        log.info(pumpManager?.state.debugDescription ?? "No pump manager")
        return log.getDebugLogs()
    }

    // MARK: - Alert Acknowledgement

    func acknowledgeAlert() {
        pumpManager?.dismissActiveAlert()
    }

    // MARK: - Diagnostics

    func testCommunication() {
        refreshStatus()
    }

    // MARK: - DiaconnStateObserver

    func stateDidUpdate(_ newState: DiaconnPumpManagerState, _: DiaconnPumpManagerState) {
        updateFromNewState(newState)
    }

    func deviceScanDidUpdate(_: DiaconnPumpScan) {}

    // MARK: - Debug: log cursor change

    func applyStoredLogNum() {
        guard let value = UInt16(editStoredLogNum) else { return }
        pumpManager?.state.storedLastLogNum = value
        pumpManager?.notifyStateDidChange()
        storedLogNum = value
    }

    func applyStoredWrapCount() {
        guard let value = UInt8(editStoredWrapCount) else { return }
        pumpManager?.state.storedWrappingCount = value
        pumpManager?.notifyStateDidChange()
        storedWrapCount = value
    }

    // MARK: -

    func refreshStatus() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshErrorMessage = nil
        // If disconnected, reconnect then query status; if connected, query status directly
        pumpManager?.ensureCurrentPumpData { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRefreshing = false
                self?.updateFromState()
                // Show error message if still disconnected after connection attempt
                if self?.isConnected == false {
                    self?.refreshErrorMessage = LocalizedString(
                        "Unable to connect to pump. Make sure the pump is nearby.",
                        comment: "Error shown when pump reconnection fails"
                    )
                }
            }
        }
    }

    func deletePump() {
        pumpManager?.notifyDelegateOfDeactivation {
            DispatchQueue.main.async { self.onFinish() }
        }
    }
}
