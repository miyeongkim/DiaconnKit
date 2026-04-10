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

            Text("Setup Complete")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("The Diaconn G8 pump has been successfully connected.\n\nTrio will automatically manage insulin delivery.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: finish) {
                Text("Done")
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
        .navigationTitle("Setup Complete")
    }
}
