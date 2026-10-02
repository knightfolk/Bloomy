import AppKit
import DarkbloomTelemetry
import SwiftUI
import UniformTypeIdentifiers

struct SupportPacketPreviewPresentation: Identifiable {
    let id = UUID()
    let snapshot: SupportPacketSnapshot
}

struct SupportPacketDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(snapshot: SupportPacketSnapshot) {
        data = snapshot.data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              data.count <= SupportPacketSnapshot.maximumBytes else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard data.count <= SupportPacketSnapshot.maximumBytes else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

struct SupportPacketPreviewView: View {
    let snapshot: SupportPacketSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var reviewed = false
    @State private var showsSave = false
    @State private var resultMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review support report").font(.title2.bold())
            Text("\(snapshot.alertCount) alerts · \(snapshot.omittedAlertCount) omitted · \(snapshot.data.count) bytes")
                .foregroundStyle(.secondary)
            Text("Includes provider status, recognized model identifiers, activity counts, alerts, and recommendations, with observation times and sources. Logs, account IDs, credentials, balances, file paths, and connection addresses are excluded. Previewing creates no file; review the report before saving or sharing.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(verbatim: snapshot.previewText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            Toggle("I reviewed this report before saving or sharing", isOn: $reviewed)
                .toggleStyle(.checkbox)
            if let resultMessage {
                Text(resultMessage).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save JSON…") { showsSave = true }
                    .disabled(!reviewed)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 600, idealWidth: 700, minHeight: 550, idealHeight: 650)
        .fileExporter(
            isPresented: $showsSave,
            document: SupportPacketDocument(snapshot: snapshot),
            contentType: .json,
            defaultFilename: "darkbloom-support-packet"
        ) { result in
            switch result {
            case .success: resultMessage = "The reviewed report was saved."
            case .failure: resultMessage = "The report could not be saved. You can retry or close this preview."
            }
        }
    }
}
