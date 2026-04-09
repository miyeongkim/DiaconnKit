import Foundation
import LoopKit

public enum DiaconnPumpManagerAlert: Hashable, Codable {
    case occlusion(_ raw: Data)
    case insulinLack(_ raw: Data)

    var contentTitle: String {
        switch self {
        case .occlusion:
            return LocalizedString("Occlusion Detected", comment: "Alert title for occlusion")
        case .insulinLack:
            return LocalizedString("Low Insulin", comment: "Alert title for insulin lack")
        }
    }

    var contentBody: String {
        switch self {
        case .occlusion:
            return LocalizedString("Check the infusion set and reservoir, then try again.", comment: "Alert body for occlusion")
        case .insulinLack:
            return LocalizedString("Insulin reservoir is running low. Replace it soon.", comment: "Alert body for insulin lack")
        }
    }

    public var identifier: String {
        switch self {
        case .occlusion:
            return "occlusion"
        case .insulinLack:
            return "insulinLack"
        }
    }

    var type: PumpAlarmType {
        switch self {
        case .occlusion:
            return .occlusion
        case .insulinLack:
            return .noInsulin
        }
    }

    var raw: Data {
        switch self {
        case let .occlusion(raw):
            return raw
        case let .insulinLack(raw):
            return raw
        }
    }

    var actionButtonLabel: String {
        LocalizedString("OK", comment: "Alert acknowledge button")
    }

    var foregroundContent: Alert.Content {
        Alert.Content(title: contentTitle, body: contentBody, acknowledgeActionButtonLabel: actionButtonLabel)
    }

    var backgroundContent: Alert.Content {
        Alert.Content(title: contentTitle, body: contentBody, acknowledgeActionButtonLabel: actionButtonLabel)
    }
}
