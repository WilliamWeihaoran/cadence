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
    // `performsMigrations: false` / `preparesStore: false`, and neither is a decision to skip a
    // migration (T-309). Read-only never migrated — the store is opened `allowsSave: false`, so a
    // migration pass there could only fail. Read-write has already migrated:
    // `makeReadWriteContainer()` ran `CadenceMCPStorePreparation.prepare` above, and these two
    // services used to re-run it, giving one launch four note migrations, two tag seed/sync passes
    // and two integrity repairs against a live store before the first tool call.
    let readService = CadenceReadService(context: context, performsMigrations: false)
    let writeService: CadenceWriteService?
    if writesEnabled {
        // No `try` on the initializer itself: `CadenceWriteService.init(context:…)` is not
        // throwing. The only throwing call here is `defaultLogger()`, which carries its own.
        writeService = CadenceWriteService(
            context: context,
            notifiesExternalWrites: true,
            auditLogger: try CadenceMCPAuditLogger.defaultLogger(),
            preparesStore: false
        )
    } else {
        writeService = nil
    }
    // **Two literals, one number, and they have to agree.** This is the version in the
    // `initialize` handshake; `CadenceMCPToolDefinitions.serverVersion` is the one `mcp_diagnostics`
    // answers with. A client reads whichever it happens to ask for, so a bump applied to one of
    // them advertises two different protocol versions from one process. Found by the smoke test
    // printing `0.5.0` from the handshake while the diagnostics tool already said `0.6.0` (T-414);
    // `CadenceMCPToolContractTests.theTwoAdvertisedServerVersionsAreOneNumber` now pins the pair.
    let server = Server(
        name: "cadence-mcp",
        version: "0.6.0",
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
