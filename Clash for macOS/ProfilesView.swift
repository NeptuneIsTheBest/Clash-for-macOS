import SwiftUI
import UniformTypeIdentifiers

struct ProfilesView: View {
    @State private var importURL: String = ""
    @State private var showFileImporter = false
    @State private var editingProfile: Profile?
    @Bindable private var profileManager = ProfileManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            SettingsHeader(title: "Profiles") {
                Button(action: {
                    Task {
                        await profileManager.updateAllProfiles()
                    }
                }) {
                    if case .downloading = profileManager.downloadStatus {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                            .padding(8)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .buttonStyle(.plain)
                .help("Refresh All")
                .disabled(profileManager.downloadStatus == .downloading)
            }
            .padding(.top, 30)
            .padding(.horizontal, 30)
            
            SettingsSection(title: "Import Profile", icon: "link") {
                HStack(spacing: 12) {
                    TextField("Import URL", text: $importURL)
                        .textFieldStyle(.roundedBorder)
                    
                    if !importURL.isEmpty {
                        Button(action: { importURL = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: {
                        Task {
                            let success = await profileManager.downloadProfile(from: importURL)
                            if success {
                                importURL = ""
                            }
                        }
                    }) {
                        if case .downloading = profileManager.downloadStatus {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 60, height: 16)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.5))
                                .cornerRadius(6)
                        } else {
                            Text("Download")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .cornerRadius(6)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(importURL.isEmpty || profileManager.downloadStatus == .downloading)
                    
                    Button(action: { showFileImporter = true }) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .background(Color.primary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Import from File")
                }
            }
            .padding(.horizontal, 30)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(profileManager.profiles) { profile in
                        ProfileRow(
                            profile: profile,
                            isSelected: profileManager.selectedProfileId == profile.id,
                            onUpdate: {
                                Task {
                                    await profileManager.updateProfile(profile)
                                }
                            },
                            onEdit: {
                                editingProfile = profile
                            },
                            onDelete: {
                                profileManager.deleteProfile(profile)
                            }
                        )
                        .onTapGesture {
                            profileManager.selectProfile(profile)
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.yaml],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await profileManager.importProfile(from: url)
                }
            case .failure(let error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
        .sheet(item: $editingProfile) { profile in
            if let index = profileManager.profiles.firstIndex(where: { $0.id == profile.id }) {
                ProfileEditorView(
                    profile: $profileManager.profiles[index],
                    isPresented: Binding(
                        get: { editingProfile != nil },
                        set: { if !$0 { editingProfile = nil } }
                    )
                )
            }
        }
    }
    
}



struct ProfileRow: View {
    let profile: Profile
    let isSelected: Bool
    var onUpdate: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    
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
                if profile.type == .remote {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Remote")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                        Text("Subscription")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                }
                
                if profile.type == .remote {
                    Button(action: onUpdate) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.gray)
                            .padding(8)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Update")
                }
                
                Button(action: onEdit) {
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
            if profile.type == .remote {
                Button(action: onUpdate) {
                    Label("Update", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
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
