import Foundation
import JavaScriptCore
import Testing
@testable import AbstractCore

@Suite struct DelegationPluginTests {
    var pluginFolder: URL {
        let here = URL(fileURLWithPath: #filePath)
        let repo = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return repo.appendingPathComponent("Abstract/Resources/Plugins/delegation.abstractplugin")
    }

    func evaluate(_ expression: String, args: [String] = []) throws -> JSONValue {
        let source = try String(contentsOf: pluginFolder.appendingPathComponent("background.js"), encoding: .utf8)
        let context = try #require(JSContext())
        context.evaluateScript(source)
        context.setObject(args, forKeyedSubscript: "__argTexts" as NSString)
        context.evaluateScript("const __args = __argTexts.map((text) => JSON.parse(text));")
        let result = context.evaluateScript("JSON.stringify(\(expression))")
        if let exception = context.exception {
            Issue.record("\(expression) threw: \(exception.toString() ?? "?")")
            return .null
        }
        let text = try #require(result?.toString())
        return JSONValue(any: try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed))
    }

    static let chats = #"[{"id":"parent","projectKey":"mac:project","branch":"feature","parentId":null},{"id":"child","projectKey":"mac:project","branch":"child-branch","parentId":"parent"},{"id":"grandchild","projectKey":"mac:project","branch":"grandchild-branch","parentId":"child"}]"#
    static let request = #"{"title":"Add tests","prompt":"Test the API","agent":"codex"}"#

    @Test func packageOffersTwoAgentTools() throws {
        let manifest = try PluginPackage.inspect(folder: pluginFolder).manifest
        #expect(manifest.id == "sh.abstract.delegation")
        #expect(manifest.background == "background.js")
        #expect(manifest.agentTools.map(\.name) == ["delegate", "wait_for"])
        #expect(manifest.grantedCapabilities.isSuperset(of: [.agentTools, .chatsCreate, .chatsMessage, .turnsRead]))
    }

    @Test func limitsAndCyclesAreRefused() throws {
        let empty = #"{"children":[],"waits":{}}"#
        #expect(try evaluate("Delegation.check(__args[0], __args[1], 'parent', __args[2]).agent",
                             args: [empty, Self.chats, Self.request]) == .string("codex"))
        let five = #"{"children":[{"parentId":"parent"},{"parentId":"parent"},{"parentId":"parent"},{"parentId":"parent"},{"parentId":"parent"}],"waits":{}}"#
        #expect(try evaluate("(() => { try { Delegation.check(__args[0], __args[1], 'parent', __args[2]); return ''; } catch (e) { return e.message; } })()",
                             args: [five, Self.chats, Self.request])
                == .string("A chat can have at most 5 sub-tasks (Settings › Agents)."))
        #expect(try evaluate("(() => { try { Delegation.check(__args[0], __args[1], 'grandchild', __args[2]); return ''; } catch (e) { return e.message; } })()",
                             args: [empty, Self.chats, Self.request]).string?.contains("two chats deep") == true)
        let cycle = #"[{"id":"a","parentId":"b"},{"id":"b","parentId":"a"}]"#
        #expect(try evaluate("(() => { try { Delegation.depth(__args[0], 'a'); return ''; } catch (e) { return e.message; } })()",
                             args: [cycle]).string?.contains("own sub-task") == true)
    }

    static func children(_ count: Int) -> String {
        let rows = Array(repeating: #"{"parentId":"parent"}"#, count: count).joined(separator: ",")
        return #"{"children":["# + rows + #"],"waits":{}}"#
    }

    static let refusal = "(() => { try { Delegation.check(__args[0], __args[1], 'parent', __args[2], __args[3]); return ''; } catch (e) { return e.message; } })()"

    @Test func theLimitComesFromThisMacInTheSnapshot() throws {
        // Settings › Agents › Sub-tasks per chat, sent for this Mac only (ABS-214).
        let snapshot = #"{"macs":[{"id":"other","isThisMac":false,"subtasksPerChat":2},{"id":"mac","isThisMac":true,"subtasksPerChat":8}]}"#
        #expect(try evaluate("Delegation.maxChildren(__args[0])", args: [snapshot]) == .number(8))

        // Eight start; the ninth is refused, naming eight and where to change it.
        #expect(try evaluate(Self.refusal, args: [Self.children(7), Self.chats, Self.request, "8"]) == .string(""))
        #expect(try evaluate(Self.refusal, args: [Self.children(8), Self.chats, Self.request, "8"])
                == .string("A chat can have at most 8 sub-tasks (Settings › Agents)."))

        // Lowered below what's running: nothing is touched, the next is refused.
        #expect(try evaluate(Self.refusal, args: [Self.children(3), Self.chats, Self.request, "2"])
                == .string("A chat can have at most 2 sub-tasks (Settings › Agents)."))
        #expect(try evaluate(Self.refusal, args: [Self.children(1), Self.chats, Self.request, "1"])
                == .string("A chat can have at most 1 sub-task (Settings › Agents)."))
    }

    @Test func anOlderMacFallsBackToFive() throws {
        for snapshot in [#"{"macs":[{"id":"mac","isThisMac":true}]}"#,
                         #"{"macs":[{"id":"mac","isThisMac":true,"subtasksPerChat":null}]}"#,
                         #"{"macs":[{"id":"other","isThisMac":false,"subtasksPerChat":8}]}"#,
                         #"{"macs":[]}"#, #"{}"#, "null"] {
            #expect(try evaluate("Delegation.maxChildren(__args[0])", args: [snapshot]) == .number(5))
        }
        #expect(try evaluate(Self.refusal, args: [Self.children(4), Self.chats, Self.request, "5"]) == .string(""))
    }

    @Test func reportsWaitForBothChildrenAndFailuresWakeEarly() throws {
        let waiting = #"{"children":[{"id":"a","parentId":"parent","title":"API","agent":"claude","outcome":"done","summary":"Added it","branch":"api","changedFiles":2},{"id":"b","parentId":"parent","title":"Tests","agent":"codex","outcome":null}],"waits":{"parent":["a","b"]}}"#
        #expect(try evaluate("Delegation.ready(__args[0], 'parent')", args: [waiting]) == .null)
        let finished = try evaluate("(() => { const s = __args[0]; Delegation.finish(s, 'b', 'done', 'Tests pass', 1, 'tests'); return Delegation.report(Delegation.ready(s, 'parent')); })()",
                                    args: [waiting]).string
        #expect(finished?.contains("Added it") == true)
        #expect(finished?.contains("Tests pass") == true)
        #expect(finished?.contains("Branch: tests") == true)
        let failed = try evaluate("(() => { const s = __args[0]; Delegation.finish(s, 'b', 'failed', 'Setup failed', 0, null); return Delegation.report(Delegation.ready(s, 'parent')); })()",
                                  args: [waiting]).string
        #expect(failed?.contains("failed") == true)
        #expect(failed?.contains("Setup failed") == true)
    }

    @Test func parentLinkPersistsAndRejectsCycles() throws {
        let store = try Store.inMemory()
        var parent = Session(id: "parent", projectId: nil, name: "Parent", providerId: "claude")
        try store.save(parent)
        var child = Session(id: "child", projectId: nil, name: "Child", providerId: "codex")
        child.parentSessionId = parent.id
        try store.save(child)
        #expect(try store.session("child")?.parentSessionId == "parent")
        let copied = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(child))
        #expect(copied.parentSessionId == "parent")
        parent.parentSessionId = child.id
        #expect(throws: Error.self) { try store.save(parent) }
        #expect(try store.session("parent")?.parentSessionId == nil)
    }

    @Test func creatingAChildThroughThePluginBridgeCarriesItsParentAndTitle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("abstract-delegation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PluginStorage(directory: root, pluginId: "sh.abstract.delegation")
        var bridge = PluginBridge(capabilities: [.chatsCreate], alwaysAllowedActions: [.chatsCreate])
        bridge.knownChatIds = ["parent"]
        bridge.knownProjectKeys = ["mac:project"]
        let message = #"{"api":2,"type":"createChat","id":"1","payload":{"parentId":"parent","projectKey":"mac:project","title":"Add tests","prompt":"Test the API","agentId":"codex"}}"#
        guard case .action(_, let action) = bridge.handle(message, storage: storage) else {
            Issue.record("The child action was refused")
            return
        }
        #expect(action.parentId == "parent")
        #expect(action.title == "Add tests")
        #expect(action.agentId == "codex")
        let unknown = message.replacingOccurrences(of: "\"parentId\":\"parent\"", with: "\"parentId\":\"unknown\"")
        guard case .refused = bridge.handle(unknown, storage: storage) else {
            Issue.record("An unknown parent was accepted")
            return
        }
    }
}
