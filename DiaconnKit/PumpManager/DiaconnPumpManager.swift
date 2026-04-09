import CoreBluetooth
import HealthKit
public import LoopKit
import UIKit
import UserNotifications

internal protocol DiaconnStateObserver: AnyObject {
    func stateDidUpdate(_ state: DiaconnPumpManagerState, _ oldState: DiaconnPumpManagerState)
    func deviceScanDidUpdate(_ device: DiaconnPumpScan)
}

public class DiaconnPumpManager: DeviceManager, AlertResponder, AlertSoundVendor {
    // MARK: - Properties

    public private(set) var bluetooth: DiaconnBluetoothManager

    private var oldState: DiaconnPumpManagerState
    public var state: DiaconnPumpManagerState
    public var rawState: PumpManager.RawStateValue {
        state.rawValue
    }

    public static let pluginIdentifier: String = "DiaconnG8"
    public let managerIdentifier: String = "DiaconnG8"

    public var localizedTitle: String {
        state.getFriendlyDeviceName()
    }

    public let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()
    private let statusObservers = WeakSynchronizedSet<PumpManagerStatusObserver>()
    let stateObservers = WeakSynchronizedSet<DiaconnStateObserver>()

    private var doseReporter: DiaconnDoseProgressReporter?

    private let log = DiaconnLogger(category: "DiaconnPumpManager")
    private let pumpQueue = DispatchQueue(label: "com.diaconkit.pumpmanager", qos: .userInitiated)

    // MARK: - Init

    init(state: DiaconnPumpManagerState) {
        self.state = state
        oldState = DiaconnPumpManagerState(rawValue: state.rawValue)
        bluetooth = DiaconnBluetoothManager()
        bluetooth.pumpManager = self
    }

    public required convenience init?(rawState: PumpManager.RawStateValue) {
        self.init(state: DiaconnPumpManagerState(rawValue: rawState))
    }

    // MARK: - Computed Properties

    public var isOnboarded: Bool {
        state.isOnBoarded
    }

    public var isBluetoothConnected: Bool {
        bluetooth.isConnected
    }

    private let basalIntervals: [TimeInterval] = Array(0 ..< 24).map { TimeInterval(60 * 60 * $0) }
    public var currentBaseBasalRate: Double {
        guard !state.basalSchedule.isEmpty else {
            return 0
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let nowTimeInterval = now.timeIntervalSince(startOfDay)

        let index = (basalIntervals.firstIndex(where: { $0 > nowTimeInterval }) ?? 24) - 1
        return state.basalSchedule.indices.contains(index) ? state.basalSchedule[index] : 0
    }

    public var status: PumpManagerStatus {
        PumpManagerStatus(
            timeZone: TimeZone.current,
            device: device,
            pumpBatteryChargeRemaining: state.batteryRemaining,
            basalDeliveryState: state.basalDeliveryState,
            bolusState: bolusState,
            insulinType: state.insulinType
        )
    }

    private var bolusState: PumpManagerStatus.BolusState {
        switch state.bolusState {
        case .noBolus:
            return .noBolus
        case .initiating:
            return .initiating
        case .inProgress:
            // DoseEntry 대신 현재 볼루스 정보로 생성
            let dose = DoseEntry(
                type: .bolus,
                startDate: state.lastBolusDate ?? Date(),
                endDate: nil,
                value: state.totalUnits ?? state.lastBolusAmount,
                unit: .units,
                deliveredUnits: state.deliveredUnits,
                description: "Bolus in progress",
                syncIdentifier: UUID().uuidString,
                scheduledBasalRate: nil
            )
            return .inProgress(dose)
        case .canceling:
            return .canceling
        }
    }

    private var device: HKDevice {
        HKDevice(
            name: "DiaconnPumpManager",
            manufacturer: "G2E",
            model: state.getFriendlyDeviceName(),
            hardwareVersion: nil,
            firmwareVersion: state.firmwareVersion,
            softwareVersion: nil,
            localIdentifier: state.bleIdentifier,
            udiDeviceIdentifier: nil
        )
    }

    public var debugDescription: String {
        [
            "## DiaconnPumpManager",
            state.debugDescription
        ].joined(separator: "\n")
    }

    // MARK: - Status Highlight

    public func buildPumpStatusHighlight(for state: DiaconnPumpManagerState) -> PumpStatusHighlight? {
        if !state.isOnBoarded {
            return PumpStatusHighlight(
                localizedMessage: LocalizedString(
                    "Finish Setup",
                    comment: "Status highlight when Diaconn G8 setup is not complete."
                ),
                imageName: "exclamationmark.circle.fill",
                state: .warning
            )
        }

        if state.isPumpSuspended {
            return PumpStatusHighlight(
                localizedMessage: LocalizedString(
                    "Insulin Suspended",
                    comment: "Status highlight that insulin delivery was suspended."
                ),
                imageName: "pause.circle.fill",
                state: .warning
            )
        }

        if state.reservoirLevel == 0 {
            return PumpStatusHighlight(
                localizedMessage: LocalizedString("No Insulin", comment: "Status highlight that a pump is out of insulin."),
                imageName: "exclamationmark.circle.fill",
                state: .critical
            )
        }

        if Date().timeIntervalSince(state.lastStatusDate) > 12 * 60 {
            return PumpStatusHighlight(
                localizedMessage: LocalizedString(
                    "Signal Loss",
                    comment: "Status highlight when communications with the pump haven't happened recently."
                ),
                imageName: "exclamationmark.circle.fill",
                state: .critical
            )
        }

        return nil
    }

    // MARK: - State Observers

    func addStateObserver(_ observer: DiaconnStateObserver, queue: DispatchQueue = .main) {
        stateObservers.insert(observer, queue: queue)
    }

    func removeStateObserver(_ observer: DiaconnStateObserver) {
        stateObservers.removeElement(observer)
    }

    public func notifyStateDidChange() {
        let newState = state
        let old = oldState
        oldState = DiaconnPumpManagerState(rawValue: newState.rawValue)

        let status = self.status
        let oldStatus = PumpManagerStatus(
            timeZone: TimeZone.current,
            device: device,
            pumpBatteryChargeRemaining: old.batteryRemaining,
            basalDeliveryState: old.basalDeliveryState,
            bolusState: .noBolus, // old status bolusState isn't perfectly stored, but loop usually only cares about newState
            insulinType: old.insulinType
        )

        pumpDelegate.notify { [status, oldStatus] delegate in
            guard let delegate = delegate else { return }
            delegate.pumpManagerDidUpdateState(self)
            delegate.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
        }

        statusObservers.forEach { observer in
            observer.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
        }

        stateObservers.forEach { observer in
            observer.stateDidUpdate(newState, old)
        }
    }

    // MARK: - Device Communication Logging

    public func logDeviceCommunication(_ message: String, type: DeviceLogEntryType = .send) {
        pumpDelegate.notify { delegate in
            guard let delegate = delegate else { return }
            delegate.deviceManager(
                self,
                logEventForDeviceIdentifier: self.state.bleIdentifier,
                type: type,
                message: message,
                completion: nil
            )
        }
    }

    // MARK: - 2단계 커밋 (OTP 확인)

    /// 설정 명령 후 OTP 확인 전송 + 펌프의 0xAA 응답 대기
    /// 응답을 소비하지 않으면 다음 sendPacket이 0xAA를 잘못 수신함
    private func confirmSettingCommand(reqMsgType: UInt8, otpNumber: UInt32) throws {
        let confirmPacket = generateAppConfirmPacket(reqMsgType: reqMsgType, otpNumber: otpNumber)
        log.info("OTP confirm sending: reqMsgType=0x\(String(format: "%02X", reqMsgType)) otp=\(otpNumber)")

        guard let responseData = try bluetooth.writeAndWait(packet: confirmPacket) else {
            log.error("OTP confirm: no response (timeout)")
            throw DiaconnPumpManagerError.communicationFailure
        }

        // 0xAA 응답 확인
        let msgType = responseData.count > 1 ? responseData[1] : 0
        let resultByte = responseData.count > 4 ? responseData[4] : 0xFF
        log
            .info(
                "OTP confirm response: msgType=0x\(String(format: "%02X", msgType)) result=\(resultByte) (\(resultByte == 0 ? "✅ OK" : "❌ FAIL"))"
            )

        guard resultByte == 0 else {
            let settingResult = DiaconnPacketType.SettingResult(rawValue: Int(resultByte))
            throw DiaconnPumpManagerError.settingFailed(settingResult ?? .protocolError)
        }
    }

    // MARK: - 펌프 상태 조회

    /// BigAPSMainInfoInquire (0x54) → 182바이트 응답으로 전체 상태 업데이트
    func fetchPumpStatus(completion: @escaping (Result<DiaconnPumpStatus, Error>) -> Void) {
        pumpQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                self.log.info("[fetchPumpStatus] Sending BigAPSMainInfoInquire (0x54)...")

                // 요청은 표준 20바이트 패킷, 응답은 182바이트 대량 패킷
                guard let responseData = try self.bluetooth.sendPacket(
                    msgType: DiaconnPacketType.BIG_APS_MAIN_INFO_INQUIRE,
                    timeout: 15.0
                ) else {
                    self.log.error("[fetchPumpStatus] No response (timeout or nil)")
                    completion(.failure(DiaconnPumpManagerError.communicationFailure))
                    return
                }

                self.log.info("[fetchPumpStatus] Response received: \(responseData.count) bytes")

                // 헤더 + 앞 16바이트 로그 (os_log 길이 제한 고려)
                let headerHex = responseData.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
                self.log.info("[fetchPumpStatus] Header[0..15]: \(headerHex)")

                // 응답 첫 바이트(SOP) 및 msgType 확인
                if responseData.count >= 2 {
                    let sop = responseData[0]
                    let msgType = responseData[1]
                    self.log
                        .info(
                            "[fetchPumpStatus] SOP=0x\(String(format: "%02X", sop)) msgType=0x\(String(format: "%02X", msgType)) (expected SOP=0xED msgType=0x94)"
                        )
                }

                // result 바이트 (offset 4) 확인
                if responseData.count > 4 {
                    let resultByte = responseData[4]
                    self.log.info("[fetchPumpStatus] result byte=\(resultByte) (expected 16=success)")
                }

                // 리저브/배터리 원시값 (offset 5~7)
                if responseData.count > 7 {
                    let rawReservoir = UInt16(responseData[5]) | (UInt16(responseData[6]) << 8)
                    let rawBattery = responseData[7]
                    self.log
                        .info(
                            "[fetchPumpStatus] raw reservoirShort=\(rawReservoir) (\(Double(rawReservoir) / 100.0)U) rawBattery=\(rawBattery)%"
                        )
                }

                guard let pumpStatus = parseBigAPSMainInfoResponse(responseData) else {
                    self.log.error("[fetchPumpStatus] parseBigAPSMainInfoResponse returned nil — validate/parse failed")
                    // CRC 검증 결과 로그
                    let defect = DiaconnPacketDecoder.validatePacket(responseData)
                    self.log.error("[fetchPumpStatus] validatePacket defect=\(defect) (0=ok, 97=len, 98=sop, 99=crc)")
                    completion(.failure(DiaconnPumpManagerError.communicationFailure))
                    return
                }

                self.log.info("[fetchPumpStatus] Parse success:")
                self.log.info("  remainInsulin=\(pumpStatus.remainInsulin)U")
                self.log.info("  remainBattery=\(pumpStatus.remainBattery)%")
                self.log
                    .info(
                        "  basePauseStatus=\(pumpStatus.basePauseStatus) (1=정지됨, 2=해제/동작중) isSuspended=\(pumpStatus.isSuspended)"
                    )
                self.log
                    .info("  tbStatus=\(pumpStatus.tbStatus) (1=임시기저중, 2=해제) isTempBasalRunning=\(pumpStatus.isTempBasalRunning)")
                self.log.info("  tempBasalStatus=\(pumpStatus.tempBasalStatus) (0=none)")
                self.log.info("  basalAmount=\(pumpStatus.basalAmount)U/h")
                self.log
                    .info(
                        "  pumpTime=\(pumpStatus.pumpYear)-\(pumpStatus.pumpMonth)-\(pumpStatus.pumpDay) \(pumpStatus.pumpHour):\(pumpStatus.pumpMinute):\(pumpStatus.pumpSecond)"
                    )
                self.log.info("  firmwareVersion=\(pumpStatus.firmwareVersion)")
                self.log.info("  serialNumber=\(pumpStatus.serialNumber)")
                self.log.info("  maxBasalPerHour=\(pumpStatus.maxBasalPerHour)U/h  maxBolus=\(pumpStatus.maxBolus)U")

                self.state.updateFromPumpStatus(pumpStatus)
                self.notifyStateDidChange()

                let reservoirLevel = pumpStatus.remainInsulin
                let now = Date()
                self.pumpDelegate.notify { delegate in
                    guard let delegate = delegate else { return }
                    delegate.pumpManager(self, didReadReservoirValue: reservoirLevel, at: now) { _ in }
                }

                // 펌프 로그 조회 후 Trio 히스토리에 저장
                self.syncLogHistory()

                completion(.success(pumpStatus))

            } catch {
                self.log.error("[fetchPumpStatus] failed: \(error)")
                completion(.failure(error))
            }
        }
    }
}

// MARK: - PumpManager Protocol

extension DiaconnPumpManager: PumpManager {
    public static var onboardingMaximumBasalScheduleEntryCount: Int {
        24
    }

    public static var onboardingSupportedBasalRates: [Double] {
        stride(from: 0.01, through: 16.0, by: 0.01).map { $0 }
    }

    public static var onboardingSupportedBolusVolumes: [Double] {
        stride(from: 0.05, through: 25.0, by: 0.05).map { $0 }
    }

    public static var onboardingSupportedMaximumBolusVolumes: [Double] {
        stride(from: 0.05, through: 25.0, by: 0.05).map { $0 }
    }

    public var supportedMaximumBolusVolumes: [Double] {
        stride(from: 0.05, through: max(state.maxBolus, 25.0), by: 0.05).map { $0 }
    }

    public var lastSync: Date? {
        state.lastStatusDate
    }

    public func estimatedDuration(toBolus units: Double) -> TimeInterval {
        // 디아콘 G8 볼루스 속도: 1~8 (1 = 느림, 8 = 빠름)
        // 기본값 4 사용 시 약 2초/U
        let secondsPerUnit = max(1.0, 9.0 - Double(state.bolusSpeed)) * 0.5
        return units * secondsPerUnit
    }

    public static let managerIdentifier = "DiaconnG8"

    public var deliveryLimits: DeliveryLimits {
        DeliveryLimits(
            maximumBasalRate: HKQuantity(
                unit: HKUnit.internationalUnit().unitDivided(by: .hour()),
                doubleValue: state.maxBasalPerHour
            ),
            maximumBolus: HKQuantity(unit: .internationalUnit(), doubleValue: state.maxBolus)
        )
    }

    public var isClockOffset: Bool {
        // 펌프 시간과 시스템 시간 차이 확인
        guard let pumpTime = state.pumpTime else { return false }
        let offset = abs(pumpTime.timeIntervalSinceNow)
        return offset > 60 // 1분 이상 차이나면 offset으로 간주
    }

    public var supportedBolusVolumes: [Double] {
        // 0.01U 단위 (amount * 100이므로)
        stride(from: 0.05, through: max(state.maxBolus, 25.0), by: 0.05).map { $0 }
    }

    public var supportedBasalRates: [Double] {
        stride(from: 0.01, through: max(state.maxBasalPerHour, 16.0), by: 0.01).map { $0 }
    }

    public var maximumBasalScheduleEntryCount: Int {
        24
    }

    public var minimumBasalScheduleEntryDuration: TimeInterval {
        TimeInterval(60 * 60) // 1시간
    }

    public var pumpManagerDelegate: PumpManagerDelegate? {
        get { pumpDelegate.delegate }
        set { pumpDelegate.delegate = newValue }
    }

    public var delegateQueue: DispatchQueue! {
        get { pumpDelegate.queue }
        set { pumpDelegate.queue = newValue }
    }

    public func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue) {
        statusObservers.insert(observer, queue: queue)
    }

    public func removeStatusObserver(_ observer: PumpManagerStatusObserver) {
        statusObservers.removeElement(observer)
    }

    public func ensureCurrentPumpData(completion: ((Date?) -> Void)?) {
        log.info("ensureCurrentPumpData called (connected=\(state.isConnected))")

        // 연결 안 된 경우 저장된 bleIdentifier로 재연결 시도
        // 재연결 성공 시 didUpdateNotificationStateFor에서 fetchPumpStatus가 자동 호출됨
        if !bluetooth.isConnected {
            guard let bleIdentifier = state.bleIdentifier else {
                log.error("ensureCurrentPumpData: not connected and no bleIdentifier saved")
                completion?(state.lastStatusDate)
                return
            }

            log.info("Not connected — reconnecting to \(bleIdentifier)")
            bluetooth.connect(bleIdentifier) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    // fetchPumpStatus는 didUpdateNotificationStateFor에서 자동 호출됨
                    // 완료 콜백은 fetchPumpStatus 이후에 처리
                    self.log.info("Reconnected successfully")
                    completion?(self.state.lastStatusDate)
                case let .failure(error):
                    self.log.error("Reconnect failed: \(error.localizedDescription)")
                    completion?(self.state.lastStatusDate)
                case .timeout:
                    self.log.error("Reconnect timed out")
                    completion?(self.state.lastStatusDate)
                }
            }
            return
        }

        // 이미 연결된 경우 바로 상태 조회
        fetchPumpStatus { [weak self] result in
            switch result {
            case .success:
                self?.log.info("Pump status updated successfully")
                completion?(self?.state.lastStatusDate)
            case let .failure(error):
                self?.log.error("Failed to update pump status: \(error)")
                completion?(self?.state.lastStatusDate)
            }
        }
    }

    public func setMustProvideBLEHeartbeat(_: Bool) {
        // 디아콘 G8은 BLE heartbeat 불필요
    }

    public func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> DoseProgressReporter? {
        let reporter = DiaconnDoseProgressReporter(dispatchQueue: dispatchQueue)
        if let totalUnits = state.totalUnits {
            reporter.totalUnits = totalUnits
        }
        if let deliveredUnits = state.deliveredUnits {
            reporter.notify(deliveredUnits: deliveredUnits, done: false)
        }
        doseReporter = reporter
        return doseReporter
    }

    public func enactBolus(
        units: Double,
        activationType: BolusActivationType,
        completion: @escaping (PumpManagerError?) -> Void
    ) {
        log.info("enactBolus: \(units)U activationType=\(activationType)")
        state.lastBolusAutomatic = (activationType == .automatic)

        guard state.isConnected else {
            completion(.communication(DiaconnPumpManagerError.notConnected))
            return
        }

        guard state.bolusState == .noBolus else {
            completion(.communication(DiaconnPumpManagerError.bolusInProgress))
            return
        }

        state.bolusState = .initiating
        notifyStateDidChange()

        pumpQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // 볼루스 명령 전송 (0x07) + 응답 대기 (OTP 번호 수신)
                var payload = Data()
                payload.appendShortLE(UInt16(units * 100))
                guard let responseData = try self.bluetooth.sendPacket(
                    msgType: DiaconnPacketType.INJECTION_SNACK_SETTING,
                    payload: payload
                ) else {
                    throw DiaconnPumpManagerError.communicationFailure
                }

                guard let response = parseBolusSettingResponse(responseData) else {
                    throw DiaconnPumpManagerError.communicationFailure
                }

                guard response.isSuccess else {
                    let settingResult = DiaconnPacketType.SettingResult(rawValue: Int(response.result))
                    throw DiaconnPumpManagerError.settingFailed(settingResult ?? .protocolError)
                }

                // 3. OTP 확인 전송 (2단계 커밋)
                try self.confirmSettingCommand(
                    reqMsgType: DiaconnPacketType.INJECTION_SNACK_SETTING,
                    otpNumber: response.otpNumber
                )

                // 4. 상태 업데이트
                self.state.bolusState = .inProgress
                self.state.lastBolusAmount = units
                self.state.lastBolusDate = Date()
                self.state.totalUnits = units
                self.state.deliveredUnits = 0
                self.doseReporter?.totalUnits = units
                self.notifyStateDidChange()

                completion(nil)

            } catch {
                self.log.error("enactBolus failed: \(error)")
                self.state.bolusState = .noBolus
                self.notifyStateDidChange()

                let pumpError: DiaconnPumpManagerError
                if let diaconnError = error as? DiaconnPumpManagerError {
                    pumpError = diaconnError
                } else {
                    pumpError = .unknown(error.localizedDescription)
                }
                completion(.communication(pumpError))
            }
        }
    }

    public func cancelBolus(completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) {
        log.info("cancelBolus called")

        state.bolusState = .canceling
        notifyStateDidChange()

        pumpQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // 주입 취소 (0x2B), reqMsgType = 0x07 (볼루스)
                guard let responseData = try self.bluetooth.sendPacket(
                    msgType: DiaconnPacketType.INJECTION_CANCEL_SETTING,
                    payload: Data([DiaconnPacketType.INJECTION_SNACK_SETTING])
                ) else {
                    throw DiaconnPumpManagerError.communicationFailure
                }

                if let response = parseInjectionCancelResponse(responseData), response.isSuccess {
                    _ = try? self.confirmSettingCommand(
                        reqMsgType: DiaconnPacketType.INJECTION_CANCEL_SETTING,
                        otpNumber: response.otpNumber
                    )
                }

                self.state.bolusState = .noBolus
                self.notifyStateDidChange()
                completion(.success(nil))

            } catch {
                self.log.error("cancelBolus failed: \(error)")
                self.state.bolusState = .noBolus
                self.notifyStateDidChange()

                let pumpError: DiaconnPumpManagerError
                if let diaconnError = error as? DiaconnPumpManagerError {
                    pumpError = diaconnError
                } else {
                    pumpError = .unknown(error.localizedDescription)
                }
                completion(.failure(PumpManagerError.communication(pumpError)))
            }
        }
    }

    public func enactTempBasal(
        unitsPerHour: Double,
        for duration: TimeInterval,
        completion: @escaping (PumpManagerError?) -> Void
    ) {
        let durationMinutes = Int(duration / 60)
        log.info("enactTempBasal: \(unitsPerHour)U/hr for \(durationMinutes)min")

        guard state.isConnected else {
            completion(.communication(DiaconnPumpManagerError.notConnected))
            return
        }

        pumpQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let packet: Data
                if unitsPerHour == 0, durationMinutes == 0 {
                    // 임시 기저 해제
                    packet = generateTempBasalCancelPacket()
                } else {
                    // 현재 스케줄 기저율과 동일하면 임시기저 불필요
                    let scheduledRate = self.currentBaseBasalRate
                    if abs(unitsPerHour - scheduledRate) < 0.005 {
                        self.log
                            .info(
                                "enactTempBasal: \(unitsPerHour)U/h == scheduled \(scheduledRate)U/h — skipping TBR"
                            )
                        // 이미 임시기저가 실행 중이라면 해제
                        if self.state.isTempBasalInProgress {
                            let cancelPacket = generateTempBasalCancelPacket()
                            if let cancelResp = try? self.bluetooth.writeAndWait(packet: cancelPacket),
                               let parsed = parseTempBasalSettingResponse(cancelResp), parsed.isSuccess
                            {
                                try? self.confirmSettingCommand(
                                    reqMsgType: DiaconnPacketType.TEMP_BASAL_SETTING,
                                    otpNumber: parsed.otpNumber
                                )
                            }
                            self.state.isTempBasalInProgress = false
                            self.state.tempBasalUnits = nil
                            self.state.tempBasalDuration = nil
                            self.state.basalDeliveryOrdinal = .active
                            self.notifyStateDidChange()
                        }
                        completion(nil)
                        return
                    }

                    // 이미 임시기저가 실행 중이면 status=3 스텔스 모드로 끊김 없이 변경
                    let tbrStatus: UInt8 = self.state.isTempBasalInProgress ? 3 : 1
                    packet = generateTempBasalAbsolutePacket(
                        unitsPerHour: unitsPerHour,
                        durationMinutes: durationMinutes,
                        status: tbrStatus
                    )
                }

                guard let responseData = try self.bluetooth.writeAndWait(packet: packet) else {
                    throw DiaconnPumpManagerError.communicationFailure
                }

                guard let response = parseTempBasalSettingResponse(responseData) else {
                    throw DiaconnPumpManagerError.communicationFailure
                }

                guard response.isSuccess else {
                    let settingResult = DiaconnPacketType.SettingResult(rawValue: Int(response.result))
                    throw DiaconnPumpManagerError.settingFailed(settingResult ?? .protocolError)
                }

                // OTP 확인
                try self.confirmSettingCommand(
                    reqMsgType: DiaconnPacketType.TEMP_BASAL_SETTING,
                    otpNumber: response.otpNumber
                )

                // 상태 업데이트
                if unitsPerHour == 0, durationMinutes == 0 {
                    self.state.isTempBasalInProgress = false
                    self.state.tempBasalUnits = nil
                    self.state.tempBasalDuration = nil
                    self.state.basalDeliveryOrdinal = .active
                } else {
                    self.state.isTempBasalInProgress = true
                    self.state.tempBasalUnits = unitsPerHour
                    self.state.tempBasalDuration = duration
                    self.state.basalDeliveryDate = Date()
                    self.state.basalDeliveryOrdinal = .tempBasal
                }
                self.notifyStateDidChange()
                self.syncLogHistory()

                completion(nil)

            } catch {
                self.log.error("enactTempBasal failed: \(error)")

                let pumpError: DiaconnPumpManagerError
                if let diaconnError = error as? DiaconnPumpManagerError {
                    pumpError = diaconnError
                } else {
                    pumpError = .unknown(error.localizedDescription)
                }
                completion(.communication(pumpError))
            }
        }
    }

    public func suspendDelivery(completion: @escaping (Error?) -> Void) {
        log.info("suspendDelivery called")

        pumpQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let packet = generateSuspendPacket()
                guard let responseData = try self.bluetooth.writeAndWait(packet: packet) else {
                    throw DiaconnPumpManagerError.communicationFailure
                }

                guard let response = parseBasalPauseSettingResponse(responseData) else {
                    throw DiaconnPumpManagerError.communicationFailure
                }

                guard response.isSuccess else {
                    throw DiaconnPumpManagerError.settingFailed(
                        DiaconnPacketType.SettingResult(rawValue: Int(response.result)) ?? .protocolError
                    )
                }

                try self.confirmSettingCommand(
                    reqMsgType: DiaconnPacketType.BASAL_PAUSE_SETTING,
                    otpNumber: response.otpNumber
                )

                self.state.isPumpSuspended = true
                self.state.basalDeliveryOrdinal = .suspended
                self.state.basalDeliveryDate = Date()
                self.notifyStateDidChange()
                self.syncLogHistory()

                completion(nil)

            } catch {
                self.log.error("suspendDelivery failed: \(error)")
                completion(error)
            }
        }
    }

    public func resumeDelivery(completion: @escaping (Error?) -> Void) {
        log.info("resumeDelivery called")

        pumpQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let packet = generateResumePacket()
                guard let responseData = try self.bluetooth.writeAndWait(packet: packet) else {
                    throw DiaconnPumpManagerError.communicationFailure
                }

                guard let response = parseBasalPauseSettingResponse(responseData) else {
                    throw DiaconnPumpManagerError.communicationFailure
                }

                guard response.isSuccess else {
                    throw DiaconnPumpManagerError.settingFailed(
                        DiaconnPacketType.SettingResult(rawValue: Int(response.result)) ?? .protocolError
                    )
                }

                try self.confirmSettingCommand(
                    reqMsgType: DiaconnPacketType.BASAL_PAUSE_SETTING,
                    otpNumber: response.otpNumber
                )

                self.state.isPumpSuspended = false
                self.state.basalDeliveryOrdinal = .active
                self.state.basalDeliveryDate = Date()
                self.notifyStateDidChange()
                self.syncLogHistory()

                completion(nil)

            } catch {
                self.log.error("resumeDelivery failed: \(error)")
                completion(error)
            }
        }
    }

    public func syncBasalRateSchedule(
        items scheduleItems: [RepeatingScheduleValue<Double>],
        completion: @escaping (Result<BasalRateSchedule, Error>) -> Void
    ) {
        let basalSchedule = DiaconnPumpManagerState.convertBasal(scheduleItems)

        pumpQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // 24시간 프로파일을 4개 그룹으로 분할 전송
                let packets = generateFullBasalProfile(
                    pattern: self.state.basalPattern,
                    hourlyRates: basalSchedule
                )

                guard let writeChar = self.bluetooth.writeCharacteristic else {
                    throw DiaconnPumpManagerError.notConnected
                }

                // 마지막 패킷을 제외한 나머지를 먼저 전송
                for packet in packets.dropLast() {
                    self.bluetooth.peripheral?.writeValue(packet, for: writeChar, type: .withoutResponse)
                    Thread.sleep(forTimeInterval: 0.2)
                }

                // 마지막 패킷 전송 + 응답 대기
                guard let lastPacket = packets.last,
                      let responseData = try self.bluetooth.writeAndWait(packet: lastPacket)
                else {
                    throw DiaconnPumpManagerError.communicationFailure
                }

                guard let response = parseBasalSettingResponse(responseData) else {
                    throw DiaconnPumpManagerError.communicationFailure
                }

                guard response.isSuccess else {
                    throw DiaconnPumpManagerError.settingFailed(
                        DiaconnPacketType.SettingResult(rawValue: Int(response.result)) ?? .protocolError
                    )
                }

                try self.confirmSettingCommand(
                    reqMsgType: DiaconnPacketType.BASAL_SETTING,
                    otpNumber: response.otpNumber
                )

                self.state.basalSchedule = basalSchedule
                self.notifyStateDidChange()

                if let schedule = BasalRateSchedule(dailyItems: scheduleItems) {
                    completion(.success(schedule))
                } else {
                    completion(.failure(DiaconnPumpManagerError.communicationFailure))
                }

            } catch {
                self.log.error("syncBasalRateSchedule failed: \(error)")
                completion(.failure(error))
            }
        }
    }

    public func syncDeliveryLimits(
        limits deliveryLimits: DeliveryLimits,
        completion: @escaping (Result<DeliveryLimits, Error>) -> Void
    ) {
        // 디아콘 G8은 펌프 자체에서 한도 관리 (BigAPSMainInfo에서 조회됨)
        completion(.success(deliveryLimits))
    }

    public func roundToSupportedBolusVolume(units: Double) -> Double {
        // 0.01U 단위 (amount * 100 → short)
        (units * 100).rounded() / 100
    }

    public func roundToSupportedBasalRate(unitsPerHour: Double) -> Double {
        // 0.01U/hr 단위
        (unitsPerHour * 100).rounded() / 100
    }

    // MARK: - Additional PumpManager Requirements

    public var pumpRecordsBasalProfileStartEvents: Bool {
        // 디아콘 G8은 기저 프로파일 시작 이벤트를 기록하지 않음
        false
    }

    public var pumpReservoirCapacity: Double {
        // 디아콘 G8 저장소 용량 (300U)
        300
    }

    public func estimatedUnitsDelivered(since _: Date) -> Double {
        // 시작 시간 이후 전달된 예상 인슐린 양
        // 실제 구현에서는 펌프 로그를 조회해야 하지만, 임시로 0 반환
        0
    }

    public var lastReconciliation: Date? {
        // 마지막 reconciliation 시간
        state.lastStatusDate
    }

    // MARK: - Bolus Speed Setting

    public func setBolusSpeed(_ speed: UInt8, completion: @escaping (Error?) -> Void) {
        let clampedSpeed = min(max(speed, 1), 8)
        log.info("setBolusSpeed: \(clampedSpeed)")

        pumpQueue.async { [weak self] in
            guard let self else { return }
            do {
                guard let responseData = try self.bluetooth.sendPacket(
                    msgType: DiaconnPacketType.BOLUS_SPEED_SETTING,
                    payload: Data([clampedSpeed])
                ) else { throw DiaconnPumpManagerError.communicationFailure }

                guard let response = parseBolusSettingResponse(responseData), response.isSuccess else {
                    throw DiaconnPumpManagerError.communicationFailure
                }

                try self.confirmSettingCommand(
                    reqMsgType: DiaconnPacketType.BOLUS_SPEED_SETTING,
                    otpNumber: response.otpNumber
                )

                self.state.bolusSpeed = clampedSpeed
                self.notifyStateDidChange()
                completion(nil)
            } catch {
                self.log.error("setBolusSpeed failed: \(error)")
                completion(error)
            }
        }
    }

    // MARK: - Sound Setting

    public func setSoundSetting(beepAndAlarm: UInt8, alarmIntensity: UInt8, completion: @escaping (Error?) -> Void) {
        log.info("setSoundSetting: beepAndAlarm=\(beepAndAlarm) alarmIntensity=\(alarmIntensity)")

        pumpQueue.async { [weak self] in
            guard let self else { return }
            do {
                guard let responseData = try self.bluetooth.sendPacket(
                    msgType: DiaconnPacketType.SOUND_SETTING,
                    payload: Data([beepAndAlarm + 1, alarmIntensity + 1])
                ) else { throw DiaconnPumpManagerError.communicationFailure }

                guard let response = parseSoundSettingResponse(responseData), response.isSuccess else {
                    throw DiaconnPumpManagerError.communicationFailure
                }

                try self.confirmSettingCommand(
                    reqMsgType: DiaconnPacketType.SOUND_SETTING,
                    otpNumber: response.otpNumber
                )

                self.state.beepAndAlarm = beepAndAlarm
                self.state.alarmIntensity = alarmIntensity
                self.notifyStateDidChange()
                completion(nil)
            } catch {
                self.log.error("setSoundSetting failed: \(error)")
                completion(error)
            }
        }
    }

    // MARK: - 테스트용 로그 직접 조회

    /// 지정한 범위의 로그를 fetch하고 raw 응답 + 파싱 결과를 반환한다.
    /// 커서 상태는 변경하지 않는 읽기 전용 테스트 도구.
    public func testFetchLogEntries(
        start: UInt16,
        end: UInt16,
        completion: @escaping (Result<(rawResponse: Data, entries: [DiaconnLogEntry]), Error>) -> Void
    ) {
        pumpQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let packet = generateBigLogInquirePacket(start: start, end: end)
                guard let responseData = try self.bluetooth.writeAndWait(packet: packet, timeout: 15.0) else {
                    completion(.failure(DiaconnPumpManagerError.communicationFailure))
                    return
                }
                let entries = parseBigLogInquireResponse(responseData) ?? []
                completion(.success((rawResponse: responseData, entries: entries)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Pump Event Reconciliation

    public func reconcileDoses(completion: @escaping (_ result: PumpManagerResult<[DoseEntry]>) -> Void) {
        log.info("reconcileDoses called")

        pumpQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let entries = try self.fetchNewLogEntries()
                let doses = self.logEntriesToDoses(entries)
                completion(.success(doses))
            } catch {
                self.log.error("reconcileDoses failed: \(error)")
                completion(.failure(.communication(DiaconnPumpManagerError.communicationFailure)))
            }
        }
    }

    /// 펌프에서 마지막 동기화 이후 새 로그를 fetch하고 커서를 업데이트한다.
    private func fetchNewLogEntries() throws -> [DiaconnLogEntry] {
        let pumpLastLogNum = state.pumpLastLogNum
        let pumpWrapCount = state.pumpWrappingCount

        NSLog(
            "[DiaconnKit] fetchNewLogEntries: pumpLast=\(pumpLastLogNum) pumpWrap=\(pumpWrapCount) storedLast=\(state.storedLastLogNum) storedWrap=\(state.storedWrappingCount) isFirst=\(state.isFirstLogSync)"
        )

        // 최초 연결: 현재 위치를 기준점으로 저장
        if state.isFirstLogSync {
            let baseline = pumpLastLogNum >= 2 ? pumpLastLogNum - 2 : 0
            NSLog("[DiaconnKit] First log sync — baseline=\(baseline) wrap=\(pumpWrapCount)")
            state.storedLastLogNum = baseline
            state.storedWrappingCount = pumpWrapCount
            state.isFirstLogSync = false
            notifyStateDidChange()
        }

        // 2. 새 로그가 없으면 skip
        guard pumpLastLogNum != state.storedLastLogNum ||
            pumpWrapCount != state.storedWrappingCount
        else {
            log.info("No new log entries since last sync")
            return []
        }

        // 3. BIG_LOG_INQUIRE: 정상 범위만 동기화 (wrap 발생 시 이전 로그 bulk sync 없이 기준점 리셋)
        let pageSize = 11
        let pumpLast = Int(pumpLastLogNum)
        let pumpWrap = Int(pumpWrapCount)
        let storedLast = Int(state.storedLastLogNum)
        let storedWrap = Int(state.storedWrappingCount)

        // wrap 발생 시: old wrap 나머지(storedLast+1~9999) 동기화 후 새 wrap 기준으로 리셋
        let isWrapSync = pumpWrap > storedWrap
        let startLogNum = storedLast + 1
        let endLogNum = isWrapSync ? 9999 : pumpLast

        if isWrapSync {
            NSLog("[DiaconnKit] BIG_LOG_INQUIRE: wrap sync — \(startLogNum)~9999")
        }

        NSLog(
            "[DiaconnKit] BIG_LOG_INQUIRE: start=\(startLogNum) end=\(endLogNum) (pumpLast=\(pumpLast) pumpWrap=\(pumpWrap) storedLast=\(storedLast) storedWrap=\(storedWrap))"
        )

        // AndroidAPS 공식: size = ceil((end - start) / 11.0)
        let loopSize = Int(ceil(Double(endLogNum - startLogNum) / Double(pageSize)))
        guard loopSize > 0 else {
            NSLog("[DiaconnKit] BIG_LOG_INQUIRE: loopSize=0 — skipping")
            return []
        }

        var allEntries: [DiaconnLogEntry] = []

        for i in 0 ..< loopSize {
            let pageStart = startLogNum + i * pageSize
            let pageEnd = pageStart + min(endLogNum - pageStart, pageSize)
            NSLog("[DiaconnKit] BIG_LOG_INQUIRE page \(i + 1)/\(loopSize): \(pageStart)~\(pageEnd)")

            let packet = generateBigLogInquirePacket(start: UInt16(pageStart), end: UInt16(pageEnd))
            guard let responseData = try bluetooth.writeAndWait(packet: packet, timeout: 15.0) else {
                throw DiaconnPumpManagerError.communicationFailure
            }

            guard let entries = parseBigLogInquireResponse(responseData) else {
                log.error("fetchNewLogEntries: parseBigLogInquireResponse returned nil for page \(pageStart)~\(pageEnd)")
                throw DiaconnPumpManagerError.communicationFailure
            }

            allEntries.append(contentsOf: entries)

            if let last = entries.last {
                state.storedLastLogNum = last.logNum
                // wrapCount는 엔트리별 값이 아닌 펌프 현재 값 사용 (옛날 로그의 wrap이 다를 수 있음)
                state.storedWrappingCount = pumpWrapCount
                notifyStateDidChange()
            }
        }

        if isWrapSync {
            state.storedWrappingCount = UInt8(pumpWrap)
            state.storedLastLogNum = 0
            notifyStateDidChange()
            NSLog("[DiaconnKit] BIG_LOG_INQUIRE: wrap sync done — reset to wrap=\(pumpWrap) logNum=0")
        }

        log.info("Fetched \(allEntries.count) new log entries")
        return allEntries
    }

    /// DiaconnLogEntry 배열을 LoopKit DoseEntry 배열로 변환
    private func logEntriesToDoses(_ entries: [DiaconnLogEntry]) -> [DoseEntry] {
        entries.compactMap { entry -> DoseEntry? in
            let date = entry.date
            switch entry.logKind {
            case .mealBolusFail,
                 .mealBolusSuccess,
                 .normalBolusFail,
                 .normalBolusSuccess:
                guard entry.injectAmount > 0 else { return nil }
                return DoseEntry(
                    type: .bolus,
                    startDate: date,
                    endDate: date,
                    value: entry.injectAmount,
                    unit: .units
                )
            case .squareBolusFail,
                 .squareBolusSuccess:
                guard entry.injectAmount > 0 else { return nil }
                let sqDur = TimeInterval(entry.injectTimeUnit * 10 * 60)
                return DoseEntry(
                    type: .bolus,
                    startDate: date,
                    endDate: date.addingTimeInterval(sqDur),
                    value: entry.injectAmount,
                    unit: .units
                )
            case .dualNormal:
                guard entry.injectAmount > 0 else { return nil }
                return DoseEntry(type: .bolus, startDate: date, endDate: date, value: entry.injectAmount, unit: .units)
            case .dualBolusFail,
                 .dualBolusSuccess:
                guard entry.injectAmount > 0 else { return nil }
                let dualSqDur = TimeInterval(entry.injectTimeUnit * 10 * 60)
                return DoseEntry(
                    type: .bolus,
                    startDate: date,
                    endDate: date.addingTimeInterval(dualSqDur),
                    value: entry.injectAmount,
                    unit: .units
                )
            case .tbStart:
                let duration = TimeInterval(entry.tbTime * 15 * 60)
                let rate = tbAbsoluteRate(rawRatio: entry.tbRateRatio)
                return DoseEntry(
                    type: .tempBasal,
                    startDate: date,
                    endDate: date.addingTimeInterval(duration),
                    value: rate,
                    unit: .unitsPerHour
                )
            case .suspend:
                return DoseEntry(type: .suspend, startDate: date, value: 0, unit: .unitsPerHour)
            case .suspendRelease:
                return DoseEntry(type: .resume, startDate: date, value: 0, unit: .unitsPerHour)
            default:
                return nil
            }
        }
    }

    /// AndroidAPS getTbInjectRateRatio 인코딩을 절대값 U/h로 변환
    private func tbAbsoluteRate(rawRatio: UInt16) -> Double {
        let ratio = Int(rawRatio)
        if ratio >= 50000 {
            // 퍼센트 모드: (ratio - 50000)% of 현재 기저량
            let percent = Double(ratio - 50000) / 100.0
            return currentBaseBasalRate * percent
        } else if ratio >= 1000 {
            // 절대값 모드: (ratio - 1000) / 100.0 U/h
            return Double(ratio - 1000) / 100.0
        }
        return 0
    }

    /// 펌프 로그를 조회하여 Trio에 hasNewPumpEvents로 전달한다.
    func syncLogHistory() {
        pumpQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                // 경량 로그 상태 조회 (0x56) → pumpLastLogNum/wrappingCount 갱신
                if let logStatusData = try self.bluetooth.sendPacket(
                    msgType: DiaconnPacketType.LOG_STATUS_INQUIRE,
                    timeout: 10.0
                ), let logStatus = parseLogStatusResponse(logStatusData) {
                    self.state.pumpLastLogNum = logStatus.lastLogNum
                    self.state.pumpWrappingCount = logStatus.wrappingCount
                }

                let entries = try self.fetchNewLogEntries()
                guard !entries.isEmpty else { return }

                let events = self.logEntriesToPumpEvents(entries)
                NSLog("[DiaconnKit] syncLogHistory: \(entries.count) entries → \(events.count) events")
                for event in events {
                    let doseDesc = event.dose.map { d -> String in
                        let amount = d.deliveredUnits.map { "\($0)U delivered" } ?? "\(d.type)"
                        return "doseType=\(d.type) \(amount) start=\(d.startDate) end=\(d.endDate)"
                    } ?? "no dose"
                    NSLog("[DiaconnKit]   event: title=\(event.title) eventType=\(String(describing: event.type)) \(doseDesc)")
                }
                guard !events.isEmpty else { return }

                let now = Date()
                self.pumpDelegate.notify { delegate in
                    guard let delegate = delegate else { return }
                    delegate.pumpManager(
                        self,
                        hasNewPumpEvents: events,
                        lastReconciliation: now,
                        replacePendingEvents: false
                    ) { error in
                        if let error = error {
                            NSLog("[DiaconnKit] syncLogHistory: hasNewPumpEvents error: \(error)")
                        } else {
                            NSLog("[DiaconnKit] syncLogHistory: hasNewPumpEvents stored OK")
                        }
                    }
                }
            } catch {
                self.log.error("syncLogHistory failed: \(error)")
            }
        }
    }

    /// DiaconnLogEntry 배열을 LoopKit NewPumpEvent 배열로 변환
    private func logEntriesToPumpEvents(_ entries: [DiaconnLogEntry]) -> [NewPumpEvent] {
        entries.compactMap { entry -> NewPumpEvent? in
            let date = entry.date
            var rawBytes = Data()
            rawBytes.append(entry.wrapCount)
            rawBytes.appendShortLE(entry.logNum)

            switch entry.logKind {
            case .mealBolusFail,
                 .mealBolusSuccess:
                // 펌프에서 식사 버튼으로 수동 주입 → Bolus
                guard entry.injectAmount > 0 else { return nil }
                let mealDose = DoseEntry(
                    type: .bolus,
                    startDate: date,
                    endDate: date,
                    value: entry.injectAmount,
                    unit: .units,
                    automatic: false
                )
                return NewPumpEvent(date: date, dose: mealDose, raw: rawBytes, title: "Bolus")
            case .normalBolusFail,
                 .normalBolusSuccess:
                guard entry.injectAmount > 0 else { return nil }
                let isAutomatic = state.lastBolusAutomatic
                let normalDose = DoseEntry(
                    type: .bolus,
                    startDate: date,
                    endDate: date,
                    value: entry.injectAmount,
                    unit: .units,
                    automatic: isAutomatic
                )
                return NewPumpEvent(date: date, dose: normalDose, raw: rawBytes, title: isAutomatic ? "SMB" : "Bolus")
            case .squareBolusFail,
                 .squareBolusSuccess:
                // 스퀘어 완료/취소: 실제 주입량
                guard entry.injectAmount > 0 else { return nil }
                let sqDuration = TimeInterval(entry.injectTimeUnit * 10 * 60)
                let sqDose = DoseEntry(
                    type: .bolus,
                    startDate: date,
                    endDate: date.addingTimeInterval(sqDuration),
                    value: entry.injectAmount,
                    unit: .units,
                    automatic: false
                )
                return NewPumpEvent(date: date, dose: sqDose, raw: rawBytes, title: "Extended Bolus")
            case .dualNormal:
                // 듀얼 일반주입 결과
                guard entry.injectAmount > 0 else { return nil }
                let dualNormDose = DoseEntry(
                    type: .bolus,
                    startDate: date,
                    endDate: date,
                    value: entry.injectAmount,
                    unit: .units,
                    automatic: false
                )
                return NewPumpEvent(date: date, dose: dualNormDose, raw: rawBytes, title: "Dual Bolus")
            case .dualBolusFail,
                 .dualBolusSuccess:
                // 듀얼 스퀘어 부분 완료/취소: 실제 주입량
                guard entry.injectAmount > 0 else { return nil }
                let dualSqDuration = TimeInterval(entry.injectTimeUnit * 10 * 60)
                let dualSqDose = DoseEntry(
                    type: .bolus,
                    startDate: date,
                    endDate: date.addingTimeInterval(dualSqDuration),
                    value: entry.injectAmount,
                    unit: .units,
                    automatic: false
                )
                return NewPumpEvent(date: date, dose: dualSqDose, raw: rawBytes, title: "Dual Extended Bolus")
            case .tbStart:
                let duration = TimeInterval(entry.tbTime * 15 * 60)
                let rate = tbAbsoluteRate(rawRatio: entry.tbRateRatio)
                let dose = DoseEntry(
                    type: .tempBasal,
                    startDate: date,
                    endDate: date.addingTimeInterval(duration),
                    value: rate,
                    unit: .unitsPerHour,
                    automatic: true
                )
                return NewPumpEvent(date: date, dose: dose, raw: rawBytes, title: "Temp Basal")
            case .suspend:
                let dose = DoseEntry(type: .suspend, startDate: date, value: 0, unit: .unitsPerHour)
                return NewPumpEvent(date: date, dose: dose, raw: rawBytes, title: "Suspend")
            case .suspendRelease:
                let dose = DoseEntry(type: .resume, startDate: date, value: 0, unit: .unitsPerHour)
                return NewPumpEvent(date: date, dose: dose, raw: rawBytes, title: "Resume")
            case .changeInjector:
                return NewPumpEvent(date: date, dose: nil, raw: rawBytes, title: "Insulin Change", type: .rewind)
            case .changeTube:
                return NewPumpEvent(date: date, dose: nil, raw: rawBytes, title: "Tube Prime", type: .prime)
            case .changeNeedle:
                return NewPumpEvent(date: date, dose: nil, raw: rawBytes, title: "Cannula Change", type: .prime)
            case .alarmBattery:
                return NewPumpEvent(date: date, dose: nil, raw: rawBytes, title: "Battery Low", type: .alarm)
            case .alarmBlock:
                return NewPumpEvent(date: date, dose: nil, raw: rawBytes, title: "Injection Blocked", type: .alarm)
            case .alarmShortAge:
                return NewPumpEvent(date: date, dose: nil, raw: rawBytes, title: "Insulin Low", type: .alarm)
            case .resetSys:
                return NewPumpEvent(date: date, dose: nil, raw: rawBytes, title: "Pump Reset", type: .alarm)
            default:
                return nil
            }
        }
    }
}

// MARK: - Bolus Notifications

extension DiaconnPumpManager {
    func notifyBolusDone(deliveredUnits: Double) {
        state.bolusState = .noBolus
        state.lastBolusAmount = deliveredUnits
        state.lastBolusDate = Date()
        state.deliveredUnits = nil
        state.totalUnits = nil
        doseReporter?.notify(deliveredUnits: deliveredUnits, done: true)
        doseReporter = nil
        notifyStateDidChange()
        syncLogHistory()
    }

    func notifyBolusDidUpdate(deliveredUnits: Double) {
        state.deliveredUnits = deliveredUnits
        doseReporter?.notify(deliveredUnits: deliveredUnits, done: false)
    }

    func notifyBolusError() {
        state.bolusState = .noBolus
        state.deliveredUnits = nil
        state.totalUnits = nil
        doseReporter = nil
        notifyStateDidChange()
    }
}

// MARK: - Deactivation

public extension DiaconnPumpManager {
    func notifyDelegateOfDeactivation(completion: @escaping () -> Void) {
        bluetooth.disconnect()
        pumpDelegate.notify { delegate in
            guard let delegate = delegate else {
                completion()
                return
            }
            delegate.pumpManagerWillDeactivate(self)
            completion()
        }
    }
}

// MARK: - AlertResponder

public extension DiaconnPumpManager {
    func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        // 디아콘 G8 알림 확인 처리
        log.info("Acknowledging alert: \(alertIdentifier)")

        // 현재는 알림을 바로 확인 완료 처리
        // 필요시 펌프에 앱 확인(APP_CONFIRM_SETTING) 명령 전송 가능
        completion(nil)
    }
}

// MARK: - AlertSoundVendor

public extension DiaconnPumpManager {
    func getSoundBaseURL() -> URL? {
        // 디아콘 G8은 커스텀 사운드를 제공하지 않음
        nil
    }

    func getSounds() -> [Alert.Sound] {
        // 디아콘 G8은 시스템 기본 사운드 사용
        []
    }
}
