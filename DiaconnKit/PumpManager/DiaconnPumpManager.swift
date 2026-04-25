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
    public internal(set) var activeAlert: DiaconnPumpManagerAlert?

    private let log = DiaconnLogger(category: "DiaconnPumpManager")
    private let pumpQueue = DispatchQueue(label: "com.diaconkit.pumpmanager", qos: .userInitiated)
    private let backgroundTask = DiaconnBackgroundTask()
    private let cloudUploader = DiaconnCloudUploader()
    private var cloudSyncTask: Task<Void, Never>?

    // MARK: - Init

    init(state: DiaconnPumpManagerState) {
        self.state = state
        oldState = DiaconnPumpManagerState(rawValue: state.rawValue)
        bluetooth = DiaconnBluetoothManager()
        bluetooth.pumpManager = self

        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(appMovedToBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(appMovedToForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appMovedToBackground() {
        log.info("App moved to background — starting silent audio")
        backgroundTask.start()
    }

    @objc private func appMovedToForeground() {
        backgroundTask.stop()
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
            timeZone: state.pumpTimeZone,
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
            // Create from current bolus info instead of DoseEntry
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
        guard newState != old else { return }
        oldState = newState

        let status = self.status
        let oldStatus = PumpManagerStatus(
            timeZone: old.pumpTimeZone,
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

    // MARK: - Two-step commit (OTP confirm)

    /// Send OTP confirm after setting command + wait for pump's 0xAA response
    /// If response is not consumed, next sendPacket may incorrectly receive 0xAA
    private func confirmSettingCommand(reqMsgType: UInt8, otpNumber: UInt32) throws {
        let confirmPacket = generateAppConfirmPacket(reqMsgType: reqMsgType, otpNumber: otpNumber)
        log.info("OTP confirm sending: reqMsgType=0x\(String(format: "%02X", reqMsgType)) otp=\(otpNumber)")

        guard let responseData = try bluetooth.writeAndWait(packet: confirmPacket) else {
            log.error("OTP confirm: no response (timeout)")
            throw DiaconnPumpManagerError.communicationFailure
        }

        // Verify 0xAA response
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

    // MARK: - Pump Identity Check

    /// Detect pump replacement or factory reset via serial number and incarnation.
    /// Must be called on pumpQueue.
    private func checkPumpIdentity() {
        // Query incarnation
        var currentIncarnation: UInt16 = state.syncedIncarnation
        if let incarnationData = try? bluetooth.sendPacket(
            msgType: DiaconnPacketType.INCARNATION_INQUIRE,
            timeout: 10.0
        ), let incarnation = parseIncarnationResponse(incarnationData) {
            currentIncarnation = incarnation
            log.info("Incarnation: \(incarnation) (synced: \(state.syncedIncarnation))")
        } else {
            log.error("Incarnation inquiry failed, skipping identity check")
            return
        }

        let serialChanged = state.syncedSerialNumber != nil
            && state.serialNumber != nil
            && state.serialNumber != state.syncedSerialNumber
        let incarnationChanged = state.syncedIncarnation != 0
            && currentIncarnation != state.syncedIncarnation

        if serialChanged || incarnationChanged {
            let reason = serialChanged ? "serial changed" : "incarnation changed"
            log.info("Pump \(reason), resetting log cursor")
            state.storedLastLogNum = 0
            state.storedWrappingCount = 0
            state.isFirstLogSync = true
        }

        // Update synced identifiers
        if let serial = state.serialNumber {
            state.syncedSerialNumber = serial
        }
        state.syncedIncarnation = currentIncarnation
    }

    // MARK: - Time Synchronization

    /// Check if time sync is needed (>60s drift, skip only during bolus)
    private func shouldSyncTime() -> Bool {
        guard state.bolusState == .noBolus else { return false }
        return isClockOffset
    }

    /// Cancel temp basal if running, so that time setting can proceed.
    /// Must be called on pumpQueue.
    private func cancelTempBasalForTimeSync() {
        guard state.isTempBasalInProgress else { return }
        log.info("syncTime: cancelling temp basal before time sync")
        do {
            let cancelPacket = generateTempBasalCancelPacket()
            guard let cancelResp = try bluetooth.writeAndWait(packet: cancelPacket),
                  let parsed = parseTempBasalSettingResponse(cancelResp), parsed.isSuccess
            else {
                log.error("syncTime: temp basal cancel failed")
                return
            }
            try confirmSettingCommand(
                reqMsgType: DiaconnPacketType.TEMP_BASAL_SETTING,
                otpNumber: parsed.otpNumber
            )
            state.isTempBasalInProgress = false
            state.tempBasalUnits = nil
            state.tempBasalDuration = nil
            state.basalDeliveryOrdinal = .active
            notifyStateDidChange()
            log.info("syncTime: temp basal cancelled successfully")
            Thread.sleep(forTimeInterval: 0.5)
        } catch {
            log.error("syncTime: temp basal cancel error: \(error)")
        }
    }

    /// Sync pump clock to current system time (skip during bolus, cancel temp basal first)
    /// Must be called on pumpQueue
    private func syncTimeOnQueue() {
        guard state.bolusState == .noBolus else {
            log.info("syncTime skipped: bolus in progress")
            return
        }

        // Pump rejects time setting while temp basal is running — cancel it first
        cancelTempBasalForTimeSync()

        do {
            let packet = generateTimeSettingPacket(date: Date())
            log.info("syncTime: sending TIME_SETTING (0x0F)")

            guard let responseData = try bluetooth.writeAndWait(packet: packet) else {
                throw DiaconnPumpManagerError.communicationFailure
            }

            guard let response = parseTimeSettingResponse(responseData), response.isSuccess else {
                throw DiaconnPumpManagerError.communicationFailure
            }

            try confirmSettingCommand(
                reqMsgType: DiaconnPacketType.TIME_SETTING,
                otpNumber: response.otpNumber
            )

            state.pumpTime = Date()
            state.pumpTimeSyncedAt = Date()
            state.pumpTimeZone = TimeZone.current
            notifyStateDidChange()
            log.info("syncTime: success")
        } catch {
            log.error("syncTime failed: \(error)")
        }
    }

    /// Public wrapper for external callers
    public func syncTime(completion: @escaping (Error?) -> Void) {
        pumpQueue.async { [weak self] in
            self?.syncTimeOnQueue()
            completion(nil)
        }
    }

    // MARK: - Pump status inquiry

    /// BigAPSMainInfoInquire (0x54) → update full status from 182-byte response
    func fetchPumpStatus(completion: @escaping (Result<DiaconnPumpStatus, Error>) -> Void) {
        pumpQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                self.log.info("[fetchPumpStatus] Sending BigAPSMainInfoInquire (0x54)...")

                // Request is standard 20-byte packet, response is 182-byte big packet
                guard let responseData = try self.bluetooth.sendPacket(
                    msgType: DiaconnPacketType.BIG_APS_MAIN_INFO_INQUIRE,
                    timeout: 15.0
                ) else {
                    self.log.error("[fetchPumpStatus] No response (timeout or nil)")
                    completion(.failure(DiaconnPumpManagerError.communicationFailure))
                    return
                }

                self.log.info("[fetchPumpStatus] Response received: \(responseData.count) bytes")

                // Header + first 16 bytes log (considering os_log length limit)
                let headerHex = responseData.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
                self.log.info("[fetchPumpStatus] Header[0..15]: \(headerHex)")

                // Check first byte (SOP) and msgType of response
                if responseData.count >= 2 {
                    let sop = responseData[0]
                    let msgType = responseData[1]
                    self.log
                        .info(
                            "[fetchPumpStatus] SOP=0x\(String(format: "%02X", sop)) msgType=0x\(String(format: "%02X", msgType)) (expected SOP=0xED msgType=0x94)"
                        )
                }

                // Check result byte (offset 4)
                if responseData.count > 4 {
                    let resultByte = responseData[4]
                    self.log.info("[fetchPumpStatus] result byte=\(resultByte) (expected 16=success)")
                }

                // Reservoir/battery raw values (offset 5~7)
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
                    // CRC validation result log
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
                        "  basePauseStatus=\(pumpStatus.basePauseStatus) (1=paused, 2=released/active) isSuspended=\(pumpStatus.isSuspended)"
                    )
                self.log
                    .info(
                        "  tbStatus=\(pumpStatus.tbStatus) (1=temp basal running, 2=released) isTempBasalRunning=\(pumpStatus.isTempBasalRunning)"
                    )
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

                // Delay between commands to avoid otherOperationInProgress from pump
                Thread.sleep(forTimeInterval: 1.0)

                // Detect pump replacement or factory reset (only during 5-min cycle, not every syncLogHistory)
                self.checkPumpIdentity()

                // Auto time sync (>60s drift or timezone change)
                if self.shouldSyncTime() || TimeZone.current != self.state.pumpTimeZone {
                    self.syncTimeOnQueue()
                    Thread.sleep(forTimeInterval: 1.0)
                }

                // Fetch pump logs and store in Trio history
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
        // Diaconn G8 bolus speed: 1~8 (1 = slow, 8 = fast)
        // Default 4: approximately 2 sec/U
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
        // Check time offset between pump and system
        guard let pumpTime = state.pumpTime else { return false }
        let offset = abs(pumpTime.timeIntervalSinceNow)
        return offset > 60 // Consider as offset if difference exceeds 1 minute
    }

    public var supportedBolusVolumes: [Double] {
        // Diaconn G8 minimum bolus is 0.02U; pump rejects 0.01U with parameterError
        stride(from: 0.02, through: max(state.maxBolus, 30.0), by: 0.01).map { $0 }
    }

    public var supportedBasalRates: [Double] {
        // Diaconn G8: max basal 3U/h, temp basal up to 7.5U/h, 0.01U increments
        stride(from: 0.01, through: max(state.maxBasalPerHour, 3.0), by: 0.01).map { $0 }
    }

    public var maximumBasalScheduleEntryCount: Int {
        24
    }

    public var minimumBasalScheduleEntryDuration: TimeInterval {
        TimeInterval(60 * 60) // 1 hour
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

        // If not connected, attempt reconnection using saved bleIdentifier
        // On successful reconnection, fetchPumpStatus is called automatically in didUpdateNotificationStateFor
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
                    // fetchPumpStatus is called automatically in didUpdateNotificationStateFor
                    // Completion callback is handled after fetchPumpStatus
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

        // If already connected, query status immediately
        fetchPumpStatus { [weak self] result in
            switch result {
            case .success:
                self?.log.info("Pump status updated successfully")
                // Time sync now runs inside fetchPumpStatus on pumpQueue, before completion
                completion?(self?.state.lastStatusDate)
            case let .failure(error):
                self?.log.error("Failed to update pump status: \(error)")
                completion?(self?.state.lastStatusDate)
            }
        }
    }

    public func setMustProvideBLEHeartbeat(_: Bool) {
        // Diaconn G8 does not require BLE heartbeat
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

        guard units >= 0.02 else {
            log.info("enactBolus: skipping \(units)U — below minimum 0.02U")
            completion(nil)
            return
        }

        cloudSyncTask?.cancel()
        cloudSyncTask = nil

        state.bolusState = .initiating
        notifyStateDidChange()

        pumpQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // Send bolus command (0x07) + wait for response (receive OTP number)
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

                // 3. Send OTP confirm (two-step commit)
                try self.confirmSettingCommand(
                    reqMsgType: DiaconnPacketType.INJECTION_SNACK_SETTING,
                    otpNumber: response.otpNumber
                )

                // 4. Update status
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
                // Injection cancel (0x2B), reqMsgType = 0x07 (bolus)
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

        cloudSyncTask?.cancel()
        cloudSyncTask = nil

        pumpQueue.async { [weak self] in
            guard let self = self else { return }

            var lastError: Error?
            for attempt in 1 ... 3 {
                do {
                    let packet: Data
                    if unitsPerHour == 0, durationMinutes == 0 {
                        // Cancel temp basal
                        packet = generateTempBasalCancelPacket()
                    } else {
                        // If same as current scheduled basal rate, no temp basal needed
                        let scheduledRate = self.currentBaseBasalRate
                        if abs(unitsPerHour - scheduledRate) < 0.005 {
                            self.log
                                .info(
                                    "enactTempBasal: \(unitsPerHour)U/h == scheduled \(scheduledRate)U/h — skipping TBR"
                                )
                            // If temp basal is already running, cancel it
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

                        // If temp basal is already running, use status=3 stealth mode for seamless change
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

                    // OTP confirm
                    try self.confirmSettingCommand(
                        reqMsgType: DiaconnPacketType.TEMP_BASAL_SETTING,
                        otpNumber: response.otpNumber
                    )

                    // Update status
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

                    // TBR events are recorded via syncLogHistory (pump log based)
                    self.syncLogHistory()

                    completion(nil)
                    return

                } catch let diaconnError as DiaconnPumpManagerError {
                    if case let .settingFailed(result) = diaconnError,
                       result == .otherOperationInProgress,
                       attempt < 3
                    {
                        self.log.info("enactTempBasal: pump busy, retrying (\(attempt)/3)...")
                        Thread.sleep(forTimeInterval: 2.0)
                        lastError = diaconnError
                        continue
                    }
                    lastError = diaconnError
                    break
                } catch {
                    lastError = error
                    break
                }
            }

            self.log.error("enactTempBasal failed: \(String(describing: lastError))")
            let pumpError: DiaconnPumpManagerError
            if let diaconnError = lastError as? DiaconnPumpManagerError {
                pumpError = diaconnError
            } else {
                pumpError = .unknown(lastError?.localizedDescription ?? "Unknown")
            }
            completion(.communication(pumpError))
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
                // Split 24-hour profile into 4 groups for transmission
                let packets = generateFullBasalProfile(
                    pattern: self.state.basalPattern,
                    hourlyRates: basalSchedule
                )

                guard let writeChar = self.bluetooth.writeCharacteristic else {
                    throw DiaconnPumpManagerError.notConnected
                }

                // Send all packets except the last one first
                for packet in packets.dropLast() {
                    self.bluetooth.peripheral?.writeValue(packet, for: writeChar, type: .withoutResponse)
                    Thread.sleep(forTimeInterval: 0.2)
                }

                // Send last packet + wait for response
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
        // Diaconn G8 manages limits on pump itself (queried via BigAPSMainInfo)
        completion(.success(deliveryLimits))
    }

    public func roundToSupportedBolusVolume(units: Double) -> Double {
        // 0.01U increments (amount * 100 → short)
        (units * 100).rounded() / 100
    }

    public func roundToSupportedBasalRate(unitsPerHour: Double) -> Double {
        // 0.01U/hr increments
        (unitsPerHour * 100).rounded() / 100
    }

    // MARK: - Additional PumpManager Requirements

    public var pumpRecordsBasalProfileStartEvents: Bool {
        // Diaconn G8 does not log basal profile start events
        false
    }

    public var pumpReservoirCapacity: Double {
        // Diaconn G8 reservoir capacity (300U)
        300
    }

    public func estimatedUnitsDelivered(since _: Date) -> Double {
        // Estimated insulin delivered since start time
        // Actual implementation should query pump logs, returning 0 temporarily
        0
    }

    public var lastReconciliation: Date? {
        // Last reconciliation time
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

    // MARK: - Direct log inquiry for testing

    /// Fetch logs in the specified range and return raw response + parsed results.
    /// Read-only test tool that does not modify cursor state.
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

    /// Fetch new logs since last sync from pump and update cursor.
    private func fetchNewLogEntries() throws -> [DiaconnLogEntry] {
        let pumpLastLogNum = state.pumpLastLogNum
        let pumpWrapCount = state.pumpWrappingCount

        NSLog(
            "[DiaconnKit] fetchNewLogEntries: pumpLast=\(pumpLastLogNum) pumpWrap=\(pumpWrapCount) storedLast=\(state.storedLastLogNum) storedWrap=\(state.storedWrappingCount) isFirst=\(state.isFirstLogSync)"
        )

        // First connection: save current position as baseline
        if state.isFirstLogSync {
            let baseline = pumpLastLogNum >= 2 ? pumpLastLogNum - 2 : 0
            NSLog("[DiaconnKit] First log sync — baseline=\(baseline) wrap=\(pumpWrapCount)")
            state.storedLastLogNum = baseline
            state.storedWrappingCount = pumpWrapCount
            state.isFirstLogSync = false
            notifyStateDidChange()
        }

        // 2. Skip if no new logs
        guard pumpLastLogNum != state.storedLastLogNum ||
            pumpWrapCount != state.storedWrappingCount
        else {
            log.info("No new log entries since last sync")
            return []
        }

        // 3. BIG_LOG_INQUIRE: sync only normal range (on wrap, reset baseline without bulk syncing old logs)
        let pageSize = 11
        let pumpLast = Int(pumpLastLogNum)
        let pumpWrap = Int(pumpWrapCount)
        let storedLast = Int(state.storedLastLogNum)
        let storedWrap = Int(state.storedWrappingCount)

        // On wrap: sync remainder of old wrap (storedLast+1~9999) then reset to new wrap baseline
        let isWrapSync = pumpWrap > storedWrap
        let startLogNum = storedLast + 1
        let endLogNum = isWrapSync ? 9999 : pumpLast

        if isWrapSync {
            NSLog("[DiaconnKit] BIG_LOG_INQUIRE: wrap sync — \(startLogNum)~9999")
        }

        NSLog(
            "[DiaconnKit] BIG_LOG_INQUIRE: start=\(startLogNum) end=\(endLogNum) (pumpLast=\(pumpLast) pumpWrap=\(pumpWrap) storedLast=\(storedLast) storedWrap=\(storedWrap))"
        )

        // AndroidAPS formula: size = ceil((end - start) / 11.0)
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
                // Use pump's current wrapCount, not per-entry value (old logs may have different wrap)
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

    /// Convert DiaconnLogEntry array to LoopKit DoseEntry array
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

    /// Convert AndroidAPS getTbInjectRateRatio encoding to absolute U/h
    private func tbAbsoluteRate(rawRatio: UInt16) -> Double {
        let ratio = Int(rawRatio)
        if ratio >= 50000 {
            // Percent mode: (ratio - 50000)% of current basal rate
            let percent = Double(ratio - 50000) / 100.0
            return currentBaseBasalRate * percent
        } else if ratio >= 1000 {
            // Absolute mode: (ratio - 1000) / 100.0 U/h
            return Double(ratio - 1000) / 100.0
        }
        return 0
    }

    /// Query pump logs and deliver to Trio via hasNewPumpEvents.
    func syncLogHistory() {
        pumpQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                // Lightweight log status inquiry (0x56) → update pumpLastLogNum/wrappingCount
                if let logStatusData = try self.bluetooth.sendPacket(
                    msgType: DiaconnPacketType.LOG_STATUS_INQUIRE,
                    timeout: 10.0
                ), let logStatus = parseLogStatusResponse(logStatusData) {
                    self.state.pumpLastLogNum = logStatus.lastLogNum
                    self.state.pumpWrappingCount = logStatus.wrappingCount
                }

                let entries = try self.fetchNewLogEntries()

                // Detect device lifecycle events from log entries
                for entry in entries {
                    switch entry.logKind {
                    case .changeInjector:
                        self.state.reservoirDate = entry.date
                    case .changeNeedle:
                        self.state.cannulaDate = entry.date
                    case .resetSys:
                        self.state.batteryDate = entry.date
                    default:
                        break
                    }
                }

                if !entries.isEmpty {
                    let events = self.logEntriesToPumpEvents(entries)
                    NSLog("[DiaconnKit] syncLogHistory: \(entries.count) entries → \(events.count) events")
                    for event in events {
                        let doseDesc = event.dose.map { d -> String in
                            let amount = d.deliveredUnits.map { "\($0)U delivered" } ?? "\(d.type)"
                            return "doseType=\(d.type) \(amount) start=\(d.startDate) end=\(d.endDate)"
                        } ?? "no dose"
                        NSLog(
                            "[DiaconnKit]   event: title=\(event.title) eventType=\(String(describing: event.type)) \(doseDesc)"
                        )
                    }
                    if !events.isEmpty {
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
                    }
                }
            } catch {
                self.log.error("syncLogHistory failed: \(error)")
            }

            if self.state.cloudLogSyncEnabled {
                self.cloudSyncTask = Task { [weak self] in await self?.syncCloudLogHistory() }
            }
        }
    }

    // MARK: - Cloud Log Sync

    private func syncCloudLogHistory() async {
        guard state.cloudLogSyncEnabled,
              !state.isCloudSyncing,
              let pumpUid = state.serialNumber,
              let pumpVersion = state.firmwareVersion
        else { return }

        let incarnationNum = Int(state.syncedIncarnation)
        let pumpLastNum = Int(state.pumpLastLogNum)
        let pumpWrappingCount = Int(state.pumpWrappingCount)

        do {
            let platformLastNo = try await cloudUploader.getPumpLastNo(
                pumpUid: pumpUid,
                pumpVersion: pumpVersion,
                incarnationNum: incarnationNum
            )
            NSLog(
                "[DiaconnKit] syncCloudLogHistory: platformLastNo=\(platformLastNo) pumpLast=\(pumpLastNum) pumpWrap=\(pumpWrappingCount)"
            )

            let platformWrappingCount = platformLastNo < 0 ? 0 : Int(platformLastNo / 10000)
            let platformLogNo = platformLastNo == -1 ? 9999 : Int(platformLastNo % 10000)

            state.cloudSyncedIncarnation = UInt16(incarnationNum)
            state.cloudLastWrapCount = platformWrappingCount
            state.cloudLastLogNum = platformLastNo == -1 ? 0 : Int(platformLastNo % 10000)
            notifyStateDidChange()

            let (start, end, loopSize) = cloudLogLoopCount(
                platformLastNo: Int(platformLastNo),
                platformLogNo: platformLogNo,
                platformWrappingCount: platformWrappingCount,
                pumpLastNum: pumpLastNum,
                pumpWrappingCount: pumpWrappingCount
            )

            guard loopSize > 0 else {
                NSLog("[DiaconnKit] syncCloudLogHistory: no new logs to upload")
                return
            }

            NSLog("[DiaconnKit] syncCloudLogHistory: uploading \(loopSize) pages start=\(start) end=\(end)")

            state.isCloudSyncing = true
            state.cloudSyncCurrentPage = 0
            state.cloudSyncTotalPages = loopSize
            notifyStateDidChange()

            let appUid = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString ?? "" }
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
            let pageSize = 11

            for i in 0 ..< loopSize {
                guard !Task.isCancelled else {
                    NSLog("[DiaconnKit] syncCloudLogHistory: cancelled at page \(i + 1)/\(loopSize)")
                    break
                }

                let pageStart = start + i * pageSize
                let pageEnd = min(pageStart + pageSize, end)

                let entries = try await fetchLogsForCloudRange(start: UInt16(pageStart), end: UInt16(pageEnd))
                guard !entries.isEmpty else { continue }

                let pumpLogs = entries.map { entry in
                    DiaconnPumpLog(
                        pumplog_no: Int64(entry.logNum),
                        pumplog_wrapping_count: Int(entry.wrapCount),
                        pumplog_data: entry.logDataBytes.hexString,
                        act_type: "1"
                    )
                }

                let dto = DiaconnPumpLogDto(
                    app_uid: appUid,
                    app_version: appVersion,
                    pump_uid: pumpUid,
                    pump_version: pumpVersion,
                    incarnation_num: incarnationNum,
                    pumplog_info: pumpLogs
                )

                let success = try await cloudUploader.uploadPumpLogs(dto: dto)
                NSLog(
                    "[DiaconnKit] syncCloudLogHistory: page \(i + 1)/\(loopSize) (\(pageStart)~\(pageEnd), \(entries.count) entries) ok=\(success)"
                )
                if !success { break }

                if let lastEntry = entries.last {
                    state.cloudLastLogNum = Int(lastEntry.logNum)
                    state.cloudLastWrapCount = Int(lastEntry.wrapCount)
                }
                state.cloudSyncCurrentPage = i + 1
                // Notify UI every 10 pages to avoid flooding main thread
                if (i + 1) % 10 == 0 {
                    notifyStateDidChange()
                }
            }

            state.isCloudSyncing = false
            notifyStateDidChange()
        } catch {
            NSLog("[DiaconnKit] syncCloudLogHistory error: \(error)")
            state.isCloudSyncing = false
            notifyStateDidChange()
        }
    }

    private func fetchLogsForCloudRange(start: UInt16, end: UInt16) async throws -> [DiaconnLogEntry] {
        try await withCheckedThrowingContinuation { continuation in
            pumpQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: DiaconnPumpManagerError.communicationFailure)
                    return
                }
                do {
                    let packet = generateBigLogInquirePacket(start: start, end: end)
                    guard let responseData = try self.bluetooth.writeAndWait(packet: packet, timeout: 15.0) else {
                        throw DiaconnPumpManagerError.communicationFailure
                    }
                    let entries = parseBigLogInquireResponse(responseData) ?? []
                    continuation.resume(returning: entries)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func cloudLogLoopCount(
        platformLastNo: Int,
        platformLogNo: Int,
        platformWrappingCount: Int,
        pumpLastNum: Int,
        pumpWrappingCount: Int
    ) -> (start: Int, end: Int, size: Int) {
        let start: Int
        let end: Int

        if pumpWrappingCount * 10000 + pumpLastNum - platformLastNo > 10000 {
            start = pumpLastNum
            end = 10000
        } else if pumpWrappingCount > platformWrappingCount, platformLogNo < 9999 {
            start = platformLogNo + 1
            end = 10000
        } else if pumpWrappingCount > platformWrappingCount, platformLogNo >= 9999 {
            start = 0
            end = pumpLastNum
        } else {
            start = platformLogNo + 1
            end = pumpLastNum
        }

        let size = max(0, Int(ceil(Double(end - start) / 11.0)))
        return (start, end, size)
    }

    /// Convert DiaconnLogEntry array to LoopKit NewPumpEvent array
    private func logEntriesToPumpEvents(_ entries: [DiaconnLogEntry]) -> [NewPumpEvent] {
        entries.compactMap { entry -> NewPumpEvent? in
            let date = entry.date
            var rawBytes = Data()
            rawBytes.append(entry.wrapCount)
            rawBytes.appendShortLE(entry.logNum)

            switch entry.logKind {
            case .mealBolusFail,
                 .mealBolusSuccess:
                // Manual injection via meal button on pump → Bolus
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
                // Square complete/cancel: actual injected amount
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
                // Dual normal injection result
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
                // Dual square partial complete/cancel: actual injected amount
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

    func notifyBolusDidUpdate(deliveredUnits: Double, setAmount: Double? = nil) {
        if let setAmount = setAmount, setAmount > 0 {
            state.totalUnits = setAmount
            doseReporter?.totalUnits = setAmount
        }
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

    func notifyBasalSuspended() {
        state.isPumpSuspended = true
        state.basalDeliveryOrdinal = .suspended
        state.basalDeliveryDate = Date()
        notifyStateDidChange()
    }

    func notifyBasalResumed() {
        state.isPumpSuspended = false
        state.basalDeliveryOrdinal = .active
        state.basalDeliveryDate = Date()
        notifyStateDidChange()
    }

    /// Notify alert (for pump-originated report packets)
    func notifyAlert(_ alert: DiaconnPumpManagerAlert) {
        activeAlert = alert
        log.info("notifyAlert: set activeAlert=\(alert.identifier)")
        notifyStateDidChange()

        let identifier = Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: alert.identifier)
        let loopAlert = Alert(
            identifier: identifier,
            foregroundContent: alert.foregroundContent,
            backgroundContent: alert.backgroundContent,
            trigger: .immediate
        )

        let events = [NewPumpEvent(
            date: Date.now,
            dose: nil,
            raw: alert.raw,
            title: "Alarm: \(alert.foregroundContent.title)",
            type: .alarm,
            alarmType: alert.type
        )]

        pumpDelegate.notify { delegate in
            guard let delegate = delegate else {
                self.log.error("Alarm could not be reported -> Missing delegate")
                return
            }

            delegate.issueAlert(loopAlert)
            delegate.pumpManager(
                self,
                hasNewPumpEvents: events,
                lastReconciliation: self.state.lastStatusDate,
                replacePendingEvents: false
            ) { error in
                if let error = error {
                    self.log.error("Failed to report pump alarm event: \(error)")
                }
            }
        }
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
        log.info("Acknowledging alert: \(alertIdentifier)")
        // Don't clear activeAlert here — Trio auto-acks immediately.
        // activeAlert is cleared by user action via dismissActiveAlert().
        completion(nil)
    }

    /// Called by user tapping Acknowledge in settings UI
    func dismissActiveAlert() {
        guard let alert = activeAlert else { return }
        log.info("dismissActiveAlert: clearing \(alert.identifier)")
        let identifier = Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: alert.identifier)
        pumpDelegate.notify { delegate in
            delegate?.retractAlert(identifier: identifier)
        }
        activeAlert = nil
        notifyStateDidChange()
    }
}

// MARK: - AlertSoundVendor

public extension DiaconnPumpManager {
    func getSoundBaseURL() -> URL? {
        // Diaconn G8 does not provide custom sounds
        nil
    }

    func getSounds() -> [Alert.Sound] {
        // Diaconn G8 uses system default sounds
        []
    }
}
