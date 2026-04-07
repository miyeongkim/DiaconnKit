import Foundation
import LoopKit

public struct UnfinalizedDose {
    public enum DoseType {
        case bolus
        case tempBasal
    }

    public let type: DoseType
    public let units: Double
    public let startDate: Date
    public var endDate: Date?
    public var isFinished: Bool

    public init(type: DoseType, units: Double, startDate: Date = Date()) {
        self.type = type
        self.units = units
        self.startDate = startDate
        isFinished = false
    }

    public var duration: TimeInterval {
        guard let endDate = endDate else {
            return Date().timeIntervalSince(startDate)
        }
        return endDate.timeIntervalSince(startDate)
    }
}
