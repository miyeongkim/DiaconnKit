import Combine
import DiaconnKit
import Foundation
import LoopKit

class DiaconnSettingsViewModel: ObservableObject, DiaconnStateObserver {
    @Published var isConnected: Bool = false
    @Published var reservoirLevel: Double = 0
    @Published var batteryRemaining: Double = 0
    @Published var firmwareVersion: String?
    @Published var basalStateDescription: String = "알 수 없음"
    @Published var isRefreshing: Bool = false
    @Published var insulinType: InsulinType?
    @Published var basalDeliveryState: PumpManagerStatus.BasalDeliveryState?
    @Published var isSuspending: Bool = false
    @Published var pumpTime: Date?
    @Published var bolusSpeed: UInt8 = 4
    @Published var beepAndAlarm: UInt8 = 0
    @Published var alarmIntensity: UInt8 = 0

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
        isConnected = state.isConnected
        reservoirLevel = state.reservoirLevel
        batteryRemaining = state.batteryRemaining
        firmwareVersion = state.firmwareVersion
        insulinType = state.insulinType
        basalDeliveryState = state.basalDeliveryState
        pumpTime = state.pumpTime
        bolusSpeed = state.bolusSpeed
        beepAndAlarm = state.beepAndAlarm
        alarmIntensity = state.alarmIntensity

        switch state.basalDeliveryOrdinal {
        case .active: basalStateDescription = "활성"
        case .suspended: basalStateDescription = "중단됨"
        case .tempBasal:
            basalStateDescription = state.tempBasalUnits.map { String(format: "임시 기저 %.2fU/hr", $0) } ?? "임시 기저"
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
                DispatchQueue.main.async { self?.isSuspending = false }
            }
        } else {
            pumpManager?.suspendDelivery { [weak self] _ in
                DispatchQueue.main.async { self?.isSuspending = false }
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

    // MARK: - DiaconnStateObserver

    func stateDidUpdate(_: DiaconnPumpManagerState, _: DiaconnPumpManagerState) {
        updateFromState()
    }

    func deviceScanDidUpdate(_: DiaconnPumpScan) {}

    // MARK: -

    func refreshStatus() {
        guard !isRefreshing else { return }
        isRefreshing = true
        pumpManager?.fetchPumpStatus { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRefreshing = false
                self?.updateFromState()
            }
        }
    }

    func deletePump() {
        pumpManager?.notifyDelegateOfDeactivation {
            DispatchQueue.main.async { self.onFinish() }
        }
    }
}
