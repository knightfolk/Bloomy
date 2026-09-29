import SwiftUI
import VisionKit

struct PairingView: View {
    @Environment(CompanionStore.self) private var store
    @State private var scannerPresented = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(.mint)
                        Text("Pair with your Mac")
                            .font(.largeTitle.bold())
                        Text("Scan the one-time code in Bloomy. Your phone and Mac create device identities; there is no shared password.")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    if store.connection == .pairing {
                        ProgressView("Creating secure pairing…")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if case let .awaitingApproval(code) = store.connection {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Approve on the Mac", systemImage: "macbook.and.iphone")
                                .font(.headline)
                            Text(code)
                                .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                                .tracking(6)
                                .accessibilityLabel("Comparison code \(code.map(String.init).joined(separator: " "))")
                            Text("Confirm that this six-digit code matches Bloomy, then approve this iPhone on the Mac.")
                                .foregroundStyle(.secondary)
                            Button("I approved it — connect") {
                                Task { await store.connectAfterApproval() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        Button {
                            scannerPresented = true
                        } label: {
                            Label("Scan pairing code", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Simulator or manual code").font(.headline)
                            TextField("dc-pair:1:…", text: $store.qrText, axis: .vertical)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button("Use pasted code") {
                                Task { await store.pair(scannedCode: store.qrText) }
                            }
                            .disabled(store.qrText.isEmpty)
                        }
                    }

                    Label("LAN and user-managed Tailscale routes are supported. Tailscale stays outside this app for the first release.", systemImage: "network")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let error = store.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("pairingError")
                    }
                }
                .padding(24)
            }
            .navigationTitle("Bloomy")
            .sheet(isPresented: $scannerPresented) {
                QRScannerView { value in
                    scannerPresented = false
                    Task { await store.pair(scannedCode: value) }
                }
                .ignoresSafeArea()
            }
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    let onCode: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: @MainActor (String) -> Void
        init(onCode: @escaping @MainActor (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case let .barcode(code) = item, let value = code.payloadStringValue {
                    dataScanner.stopScanning(); onCode(value); return
                }
            }
        }
    }
}
