import DiaconnKit
import LoopKit
import SwiftUI

// MARK: - App State

class TestAppState: ObservableObject {
    @Published var isConnected = false

    let pumpManager: DiaconnPumpManager

    // 패킷 인스펙터
    @Published var lastPacket: PacketInspection?

    // 로그 조회
    @Published var logRawResponse: Data?
    @Published var logEntries: [DiaconnLogEntry] = []
    @Published var logFetchError: String?

    // 볼루스
    @Published var bolusResult: String?
    @Published var bolusError: String?

    // 임시 기저
    @Published var tempBasalResult: String?
    @Published var tempBasalError: String?

    // 동기화
    @Published var reconcileEntries: [DoseEntry] = []
    @Published var reconcileError: String?

    struct PacketInspection {
        let raw: Data
        let msgType: UInt8
        let parsed: DiaconnPumpStatus?
        let logEntries: [DiaconnLogEntry]?

        var hexRows: [(offset: Int, bytes: [String])] {
            let b = Array(raw)
            return stride(from: 0, to: b.count, by: 16).map { s in
                (s, b[s ..< min(s + 16, b.count)].map { String(format: "%02X", $0) })
            }
        }
    }

    init() {
        pumpManager = DiaconnPumpManager(state: DiaconnPumpManagerState(basalSchedule: []))
        pumpManager.bluetooth.pumpManager = pumpManager

        pumpManager.bluetooth.onRawPacketReceived = { [weak self] data in
            let msgType = data.count > 1 ? data[1] : 0
            let parsed = (msgType == 0x94 && data.count == 182) ? parseBigAPSMainInfoResponse(data) : nil
            let logEntries = (msgType == 0xB2 && data.count == 182) ? parseBigLogInquireResponse(data) : nil
            DispatchQueue.main.async {
                self?.lastPacket = PacketInspection(raw: data, msgType: msgType, parsed: parsed, logEntries: logEntries)
            }
        }
    }

    func onConnected() { isConnected = true }

    func onDisconnected() {
        isConnected = false
        lastPacket = nil
        logRawResponse = nil
        logEntries = []
        logFetchError = nil
        bolusResult = nil
        bolusError = nil
        tempBasalResult = nil
        tempBasalError = nil
        reconcileEntries = []
        reconcileError = nil
    }

    func fetchLog(wrapCount: UInt8, logNum: UInt16) {
        logFetchError = nil
        pumpManager.testFetchLogEntries(wrapCount: wrapCount, logNum: logNum) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case let .success(response):
                    self?.logRawResponse = response.rawResponse
                    self?.logEntries = response.entries
                case let .failure(error):
                    self?.logFetchError = error.localizedDescription
                }
            }
        }
    }

    func enactBolus(units: Double) {
        bolusResult = nil
        bolusError = nil
        pumpManager.enactBolus(units: units, activationType: .manualNoRecommendation) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.bolusError = error.localizedDescription
                } else {
                    self?.bolusResult = "볼루스 \(String(format: "%.2f", units))U 주입 시작"
                }
            }
        }
    }

    func cancelBolus() {
        bolusResult = nil
        bolusError = nil
        pumpManager.cancelBolus { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.bolusResult = "볼루스 취소 완료"
                case let .failure(error):
                    self?.bolusError = error.localizedDescription
                }
            }
        }
    }

    func enactTempBasal(unitsPerHour: Double, durationMin: Double) {
        tempBasalResult = nil
        tempBasalError = nil
        pumpManager.enactTempBasal(unitsPerHour: unitsPerHour, for: durationMin * 60) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.tempBasalError = error.localizedDescription
                } else {
                    self?.tempBasalResult = "임시 기저 \(String(format: "%.2f", unitsPerHour))U/h × \(Int(durationMin))분 설정"
                }
            }
        }
    }

    func cancelTempBasal() {
        tempBasalResult = nil
        tempBasalError = nil
        pumpManager.enactTempBasal(unitsPerHour: 0, for: 0) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.tempBasalError = error.localizedDescription
                } else {
                    self?.tempBasalResult = "임시 기저 취소 완료"
                }
            }
        }
    }

    func suspendDelivery() {
        tempBasalResult = nil
        tempBasalError = nil
        pumpManager.suspendDelivery { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.tempBasalError = error.localizedDescription
                } else {
                    self?.tempBasalResult = "펌프 일시정지 완료"
                }
            }
        }
    }

    func resumeDelivery() {
        tempBasalResult = nil
        tempBasalError = nil
        pumpManager.resumeDelivery { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.tempBasalError = error.localizedDescription
                } else {
                    self?.tempBasalResult = "펌프 재개 완료"
                }
            }
        }
    }

    func reconcileDoses() {
        reconcileEntries = []
        reconcileError = nil
        pumpManager.reconcileDoses { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case let .success(doses):
                    self?.reconcileEntries = doses
                case let .failure(error):
                    self?.reconcileError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    @StateObject private var appState = TestAppState()

    var body: some View {
        NavigationView {
            if appState.isConnected {
                MenuView(appState: appState)
            } else {
                DiaconnScanView(viewModel: DiaconnScanViewModel(
                    pumpManager: appState.pumpManager,
                    nextStep: { appState.onConnected() }
                ))
            }
        }
    }
}

// MARK: - Menu View

struct MenuView: View {
    @ObservedObject var appState: TestAppState

    var body: some View {
        List {
            Section {
                statusRow
            }

            Section("진단") {
                NavigationLink("펌프 상태") {
                    PumpStatusView(appState: appState)
                }
                NavigationLink("패킷 인스펙터") {
                    PacketInspectorView(appState: appState)
                }
                NavigationLink("로그 조회") {
                    LogFetchView(appState: appState)
                }
            }

            Section("제어") {
                NavigationLink("볼루스") {
                    BolusView(appState: appState)
                }
                NavigationLink("임시 기저") {
                    TempBasalView(appState: appState)
                }
                NavigationLink("동기화 (reconcileDoses)") {
                    ReconcileView(appState: appState)
                }
            }

            Section {
                Button(role: .destructive) {
                    appState.onDisconnected()
                } label: {
                    Label("연결 해제", systemImage: "antenna.radiowaves.left.and.right.slash")
                }
            }
        }
        .navigationTitle("Diaconn G8")
    }

    private var statusRow: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text("연결됨")
            Spacer()
            Button("Fetch") {
                appState.pumpManager.fetchPumpStatus { _ in }
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Pump Status View

struct PumpStatusView: View {
    @ObservedObject var appState: TestAppState

    var state: DiaconnPumpManagerState { appState.pumpManager.state }

    var body: some View {
        List {
            Section("인슐린 / 배터리") {
                row("잔여 인슐린", String(format: "%.2f U", state.reservoirLevel))
                row("배터리", "\(Int(state.batteryRemaining * 100))%")
            }
            Section("상태") {
                row("일시정지", state.isPumpSuspended ? "정지 중" : "정상")
                row("임시 기저", state.isTempBasalInProgress ? "진행 중" : "없음")
                row("볼루스 상태", bolusStateLabel)
            }
            Section("로그 커서") {
                row("pumpLastLogNum", "\(state.pumpLastLogNum)")
                row("pumpWrappingCount", "\(state.pumpWrappingCount)")
                row("storedLastLogNum", "\(state.storedLastLogNum)")
                row("storedWrappingCount", "\(state.storedWrappingCount)")
                row("isFirstLogSync", "\(state.isFirstLogSync)")
            }
            Section("펌프 정보") {
                row("펌웨어", state.firmwareVersion ?? "-")
                row("시리얼", state.serialNumber ?? "-")
            }
        }
        .navigationTitle("펌프 상태")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Fetch") { appState.pumpManager.fetchPumpStatus { _ in } }
            }
        }
    }

    private var bolusStateLabel: String {
        switch appState.pumpManager.state.bolusState {
        case .noBolus: return "없음"
        case .initiating: return "시작 중"
        case .inProgress: return "주입 중"
        case .canceling: return "취소 중"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
    }
}

// MARK: - Packet Inspector View

struct PacketInspectorView: View {
    @ObservedObject var appState: TestAppState
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { appState.pumpManager.fetchPumpStatus { _ in } }) {
                Label("BigAPSMainInfoInquire (0x54) 요청", systemImage: "arrow.up.circle")
                    .frame(maxWidth: .infinity).padding(10)
            }
            .buttonStyle(.borderedProminent)
            .padding()

            if let p = appState.lastPacket {
                Picker("", selection: $tab) {
                    Text("Hex Dump").tag(0)
                    Text("파싱 결과").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Divider().padding(.top, 6)

                if tab == 0 {
                    HexDumpView(raw: p.raw)
                } else {
                    ParsedView(packet: p)
                }
            } else {
                Spacer()
                Text("버튼을 눌러 데이터를 수신하세요").foregroundColor(.secondary)
                Spacer()
            }
        }
        .navigationTitle("패킷 인스펙터")
    }
}

// MARK: - Log Fetch View

struct LogFetchView: View {
    @ObservedObject var appState: TestAppState
    @State private var wrapCountText = "0"
    @State private var logNumText = "0"
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("요청 파라미터") {
                    HStack {
                        Text("wrapCount").foregroundColor(.secondary)
                        Spacer()
                        TextField("0", text: $wrapCountText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("logNum").foregroundColor(.secondary)
                        Spacer()
                        TextField("0", text: $logNumText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    Button("BIG_LOG_INQUIRE (0x72) 요청") { sendFetch() }
                        .frame(maxWidth: .infinity)
                }
                if let err = appState.logFetchError {
                    Section { Text(err).foregroundColor(.red).font(.caption) }
                }
            }
            .frame(maxHeight: 220)

            if appState.logRawResponse != nil {
                Picker("", selection: $tab) {
                    Text("Hex Dump").tag(0)
                    Text("파싱 결과 (\(appState.logEntries.count)건)").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                if tab == 0, let raw = appState.logRawResponse {
                    HexDumpView(raw: raw)
                } else {
                    LogEntryListView(entries: appState.logEntries)
                }
            } else {
                Spacer()
                Text("버튼을 눌러 로그를 수신하세요").foregroundColor(.secondary)
                Spacer()
            }
        }
        .navigationTitle("로그 조회")
        .onAppear {
            wrapCountText = "\(appState.pumpManager.state.storedWrappingCount)"
            logNumText = "\(appState.pumpManager.state.storedLastLogNum)"
        }
    }

    private func sendFetch() {
        appState.fetchLog(wrapCount: UInt8(wrapCountText) ?? 0, logNum: UInt16(logNumText) ?? 0)
    }
}

// MARK: - Bolus View

struct BolusView: View {
    @ObservedObject var appState: TestAppState
    @State private var unitsText = "1.0"

    var body: some View {
        Form {
            Section("볼루스 주입") {
                HStack {
                    Text("용량").foregroundColor(.secondary)
                    Spacer()
                    TextField("1.0", text: $unitsText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text("U").foregroundColor(.secondary)
                }
                Button("주입 시작") {
                    guard let u = Double(unitsText) else { return }
                    appState.enactBolus(units: u)
                }
                .frame(maxWidth: .infinity)

                Button("주입 취소", role: .destructive) {
                    appState.cancelBolus()
                }
                .frame(maxWidth: .infinity)
            }

            resultSection(result: appState.bolusResult, error: appState.bolusError)

            Section("현재 상태") {
                stateRow("볼루스 상태", bolusStateLabel)
                if let delivered = appState.pumpManager.state.deliveredUnits,
                   let total = appState.pumpManager.state.totalUnits
                {
                    stateRow("주입 진행", String(format: "%.2f / %.2f U", delivered, total))
                }
            }
        }
        .navigationTitle("볼루스")
    }

    private var bolusStateLabel: String {
        switch appState.pumpManager.state.bolusState {
        case .noBolus: return "없음"
        case .initiating: return "시작 중"
        case .inProgress: return "주입 중"
        case .canceling: return "취소 중"
        }
    }
}

// MARK: - Temp Basal View

struct TempBasalView: View {
    @ObservedObject var appState: TestAppState
    @State private var rateText = "0.5"
    @State private var durationText = "30"

    var body: some View {
        Form {
            Section("임시 기저 설정") {
                HStack {
                    Text("속도").foregroundColor(.secondary)
                    Spacer()
                    TextField("0.5", text: $rateText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text("U/h").foregroundColor(.secondary)
                }
                HStack {
                    Text("시간").foregroundColor(.secondary)
                    Spacer()
                    TextField("30", text: $durationText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    Text("분").foregroundColor(.secondary)
                }
                Button("임시 기저 설정") {
                    guard let r = Double(rateText), let d = Double(durationText) else { return }
                    appState.enactTempBasal(unitsPerHour: r, durationMin: d)
                }
                .frame(maxWidth: .infinity)

                Button("임시 기저 취소", role: .destructive) {
                    appState.cancelTempBasal()
                }
                .frame(maxWidth: .infinity)
            }

            Section("펌프 일시정지 / 재개") {
                Button("일시정지") { appState.suspendDelivery() }
                    .frame(maxWidth: .infinity)
                Button("재개", role: .destructive) { appState.resumeDelivery() }
                    .frame(maxWidth: .infinity)
            }

            resultSection(result: appState.tempBasalResult, error: appState.tempBasalError)

            Section("현재 상태") {
                stateRow("일시정지", appState.pumpManager.state.isPumpSuspended ? "정지 중" : "정상")
                stateRow("임시 기저", appState.pumpManager.state.isTempBasalInProgress ? "진행 중" : "없음")
                if let rate = appState.pumpManager.state.tempBasalUnits {
                    stateRow("속도", String(format: "%.2f U/h", rate))
                }
            }
        }
        .navigationTitle("임시 기저")
    }
}

// MARK: - Reconcile View

struct ReconcileView: View {
    @ObservedObject var appState: TestAppState

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Button("reconcileDoses 실행") { appState.reconcileDoses() }
                        .frame(maxWidth: .infinity)
                }
                if let err = appState.reconcileError {
                    Section { Text(err).foregroundColor(.red).font(.caption) }
                }
            }
            .frame(maxHeight: 130)

            if appState.reconcileEntries.isEmpty && appState.reconcileError == nil {
                Spacer()
                Text("버튼을 눌러 동기화를 실행하세요").foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    Section("DoseEntry (\(appState.reconcileEntries.count)건)") {
                        ForEach(appState.reconcileEntries.indices, id: \.self) { i in
                            DoseEntryRow(dose: appState.reconcileEntries[i])
                        }
                    }
                }
            }
        }
        .navigationTitle("동기화")
    }
}

struct DoseEntryRow: View {
    let dose: DoseEntry

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(typeLabel).font(.subheadline.bold())
                Spacer()
                Text(Self.fmt.string(from: dose.startDate)).font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Text(valueLabel).font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var typeLabel: String {
        switch dose.type {
        case .bolus: return "볼루스"
        case .tempBasal: return "임시 기저"
        case .basal: return "기저"
        case .suspend: return "일시정지"
        case .resume: return "재개"
        default: return "\(dose.type)"
        }
    }

    private var valueLabel: String {
        switch dose.type {
        case .bolus: return String(format: "%.2f U", dose.deliveredUnits ?? dose.programmedUnits)
        case .tempBasal: return String(format: "%.2f U/h", dose.unitsPerHour)
        default: return ""
        }
    }
}

// MARK: - Shared Helpers

@ViewBuilder func resultSection(result: String?, error: String?) -> some View {
    if let result = result {
        Section("결과") {
            Label(result, systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }
    if let error = error {
        Section("오류") {
            Label(error, systemImage: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
        }
    }
}

func stateRow(_ label: String, _ value: String) -> some View {
    HStack {
        Text(label).foregroundColor(.secondary)
        Spacer()
        Text(value).bold()
    }
}

// MARK: - Log Entry List View

struct LogEntryListView: View {
    let entries: [DiaconnLogEntry]

    var body: some View {
        if entries.isEmpty {
            VStack {
                Spacer()
                Text("파싱된 항목 없음\n(응답이 패딩이거나 빈 로그)")
                    .multilineTextAlignment(.center).foregroundColor(.secondary)
                Spacer()
            }
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(entries.indices, id: \.self) { i in
                        LogEntryRow(entry: entries[i])
                        Divider()
                    }
                }
            }
        }
    }
}

struct LogEntryRow: View {
    let entry: DiaconnLogEntry

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("#\(entry.logNum)").font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
                Text(kindLabel).font(.subheadline.bold())
                Spacer()
                Text(Self.fmt.string(from: entry.date)).font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
            }
            HStack(spacing: 16) {
                if entry.amount > 0 { chip("용량", String(format: "%.2f U", entry.amount)) }
                if entry.rate > 0 { chip("비율", String(format: "%.2f", entry.rate)) }
                if entry.durationMin > 0 { chip("지속", "\(entry.durationMin)분") }
            }
            .font(.caption)
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private var kindLabel: String {
        switch entry.logKind {
        case .mealBolus: return "식사 볼루스"
        case .snackBolus: return "간식 볼루스"
        case .squareBolus: return "확장 볼루스"
        case .dualBolus: return "듀얼 볼루스"
        case .basalChange: return "기저 변경"
        case .tempBasalStart: return "임시기저 시작"
        case .tempBasalEnd: return "임시기저 종료"
        case .suspend: return "일시정지"
        case .resume: return "재개"
        case .alarm: return "알람"
        case .unknown: return "알 수 없음"
        }
    }

    private func chip(_ title: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(title).foregroundColor(.secondary)
            Text(value).bold()
        }
    }
}

// MARK: - Hex Dump View

struct HexDumpView: View {
    let raw: Data

    private var hexRows: [(offset: Int, bytes: [String])] {
        let b = Array(raw)
        return stride(from: 0, to: b.count, by: 16).map { s in
            (s, b[s ..< min(s + 16, b.count)].map { String(format: "%02X", $0) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    summaryRow("크기", "\(raw.count) bytes")
                    if raw.count > 1 { summaryRow("msgType", String(format: "0x%02X", raw[1])) }
                    let defect = DiaconnPacketDecoder.validatePacket(raw)
                    summaryRow("CRC", defect == 0 ? "✅ OK" : "❌ FAIL (\(defect))")
                    if raw.count > 4 {
                        let r = raw[4]
                        summaryRow("result [4]", "\(r) \(r == 16 ? "✅" : "❌ (expected 16)")")
                    }
                }
                .padding(.horizontal)

                Divider().padding(.vertical, 6)

                HStack(spacing: 12) {
                    legend(.blue, "헤더 [0-3]")
                    legend(.primary, "payload")
                    legend(.orange, "CRC")
                }
                .font(.caption2).padding(.horizontal).padding(.bottom, 4)

                ForEach(hexRows, id: \.offset) { row in
                    HStack(alignment: .top, spacing: 6) {
                        Text(String(format: "%03d", row.offset))
                            .foregroundColor(.secondary).frame(width: 28, alignment: .trailing)
                        Text(row.bytes.joined(separator: " "))
                            .foregroundColor(hexColor(offset: row.offset, total: raw.count))
                    }
                    .font(.system(size: 11, design: .monospaced)).padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
        .font(.caption).padding(.vertical, 2)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }

    private func hexColor(offset: Int, total: Int) -> Color {
        if offset < 4 { return .blue }
        if offset + 16 >= total { return .orange }
        return .primary
    }
}

// MARK: - Parsed View

struct ParsedView: View {
    let packet: TestAppState.PacketInspection

    var body: some View {
        if let entries = packet.logEntries {
            LogEntryListView(entries: entries)
        } else if let s = packet.parsed {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("기본 상태") {
                        row("리저버", String(format: "%.2f U", s.remainInsulin))
                        row("배터리", "\(s.remainBattery) %")
                        row("일시정지", s.isSuspended ? "정지" : "정상")
                        row("펌웨어", s.firmwareVersion)
                        row("시리얼", s.serialNumber)
                    }
                    section("로그 상태") {
                        row("lastLogNum", "\(s.lastLogNum)")
                        row("wrappingCount", "\(s.wrappingCount)")
                    }
                    section("기저") {
                        row("기저량", String(format: "%.2f U/h", s.basalAmount))
                        row("임시기저 상태", "\(s.tempBasalStatus)")
                        row("임시기저 비율", "\(s.tempBasalRateRatio) %")
                        row("경과시간", "\(s.tempBasalElapsedTime) min")
                    }
                    section("한도") {
                        row("최대 기저/h", String(format: "%.2f U/h", s.maxBasalPerHour))
                        row("최대 볼루스", String(format: "%.2f U", s.maxBolus))
                    }
                    section("펌프 시간") {
                        row("시간", String(
                            format: "%d-%02d-%02d %02d:%02d:%02d",
                            s.pumpYear,
                            s.pumpMonth,
                            s.pumpDay,
                            s.pumpHour,
                            s.pumpMinute,
                            s.pumpSecond
                        ))
                    }
                }
            }
        } else {
            VStack {
                Spacer()
                Image(systemName: "xmark.circle").font(.largeTitle).foregroundColor(.red)
                Text("파싱 실패").foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption.bold()).foregroundColor(.secondary)
                .padding(.horizontal).padding(.top, 12).padding(.bottom, 2)
            content()
            Divider()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
        .font(.subheadline).padding(.horizontal).padding(.vertical, 5)
    }
}
