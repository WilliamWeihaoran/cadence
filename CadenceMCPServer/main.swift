import Foundation
import MCP

do {
    let container = try CadenceModelContainerFactory.makeReadOnlyContainer()
    let service = CadenceReadService(container: container)
    let server = Server(
        name: "cadence-mcp",
        version: "0.1.0",
        capabilities: .init(tools: .init(listChanged: false))
    )
    let router = CadenceMCPToolRouter(service: service)
    await router.register(on: server)

    try await server.start(transport: StdioTransport())
    while true {
        try await Task.sleep(nanoseconds: 3_600_000_000_000)
    }
} catch {
    FileHandle.standardError.write(Data("CadenceMCPServer failed: \(error.localizedDescription)\n".utf8))
    Foundation.exit(1)
}
