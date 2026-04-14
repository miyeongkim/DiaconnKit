import Combine
import Foundation

class DiaconnScanViewModel: ObservableObject, DiaconnStateObserver {
    @Published var devices: [DiaconnPumpScan] = []
    @Published var isScanning = false
    @Published var isConnecting = false
    @Published var errorMessage: String?

    private weak var pumpManager: DiaconnPumpManager?
    private var nextStep: () -> Void

    init(pumpManager: DiaconnPumpManager?, nextStep: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.nextStep = nextStep
        pumpManager?.addStateObserver(self, queue: .main)
    }

    func startScanning() {
        guard let pumpManager = pumpManager else { return }

        devices = []
        isScanning = true
        errorMessage = nil

        do {
            try pumpManager.bluetooth.startScan()
        } catch {
            errorMessage = error.localizedDescription
            isScanning = false
        }
    }

    func stopScanning() {
        pumpManager?.bluetooth.stopScan()
        isScanning = false
    }

    func connect(to device: DiaconnPumpScan) {
        isConnecting = true
        errorMessage = nil

        pumpManager?.state.bleIdentifier = device.bleIdentifier
        pumpManager?.state.deviceName = device.name

        pumpManager?.bluetooth.connect(device.bleIdentifier) { [weak self] result in
            DispatchQueue.main.async {
                self?.isConnecting = false

                switch result {
                case .success:
                    self?.nextStep()
                case let .failure(error):
                    self?.errorMessage = error.localizedDescription
                case .timeout:
                    self?.errorMessage = "Connection timed out"
                }
            }
        }
    }

    // MARK: - DiaconnStateObserver

    func stateDidUpdate(_: DiaconnPumpManagerState, _: DiaconnPumpManagerState) {}

    func deviceScanDidUpdate(_ device: DiaconnPumpScan) {
        if !devices.contains(where: { $0.bleIdentifier == device.bleIdentifier }) {
            devices.append(device)
        }
    }
}
