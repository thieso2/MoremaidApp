import Foundation
import FlyingFox

actor MoremaidServer {
    private let port: UInt16
    private var server: HTTPServer?
    var projectManager: ProjectManager?

    init(port: UInt16) {
        self.port = port
    }

    func start(projectManager: ProjectManager) async throws {
        self.projectManager = projectManager

        let server = HTTPServer(address: .loopback(port: port))
        self.server = server

        await server.appendRoute("GET /favicon.ico") { _ in
            HTTPResponse(statusCode: .noContent)
        }

        await server.appendRoute("GET /view") { [weak self] request in
            guard let self else {
                return HTTPResponse(statusCode: .internalServerError)
            }
            return await self.handleView(request: request)
        }

        await server.appendRoute("GET /api/file") { [weak self] request in
            guard let self else {
                return HTTPResponse(statusCode: .internalServerError)
            }
            return await self.handleRawFile(request: request)
        }

        await server.appendRoute("GET /api/search") { [weak self] request in
            guard let self else {
                return HTTPResponse(statusCode: .internalServerError)
            }
            return await self.handleSearch(request: request)
        }

        await server.appendRoute("GET /api/pdf") { [weak self] request in
            guard let self else {
                return HTTPResponse(statusCode: .internalServerError)
            }
            return await self.handlePDF(request: request)
        }

        await server.appendRoute("GET /ws", to: .webSocket(LiveReloadHandler()))

        try await server.run()
    }

    func stop() {
        Task {
            await server?.stop(timeout: 3)
        }
    }
}
