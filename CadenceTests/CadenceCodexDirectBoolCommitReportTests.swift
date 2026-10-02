import Foundation
import Testing

@MainActor
struct CadenceCodexDirectBoolCommitReportTests {
    private func offenders(_ source: String) -> [String] {
        CadenceSaveCommitRule.directBoolClosureReportOffenders(in: source)
    }

    @Test func codexDirectBoolLiteralDiffersFromTheAllowedVoidFieldEdit() throws {
        let positive = """
        struct Page {
            var body: some View {
                row.dropDestination(for: String.self) { items, location in
                    task.priorityRaw = 2
                    try? modelContext.save()
                    return true
                }
            }
        }
        """
        let negative = positive.replacingOccurrences(
            of: "dropDestination(for: String.self)", with: "onChange(of: task.priorityRaw)"
        ).replacingOccurrences(of: "return true", with: "refresh()")
        #expect(offenders(positive) == ["Page.body"])
        #expect(offenders(negative).isEmpty)
        #expect(offenders(positive) != offenders(negative))
    }

    @Test func codexDirectBoolPrivateHelperRequiresExclusiveActionCallers() {
        let positive = """
        struct Page {
            var body: some View {
                row.dropDestination(for: String.self) { items, location in
                    persist()
                    return true
                }
            }
            private func persist() {
                task.priorityRaw = 2
                try? modelContext.save()
            }
        }
        """
        let mixed = positive.replacingOccurrences(of: "private func persist()", with: """
        private func refresh() { persist() }
        private func persist()
        """)
        let escaped = positive.replacingOccurrences(of: "private func persist()", with: """
        private var action: () -> Void { persist }
        private func persist()
        """)
        #expect(offenders(positive) == ["Page.persist"])
        #expect(offenders(mixed).isEmpty)
        #expect(offenders(escaped).isEmpty)
    }

    @Test func codexDirectBoolCustomParameterUsesItsReturnTypeNotItsInput() {
        let positive = """
        struct Page {
            private func accept(action: (Task) -> Bool) {}
            var body: some View {
                accept(action: { task in
                    task.priorityRaw = 2
                    try? modelContext.save()
                    return true
                })
            }
        }
        """
        let negative = positive.replacingOccurrences(of: "(Task) -> Bool", with: "(Bool) -> Void")
        #expect(offenders(positive) == ["Page.body"])
        #expect(offenders(negative).isEmpty)
    }

    @Test func codexDirectBoolMemberwiseParameterIsQualifiedByItsComponentType() {
        let source = """
        struct DropRow { let action: (Task) -> Bool }
        struct EditRow { let action: (Task) -> Void }
        struct Page {
            var body: some View {
                DropRow(action: { task in try? modelContext.save(); return true })
            }
            var editor: some View {
                EditRow(action: { task in try? modelContext.save() })
            }
        }
        """
        #expect(offenders(source) == ["Page.body"])
    }

    @Test func codexDirectBoolTargetNotificationAndNestedVoidClosuresStaySeparate() {
        let source = """
        struct Page {
            var body: some View {
                row.dropDestination(for: String.self) { items, location in
                    onChange(of: task.priorityRaw) { value in
                        try? modelContext.save()
                    }
                    return true
                } isTargeted: { targeted in
                    try? modelContext.save()
                }
            }
        }
        """
        #expect(offenders(source).isEmpty)
        let inline = source.replacingOccurrences(
            of: "onChange(of: task.priorityRaw) { value in\n                try? modelContext.save()\n            }",
            with: "try? modelContext.save()"
        )
        #expect(inline != source, "the paired control must actually move the save out of the nested closure")
        #expect(offenders(inline) == ["Page.body"])
    }

    @Test func codexDirectBoolCommentsAndLiteralsCannotSupplyAContractOrASave() {
        let source = #"""
        struct Page {
            // let action: () -> Bool
            var body: some View {
                Text("row.dropDestination(for: String.self) { try? modelContext.save(); return true }")
                onChange(of: task.priorityRaw) { value in try? modelContext.save() }
            }
        }
        """#
        #expect(offenders(source).isEmpty)
    }

    @Test func codexDirectBoolDoesNotTreatStoredVoidCallbackTransportAsDirect() {
        let source = """
        struct Column {
            let action: (Task) -> Void
            var body: some View {
                row.dropDestination(for: String.self) { items, location in
                    action(task)
                    return true
                }
            }
        }
        struct Page {
            var body: some View {
                Column(action: { task in try? modelContext.save() })
            }
        }
        """
        #expect(offenders(source).isEmpty,
                "coverage boundary, not permission: stored callback forwarding is outside the approved direct-only rule")
    }

    @Test func codexDirectBoolDoesNotGuessTheModernVoidDropOverloadFromItsName() {
        let source = """
        struct Page {
            var body: some View {
                row.dropDestination(for: String.self, isEnabled: true) { items, session in
                    try? modelContext.save()
                }
            }
        }
        """
        #expect(offenders(source).isEmpty)
    }

    @Test func codexDirectBoolThrowingOrNonPrivateHelpersAreNotAnExclusiveVoidProof() {
        let source = """
        struct Page {
            var body: some View {
                row.dropDestination(for: String.self) { items, location in
                    persist()
                    return true
                }
            }
            func persist() { try? modelContext.save() }
        }
        """
        #expect(offenders(source).isEmpty)
        #expect(offenders(source.replacingOccurrences(
            of: "func persist()", with: "private func persist() throws"
        )).isEmpty)
    }

    @Test func codexDirectBoolRuleIsWiredIntoTheExistingReportHalf() {
        let source = """
        struct Page {
            var body: some View {
                row.dropDestination(for: String.self) { items, location in
                    try? modelContext.save()
                    return true
                }
            }
        }
        """
        #expect(CadenceSaveCommitRule.reportOffenders(in: source) == ["body"],
                "the real-tree report sweep must call the new detector, not merely test it in isolation")
        #expect(CadenceSaveCommitRule.reportExemptions.isEmpty)
    }

    @Test func codexDirectBoolUnknownOverloadsAndExplicitInitializersAreNotProof() {
        let source = """
        struct Page {
            private func accept(action: (Task) -> Bool) {}
            private func accept(action: (Task) -> Void) {}
            var body: some View {
                accept(action: { task in try? modelContext.save(); return true })
            }
        }
        """
        #expect(offenders(source).isEmpty)
        let initializer = """
        struct Row {
            let action: (Task) -> Bool
            init(action: (Task) -> Void) {}
        }
        struct Page {
            var body: some View { Row(action: { task in try? modelContext.save(); return true }) }
        }
        """
        #expect(offenders(initializer).isEmpty)
    }

    @Test func codexDirectBoolControlFlowIsNotANestedCallbackButTaskIs() {
        let source = """
        struct Page {
            var body: some View {
                row.dropDestination(for: String.self) { items, location in
                    if ready { try? modelContext.save() }
                    return true
                }
            }
        }
        """
        #expect(offenders(source) == ["Page.body"])
        #expect(offenders(source.replacingOccurrences(
            of: "if ready", with: "Task"
        )).isEmpty)
        #expect(offenders(source.replacingOccurrences(of: "return true", with: "return false")).isEmpty)
    }

    @Test func codexDirectBoolNestedDeclarationCannotSupplyAcceptanceOrAnExclusiveCaller() {
        let source = """
        struct Page {
            var body: some View {
                row.dropDestination(for: String.self) { items, session in
                    func predicate() -> Bool { return true }
                    try? modelContext.save()
                }
            }
        }
        """
        #expect(offenders(source).isEmpty)
        let helper = """
        struct Page {
            var body: some View {
                row.dropDestination(for: String.self) { items, location in
                    func unrelated() { persist() }
                    return true
                }
            }
            private func persist() { try? modelContext.save() }
        }
        """
        #expect(offenders(helper).isEmpty)
    }
}
