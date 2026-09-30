import XCTest
@testable import CopyShot

final class ModeScopedQuickActionsTests: XCTestCase {
    func testVersionTwoDoesNotRemigrateLegacyFieldsWhenModesAreMissing() throws {
        let data = Data(#"{"schemaVersion":2,"actionOrder":["search_web"],"disabledActionIds":["search_web"]}"#.utf8)
        let config = try JSONDecoder().decode(QuickActionsConfig.self, from: data)
        XCTAssertEqual(config.modeConfiguration(for: .standardOCR), ActionRegistry.shared.defaultConfiguration(for: .standardOCR))
    }

    func testLegacyMigrationPreservesPreferencesAndDisablesOmittedActions() throws {
        let data = Data(#"{"actionOrder":["search_web","search_web","future_action"],"disabledActionIds":["search_web"],"searchEngine":"Kagi","defaultTranslateLanguage":"de","showNumericShortcuts":false,"playHapticsOnHover":false,"subActionOrder":{"change_case":["uppercase"]},"disabledSubActionIds":{"change_case":["lowercase"]}}"#.utf8)
        let config = try JSONDecoder().decode(QuickActionsConfig.self, from: data)
        let ocr = config.modeConfiguration(for: .standardOCR)
        XCTAssertEqual(ocr.actionOrder, ["search_web", "future_action", "change_case", "join_lines", "translate"])
        XCTAssertEqual(Set(ocr.disabledActionIds), ["search_web", "change_case", "join_lines", "translate"])
        XCTAssertEqual(config.searchEngine, .kagi)
        XCTAssertEqual(config.defaultTranslateLanguage, "de")
        XCTAssertFalse(config.showNumericShortcuts)
        XCTAssertFalse(config.playHapticsOnHover)
        XCTAssertEqual(config.subActionOrder["change_case"], ["uppercase"])
        XCTAssertEqual(config.disabledSubActionIds["change_case"], ["lowercase"])
        XCTAssertEqual(config.modeConfiguration(for: .table).disabledActionIds, ["table_tsv"])
        XCTAssertEqual(try JSONDecoder().decode(QuickActionsConfig.self, from: JSONEncoder().encode(config)), config)
    }

    func testMissingModesAndExplicitEmptyOrders() throws {
        let config = try JSONDecoder().decode(QuickActionsConfig.self, from: Data(#"{"schemaVersion":2,"modes":{"qrBarcode":{"actionOrder":[],"disabledActionIds":[]},"futureMode":{"actionOrder":["future"],"disabledActionIds":[]}}}"#.utf8))
        XCTAssertEqual(config.modeConfiguration(for: .qrBarcode).actionOrder, ["search_web", "copy_raw"])
        XCTAssertEqual(Set(config.modeConfiguration(for: .qrBarcode).disabledActionIds), ["search_web", "copy_raw"])
        XCTAssertEqual(config.modes["futureMode"]?.actionOrder, ["future"])
        XCTAssertEqual(config.modeConfiguration(for: .latex).actionOrder, ["latex_wrap_dollar", "search_math"])
    }

    func testNewCatalogEntriesAreAppendedDisabledAndModesAreIndependent() {
        var config = QuickActionsConfig()
        config.setModeConfiguration(.init(actionOrder: ["copy_raw", "copy_raw", "unknown"], disabledActionIds: []), for: .qrBarcode)
        let qr = config.modeConfiguration(for: .qrBarcode)
        XCTAssertEqual(qr.actionOrder, ["copy_raw", "unknown", "search_web"])
        XCTAssertEqual(qr.disabledActionIds, ["search_web"])
        XCTAssertEqual(config.modeConfiguration(for: .standardOCR).actionOrder, ["change_case", "join_lines", "search_web", "translate"])
        XCTAssertEqual(QuickAction.actions(for: "hello", mode: .qrBarcode, config: config).map(\.id), ["copy_raw"])
    }

    func testAvailabilityIsVisibleInCatalogButFilteredAtRuntime() {
        let registry = ActionRegistry(translationAvailable: false)
        let config = QuickActionsConfig()
        let catalog = registry.catalog(for: .standardOCR, config: config)
        XCTAssertEqual(catalog.map { $0.metadata.id }, ["change_case", "join_lines", "search_web", "translate"])
        XCTAssertNotNil(catalog.last?.unavailableReason)
        let actions = registry.actions(context: .init(payload: .standardText("hello")), config: config)
        XCTAssertEqual(actions.map(\.id), ["change_case", "join_lines", "search_web"])
        XCTAssertEqual(actions.map(\.shortcutNumber), [1, 2, 3])
    }

    func testRepeatedSubActionIDsResolveOnlyOnce() {
        var config = QuickActionsConfig()
        config.subActionOrder["change_case"] = ["uppercase", "uppercase", "lowercase"]
        let action = ActionRegistry.shared.actions(context: .init(payload: .standardText("sample")), config: config).first
        XCTAssertEqual(action?.subActions?.map(\.id), ["uppercase", "lowercase"])
        XCTAssertEqual(action?.subActions?.map(\.shortcutNumber), [1, 2])
    }

    func testProviderEntriesAppendDisabledAndCannotRunInIncompatibleMode() {
        struct Provider: ActionProvider {
            let definitions: [ActionDefinition] = [.init(
                metadata: .init(id: "future", title: "Future", description: "", icon: .system("star"), hasSubActions: false,
                                hasParameters: false, supportedModes: [.qrBarcode]), defaultEnabledModes: [.qrBarcode],
                makeAction: { _, _ in QuickAction(id: "future", title: "Future", icon: .system("star"), shortcutNumber: nil) }
            )]
        }
        let registry = ActionRegistry(providers: [BuiltInActionProvider(), Provider()])
        var config = QuickActionsConfig()
        let catalog = registry.catalog(for: .qrBarcode, config: config)
        XCTAssertEqual(catalog.last?.metadata.id, "future")
        XCTAssertEqual(catalog.last?.isEnabled, false)
        config.modes[CaptureMode.standardOCR.rawValue] = .init(actionOrder: ["future"], disabledActionIds: [])
        XCTAssertTrue(registry.actions(context: .init(payload: .standardText("sample")), config: config).isEmpty)
    }
}
