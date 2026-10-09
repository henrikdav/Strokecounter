import CoreGraphics
import CoreImage
import ImageIO
import Vision

// Reads the text on a photographed scorecard page with Vision, on the device (no network). Each recognized line is
// split into words, each with its own box, because a table row often comes back as one line ("4 4 3 5 4").
// Only words and boxes are returned; finding the holes, par, index and lengths is done by the web app
// (parseScorecard in web/index.html), where it is tested.
enum ScorecardReader {
    // A page as the web app wants it: { width, height, words: [{ text, x, y, w, h }] }, with the word's center and
    // size in pixels and y growing downwards, like on screen.
    static func read(_ photo: CGImage, orientation: CGImagePropertyOrientation) -> [String: Any] {
        // The photo as taken, and the card cut out and straightened when its outline is found; each turned four
        // ways, since a wide card is often photographed sideways. A quick pass on each finds the one that reads
        // best (the most numbers), then the careful pass reads that one.
        let turns = { (o: CGImagePropertyOrientation) in [o, o.turnedRight, o.turnedLeft, o.turnedRight.turnedRight] }
        var candidates = turns(orientation).map { (photo, $0) }
        if let card = straightened(photo, orientation: orientation) { candidates += turns(.up).map { (card, $0) } }
        let scores = candidates.map { digitWords(page($0.0, orientation: $0.1, level: .fast)) }
        let best = zip(candidates, scores).max { $0.1 < $1.1 }?.0 ?? (photo, orientation)
        var result = page(best.0, orientation: best.1, level: .accurate)

        // Small lone digits in a sparse table (par 3, index 7) are often missed when the whole page is read at once.
        // Reading it again in overlapping bands, each a tenth of the page, finds most of them; a word is added
        // only where nothing was read yet.
        var words = result["words"] as? [[String: Any]] ?? []
        for y in stride(from: 0.0, to: 0.95, by: 0.05) {
            let band = CGRect(x: 0, y: y, width: 1, height: min(0.1, 1 - y))
            let found = page(best.0, orientation: best.1, level: .accurate, region: band)["words"] as? [[String: Any]] ?? []
            for word in found where !words.contains(where: { overlap($0, word) }) { words.append(word) }
        }
        result["words"] = words
        return result
    }

    // Whether two words' boxes overlap at all (a word read again in a band lands a little differently).
    private static func overlap(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        let v = { (w: [String: Any], k: String) in (w[k] as? Double) ?? 0 }
        return abs(v(a, "x") - v(b, "x")) < (v(a, "w") + v(b, "w")) / 2 && abs(v(a, "y") - v(b, "y")) < (v(a, "h") + v(b, "h")) / 2
    }

    // The card cut out of the photo and straightened, when Vision finds its outline (a photo taken at an angle
    // otherwise gives uneven columns). Nil when no outline is found; the photo is then read as it is.
    private static func straightened(_ photo: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let upright = CIImage(cgImage: photo).oriented(orientation)
        let request = VNDetectRectanglesRequest()
        request.minimumSize = 0.3
        request.minimumConfidence = 0.6
        request.quadratureTolerance = 30
        request.minimumAspectRatio = 0.15
        request.maximumObservations = 1
        try? VNImageRequestHandler(ciImage: upright).perform([request])
        guard let card = request.results?.first else { return nil }
        let size = upright.extent.size
        let point = { (p: CGPoint) in CIVector(cgPoint: CGPoint(x: p.x * size.width, y: p.y * size.height)) }
        let corrected = upright.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": point(card.topLeft), "inputTopRight": point(card.topRight),
            "inputBottomLeft": point(card.bottomLeft), "inputBottomRight": point(card.bottomRight)
        ])
        return CIContext().createCGImage(corrected, from: corrected.extent)
    }

    // Reads the page, or only a region of it (normalized, origin at the bottom left like Vision's own boxes).
    private static func page(_ image: CGImage, orientation: CGImagePropertyOrientation,
                             level: VNRequestTextRecognitionLevel,
                             region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> [String: Any] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.regionOfInterest = region
        // Scorecards are mostly numbers and short labels; correcting them towards dictionary words does harm.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["sv-SE", "en-US"]
        try? VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])

        let sideways = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
        let width = Double(sideways ? image.height : image.width)
        let height = Double(sideways ? image.width : image.height)
        var words: [[String: Any]] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            var start: String.Index?
            for i in text.indices + [text.endIndex] {
                let isSpace = i == text.endIndex || text[i].isWhitespace
                if !isSpace, start == nil { start = i }
                guard isSpace, let s = start else { continue }
                start = nil
                let range = s..<i
                // Vision's box is normalized within the region, with the origin at the bottom left.
                let inRegion = (try? candidate.boundingBox(for: range))??.boundingBox ?? observation.boundingBox
                let box = CGRect(x: region.minX + inRegion.minX * region.width, y: region.minY + inRegion.minY * region.height,
                                 width: inRegion.width * region.width, height: inRegion.height * region.height)
                words.append([
                    "text": String(text[range]),
                    "x": box.midX * width, "y": (1 - box.midY) * height,
                    "w": box.width * width, "h": box.height * height
                ])
            }
        }
        return ["width": width, "height": height, "words": words]
    }

    private static func digitWords(_ page: [String: Any]) -> Int {
        (page["words"] as? [[String: Any]] ?? []).filter { ($0["text"] as? String)?.contains(where: \.isNumber) == true }.count
    }
}

private extension CGImagePropertyOrientation {
    var turnedRight: CGImagePropertyOrientation {
        switch self {
        case .up: return .right
        case .right: return .down
        case .down: return .left
        case .left: return .up
        default: return .right
        }
    }

    var turnedLeft: CGImagePropertyOrientation {
        switch self {
        case .up: return .left
        case .left: return .down
        case .down: return .right
        case .right: return .up
        default: return .left
        }
    }
}
