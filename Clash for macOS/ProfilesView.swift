import SwiftUI

struct Profile: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var type: ProfileType
    var url: String?
    var lastUpdated: Date
    var traffic: String?
    
    enum ProfileType {
        case remote
        case local
    }
}

struct ProfilesView: View {
    @State private var importURL: String = ""
    @State private var selectedProfileId: UUID?
    @State private var profiles: [Profile] = [
        Profile(name: "Default Config", type: .local, lastUpdated: Date(), traffic: "1.2 GB"),
        Profile(name: "Remote Server A", type: .remote, url: "https://example.com/config.yaml", lastUpdated: Date().addingTimeInterval(-3600), traffic: "500 MB")
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            SettingsHeader(title: "Profiles") {
                Button(action: {
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Refresh All")
            }
            .padding(.top, 30)
            .padding(.horizontal, 30)
            
            SettingsSection(title: "Import Profile", icon: "link") {
                HStack(spacing: 12) {
                    TextField("Import URL", text: $importURL)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    if !importURL.isEmpty {
                        Button(action: { importURL = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: {
                        addNewProfile()
                    }) {
                        Text("Download")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(importURL.isEmpty)
                }
            }
            .padding(.horizontal, 30)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(profiles) { profile in
                        ProfileRow(profile: profile, isSelected: selectedProfileId == profile.id)
                            .onTapGesture {
                                selectedProfileId = profile.id
                            }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
    }
    
    private func addNewProfile() {
        guard !importURL.isEmpty else { return }
        let newProfile = Profile(
            name: "New Profile \(profiles.count + 1)",
            type: .remote,
            url: importURL,
            lastUpdated: Date(),
            traffic: "0 KB"
        )
        profiles.append(newProfile)
        importURL = ""
    }
}

struct ProfileRow: View {
    let profile: Profile
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .strokeBorder(isSelected ? Color.green : Color.gray.opacity(0.5), lineWidth: 2)
                    .frame(width: 20, height: 20)
                
                if isSelected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.trailing, 4)
            
            ZStack {
                Circle()
                    .fill(profile.type == .local ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                    .frame(width: 48, height: 48)
                
                Image(systemName: profile.type == .local ? "doc.text.fill" : "globe")
                    .font(.system(size: 20))
                    .foregroundStyle(profile.type == .local ? Color.orange : Color.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    if let url = profile.url {
                        Text(url)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Local Configuration")
                    }
                }
                .font(.caption)
                .foregroundStyle(.gray)
                
                Text("Updated: \(DateFormatters.mediumDateTime.string(from: profile.lastUpdated))")
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.8))
            }
            
            Spacer()
            
            HStack(spacing: 20) {
                if let traffic = profile.traffic {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(traffic)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Text("Usage")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                }
                
                Button(action: {
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.gray)
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Update")
                
                Button(action: {
                }) {
                    Image(systemName: "pencil")
                        .foregroundStyle(.gray)
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Edit")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.green.opacity(0.05) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contextMenu {
            Button(action: {}) {
                Label("Update", systemImage: "arrow.triangle.2.circlepath")
            }
            Button(action: {}) {
                Label("Edit", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: {}) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    ProfilesView()
        .frame(width: 800, height: 600)
        .background(Color(red: 0.14, green: 0.14, blue: 0.14))
}
