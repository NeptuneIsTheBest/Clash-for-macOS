import SwiftUI

struct ProfileEditorView: View {
    @Binding var profile: Profile
    @Binding var isPresented: Bool
    
    @State private var profileName: String = ""
    @State private var profileURL: String = ""
    @State private var profileNotes: String = ""
    @State private var profileUserAgent: String = ""
    @State private var updateInterval: Int = 0
    @State private var useSystemProxy: Bool = false
    @State private var useClashProxy: Bool = false
    @State private var profileContent: String = ""
    @State private var isSaving: Bool = false
    @State private var showCopyConfirm: Bool = false
    
    private let updateIntervalOptions: [(String, Int)] = [
        ("Disabled", 0),
        ("30 min", 30),
        ("1 hour", 60),
        ("3 hours", 180),
        ("6 hours", 360),
        ("12 hours", 720),
        ("24 hours", 1440)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider()
            
            HSplitView {
                leftPanel
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
                
                rightPanel
                    .frame(minWidth: 400)
            }
            
            Divider()
            
            bottomBar
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            loadProfileData()
        }
    }
    
    private var header: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.blue)
            Text("Edit Profile")
                .font(.headline)
            
            Spacer()
            
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.gray.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var leftPanel: some View {
        Form {
            Section("Basic Information") {
                TextField("Name", text: $profileName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if profile.type == .remote {
                    TextField("URL", text: $profileURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                TextField("Notes", text: $profileNotes, axis: .vertical)
                    .lineLimit(3...5)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            if profile.type == .remote {
                Section("Update Settings") {
                    TextField("User-Agent", text: $profileUserAgent)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Picker("Auto Update", selection: $updateInterval) {
                        ForEach(updateIntervalOptions, id: \.1) { option in
                            Text(option.0).tag(option.1)
                        }
                    }
                }
                
                Section("Connection") {
                    Toggle("Use System Proxy", isOn: $useSystemProxy)
                        .onChange(of: useSystemProxy) { _, newValue in
                            if newValue { useClashProxy = false }
                        }
                    
                    Toggle("Use Clash Proxy", isOn: $useClashProxy)
                        .onChange(of: useClashProxy) { _, newValue in
                            if newValue { useSystemProxy = false }
                        }
                }
            }
            
            Section("Metadata") {
                LabeledContent("Type") {
                    Text(profile.type == .remote ? "Remote" : "Local")
                        .foregroundStyle(profile.type == .remote ? .blue : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)
                }
                
                LabeledContent("Last Updated") {
                    Text(DateFormatters.mediumDateTime.string(from: profile.lastUpdated))
                        .foregroundStyle(.secondary)
                }
                
                if let lastAutoUpdate = profile.lastAutoUpdate {
                    LabeledContent("Last Auto Update") {
                        Text(DateFormatters.mediumDateTime.string(from: lastAutoUpdate))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var rightPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Configuration Content", systemImage: "doc.plaintext")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                HStack(spacing: 8) {
                    if showCopyConfirm {
                        Text("Copied!")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                    
                    Button(action: copyContent) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Simple Line Numbers (Static approximation based on line count)
                    // Note: True synced scrolling with TextEditor is complex in SwiftUI.
                    // This is a visual guide.
                    let lineCount = profileContent.components(separatedBy: .newlines).count
                    ScrollView(.vertical) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(Array(1...max(1, lineCount)).map(String.init).joined(separator: "\n"))
                                .font(.system(size: 13, design: .monospaced))
                                .lineSpacing(4) // Approximate adjustments
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 8)
                        }
                    }
                    .disabled(true) // Disable interaction for line numbers
                    .frame(width: 40)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    
                    Divider()
                    
                    TextEditor(text: $profileContent)
                        .font(.system(size: 13, design: .monospaced))
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
    }
    
    private var bottomBar: some View {
        HStack {
            if profile.type == .remote {
                Button(action: {
                    Task {
                        await ProfileManager.shared.updateProfile(profile)
                    }
                }) {
                    Label("Update Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .controlSize(.large)
            }
            
            Spacer()
            
            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.large)
            
            Button(action: saveProfile) {
                HStack {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    }
                    Text("Save")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .disabled(isSaving)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func loadProfileData() {
        profileName = profile.name
        profileURL = profile.url ?? ""
        profileNotes = profile.notes ?? ""
        profileUserAgent = profile.userAgent
        updateInterval = profile.updateInterval
        useSystemProxy = profile.useSystemProxy
        useClashProxy = profile.useClashProxy
        profileContent = ProfileManager.shared.getProfileContent(profile)
    }
    
    private func saveProfile() {
        isSaving = true
        
        var updatedProfile = profile
        updatedProfile.name = profileName
        updatedProfile.url = profile.type == .remote ? profileURL : nil
        updatedProfile.notes = profileNotes.isEmpty ? nil : profileNotes
        updatedProfile.userAgent = profileUserAgent.isEmpty ? "ClashForMacOS/1.0" : profileUserAgent
        updatedProfile.updateInterval = updateInterval
        updatedProfile.useSystemProxy = useSystemProxy
        updatedProfile.useClashProxy = useClashProxy
        
        ProfileManager.shared.updateProfileMetadata(updatedProfile)
        ProfileManager.shared.saveProfileContent(updatedProfile, content: profileContent)
        
        profile = updatedProfile
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
            isPresented = false
        }
    }
    
    private func copyContent() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(profileContent, forType: .string)
        
        withAnimation {
            showCopyConfirm = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopyConfirm = false
            }
        }
    }
}

struct EditorRow<Content: View>: View {
    let title: String
    @ViewBuilder let control: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            control
        }
    }
}
