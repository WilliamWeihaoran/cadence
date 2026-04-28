import Foundation
import MCP
import SwiftData

do {
    let container = try CadenceModelContainerFactory.makeReadWriteContainer()
    let context = ModelContext(container)
    let readService = CadenceReadService(context: context)
    let writeService = CadenceWriteService(context: context, notifiesExternalWrites: true)
    let server = Server(
        name: "cadence-mcp",
        version: "0.1.0",
        capabilities: .init(tools: .init(listChanged: false))
    )
    let router = CadenceMCPToolRouter(readService: readService, writeService: writeService)
    await router.register(on: server)

    try await server.start(transport: StdioTransport())
    while true {
        try await Task.sleep(nanoseconds: 3_600_000_000_000)
    }
} catch {
    FileHandle.standardError.write(Data("CadenceMCPServer failed: \(error.localizedDescription)\n".utf8))
    Foundation.exit(1)
}
