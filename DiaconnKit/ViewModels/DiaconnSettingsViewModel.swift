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

    // MARK: - 디버그: 로그 커서 변경

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
        // 연결이 끊겨 있으면 재연결 후 상태 조회, 연결 중이면 바로 상태 조회
        pumpManager?.ensureCurrentPumpData { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRefreshing = false
                self?.updateFromState()
                // 연결 시도 후에도 여전히 연결 안 된 경우 에러 메시지 표시
                if self?.isConnected == false {
                    self?.refreshErrorMessage = LocalizedString(
                        "펌프에 연결할 수 없습니다. 펌프가 가까이 있는지 확인하세요.",
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
