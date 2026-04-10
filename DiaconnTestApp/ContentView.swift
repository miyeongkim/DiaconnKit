import DiaconnKit
import LoopKit
import SwiftUI

// MARK: - App State

class TestAppState: ObservableObject {
    @Published var isConnected = false

    let pumpManager: DiaconnPumpManager

    // Packet inspector
    @Published var lastPacket: PacketInspection?

    // Log inquiry
    @Published var logRawResponse: Data?
    @Published var logEntries: [DiaconnLogEntry] = []
    @Published var logFetchError: String?

    // Bolus
    @Published var bolusResult: String?
    @Published var bolusError: String?

    // Temp basal
    @Published var tempBasalResult: String?
    @Published var tempBasalError: String?

    // Sync
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
                    self?.bolusResult = "Bolus \(String(format: "%.2f", units))U delivery started"
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
                    self?.bolusResult = "Bolus canceled"
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
                    self?.tempBasalResult = "Temp basal \(String(format: "%.2f", unitsPerHour))U/h x \(Int(durationMin))min set"
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
                    self?.tempBasalResult = "Temp basal canceled"
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
                    self?.tempBasalResult = "Pump suspended"
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
                    self?.tempBasalResult = "Pump resumed"
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

            Section("Diagnostics") {
                NavigationLink("Pump Status") {
                    PumpStatusView(appState: appState)
                }
                NavigationLink("Packet Inspector") {
                    PacketInspectorView(appState: appState)
                }
                NavigationLink("Log Inquiry") {
                    LogFetchView(appState: appState)
                }
            }

            Section("Control") {
                NavigationLink("Bolus") {
                    BolusView(appState: appState)
                }
                NavigationLink("Temp Basal") {
                    TempBasalView(appState: appState)
                }
                NavigationLink("Sync (reconcileDoses)") {
                    ReconcileView(appState: appState)
                }
            }

            Section {
                Button(role: .destructive) {
                    appState.onDisconnected()
                } label: {
                    Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
                }
            }
        }
        .navigationTitle("Diaconn G8")
    }

    private var statusRow: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text("Connected")
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
            Section("Insulin / Battery") {
                row("Remaining Insulin", String(format: "%.2f U", state.reservoirLevel))
                row("Battery", "\(Int(state.batteryRemaining * 100))%")
            }
            Section("Status") {
                row("Suspended", state.isPumpSuspended ? "Suspended" : "Normal")
                row("Temp Basal", state.isTempBasalInProgress ? "In Progress" : "None")
                row("Bolus State", bolusStateLabel)
            }
            Section("Log Cursor") {
                row("pumpLastLogNum", "\(state.pumpLastLogNum)")
                row("pumpWrappingCount", "\(state.pumpWrappingCount)")
                row("storedLastLogNum", "\(state.storedLastLogNum)")
                row("storedWrappingCount", "\(state.storedWrappingCount)")
                row("isFirstLogSync", "\(state.isFirstLogSync)")
            }
            Section("Pump Info") {
                row("Firmware", state.firmwareVersion ?? "-")
                row("Serial", state.serialNumber ?? "-")
            }
        }
        .navigationTitle("Pump Status")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Fetch") { appState.pumpManager.fetchPumpStatus { _ in } }
            }
        }
    }

    private var bolusStateLabel: String {
        switch appState.pumpManager.state.bolusState {
        case .noBolus: return "None"
        case .initiating: return "Initiating"
        case .inProgress: return "In Progress"
        case .canceling: return "Canceling"
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
                Label("BigAPSMainInfoInquire (0x54) Request", systemImage: "arrow.up.circle")
                    .frame(maxWidth: .infinity).padding(10)
            }
            .buttonStyle(.borderedProminent)
            .padding()

            if let p = appState.lastPacket {
                Picker("", selection: $tab) {
                    Text("Hex Dump").tag(0)
                    Text("Parsed Result").tag(1)
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
                Text("Press button to receive data").foregroundColor(.secondary)
                Spacer()
            }
        }
        .navigationTitle("Packet Inspector")
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
                Section("Request Parameters") {
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
                    Button("BIG_LOG_INQUIRE (0x72) Request") { sendFetch() }
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
                    Text("Parsed (\(appState.logEntries.count) entries)").tag(1)
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
                Text("Press button to receive logs").foregroundColor(.secondary)
                Spacer()
            }
        }
        .navigationTitle("Log Inquiry")
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
            Section("Bolus Delivery") {
                HStack {
                    Text("Amount").foregroundColor(.secondary)
                    Spacer()
                    TextField("1.0", text: $unitsText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text("U").foregroundColor(.secondary)
                }
                Button("Start Delivery") {
                    guard let u = Double(unitsText) else { return }
                    appState.enactBolus(units: u)
                }
                .frame(maxWidth: .infinity)

                Button("Cancel Delivery", role: .destructive) {
                    appState.cancelBolus()
                }
                .frame(maxWidth: .infinity)
            }

            resultSection(result: appState.bolusResult, error: appState.bolusError)

            Section("Current Status") {
                stateRow("Bolus State", bolusStateLabel)
                if let delivered = appState.pumpManager.state.deliveredUnits,
                   let total = appState.pumpManager.state.totalUnits
                {
                    stateRow("Delivery Progress", String(format: "%.2f / %.2f U", delivered, total))
                }
            }
        }
        .navigationTitle("Bolus")
    }

    private var bolusStateLabel: String {
        switch appState.pumpManager.state.bolusState {
        case .noBolus: return "None"
        case .initiating: return "Initiating"
        case .inProgress: return "In Progress"
        case .canceling: return "Canceling"
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
            Section("Temp Basal Settings") {
                HStack {
                    Text("Rate").foregroundColor(.secondary)
                    Spacer()
                    TextField("0.5", text: $rateText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text("U/h").foregroundColor(.secondary)
                }
                HStack {
                    Text("Duration").foregroundColor(.secondary)
                    Spacer()
                    TextField("30", text: $durationText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    Text("min").foregroundColor(.secondary)
                }
                Button("Set Temp Basal") {
                    guard let r = Double(rateText), let d = Double(durationText) else { return }
                    appState.enactTempBasal(unitsPerHour: r, durationMin: d)
                }
                .frame(maxWidth: .infinity)

                Button("Cancel Temp Basal", role: .destructive) {
                    appState.cancelTempBasal()
                }
                .frame(maxWidth: .infinity)
            }

            Section("Pump Suspend / Resume") {
                Button("Suspend") { appState.suspendDelivery() }
                    .frame(maxWidth: .infinity)
                Button("Resume", role: .destructive) { appState.resumeDelivery() }
                    .frame(maxWidth: .infinity)
            }

            resultSection(result: appState.tempBasalResult, error: appState.tempBasalError)

            Section("Current Status") {
                stateRow("Suspended", appState.pumpManager.state.isPumpSuspended ? "Suspended" : "Normal")
                stateRow("Temp Basal", appState.pumpManager.state.isTempBasalInProgress ? "In Progress" : "None")
                if let rate = appState.pumpManager.state.tempBasalUnits {
                    stateRow("Rate", String(format: "%.2f U/h", rate))
                }
            }
        }
        .navigationTitle("Temp Basal")
    }
}

// MARK: - Reconcile View

struct ReconcileView: View {
    @ObservedObject var appState: TestAppState

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Button("Run reconcileDoses") { appState.reconcileDoses() }
                        .frame(maxWidth: .infinity)
                }
                if let err = appState.reconcileError {
                    Section { Text(err).foregroundColor(.red).font(.caption) }
                }
            }
            .frame(maxHeight: 130)

            if appState.reconcileEntries.isEmpty && appState.reconcileError == nil {
                Spacer()
                Text("Press button to run sync").foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    Section("DoseEntry (\(appState.reconcileEntries.count) entries)") {
                        ForEach(appState.reconcileEntries.indices, id: \.self) { i in
                            DoseEntryRow(dose: appState.reconcileEntries[i])
                        }
                    }
                }
            }
        }
        .navigationTitle("Sync")
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
        case .bolus: return "Bolus"
        case .tempBasal: return "Temp Basal"
        case .basal: return "Basal"
        case .suspend: return "Suspend"
        case .resume: return "Resume"
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
        Section("Result") {
            Label(result, systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }
    if let error = error {
        Section("Error") {
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
                Text("No parsed entries\n(response is padding or empty log)")
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
                if entry.amount > 0 { chip("Amount", String(format: "%.2f U", entry.amount)) }
                if entry.rate > 0 { chip("Rate", String(format: "%.2f", entry.rate)) }
                if entry.durationMin > 0 { chip("Duration", "\(entry.durationMin)min") }
            }
            .font(.caption)
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private var kindLabel: String {
        switch entry.logKind {
        case .mealBolus: return "Meal Bolus"
        case .snackBolus: return "Snack Bolus"
        case .squareBolus: return "Extended Bolus"
        case .dualBolus: return "Dual Bolus"
        case .basalChange: return "Basal Change"
        case .tempBasalStart: return "Temp Basal Start"
        case .tempBasalEnd: return "Temp Basal End"
        case .suspend: return "Suspend"
        case .resume: return "Resume"
        case .alarm: return "Alarm"
        case .unknown: return "Unknown"
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
                    summaryRow("Size", "\(raw.count) bytes")
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
                    legend(.blue, "Header [0-3]")
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
                    section("Basic Status") {
                        row("Reservoir", String(format: "%.2f U", s.remainInsulin))
                        row("Battery", "\(s.remainBattery) %")
                        row("Suspended", s.isSuspended ? "Suspended" : "Normal")
                        row("Firmware", s.firmwareVersion)
                        row("Serial", s.serialNumber)
                    }
                    section("Log Status") {
                        row("lastLogNum", "\(s.lastLogNum)")
                        row("wrappingCount", "\(s.wrappingCount)")
                    }
                    section("Basal") {
                        row("Basal Rate", String(format: "%.2f U/h", s.basalAmount))
                        row("Temp Basal Status", "\(s.tempBasalStatus)")
                        row("Temp Basal Ratio", "\(s.tempBasalRateRatio) %")
                        row("Elapsed Time", "\(s.tempBasalElapsedTime) min")
                    }
                    section("Limits") {
                        row("Max Basal/h", String(format: "%.2f U/h", s.maxBasalPerHour))
                        row("Max Bolus", String(format: "%.2f U", s.maxBolus))
                    }
                    section("Pump Time") {
                        row("Time", String(
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
                Text("Parse Failed").foregroundColor(.secondary)
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
