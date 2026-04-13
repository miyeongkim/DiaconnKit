import LoopKit
import SwiftUI

struct DiaconnSetupCompleteView: View {
    var finish: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.green)

            Text(LocalizedString("Setup Complete", comment: "Setup complete title"))
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(LocalizedString(
                "The Diaconn G8 pump has been successfully connected.\n\nTrio will automatically manage insulin delivery.",
                comment: "Setup complete description"
            ))
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: finish) {
                Text(LocalizedString("Done", comment: "Done button"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .navigationTitle(LocalizedString("Setup Complete", comment: "Setup complete navigation title"))
    }
}
