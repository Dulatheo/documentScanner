import Foundation

/// Test integration with CloudConvert (cloudconvert.com) — a paid cloud
/// conversion API — as an alternative source for DOCX/XLSX/PPTX export
/// (DESIGN_SPEC §5/§9 "Office format export"), tried because the
/// hand-rolled OCR-geometry heuristics in DocxExportService/
/// XlsxExportService/PptxExportService (kept intact and simply unused for
/// now — see `ExportSheetView`) produced layout that looked noticeably off
/// from the real scan. This converts the same PDF already generated for
/// plain PDF export (`PDFExportService`'s output, invisible OCR text layer
/// and all) via CloudConvert's own conversion engine, which does real
/// layout reconstruction rather than approximating it from OCR line boxes.
///
/// Needs `CloudConvertConfig.apiKey` set (see `CloudConvertConfig.swift.example`
/// — the real file is gitignored, never committed). This directly embeds a
/// paid API key in the app, which is fine for local testing but must NOT
/// ship this way: anyone can decompile a release build and extract the key
/// to run up charges on the developer's account. Before shipping, route
/// this through a backend proxy that holds the key server-side instead.
enum CloudConvertError: Error, LocalizedError {
    case missingAPIKey
    case taskNotFound(String)
    case jobFailed(String)
    case timeout
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "CloudConvert API key not configured — see CloudConvertConfig.swift.example"
        case .taskNotFound(let name):
            return "CloudConvert task \"\(name)\" not found in job response"
        case .jobFailed(let message):
            return "CloudConvert job failed: \(message)"
        case .timeout:
            return "CloudConvert conversion timed out"
        case .invalidResponse:
            return "CloudConvert returned an unexpected response"
        }
    }
}

enum CloudConvertService {
    private static let baseURL = "https://api.cloudconvert.com/v2"
    private static let pollIntervalNanoseconds: UInt64 = 2_000_000_000
    private static let pollTimeoutSeconds: TimeInterval = 120

    /// Converts the PDF at `pdfURL` to `outputFormat` ("docx"/"xlsx"/"pptx")
    /// via CloudConvert, returning a local URL to the downloaded result
    /// named `filenameBase.<outputFormat>`.
    static func convert(pdfURL: URL, outputFormat: String, filenameBase: String) async throws -> URL {
        guard !CloudConvertConfig.apiKey.isEmpty else { throw CloudConvertError.missingAPIKey }
        let apiKey = CloudConvertConfig.apiKey

        let job = try await createJob(apiKey: apiKey, outputFormat: outputFormat)
        guard let jobId = job["id"] as? String else { throw CloudConvertError.invalidResponse }
        let importTask = try findTask(job, name: "import-file")
        try await uploadFile(importTask: importTask, fileURL: pdfURL)

        let finishedJob = try await pollUntilFinished(apiKey: apiKey, jobId: jobId)
        let exportTask = try findTask(finishedJob, name: "export-file")
        guard
            let result = exportTask["result"] as? [String: Any],
            let files = result["files"] as? [[String: Any]],
            let fileURLString = files.first?["url"] as? String,
            let fileURL = URL(string: fileURLString)
        else {
            throw CloudConvertError.invalidResponse
        }

        return try await downloadFile(from: fileURL, filename: "\(filenameBase).\(outputFormat)")
    }

    private static func createJob(apiKey: String, outputFormat: String) async throws -> [String: Any] {
        let body: [String: Any] = [
            "tasks": [
                "import-file": ["operation": "import/upload"],
                "convert-file": [
                    "operation": "convert",
                    "input": "import-file",
                    "input_format": "pdf",
                    "output_format": outputFormat,
                ],
                "export-file": [
                    "operation": "export/url",
                    "input": "convert-file",
                ],
            ],
        ]
        var request = URLRequest(url: URL(string: "\(baseURL)/jobs")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let json = try await performRequest(request)
        guard let data = json["data"] as? [String: Any] else { throw CloudConvertError.invalidResponse }
        return data
    }

    private static func findTask(_ job: [String: Any], name: String) throws -> [String: Any] {
        guard let tasks = job["tasks"] as? [[String: Any]] else { throw CloudConvertError.invalidResponse }
        guard let task = tasks.first(where: { ($0["name"] as? String) == name }) else {
            throw CloudConvertError.taskNotFound(name)
        }
        return task
    }

    private static func uploadFile(importTask: [String: Any], fileURL: URL) async throws {
        guard
            let result = importTask["result"] as? [String: Any],
            let form = result["form"] as? [String: Any],
            let urlString = form["url"] as? String,
            let uploadURL = URL(string: urlString),
            let parameters = form["parameters"] as? [String: Any]
        else {
            throw CloudConvertError.invalidResponse
        }

        let boundary = "----DocumentScannerBoundary\(UUID().uuidString)"
        var body = Data()
        for (key, value) in parameters {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CloudConvertError.invalidResponse
        }
    }

    private static func pollUntilFinished(apiKey: String, jobId: String) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(pollTimeoutSeconds)
        while true {
            var request = URLRequest(url: URL(string: "\(baseURL)/jobs/\(jobId)")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let json = try await performRequest(request)
            guard let job = json["data"] as? [String: Any], let status = job["status"] as? String else {
                throw CloudConvertError.invalidResponse
            }
            if status == "finished" { return job }
            if status == "error" {
                let message = (job["message"] as? String) ?? "unknown error"
                throw CloudConvertError.jobFailed(message)
            }
            if Date() > deadline { throw CloudConvertError.timeout }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
    }

    private static func downloadFile(from url: URL, filename: String) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CloudConvertError.invalidResponse
        }
        return ImageStore.writeExportFile(data: data, filename: filename)
    }

    private static func performRequest(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw CloudConvertError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw CloudConvertError.jobFailed(message)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudConvertError.invalidResponse
        }
        return json
    }
}
