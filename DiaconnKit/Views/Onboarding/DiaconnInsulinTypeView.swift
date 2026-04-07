import LoopKit
import LoopKitUI
import SwiftUI

struct DiaconnInsulinTypeView: View {
    @State private var insulinType: InsulinType?
    private let supportedInsulinTypes: [InsulinType]
    private let didConfirm: (InsulinType) -> Void
    private let didCancel: () -> Void

    init(
        initialValue: InsulinType,
        supportedInsulinTypes: [InsulinType],
        didConfirm: @escaping (InsulinType) -> Void,
        didCancel: @escaping () -> Void
    ) {
        _insulinType = State(initialValue: initialValue)
        self.supportedInsulinTypes = supportedInsulinTypes
        self.didConfirm = didConfirm
        self.didCancel = didCancel
    }

    var body: some View {
        VStack {
            List {
                Section {
                    Text(LocalizedString(
                        "Select the type of insulin that you will be using in this pump.",
                        comment: "Title text for insulin type confirmation page"
                    ))
                }
                Section {
                    InsulinTypeChooser(insulinType: $insulinType, supportedInsulinTypes: supportedInsulinTypes)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .insetGroupedListStyle()

            Button(action: {
                if let insulinType {
                    didConfirm(insulinType)
                }
            }) {
                Text(LocalizedString("Continue", comment: "Text for continue button"))
                    .actionButtonStyle(.primary)
                    .padding()
            }
            .disabled(insulinType == nil)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(LocalizedString("Cancel", comment: "Cancel button title")) {
                    didCancel()
                }
            }
        }
    }
}
