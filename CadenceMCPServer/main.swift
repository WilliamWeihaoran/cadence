import Foundation
import MCP
import SwiftData

do {
    let writesEnabled = CadenceModelContainerFactory.writesEnabled
    let container: ModelContainer
    if writesEnabled {
        container = try CadenceModelContainerFactory.makeReadWriteContainer()
    } else {
        container = try CadenceModelContainerFactory.makeReadOnlyContainer()
    }
    let context = ModelContext(container)
    let readService = CadenceReadService(context: context, performsMigrations: writesEnabled)
    let writeService: CadenceWriteService?
    if writesEnabled {
        // No `try` on the initializer itself: `CadenceWriteService.init(context:…)` is not
        // throwing. The only throwing call here is `defaultLogger()`, which carries its own.
        writeService = CadenceWriteService(
            context: context,
            notifiesExternalWrites: true,
            auditLogger: try CadenceMCPAuditLogger.defaultLogger()
        )
    } else {
        writeService = nil
    }
    let server = Server(
        name: "cadence-mcp",
        version: "0.4.0",
        capabilities: .init(tools: .init(listChanged: false))
    )
    let router = CadenceMCPToolRouter(readService: readService, writeService: writeService, writesEnabled: writesEnabled)
    await router.register(on: server)

    try await server.start(transport: StdioTransport())
    while true {
        try await Task.sleep(nanoseconds: 3_600_000_000_000)
    }
} catch {
    FileHandle.standardError.write(Data("CadenceMCPServer failed: \(error.localizedDescription)\n".utf8))
    Foundation.exit(1)
}
