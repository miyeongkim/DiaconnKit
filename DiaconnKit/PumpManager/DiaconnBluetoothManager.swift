import CoreBluetooth
import Foundation
public import LoopKit

public enum DiaconnConnectionResult {
    case success
    case failure(Error)
    case timeout
}

public struct DiaconnPumpScan {
    public let bleIdentifier: String
    public let name: String
    public let peripheral: CBPeripheral
}

/// 디아콘 G8 BLE 통신 관리자
/// Nordic UART Service (NUS) 프로토콜 사용
public class DiaconnBluetoothManager: NSObject {
    private let log = DiaconnLogger(category: "BluetoothManager")

    // MARK: - BLE UUIDs (Nordic UART Service)

    /// Indicate/Read: 펌프 → 앱 (NUS TX)
    private let INDICATE_CHAR_UUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")
    /// Write: 앱 → 펌프 (NUS RX)
    private let WRITE_CHAR_UUID = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")

    /// 쓰기 간격 (ms) - AndroidAPS: 50ms
    private let WRITE_DELAY_MS: UInt64 = 50

    private var manager: CBCentralManager!
    private let managerQueue = DispatchQueue(label: "com.diaconkit.bluetooth", qos: .userInitiated)

    weak var pumpManager: DiaconnPumpManager?

    private(set) var peripheral: CBPeripheral?
    private var indicateCharacteristic: CBCharacteristic?
    private(set) var writeCharacteristic: CBCharacteristic?

    public var isConnected: Bool {
        peripheral?.state == .connected
    }

    private var connectionCompletion: ((DiaconnConnectionResult) -> Void)?
    public var devices: [DiaconnPumpScan] = []
    private var pendingScan = false

    private var readBuffer = Data()

    /// 중복 패킷 방지: 마지막으로 처리한 보고 패킷의 seqNo
    private var lastReportSeqNo: UInt8 = 0xFF

    /// 응답 대기를 위한 세마포어
    private let responseSemaphore = DispatchSemaphore(value: 0)
    private var lastResponse: Data?

    /// 테스트/디버그용: 완성된 패킷이 수신될 때마다 호출 (raw bytes)
    public var onRawPacketReceived: ((Data) -> Void)?

    /// 메시지 시퀀스 기반 응답 매칭
    private var pendingResponseHandlers: [UInt8: (Data) -> Void] = [:]

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: managerQueue)
    }

    // MARK: - Scanning

    public func startScan() throws {
        devices = []

        guard manager.state == .poweredOn else {
            // BLE가 아직 준비 안 됐으면 준비되면 자동 시작
            pendingScan = true
            log.info("Bluetooth not ready yet, will scan when powered on")
            return
        }

        guard !manager.isScanning else {
            log.info("Already scanning...")
            return
        }

        pendingScan = false
        manager.scanForPeripherals(withServices: nil)
        log.info("Started scanning for Diaconn G8")
    }

    public func stopScan() {
        manager.stopScan()
        devices = []
        log.info("Stopped scanning")
    }

    // MARK: - Connection

    public func connect(_ bleIdentifier: String, completion: @escaping (DiaconnConnectionResult) -> Void) {
        guard let identifier = UUID(uuidString: bleIdentifier) else {
            completion(.failure(NSError(
                domain: "DiaconnKit",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid BLE identifier"]
            )))
            return
        }

        connectionCompletion = completion

        let peripherals = manager.retrievePeripherals(withIdentifiers: [identifier])
        guard let peripheral = peripherals.first else {
            completion(.failure(NSError(
                domain: "DiaconnKit",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Peripheral not found"]
            )))
            return
        }

        self.peripheral = peripheral
        // autoConnect = false (직접 연결)
        manager.connect(peripheral, options: nil)
    }

    public func disconnect() {
        guard let peripheral = peripheral else { return }
        manager.cancelPeripheralConnection(peripheral)
        self.peripheral = nil
        pumpManager?.state.isConnected = false
        pumpManager?.notifyStateDidChange()
        log.info("Disconnected from Diaconn G8")
    }

    // MARK: - Write Packet

    /// 이전 명령의 응답이 늦게 도착해 세마포어를 미리 signal한 경우를 방어
    private func drainResponseSemaphore() {
        while responseSemaphore.wait(timeout: .now()) == .success {}
        lastResponse = nil
    }

    /// 이미 인코딩된 패킷을 전송하고 응답 대기 (이중 전송 방지용)
    public func writeAndWait(
        packet: Data,
        timeout: TimeInterval = 10.0
    ) throws -> Data? {
        guard let writeCharacteristic = writeCharacteristic else {
            throw NSError(
                domain: "DiaconnKit",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No write characteristic available"]
            )
        }

        let msgType = packet.count > 1 ? packet[1] : 0
        pumpManager?.logDeviceCommunication(
            "TX: \(packet.map { String(format: "%02X", $0) }.joined(separator: " "))",
            type: .send
        )

        drainResponseSemaphore()
        peripheral?.writeValue(packet, for: writeCharacteristic, type: .withoutResponse)

        log.info("[TX] Waiting for response (timeout=\(timeout)s) msgType=0x\(String(format: "%02X", msgType))")
        let result = responseSemaphore.wait(timeout: .now() + timeout)
        if result == .timedOut {
            log.error("[TX] Response timeout for msgType=0x\(String(format: "%02X", msgType))")
            return nil
        }

        log.info("[TX] Response received for msgType=0x\(String(format: "%02X", msgType)) size=\(lastResponse?.count ?? 0)")
        return lastResponse
    }

    /// 20바이트 패킷 전송 및 응답 대기
    public func sendPacket(
        msgType: UInt8,
        msgConEnd: UInt8 = DiaconnPacketType.MSG_CON_END,
        payload: Data? = nil,
        timeout: TimeInterval = 10.0
    ) throws -> Data? {
        guard let writeCharacteristic = writeCharacteristic else {
            throw NSError(
                domain: "DiaconnKit",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No write characteristic available"]
            )
        }

        let packet = DiaconnPacketEncoder.encode(msgType: msgType, msgConEnd: msgConEnd, payload: payload)
        let seq = packet[DiaconnPacketType.MSG_SEQ_LOC]

        pumpManager?.logDeviceCommunication(
            "TX: msgType=\(String(format: "0x%02X", msgType)) seq=\(seq) data=\(packet.map { String(format: "%02X", $0) }.joined(separator: " "))",
            type: .send
        )

        drainResponseSemaphore()

        // WRITE_TYPE_NO_RESPONSE (writeWithoutResponse)
        peripheral?.writeValue(packet, for: writeCharacteristic, type: .withoutResponse)

        // 응답 대기
        log.info("[TX] Waiting for response (timeout=\(timeout)s) msgType=0x\(String(format: "%02X", msgType))")
        let result = responseSemaphore.wait(timeout: .now() + timeout)
        if result == .timedOut {
            log.error("[TX] Response timeout for msgType=0x\(String(format: "%02X", msgType))")
            return nil
        }

        log.info("[TX] Response received for msgType=0x\(String(format: "%02X", msgType)) size=\(lastResponse?.count ?? 0)")
        return lastResponse
    }

    /// 182바이트 대량 패킷 전송
    public func sendBigPacket(
        msgType: UInt8,
        msgConEnd: UInt8 = DiaconnPacketType.MSG_CON_END,
        payload: Data? = nil,
        timeout: TimeInterval = 15.0
    ) throws -> Data? {
        guard let writeCharacteristic = writeCharacteristic else {
            throw NSError(
                domain: "DiaconnKit",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No write characteristic available"]
            )
        }

        let packet = DiaconnPacketEncoder.encodeBig(msgType: msgType, msgConEnd: msgConEnd, payload: payload)

        pumpManager?.logDeviceCommunication(
            "TX(BIG): msgType=\(String(format: "0x%02X", msgType)) len=\(packet.count)",
            type: .send
        )

        drainResponseSemaphore()

        // BLE MTU에 따라 분할 전송
        var offset = 0
        while offset < packet.count {
            let chunkSize = min(20, packet.count - offset)
            let chunk = packet.subdata(in: offset ..< offset + chunkSize)
            peripheral?.writeValue(chunk, for: writeCharacteristic, type: .withoutResponse)
            offset += chunkSize

            // 쓰기 간격 50ms
            if offset < packet.count {
                Thread.sleep(forTimeInterval: Double(WRITE_DELAY_MS) / 1000.0)
            }
        }

        let result = responseSemaphore.wait(timeout: .now() + timeout)
        if result == .timedOut {
            log.error("Response timeout for big msgType=\(String(format: "0x%02X", msgType))")
            return nil
        }

        return lastResponse
    }
}

// MARK: - CBCentralManagerDelegate

extension DiaconnBluetoothManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.info("Bluetooth state: \(central.state.rawValue)")
        if central.state == .poweredOn, pendingScan {
            pendingScan = false
            central.scanForPeripherals(withServices: nil)
            log.info("Started scanning (deferred)")
        }
    }

    public func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData _: [String: Any],
        rssi _: NSNumber
    ) {
        let name = peripheral.name ?? "Unknown"

        guard name.contains("DIACONN") else { return }

        log.info("Discovered Diaconn device: \(name)")

        let device = DiaconnPumpScan(
            bleIdentifier: peripheral.identifier.uuidString,
            name: name,
            peripheral: peripheral
        )
        devices.append(device)

        pumpManager?.stateObservers.forEach { observer in
            observer.deviceScanDidUpdate(device)
        }
    }

    public func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.info("Connected to: \(peripheral.name ?? "Unknown")")
        peripheral.delegate = self
        // 모든 서비스 검색 (NUS 서비스 UUID를 직접 사용할 수도 있음)
        peripheral.discoverServices(nil)
    }

    public func centralManager(_: CBCentralManager, didFailToConnect _: CBPeripheral, error: Error?) {
        log.error("Failed to connect: \(error?.localizedDescription ?? "unknown")")
        connectionCompletion?(.failure(error ?? NSError(domain: "DiaconnKit", code: -1)))
        connectionCompletion = nil
    }

    public func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error _: Error?) {
        log.info("Disconnected: \(peripheral.name ?? "Unknown")")
        pumpManager?.state.isConnected = false
        pumpManager?.notifyStateDidChange()
    }
}

// MARK: - CBPeripheralDelegate

extension DiaconnBluetoothManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            log.error("Service discovery error: \(error!.localizedDescription)")
            connectionCompletion?(.failure(error!))
            return
        }

        // 모든 서비스에서 NUS characteristic 검색
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics([INDICATE_CHAR_UUID, WRITE_CHAR_UUID], for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            log.error("Characteristic discovery error: \(error!.localizedDescription)")
            return
        }

        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == INDICATE_CHAR_UUID {
                indicateCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                log.info("Found indicate characteristic")
            } else if characteristic.uuid == WRITE_CHAR_UUID {
                writeCharacteristic = characteristic
                log.info("Found write characteristic")
            }
        }
    }

    public func peripheral(_: CBPeripheral, didUpdateNotificationStateFor _: CBCharacteristic, error: Error?) {
        guard error == nil else {
            log.error("Notification state error: \(error!.localizedDescription)")
            connectionCompletion?(.failure(error!))
            return
        }

        log.info("Notifications enabled, connection ready")

        // 1.6초 대기 후 연결 완료 (AndroidAPS 기준)
        managerQueue.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self = self else { return }
            self.pumpManager?.state.isConnected = true
            self.pumpManager?.notifyStateDidChange()
            self.connectionCompletion?(.success)
            self.connectionCompletion = nil

            // 연결 직후 펌프 전체 상태 조회 (리저버, 배터리, 기저 등)
            self.log.info("Connection ready — fetching initial pump status")
            self.pumpManager?.fetchPumpStatus { [weak self] result in
                switch result {
                case let .success(status):
                    self?.log.info("Initial pump status OK: reservoir=\(status.remainInsulin)U battery=\(status.remainBattery)%")
                case let .failure(error):
                    self?.log.error("Initial pump status failed: \(error.localizedDescription)")
                }
            }
        }
    }

    public func peripheral(_: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else {
            log.error("Read error: \(error?.localizedDescription ?? "no data")")
            return
        }

        pumpManager?.logDeviceCommunication(
            "RX: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))",
            type: .receive
        )

        processReceivedData(data)
    }

    // MARK: - Response Processing

    private func processReceivedData(_ data: Data) {
        readBuffer.append(data)

        // 패킷 완성 확인
        guard !readBuffer.isEmpty else { return }

        let sop = readBuffer[0]
        let expectedLength: Int
        if sop == DiaconnPacketType.SOP {
            expectedLength = DiaconnPacketType.MSG_LEN
        } else if sop == DiaconnPacketType.SOP_BIG {
            expectedLength = DiaconnPacketType.MSG_LEN_BIG
        } else {
            log.error("[RX] Invalid SOP: 0x\(String(format: "%02X", sop)) — buffer cleared")
            readBuffer = Data()
            return
        }

        log.debug("[RX] buffer \(readBuffer.count)/\(expectedLength) bytes (SOP=0x\(String(format: "%02X", sop)))")

        guard readBuffer.count >= expectedLength else {
            return // 아직 데이터 부족, 계속 수집
        }

        // 패킷 완성 → 검증 및 처리
        let packet = readBuffer.subdata(in: 0 ..< expectedLength)
        readBuffer = readBuffer.subdata(in: expectedLength ..< readBuffer.count)

        let defect = DiaconnPacketDecoder.validatePacket(packet)
        if defect != 0 {
            log.error("[RX] Packet defect=\(defect) (97=len, 98=sop, 99=crc)")
            return
        }

        let msgType = DiaconnPacketDecoder.getMsgType(packet)
        let packetType = DiaconnPacketDecoder.getType(packet)

        log
            .info(
                "[RX] Complete packet: msgType=0x\(String(format: "%02X", msgType)) packetType=\(packetType) size=\(packet.count)"
            )

        // raw 패킷 콜백 (테스트/디버그용)
        onRawPacketReceived?(packet)

        if packetType == 3 {
            // 보고 패킷 (비요청) → 중복 seqNo 무시
            let seqNo = packet[DiaconnPacketType.MSG_SEQ_LOC]
            guard seqNo != lastReportSeqNo else {
                log.info("[RX] Duplicate report ignored: msgType=0x\(String(format: "%02X", msgType)) seqNo=\(seqNo)")
                return
            }
            lastReportSeqNo = seqNo
            handleReportPacket(msgType: msgType, data: packet)
        } else {
            // 설정/조회 응답 → 세마포어로 전달
            log.info("[RX] Signaling response semaphore for msgType=0x\(String(format: "%02X", msgType))")
            lastResponse = packet
            responseSemaphore.signal()
        }
    }

    /// 비요청 보고 패킷 처리
    private func handleReportPacket(msgType: UInt8, data: Data) {
        let payload = DiaconnPacketDecoder.getPayload(data)

        switch msgType {
        case DiaconnPacketType.INJECTION_PROGRESS_REPORT:
            guard payload.count >= 6 else {
                log.error("Bolus progress report: payload too short (\(payload.count) bytes)")
                break
            }
            let setAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: 0)) / 100.0
            let currentAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: 2)) / 100.0
            let speed = DiaconnPacketDecoder.readByte(payload, offset: 4)
            let progressPercent = DiaconnPacketDecoder.readByte(payload, offset: 5)
            log.info("Bolus progress: \(currentAmount)U / \(setAmount)U speed=\(speed) \(progressPercent)%")
            pumpManager?.notifyBolusDidUpdate(deliveredUnits: currentAmount)

        case DiaconnPacketType.CONFIRM_REPORT:
            log.info("Confirm report")

        case DiaconnPacketType.INJECTION_BASAL_REPORT:
            log.info("Basal injection report")

        case DiaconnPacketType.TEMP_BASAL_REPORT:
            log.info("Temp basal report")

        case DiaconnPacketType.INJECTION_SNACK_RESULT_REPORT:
            log.info("Bolus result report")
            handleBolusResultReport(payload)

        case DiaconnPacketType.INJECTION_BLOCK_REPORT:
            log.error("Injection block report (occlusion)")
            pumpManager?.notifyBolusError()

        case DiaconnPacketType.BASAL_SETTING_REPORT:
            log.info("Basal setting complete report")

        case DiaconnPacketType.INSULIN_LACK_REPORT:
            log.error("Insulin lack report")

        case DiaconnPacketType.REJECT_REPORT:
            log.error("Reject report")

        default:
            log.info("Unknown report: \(String(format: "0x%02X", msgType))")
        }
    }

    /// 볼루스 결과 보고 처리
    private func handleBolusResultReport(_ payload: Data) {
        guard payload.count >= 5 else { return }
        let result = DiaconnPacketDecoder.readByte(payload, offset: 0)
        let requestedAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: 1)) / 100.0
        let deliveredAmount = Double(DiaconnPacketDecoder.readShort(payload, offset: 3)) / 100.0

        log.info("Bolus result: requested=\(requestedAmount)U delivered=\(deliveredAmount)U canceled=\(result == 1)")

        if result == 0 {
            pumpManager?.notifyBolusDone(deliveredUnits: deliveredAmount)
        } else {
            pumpManager?.notifyBolusError()
        }
    }
}
