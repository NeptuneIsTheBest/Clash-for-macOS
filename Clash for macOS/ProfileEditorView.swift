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
    @State private var yamlError: String?
    

    
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
                    
                    HStack {
                        Text("Auto Update (min)")
                        Spacer()
                        TextField("", value: $updateInterval, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                            .onSubmit {
                                if updateInterval < 0 {
                                    updateInterval = 0
                                }
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
            
            LineNumberTextEditor(text: $profileContent)
                .onChange(of: profileContent) { _, _ in
                    yamlError = nil
                }
            
            if let error = yamlError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Invalid YAML: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
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
            .disabled(isSaving || yamlError != nil)
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
        if let error = ProfileManager.shared.validateYAML(profileContent) {
            yamlError = error
            return
        }
        
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
        
        do {
            let normalizedContent = try ProfileManager.shared.validateAndNormalizeYAML(profileContent)
            ProfileManager.shared.saveProfileContent(updatedProfile, content: normalizedContent)
        } catch {
            ProfileManager.shared.saveProfileContent(updatedProfile, content: profileContent)
        }
        
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

struct LineNumberTextEditor: NSViewRepresentable {
    @Binding var text: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let textView = LineNumberTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.delegate = context.coordinator
        
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        
        scrollView.documentView = textView
        
        let lineNumberRuler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = lineNumberRuler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        
        textView.string = text
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LineNumberTextEditor
        
        init(_ parent: LineNumberTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

class LineNumberTextView: NSTextView {
    override func didChangeText() {
        super.didChangeText()
        if let ruler = enclosingScrollView?.verticalRulerView as? LineNumberRulerView {
            ruler.needsDisplay = true
        }
    }
}

class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    
    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 40
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }
    
    @objc private func boundsDidChange(_ notification: Notification) {
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.withAlphaComponent(0.5).setFill()
        dirtyRect.fill()
        
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        
        let visibleRect = scrollView?.contentView.bounds ?? bounds
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        
        let text = textView.string as NSString
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        
        var lineNumber = 1
        for i in 0..<characterRange.location {
            if text.character(at: i) == UInt16(UnicodeScalar("\n").value) {
                lineNumber += 1
            }
        }
        
        var index = characterRange.location
        while index < characterRange.location + characterRange.length {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let glyphRangeForLine = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRangeForLine, in: textContainer)
            lineRect.origin.y += textView.textContainerInset.height - visibleRect.origin.y
            
            let lineString = "\(lineNumber)" as NSString
            let stringSize = lineString.size(withAttributes: attributes)
            let drawPoint = NSPoint(
                x: ruleThickness - stringSize.width - 8,
                y: lineRect.origin.y + (lineRect.height - stringSize.height) / 2
            )
            lineString.draw(at: drawPoint, withAttributes: attributes)
            
            lineNumber += 1
            index = lineRange.location + lineRange.length
        }
    }
}
