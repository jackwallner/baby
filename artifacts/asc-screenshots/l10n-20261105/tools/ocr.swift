import Foundation
import Vision

struct Job: Decodable { let path: String; let languages: [String]? }
struct Result: Encodable { let path: String; let lines: [String] }

do {
    let jobs = try JSONDecoder().decode([Job].self, from: FileHandle.standardInput.readDataToEndOfFile())
    var results: [Result] = []
    for job in jobs {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        if let languages = job.languages { request.recognitionLanguages = languages }
        let handler = VNImageRequestHandler(url: URL(fileURLWithPath: job.path), options: [:])
        try handler.perform([request])
        results.append(Result(path: job.path, lines: (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }))
    }
    print(String(data: try JSONEncoder().encode(results), encoding: .utf8)!)
} catch {
    FileHandle.standardError.write(Data("ocr: \(error)\n".utf8))
    exit(1)
}
