import Vision

enum OdometerOCR {
    /// Returns plausible odometer readings found in the image, best guess first.
    static func readings(in image: PlatformImage) async -> [Double] {
        guard let (cgImage, orientation) = image.cgImageWithOrientation else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try? handler.perform([request])
            let observations = request.results ?? []
            let strings = observations.compactMap { $0.topCandidates(1).first }
            return rank(strings.map { ($0.string, Double($0.confidence)) })
        }.value
    }

    /// Pulls digit runs of 3–7 digits out of recognized strings and ranks them:
    /// 5–6 digit values (typical odometers) first, then by OCR confidence.
    static func rank(_ recognized: [(text: String, confidence: Double)]) -> [Double] {
        var candidates: [(value: Double, digits: Int, confidence: Double)] = []
        for (text, confidence) in recognized {
            let cleaned = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
            for match in cleaned.matches(of: /\d{3,7}/) {
                let digits = String(match.output)
                guard let value = Double(digits) else { continue }
                candidates.append((value, digits.count, confidence))
            }
        }
        func preference(_ digits: Int) -> Int { (5...6).contains(digits) ? 0 : 1 }
        let sorted = candidates.sorted {
            (preference($0.digits), -$0.confidence, -Double($0.digits)) <
                (preference($1.digits), -$1.confidence, -Double($1.digits))
        }
        var seen = Set<Double>()
        return sorted.compactMap { seen.insert($0.value).inserted ? $0.value : nil }
    }
}
