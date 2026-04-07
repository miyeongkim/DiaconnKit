import Foundation
import LoopKit
import LoopKitUI

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }
}

class DiaconnHUDProvider: HUDProvider {
    var managerIdentifier: String {
        DiaconnPumpManager.pluginIdentifier
    }

    private var state: DiaconnPumpManagerState {
        didSet {
            guard visible else { return }

            if oldValue.reservoirLevel != state.reservoirLevel ||
                oldValue.lastStatusDate != state.lastStatusDate
            {
                updateReservoirView()
            }
        }
    }

    private let pumpManager: DiaconnPumpManager
    private let bluetoothProvider: BluetoothProvider
    private let colorPalette: LoopUIColorPalette
    private let allowedInsulinTypes: [InsulinType]

    init(
        pumpManager: DiaconnPumpManager,
        bluetoothProvider: BluetoothProvider,
        colorPalette: LoopUIColorPalette,
        allowedInsulinTypes: [InsulinType]
    ) {
        self.pumpManager = pumpManager
        self.bluetoothProvider = bluetoothProvider
        self.colorPalette = colorPalette
        self.allowedInsulinTypes = allowedInsulinTypes
        state = pumpManager.state
        pumpManager.addStateObserver(self, queue: .main)
    }

    var visible: Bool = false {
        didSet {
            if oldValue != visible, visible {
                updateReservoirView()
            }
        }
    }

    private weak var reservoirView: ReservoirVolumeHUDView?

    private func updateReservoirView() {
        guard let reservoirView = reservoirView else { return }

        let level = (state.reservoirLevel / pumpManager.pumpReservoirCapacity).clamped(to: 0 ... 1.0)
        reservoirView.level = level
        reservoirView.setReservoirVolume(volume: state.reservoirLevel, at: state.lastStatusDate)
    }

    func createHUDView() -> BaseHUDView? {
        reservoirView = ReservoirVolumeHUDView.instantiate()

        if visible {
            updateReservoirView()
        }

        return reservoirView
    }

    func didTapOnHUDView(_: BaseHUDView, allowDebugFeatures: Bool) -> HUDTapAction? {
        let vc = pumpManager.settingsViewController(
            bluetoothProvider: bluetoothProvider,
            colorPalette: colorPalette,
            allowDebugFeatures: allowDebugFeatures,
            allowedInsulinTypes: allowedInsulinTypes
        )
        return HUDTapAction.presentViewController(vc)
    }

    var hudViewRawState: HUDProvider.HUDViewRawState {
        [
            "reservoirLevel": state.reservoirLevel,
            "pumpReservoirCapacity": pumpManager.pumpReservoirCapacity,
            "lastStatusDate": state.lastStatusDate
        ]
    }

    static func createHUDView(rawValue: HUDProvider.HUDViewRawState) -> BaseHUDView? {
        guard let reservoirLevel = rawValue["reservoirLevel"] as? Double,
              let capacity = rawValue["pumpReservoirCapacity"] as? Double,
              let lastStatusDate = rawValue["lastStatusDate"] as? Date
        else {
            return nil
        }

        let view = ReservoirVolumeHUDView.instantiate()
        let level = (reservoirLevel / capacity).clamped(to: 0 ... 1.0)
        view.level = level
        view.setReservoirVolume(volume: reservoirLevel, at: lastStatusDate)
        return view
    }
}

extension DiaconnHUDProvider: DiaconnStateObserver {
    func stateDidUpdate(_ state: DiaconnPumpManagerState, _: DiaconnPumpManagerState) {
        self.state = state
    }

    func deviceScanDidUpdate(_: DiaconnPumpScan) {}
}
