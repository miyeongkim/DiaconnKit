import Foundation
public import LoopKit

internal class DiaconnDoseProgressReporter: DoseProgressReporter {
    private let dispatchQueue: DispatchQueue
    private var observers: [DoseProgressObserver] = []

    internal var progress: DoseProgress
    internal var totalUnits: Double = 1.0

    internal init(dispatchQueue: DispatchQueue) {
        self.dispatchQueue = dispatchQueue
        progress = DoseProgress(deliveredUnits: 0, percentComplete: 0)
    }

    internal func addObserver(_ observer: DoseProgressObserver) {
        dispatchQueue.async {
            self.observers.append(observer)
            // Notify immediately so the observer gets the current progress state
            observer.doseProgressReporterDidUpdate(self)
        }
    }

    internal func removeObserver(_ observer: DoseProgressObserver) {
        dispatchQueue.async {
            self.observers.removeAll { $0 === observer }
        }
    }

    func notify(deliveredUnits: Double, done: Bool) {
        let progress = DoseProgress(
            deliveredUnits: deliveredUnits,
            percentComplete: done ? 1.0 : min(deliveredUnits / max(totalUnits, 0.01), 0.99)
        )

        dispatchQueue.async {
            self.progress = progress

            for observer in self.observers {
                observer.doseProgressReporterDidUpdate(self)
            }
        }
    }
}
