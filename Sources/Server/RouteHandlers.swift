import Foundation
import FlyingFox

private let cacheControl = HTTPHeader("Cache-Control")
private let accessControlAllowOrigin = HTTPHeader("Access-Control-Allow-Origin")

extension MoremaidServer {
    func handleView(request: HTTPRequest) async -> HTTPResponse {
        guard let projectManager else {
            return HTTPResponse(statusCode: .internalServerError)
        }

        let query = request.query
        guard let projectIDString = query["project"],
              let projectID = UUID(uuidString: projectIDString),
              let filePath = query["file"] else {
            return HTTPResponse(statusCode: .badRequest,
                headers: [.contentType: "text/plain"],
                body: Data("Missing project or file parameter".utf8))
        }

        let project = await MainActor.run { projectManager.project(for: projectID) }
        guard let project else {
            return HTTPResponse(statusCode: .notFound,
                headers: [.contentType: "text/plain"],
                body: Data("Project not found".utf8))
        }

        guard let resolvedPath = PathSecurity.resolve(file: filePath, inProject: project.path) else {
            return HTTPResponse(statusCode: .forbidden)
        }

        let content: String
        do {
            content = try String(contentsOfFile: resolvedPath, encoding: .utf8)
        } catch {
            return HTTPResponse(statusCode: .notFound,
                headers: [.contentType: "text/plain"],
                body: Data("File not found".utf8))
        }

        let fileName = (filePath as NSString).lastPathComponent
        let searchQuery = query["search"]

        // Get file stats
        let fileStats = try? FileManager.default.attributesOfItem(atPath: resolvedPath)
        let modifiedDate = fileStats?[.modificationDate] as? Date
        let fileSize = fileStats?[.size] as? Int

        let forceTheme = project.themeOverride
        let embedded = query["app"] == "1"

        let html: String
        if isMarkdownFile(filePath) {
            html = HTMLGenerator.markdownPage(
                content: content,
                title: fileName,
                forceTheme: forceTheme,
                searchQuery: searchQuery,
                modifiedDate: modifiedDate,
                fileSize: fileSize,
                projectID: project.id,
                embedded: embedded
            )
        } else {
            html = HTMLGenerator.codePage(
                content: content,
                fileName: fileName,
                forceTheme: forceTheme,
                modifiedDate: modifiedDate,
                fileSize: fileSize,
                embedded: embedded
            )
        }

        return HTTPResponse(
            statusCode: .ok,
            headers: [
                .contentType: "text/html; charset=utf-8",
                cacheControl: "no-cache, no-store, must-revalidate",
            ],
            body: Data(html.utf8)
        )
    }

    func handleRawFile(request: HTTPRequest) async -> HTTPResponse {
        guard let projectManager else {
            return HTTPResponse(statusCode: .internalServerError)
        }

        let query = request.query
        guard let projectIDString = query["project"],
              let projectID = UUID(uuidString: projectIDString),
              let filePath = query["path"] else {
            return HTTPResponse(
                statusCode: .badRequest,
                headers: [.contentType: "text/plain"],
                body: Data("Missing project or path parameter".utf8)
            )
        }

        let project = await MainActor.run { projectManager.project(for: projectID) }
        guard let project else {
            return HTTPResponse(statusCode: .notFound)
        }

        guard let resolvedPath = PathSecurity.resolve(file: filePath, inProject: project.path) else {
            return HTTPResponse(statusCode: .forbidden)
        }

        guard let content = try? String(contentsOfFile: resolvedPath, encoding: .utf8) else {
            return HTTPResponse(
                statusCode: .notFound,
                headers: [.contentType: "text/plain"],
                body: Data("File not found".utf8)
            )
        }

        return HTTPResponse(
            statusCode: .ok,
            headers: [
                .contentType: "text/plain; charset=utf-8",
                accessControlAllowOrigin: "*",
            ],
            body: Data(content.utf8)
        )
    }

    func handlePDF(request: HTTPRequest) async -> HTTPResponse {
        guard let projectManager else {
            return HTTPResponse(statusCode: .internalServerError)
        }

        let query = request.query
        guard let projectIDString = query["project"],
              let projectID = UUID(uuidString: projectIDString),
              let filePath = query["file"] else {
            return HTTPResponse(
                statusCode: .badRequest,
                headers: [.contentType: "text/plain"],
                body: Data("Missing project or file parameter".utf8)
            )
        }

        let project = await MainActor.run { projectManager.project(for: projectID) }
        guard let project else {
            return HTTPResponse(statusCode: .notFound)
        }

        guard let resolvedPath = PathSecurity.resolve(file: filePath, inProject: project.path) else {
            return HTTPResponse(statusCode: .forbidden)
        }

        guard let content = try? String(contentsOfFile: resolvedPath, encoding: .utf8) else {
            return HTTPResponse(
                statusCode: .notFound,
                headers: [.contentType: "text/plain"],
                body: Data("File not found".utf8)
            )
        }

        let fileName = (filePath as NSString).lastPathComponent
        let html = HTMLGenerator.markdownPage(
            content: content,
            title: fileName,
            forceTheme: project.themeOverride,
            searchQuery: nil,
            modifiedDate: nil,
            fileSize: nil,
            projectID: project.id
        )

        do {
            let pdfData = try await PDFGenerator.generatePDF(from: html)
            let contentDisposition = HTTPHeader("Content-Disposition")
            let pdfFileName = fileName.replacingOccurrences(of: ".md", with: ".pdf")
            return HTTPResponse(
                statusCode: .ok,
                headers: [
                    .contentType: "application/pdf",
                    contentDisposition: "attachment; filename=\"\(pdfFileName)\"",
                ],
                body: pdfData
            )
        } catch {
            return HTTPResponse(
                statusCode: .internalServerError,
                headers: [.contentType: "text/plain"],
                body: Data("PDF generation failed: \(error.localizedDescription)".utf8)
            )
        }
    }

    func handleSearch(request: HTTPRequest) async -> HTTPResponse {
        guard let projectManager else {
            return HTTPResponse(statusCode: .internalServerError)
        }

        let query = request.query
        guard let projectIDString = query["project"],
              let projectID = UUID(uuidString: projectIDString),
              let searchQuery = query["q"] else {
            return HTTPResponse(
                statusCode: .badRequest,
                headers: [.contentType: "application/json"],
                body: Data("{\"error\":\"Missing parameters\"}".utf8)
            )
        }

        let project = await MainActor.run { projectManager.project(for: projectID) }
        guard let project else {
            return HTTPResponse(statusCode: .notFound)
        }

        let searchMode = query["mode"] ?? "filename"
        let filter = query["filter"] ?? "*.md"

        let results = ContentSearch.search(
            query: searchQuery,
            inProject: project.path,
            mode: searchMode == "content" ? .content : .filename,
            filter: filter == "*" ? .allFiles : .markdownOnly
        )

        let data = (try? JSONEncoder().encode(results)) ?? Data("[]".utf8)

        return HTTPResponse(
            statusCode: .ok,
            headers: [
                .contentType: "application/json",
                accessControlAllowOrigin: "*",
            ],
            body: data
        )
    }
}
