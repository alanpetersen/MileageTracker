import SwiftUI

enum EntryField: Hashable {
    case odometer, quantity, cost
}

/// Odometer field with a camera button that runs OCR and lets the user confirm the detected value.
struct OdometerCaptureSection: View {
    @Binding var odometerText: String
    @Binding var source: ReadingSource
    @Binding var photoData: Data?
    var focus: FocusState<EntryField?>.Binding
    var placeholder = "Odometer (mi)"
    /// Open the camera as soon as the form appears.
    var autoScan = false
    /// Called after a scan fills in the odometer, so the form can jump to the next field.
    var onScanned: () -> Void = {}

    @State private var showingCamera = false
    @State private var isReading = false
    @State private var candidates: [Double] = []
    @State private var ocrMessage: String?

    var body: some View {
        Section {
            HStack {
                TextField(placeholder, text: $odometerText)
                    .decimalKeyboard()
                    .focused(focus, equals: .odometer)
                    .onChange(of: odometerText) { _, _ in
                        // Typing over a scanned value makes it a manual entry.
                        if !isReading, source == .camera, !candidates.contains(where: { format($0) == odometerText }) {
                            source = .manual
                        }
                    }
                Button("Scan odometer", systemImage: "camera.viewfinder") { showingCamera = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            if isReading { HStack { ProgressView(); Text("Reading odometer…") } }
            if candidates.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(candidates.prefix(5), id: \.self) { value in
                            Button(format(value)) { odometerText = format(value) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            if let ocrMessage { Text(ocrMessage).font(.caption).foregroundStyle(.secondary) }
            if let photoData, let image = PlatformImage(data: photoData) {
                Image(platformImage: image).resizable().scaledToFit().frame(maxHeight: 120).clipShape(.rect(cornerRadius: 8))
            }
        } header: {
            Text("Odometer")
        } footer: {
            Text("Scan with the camera or type the reading. Always double-check scanned values.")
        }
        .photoCapture(isPresented: $showingCamera) { image in process(image) }
        .task {
            guard autoScan else { return }
            // Let the sheet finish presenting before stacking the camera on top of it.
            try? await Task.sleep(for: .milliseconds(500))
            showingCamera = true
        }
    }

    private func process(_ image: PlatformImage) {
        photoData = image.jpegBytes(quality: 0.7)
        isReading = true
        ocrMessage = nil
        Task {
            let found = await OdometerOCR.readings(in: image)
            candidates = found
            if let best = found.first {
                odometerText = format(best)
                source = .camera
                onScanned()
            } else {
                ocrMessage = "Couldn't find a reading in the photo — please type it in."
                focus.wrappedValue = .odometer
            }
            isReading = false
        }
    }

    private func format(_ value: Double) -> String { String(Int(value)) }
}
