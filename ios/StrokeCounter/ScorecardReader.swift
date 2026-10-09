import CoreGraphics
import ImageIO
import Vision

// Reads the text on a photographed scorecard page with Vision, on the device (no network). Each recognized line is
// split into words, each with its own box, because a table row often comes back as one line ("4 4 3 5 4").
// Only words and boxes are returned; finding the holes, par, index and lengths is done by the web app
// (parseScorecard in web/index.html), where it is tested.
enum ScorecardReader {
    // A page as the web app wants it: { width, height, words: [{ text, x, y, w, h }] }, with the word's center and
    // size in pixels and y growing downwards, like on screen.
    static func read(_ image: CGImage, orientation: CGImagePropertyOrientation) -> [String: Any] {
        // A wide card is often photographed sideways. A quick pass in each direction finds which way it reads
        // (the most numbers), then the careful pass reads it that way.
        let turns = [orientation, orientation.turnedRight, orientation.turnedLeft, orientation.turnedRight.turnedRight]
        let scores = turns.map { digitWords(page(image, orientation: $0, level: .fast)) }
        let upright = zip(turns, scores).max { $0.1 < $1.1 }?.0 ?? orientation
        return page(image, orientation: upright, level: .accurate)
    }

    private static func page(_ image: CGImage, orientation: CGImagePropertyOrientation,
                             level: VNRequestTextRecognitionLevel) -> [String: Any] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
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
                // Vision's box is normalized with the origin at the bottom left.
                let box = (try? candidate.boundingBox(for: range))??.boundingBox ?? observation.boundingBox
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
