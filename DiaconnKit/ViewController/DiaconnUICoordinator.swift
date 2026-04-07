import Combine
import DiaconnKit
import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

enum DiaconnUIScreen {
    case firstRunScreen
    case insulinConfirmationScreen
    case deviceScanningScreen
    case setupComplete
    case settings

    func next() -> DiaconnUIScreen? {
        switch self {
        case .firstRunScreen:
            return .insulinConfirmationScreen
        case .insulinConfirmationScreen:
            return .deviceScanningScreen
        case .deviceScanningScreen:
            return .setupComplete
        case .setupComplete:
            return nil
        case .settings:
            return nil
        }
    }
}

class DiaconnUICoordinator: UINavigationController, PumpManagerOnboarding, CompletionNotifying, UINavigationControllerDelegate {
    var pumpManagerOnboardingDelegate: PumpManagerOnboardingDelegate?
    var completionDelegate: CompletionDelegate?

    var screenStack = [DiaconnUIScreen]()
    var currentScreen: DiaconnUIScreen {
        screenStack.last!
    }

    private let colorPalette: LoopUIColorPalette
    private var pumpManager: DiaconnPumpManager?
    private var allowedInsulinTypes: [InsulinType]
    private var allowDebugFeatures: Bool

    init(
        pumpManager: DiaconnPumpManager? = nil,
        colorPalette: LoopUIColorPalette,
        pumpManagerSettings: PumpManagerSetupSettings? = nil,
        allowDebugFeatures: Bool,
        allowedInsulinTypes: [InsulinType] = []
    ) {
        if pumpManager == nil, pumpManagerSettings != nil {
            let basal = DiaconnPumpManagerState.convertBasal(pumpManagerSettings!.basalSchedule.items)
            self.pumpManager = DiaconnPumpManager(state: DiaconnPumpManagerState(basalSchedule: basal))
        } else if pumpManager == nil {
            self.pumpManager = DiaconnPumpManager(state: DiaconnPumpManagerState(rawValue: [:]))
        } else {
            self.pumpManager = pumpManager
        }

        self.colorPalette = colorPalette
        self.allowDebugFeatures = allowDebugFeatures
        self.allowedInsulinTypes = allowedInsulinTypes

        super.init(navigationBarClass: UINavigationBar.self, toolbarClass: UIToolbar.self)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        navigationBar.prefersLargeTitles = true

        if screenStack.isEmpty {
            screenStack = [getInitialScreen()]
            let viewController = viewControllerForScreen(currentScreen)
            viewController.isModalInPresentation = false
            setViewControllers([viewController], animated: false)
        }
    }

    private func viewControllerForScreen(_ screen: DiaconnUIScreen) -> UIViewController {
        switch screen {
        case .firstRunScreen:
            let view = DiaconnSetupView(nextAction: stepFinished)
            return hostingController(rootView: view)

        case .insulinConfirmationScreen:
            let view = DiaconnInsulinTypeView(
                initialValue: allowedInsulinTypes.first ?? .novolog,
                supportedInsulinTypes: allowedInsulinTypes,
                didConfirm: { confirmedType in
                    self.pumpManager?.state.insulinType = confirmedType
                    self.stepFinished()
                },
                didCancel: {
                    self.completionDelegate?.completionNotifyingDidComplete(self)
                }
            )
            return hostingController(rootView: view)

        case .deviceScanningScreen:
            pumpManager?.state.isOnBoarded = true
            pumpManager?.notifyStateDidChange()
            pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didOnboardPumpManager: pumpManager!)

            let viewModel = DiaconnScanViewModel(pumpManager: pumpManager, nextStep: stepFinished)
            return hostingController(rootView: DiaconnScanView(viewModel: viewModel))

        case .setupComplete:
            let nextStep: () -> Void = {
                self.pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didCreatePumpManager: self.pumpManager!)
                self.completionDelegate?.completionNotifyingDidComplete(self)
            }
            let view = DiaconnSetupCompleteView(finish: nextStep)
            return hostingController(rootView: view)

        case .settings:
            let viewModel = DiaconnSettingsViewModel(
                pumpManager: pumpManager,
                allowedInsulinTypes: allowedInsulinTypes,
                onFinish: stepFinished
            )
            let view = DiaconnSettingsView(viewModel: viewModel)
            return hostingController(rootView: view)
        }
    }

    func stepFinished() {
        if let nextStep = currentScreen.next() {
            navigateTo(nextStep)
        } else {
            pumpManager?.notifyDelegateOfDeactivation {
                DispatchQueue.main.async {
                    self.completionDelegate?.completionNotifyingDidComplete(self)
                }
            }
        }
    }

    func getInitialScreen() -> DiaconnUIScreen {
        guard let pumpManager = pumpManager else {
            return .firstRunScreen
        }

        if pumpManager.isOnboarded {
            return .settings
        }

        return .firstRunScreen
    }

    func navigateTo(_ screen: DiaconnUIScreen) {
        screenStack.append(screen)
        let viewController = viewControllerForScreen(screen)
        viewController.isModalInPresentation = false
        pushViewController(viewController, animated: true)
    }

    private func hostingController<Content: View>(rootView: Content) -> UIViewController {
        UIHostingController(rootView: rootView)
    }
}
