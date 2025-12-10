import SwiftUI

struct RuleProvidersView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsHeader(title: "Rule Providers")
                
                VStack {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.gray)
                    Text("No Rule Providers")
                        .font(.title3)
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
                
                Spacer()
            }
            .padding(30)
        }
    }
}

#Preview {
    RuleProvidersView()
}
