import XCTest
import SwiftUI
import AppKit
import EventKit
import CoreLocation
import MapKit
import Contacts
import ServiceManagement
@testable import DockGrove

// MARK: - Utilities

@MainActor final class IntegrationsUtilitiesTests: XCTestCase {
    private func utilities() -> (Utilities, IntegrationsEventAccess) {
        let utility = Utilities(store: IntegrationsUI.defaults(self))
        let access = IntegrationsEventAccess()
        utility.reminderStore = access
        utility.chooseDirectory = { XCTFail("Unexpected folder panel"); return nil }
        utility.sampleColor = { _ in XCTFail("Unexpected color sampler") }
        utility.capture = { XCTFail("Unexpected capture"); return nil }
        utility.setLoginItem = { _ in XCTFail("Unexpected login item change") }
        utility.chime = {}
        return (utility, access)
    }

    func testBookmarksPreferencesAndWaterReminder() {
        for odd in ["://example.com", "/://example.com", "?://example.com", "#://example.com"] { XCTAssertNil(Bookmark.url(odd)) }
        XCTAssertNil(Bookmark.url("ftp://example.com"))
        XCTAssertEqual(Bookmark.url("example.com")?.absoluteString, "https://example.com")
        let (utility, _) = utilities()
        utility.zones = ["UTC"]; XCTAssertEqual(utility.store.stringArray(forKey: "worldClockZones"), ["UTC"])
        utility.waterGoal = 6; XCTAssertEqual(utility.store.integer(forKey: "waterGoal"), 6)
        var chimes = 0
        utility.chime = { chimes += 1 }
        utility.timer?.fire(); IntegrationsUI.spin(0.05)
        XCTAssertFalse(utility.waterDue)
        utility.waterReminder = true
        XCTAssertTrue(utility.store.bool(forKey: "waterReminder"))
        utility.nextDrink = Date().addingTimeInterval(-1)
        utility.timer?.fire()
        XCTAssertTrue(IntegrationsUI.wait { utility.waterDue })
        XCTAssertEqual(chimes, 1)
        XCTAssertGreaterThan(utility.nextDrink, Date())
        Utilities.playChime()
        _ = LoginService.status()
    }

    func testNewestFolderSortToleratesMissingFiles() throws {
        let folder = try IntegrationsUI.temporaryDirectory(self)
        let old = folder.appendingPathComponent("old.txt"), new = folder.appendingPathComponent("new.txt")
        try Data().write(to: old); try Data().write(to: new)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: old.path)
        let (utility, _) = utilities()
        utility.folderItems = [old, folder.appendingPathComponent("gone-a"), new, folder.appendingPathComponent("gone-b")]
        utility.folderSort = "Newest"
        XCTAssertEqual(utility.sortedFolderItems.prefix(2).map(\.lastPathComponent), ["new.txt", "old.txt"])
    }

    func testFolderColorScreenshotAndLoginActions() throws {
        let folder = try IntegrationsUI.temporaryDirectory(self)
        try Data().write(to: folder.appendingPathComponent("item.txt"))
        let (utility, _) = utilities()
        var asked = 0
        utility.chooseDirectory = { asked += 1; return nil }
        utility.chooseFolder()
        XCTAssertEqual(asked, 1)
        utility.chooseDirectory = { folder }
        utility.chooseFolder()
        XCTAssertEqual(utility.folder, folder); XCTAssertEqual(utility.folderItems.map(\.lastPathComponent), ["item.txt"])

        utility.sampleColor = { handler in handler(nil); handler(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)) }
        utility.pickColor()
        XCTAssertTrue(IntegrationsUI.wait { utility.colorHex == "#FF8000" })

        for (code, prefix) in [(Int32(0), "Capture finished"), (nil, "Capture cancelled")] {
            utility.capture = { code }
            utility.screenshot()
            XCTAssertTrue(utility.busy)
            utility.screenshot() // Ignored while a capture is running.
            XCTAssertTrue(IntegrationsUI.wait { !utility.busy })
            XCTAssertTrue(utility.status?.hasPrefix(prefix) == true)
        }

        var requests: [Bool] = []
        var status = SMAppService.Status.enabled
        utility.setLoginItem = { requests.append($0) }
        utility.loginStatus = { status }
        utility.setLogin(true); XCTAssertTrue(utility.loginEnabled); XCTAssertNil(utility.status)
        status = .requiresApproval
        utility.setLogin(false); XCTAssertFalse(utility.loginEnabled); XCTAssertTrue(utility.status?.hasPrefix("Approve DockGrove") == true)
        XCTAssertEqual(requests, [true, false])
        utility.setLoginItem = { _ in throw CocoaError(.featureUnsupported) }
        utility.setLogin(true); XCTAssertTrue(utility.status?.hasPrefix("Could not change login startup") == true)
    }

    func testRemindersLoadAndComplete() {
        let (utility, access) = utilities()
        utility.reminders = [access.reminder("Old reading")]
        access.allowReminders = .success(false)
        utility.loadReminders()
        XCTAssertTrue(IntegrationsUI.wait { utility.remindersStatus == "Reminders permission was not granted." })
        XCTAssertTrue(utility.reminders.isEmpty)
        utility.reminders = [access.reminder("Old reading")]
        access.allowReminders = .failure(CocoaError(.featureUnsupported))
        utility.loadReminders()
        XCTAssertTrue(IntegrationsUI.wait { utility.remindersStatus.hasPrefix("Reminders are unavailable") })
        XCTAssertTrue(utility.reminders.isEmpty)
        access.allowReminders = .success(true)
        access.reminders = nil
        utility.loadReminders()
        XCTAssertTrue(IntegrationsUI.wait { utility.remindersStatus.hasPrefix("Reminders could not be loaded") })
        access.reminders = []
        utility.loadReminders()
        XCTAssertTrue(IntegrationsUI.wait { utility.remindersStatus == "No incomplete reminders." })
        access.reminders = [access.reminder("Water plants"), access.reminder(nil), access.reminder("Call")]
        utility.loadReminders()
        XCTAssertTrue(IntegrationsUI.wait { utility.reminders.count == 3 })
        XCTAssertEqual(utility.reminders.map { $0.title ?? "" }, ["", "Call", "Water plants"])

        let call = utility.reminders[1]
        utility.completeReminder(call)
        XCTAssertTrue(access.saved.first === call); XCTAssertTrue(call.isCompleted)
        XCTAssertFalse(utility.reminders.contains { $0 === call })
        utility.completeReminder(call)
        XCTAssertEqual(access.saved.count, 1, "Already completed reminders are not saved again")
        access.saveError = CocoaError(.fileWriteNoPermission)
        let plants = utility.reminders.last!
        utility.completeReminder(plants)
        XCTAssertFalse(plants.isCompleted); XCTAssertEqual(utility.remindersStatus, "Could not save this reminder. Refresh and try again.")
    }

    func testRemindersIgnoreLateReadsAndCompletedItems() {
        let (utility, access) = utilities()
        access.deferReminderResults = true
        utility.loadReminders()
        XCTAssertTrue(IntegrationsUI.wait { access.pendingReminderResults.count == 1 })
        utility.loadReminders()
        XCTAssertTrue(IntegrationsUI.wait { access.pendingReminderResults.count == 2 })
        let old = access.reminder("Old"), current = access.reminder("Current"), completed = access.reminder("Done")
        completed.isCompleted = true
        access.pendingReminderResults[1]([current, completed])
        XCTAssertTrue(IntegrationsUI.wait { utility.reminders.count == 1 })
        access.pendingReminderResults[0]([old])
        IntegrationsUI.spin(0.05)
        XCTAssertTrue(utility.reminders.first === current, "An older refresh must not replace the latest reading")

        utility.loadReminders()
        XCTAssertTrue(IntegrationsUI.wait { access.pendingReminderResults.count == 3 })
        utility.completeReminder(current)
        access.pendingReminderResults[2]([old])
        IntegrationsUI.spin(0.05)
        XCTAssertTrue(utility.reminders.isEmpty, "A pre-save read must not restore obsolete items")
        XCTAssertEqual(utility.remindersStatus, "No incomplete reminders.")
    }

    func testRemindersIgnoreLateAuthorizationFailures() {
        for outcome: Result<Bool, Error> in [.success(false), .failure(CocoaError(.featureUnsupported))] {
            let (utility, access) = utilities()
            access.reminderAccessDelay = 200_000_000
            access.allowReminders = outcome
            utility.loadReminders()
            IntegrationsUI.spin(0.04)
            access.reminderAccessDelay = 0
            access.allowReminders = .success(true)
            access.reminders = [access.reminder("Current")]
            utility.loadReminders()
            XCTAssertTrue(IntegrationsUI.wait { utility.reminders.count == 1 })
            IntegrationsUI.spin(0.25)
            XCTAssertEqual(utility.reminders.first?.title, "Current")
            XCTAssertTrue(utility.remindersStatus.hasPrefix("Incomplete reminders"))
        }
    }
}

// MARK: - Companion

@MainActor final class IntegrationsCompanionTests: XCTestCase {
    func testMoodsActionsAndArtwork() {
        var state = CompanionState()
        XCTAssertEqual(state.mood, "Happy to be here")
        state.energy = 30; XCTAssertEqual(state.mood, "Ready for a nap")
        state.fullness = 30; XCTAssertEqual(state.mood, "A little snack?")
        state.resting = true; XCTAssertEqual(state.mood, "Dreaming softly")

        let store = IntegrationsUI.defaults(self)
        let pet = Companion(defaults: store)
        pet.play(); XCTAssertEqual(pet.playRequest, 1)
        pet.state.resting = true
        pet.play(); XCTAssertEqual(pet.playRequest, 1)
        pet.tick()
        pet.rename("   "); XCTAssertEqual(pet.state.name, "Cream cat")
        pet.state.name = "Miso"; pet.state.sessions = 9
        pet.animal = "Miso"
        let legacy = Companion(defaults: store)
        XCTAssertEqual(legacy.animal, "Miso"); XCTAssertEqual(legacy.state.sessions, 9)
        XCTAssertEqual(legacy.displayName, "Cream cat"); XCTAssertEqual(legacy.state.name, "Miso")
        XCTAssertEqual(Companion.displayName("Miso"), "Cream cat")
        XCTAssertEqual(Companion.displayName("Fox"), "Fox")
        pet.state.sessions = 0
        pet.rename("  Pixel  "); XCTAssertEqual(pet.state.name, "Pixel")
        XCTAssertEqual(pet.displayName, "Pixel")
        XCTAssertEqual(CompanionArtwork.frames("Not an animal").count, CompanionArtwork.frames("Miso").count)
        XCTAssertEqual(CatPortrait(resting: false, accent: .blue).animal, "Miso")
        pet.state.reward(); XCTAssertEqual(pet.state.sessions, 1)
        pet.animal = "Fox"
        let restored = Companion(defaults: store)
        XCTAssertEqual(restored.animal, "Fox"); XCTAssertEqual(restored.state.sessions, 1)
    }

    func testLivePortraitTracksSelectionAndRestWithoutRecreation() throws {
        let pet = Companion(defaults: IntegrationsUI.defaults(self))
        let harness = SettingsHarness(LiveCompanionPortrait(pet: pet, accent: .blue), width: 166, height: 64)
        defer { harness.close() }
        let stage = try XCTUnwrap(harness.views(CompanionStage.self).first)
        pet.animal = "Dragon"
        harness.settle()
        XCTAssertEqual(stage.animal, "Dragon")
        pet.state.resting = true
        harness.settle()
        XCTAssertTrue(stage.resting)
        pet.animal = "Black cat"
        harness.settle()
        XCTAssertEqual(stage.animal, "Black cat")
        XCTAssertTrue(stage === harness.views(CompanionStage.self).first)
    }

    func testCompanionViewStatesAndActions() {
        let pet = Companion(defaults: IntegrationsUI.defaults(self))
        IntegrationsUI.render(CompanionView(pet: pet, accent: .orange))
        pet.state.resting = true
        IntegrationsUI.render(CompanionView(pet: pet, accent: .orange), dark: true)
        pet.state.resting = false
        let view = CompanionView(pet: pet, accent: .orange)
        let fullness = pet.state.fullness
        IntegrationsUI.press(IntegrationsUI.body(view), "Feed"); XCTAssertGreaterThan(pet.state.fullness, fullness)
        IntegrationsUI.press(IntegrationsUI.body(view), "Play"); XCTAssertEqual(pet.playRequest, 1)
        IntegrationsUI.press(IntegrationsUI.body(view), "Rest"); XCTAssertTrue(pet.state.resting)
        IntegrationsUI.press(IntegrationsUI.body(CompanionView(pet: pet, accent: .orange)), "Wake up"); XCTAssertFalse(pet.state.resting)
        IntegrationsUI.press(IntegrationsUI.body(view), "Rename"); XCTAssertEqual(pet.state.name, "Cream cat")
        IntegrationsUI.appear(IntegrationsUI.body(view))
    }

    func testCompactCompanionNameCommitsOnReturn() throws {
        let pet = Companion(defaults: IntegrationsUI.defaults(self))
        let harness = SettingsHarness(CompanionView(pet: pet, accent: .blue), width: 350, height: 650)
        defer { harness.close() }
        harness.window.styleMask.insert(.titled)
        let field = try XCTUnwrap(harness.views(NSTextField.self).first { $0.isEditable })
        XCTAssertTrue(harness.window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("  Sunny  ", replacementRange: editor.selectedRange())
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: harness.window.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        editor.keyDown(with: enter)
        harness.settle()
        XCTAssertEqual(pet.state.name, "Sunny", "Return must save the typed name without a mouse click")
    }

    func testPlayroomAccessibilityExploreSpeciesChangeAndFullscreenButton() throws {
        let pet = Companion(defaults: IntegrationsUI.defaults(self))
        pet.rename("Pixel")
        var fullscreenRequests = 0
        let harness = DockHarness(CompanionPlayroomView(pet: pet, accent: .blue, fullscreen: { fullscreenRequests += 1 }), size: CGSize(width: 980, height: 660))
        defer { harness.close() }
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let stage = try XCTUnwrap(descendants(harness.host).compactMap { $0 as? CompanionStage }.first)
        stage.reduceMotionPreference = { false }; stage.refreshScene()
        harness.act("Explore the room")
        XCTAssertEqual(stage.companionScene.motion.activity, .walk)
        XCTAssertNotEqual(stage.companionScene.motion.destination, 0.5)
        pet.animal = "Rabbit"
        harness.spin()
        XCTAssertEqual(stage.animal, "Rabbit")
        XCTAssertEqual(pet.state.name, "Pixel", "Switching species must preserve the custom name")
        // AppKit exposes a static text's content as AXValue on some SDKs, rather
        // than AXLabel. Inspect the identified feedback element's spoken text.
        func feedbackText() -> String {
            harness.nodes().filter { DockHarness.get($0, "accessibilityIdentifier") as? String == "companion-feedback" }
                .flatMap { node in ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"].compactMap { DockHarness.get(node, $0) as? String } }
                .joined(separator: " ")
        }
        XCTAssertTrue(IntegrationsUI.wait(1) { feedbackText().contains("Make yourself at home, Pixel.") },
                      "The species-change feedback must be accessible. Observed: \(feedbackText())")
        harness.press("Toggle playroom full screen")
        XCTAssertEqual(fullscreenRequests, 1)
    }

    func testPlayroomUsesReusableKeyWindowAndPreservesPet() throws {
        let defaults = IntegrationsUI.defaults(self)
        let model = DockModel(defaults: defaults)
        model.toolkit.pet.rename("Dracarys")
        model.toolkit.pet.animal = "Dragon"
        let state = model.toolkit.pet.state
        let originalHandler = DockSystemEffect.handler
        var presentations: [NSWindow] = []
        DockSystemEffect.handler = { if case .present(let window) = $0 { presentations.append(window) } }
        defer { DockSystemEffect.handler = originalHandler; model.companionWindow?.close() }
        model.showCompanionPlayroom()
        let window = try XCTUnwrap(model.companionWindow)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertFalse(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertGreaterThanOrEqual(window.contentMinSize.width, 760)
        model.showCompanionPlayroom()
        model.showNotchWidgetControls(.pet)
        XCTAssertEqual(presentations.count, 3)
        XCTAssertTrue(presentations.allSatisfy { $0 === window })
        XCTAssertEqual(model.toolkit.pet.state, state)
        XCTAssertEqual(model.toolkit.pet.animal, "Dragon")
    }

    func testNameEditorKeepsTypingThroughPetUpdatesAndReopens() throws {
        // SettingsHarness normally runs after DockHarness enables SwiftUI's AX tree.
        // This regression must also work when it is the first or only selected test.
        _ = NSApp.perform(Selector(("setAccessibilityEnhancedUserInterface:")), with: NSNumber(value: true))
        let pet = Companion(defaults: IntegrationsUI.defaults(self))
        let harness = SettingsHarness(CompanionDetailsView(pet: pet, accent: .blue), width: 240, height: 470)
        defer { harness.close() }
        harness.window.styleMask.insert(.titled)
        let field = try XCTUnwrap(harness.views(NSTextField.self).first { $0.isEditable })
        XCTAssertTrue(harness.window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("  Luna  ", replacementRange: editor.selectedRange())
        pet.tick()
        harness.settle()
        XCTAssertEqual(editor.string, "  Luna  ", "A care-state update must not reset an in-progress name")
        harness.window.makeFirstResponder(nil)
        harness.press("companion-rename")
        XCTAssertEqual(pet.state.name, "Luna")
        XCTAssertEqual(field.stringValue, "Luna")
        XCTAssertTrue(harness.window.makeFirstResponder(field))
        let reopened = try XCTUnwrap(field.currentEditor() as? NSTextView)
        reopened.selectAll(nil)
        reopened.insertText("Pixel", replacementRange: reopened.selectedRange())
        harness.window.makeFirstResponder(nil)
        harness.press("companion-rename")
        XCTAssertEqual(pet.state.name, "Pixel")
    }

    func testPlayroomActionsAndRestingInput() throws {
        let pet = Companion(defaults: IntegrationsUI.defaults(self))
        let harness = SettingsHarness(CompanionPlayroomView(pet: pet, accent: .blue), width: 980, height: 660)
        defer { harness.close() }
        let stage = try XCTUnwrap(harness.views(CompanionStage.self).first)
        stage.reduceMotionPreference = { false }
        stage.refreshScene()
        XCTAssertFalse(stage.companionScene.reducedMotion)
        XCTAssertEqual(stage.preferredFramesPerSecond, 60)
        XCTAssertTrue(stage.companionScene.playroom)
        XCTAssertNotNil(stage.onSelectDestination)
        XCTAssertTrue(stage.acceptsFirstMouse(for: nil))
        XCTAssertLessThanOrEqual(stage.companionScene.sprite.size.height, 191)
        let geometry = try XCTUnwrap(CompanionSpriteScene.geometry(for: pet.animal, size: stage.bounds.size, playroom: true))
        let click = stage.convert(NSPoint(x: geometry.x(at: 0.75), y: stage.bounds.midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: click, modifierFlags: [], timestamp: 0,
            windowNumber: harness.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        stage.mouseDown(with: event)
        harness.settle()
        XCTAssertEqual(stage.companionScene.motion.destination, 0.75, accuracy: 0.0001)
        let fullness = pet.state.fullness
        harness.press("Feed")
        XCTAssertGreaterThan(pet.state.fullness, fullness)
        harness.press("Play")
        XCTAssertEqual(pet.playRequest, 1)
        harness.press("Rest")
        XCTAssertTrue(pet.state.resting)
        let sleepingDestination = stage.companionScene.motion.destination
        stage.onSelectDestination?(0.3)
        harness.settle()
        XCTAssertEqual(stage.companionScene.motion.destination, sleepingDestination)
        harness.press("Wake up")
        XCTAssertFalse(pet.state.resting)

        stage.reduceMotionPreference = { true }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        XCTAssertTrue(stage.companionScene.reducedMotion)
        XCTAssertEqual(stage.preferredFramesPerSecond, 1)
        let still = stage.companionScene.motion.x
        let destination = stage.companionScene.motion.destination
        stage.onSelectDestination?(0.84)
        harness.settle()
        XCTAssertEqual(stage.companionScene.motion.x, still)
        XCTAssertEqual(stage.companionScene.motion.destination, destination)
        let playCount = pet.playRequest
        harness.press("Play")
        XCTAssertEqual(pet.playRequest, playCount + 1, "Care actions still work with Reduce Motion enabled")
        XCTAssertEqual(stage.companionScene.motion.activity, .idle)
        XCTAssertEqual(stage.companionScene.motion.x, still)
        harness.press("Details")
        XCTAssertTrue(harness.views(NSTextField.self).contains { $0.isEditable })
    }

    func testRoomDestinationsArriveSmoothlyAndRespectRestAndReduceMotion() {
        var motion = CompanionMotion(seed: 10)
        motion.move(to: 0.8, then: .play)
        var reached = false
        for _ in 0..<900 {
            let before = motion.x
            motion.advance(1.0 / 60, animal: "Orange cat", resting: false)
            XCTAssertLessThan(abs(motion.x - before), 0.004)
            if motion.activity == .play { reached = true; break }
        }
        XCTAssertTrue(reached)
        XCTAssertEqual(motion.x, 0.8, accuracy: 0.005)
        motion.move(to: -100)
        XCTAssertEqual(motion.destination, 0.12)
        motion.move(to: 100)
        XCTAssertEqual(motion.destination, 0.88)
        let beforeInvalid = motion
        motion.move(to: .nan)
        XCTAssertEqual(motion, beforeInvalid)
        motion.advance(0.01, animal: "Orange cat", resting: true)
        let resting = motion
        motion.move(to: 0.3)
        XCTAssertEqual(motion, resting)

        let scene = CompanionSpriteScene(size: CGSize(width: 800, height: 400))
        scene.playroom = true
        scene.advance(0)
        let command = CompanionSceneRequest(destination: 0.8)
        scene.receive(command)
        scene.advance(0.1)
        let moving = scene.motion
        scene.receive(command)
        XCTAssertEqual(scene.motion, moving, "A SwiftUI refresh must not restart the same command")
        scene.reducedMotion = true
        scene.advance(0)
        let still = scene.motion
        scene.receive(CompanionSceneRequest(destination: 0.2))
        XCTAssertEqual(scene.motion, still)
        XCTAssertEqual(scene.destination(at: -100), 0.12)
        XCTAssertEqual(scene.destination(at: 1000), 0.88)
        for width in [380.0, 800, 2400] {
            let size = CGSize(width: width, height: 600)
            let geometry = CompanionSpriteScene.geometry(for: "Dragon", size: size, playroom: true)!
            scene.size = size; scene.animal = "Dragon"; scene.advance(0)
            XCTAssertEqual(scene.sprite.position.x, geometry.x(at: scene.motion.x), accuracy: 0.001)
            for destination in [0.12, 0.5, 0.88] {
                XCTAssertEqual(scene.destination(at: geometry.x(at: destination)), destination, accuracy: 0.001,
                               "Click, toy and pet coordinates must agree at every room size")
            }
        }
    }

    func testPlayroomStaysInsideWindowWithAndWithoutDetails() throws {
        let pet = Companion(defaults: IntegrationsUI.defaults(self))
        for size in [CGSize(width: 760, height: 520), CGSize(width: 980, height: 660), CGSize(width: 1600, height: 900)] {
            let harness = SettingsHarness(CompanionPlayroomView(pet: pet, accent: .blue), width: size.width, height: size.height)
            defer { harness.close() }
            let stage = try XCTUnwrap(harness.views(CompanionStage.self).first)
            func stageBounds() -> CGRect { stage.convert(stage.bounds, to: harness.host) }
            XCTAssertEqual(stageBounds().minX, 24, accuracy: 1)
            XCTAssertEqual(stageBounds().maxX, size.width - 24, accuracy: 1,
                           "The decorative floor must not expand the SpriteKit room beyond the window")
            XCTAssertTrue(harness.host.bounds.insetBy(dx: 23, dy: 23).contains(stageBounds()))
            XCTAssertEqual(stage.companionScene.size.width, stage.bounds.width, accuracy: 1)
            harness.press("Details")
            let nameField = try XCTUnwrap(harness.views(NSTextField.self).first { $0.isEditable })
            let fieldBounds = nameField.convert(nameField.bounds, to: harness.host)
            XCTAssertLessThan(stageBounds().maxX, fieldBounds.minX, "The room must not overlap the name inspector")
            XCTAssertTrue(harness.host.bounds.insetBy(dx: 23, dy: 23).contains(stageBounds()))
            XCTAssertEqual(stage.companionScene.size.width, stage.bounds.width, accuracy: 1)
        }
    }

    func testPlayroomWalkingSpeedAndWingClockAreIndependentOfRoomWidth() throws {
        for (animal, bodyLengthsPerSecond) in [("Orange cat", 0.21), ("Cow", 0.15), ("Rabbit", 0.30), ("Dragon", 0.21)] {
            var wingTimes: [Double] = []
            for width in [380.0, 980, 2400] {
                let scene = CompanionSpriteScene(size: CGSize(width: width, height: 600))
                scene.animal = animal; scene.playroom = true
                scene.receive(CompanionSceneRequest(destination: 0.88))
                for _ in 0..<60 { scene.advance(1.0 / 60) }
                let geometry = try XCTUnwrap(CompanionSpriteScene.geometry(for: animal, size: scene.size, playroom: true))
                let measured = scene.motion.velocity * geometry.travel / geometry.spriteSize.width
                XCTAssertEqual(measured, bodyLengthsPerSecond, accuracy: 0.002,
                               "\(animal) must not run faster in a full-screen room")
                wingTimes.append(scene.motion.flightPhase)
                let frame = scene.frameIndex
                scene.size.width = 3000
                scene.advance(0)
                XCTAssertEqual(scene.frameIndex, frame, "Resizing must not skip walking poses")
                let resized = try XCTUnwrap(CompanionSpriteScene.geometry(for: animal, size: scene.size, playroom: true))
                XCTAssertEqual(scene.motion.velocity * resized.travel / resized.spriteSize.width, measured, accuracy: 0.0001)
                XCTAssertEqual(scene.motion.total, 1, accuracy: 0.0001, "Movement scaling must not slow the animation clock")
            }
            XCTAssertEqual(wingTimes[0], wingTimes[1], accuracy: 0.0001)
            XCTAssertEqual(wingTimes[1], wingTimes[2], accuracy: 0.0001)
        }

        let largeRoom = CompanionSpriteScene(size: CGSize(width: 3000, height: 600))
        largeRoom.animal = "Orange cat"; largeRoom.playroom = true
        largeRoom.receive(CompanionSceneRequest(destination: 0.12))
        for _ in 0..<3600 {
            largeRoom.advance(1.0 / 60)
            if largeRoom.motion.activity != .walk { break }
        }
        XCTAssertEqual(largeRoom.motion.x, 0.12, accuracy: 0.005)
        largeRoom.receive(CompanionSceneRequest(destination: 0.88, arrival: .play))
        for _ in 0..<1260 { largeRoom.advance(1.0 / 60) }
        XCTAssertEqual(largeRoom.motion.activity, .walk, "Do not abandon a distant toy after 20 seconds")
        var arrived = false
        for _ in 0..<3600 {
            largeRoom.advance(1.0 / 60)
            if largeRoom.motion.activity == .play { arrived = true; break }
        }
        XCTAssertTrue(arrived)
        XCTAssertEqual(largeRoom.motion.x, 0.88, accuracy: 0.005)
    }

    func testDrawingFromAssetDirectoryAndContexts() throws {
        let folder = try IntegrationsUI.temporaryDirectory(self)
        defer { CompanionDrawing.assetDirectory = nil }
        func png(_ name: String) -> Data {
            let image = NSImage(named: "Companion-" + name + "-pixel")!
            return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        }
        try png("fox").write(to: folder.appendingPathComponent("fox-pixel.png"))
        let catalog = folder.appendingPathComponent("Companion-cow-pixel.imageset")
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
        try png("cow").write(to: catalog.appendingPathComponent("cow-pixel.png"))
        CompanionDrawing.assetDirectory = folder
        XCTAssertEqual(CompanionDrawing.rig("Fox")?.frames.count, 16)
        XCTAssertEqual(CompanionDrawing.rig("Cow")?.frames.count, 16)
        XCTAssertNil(CompanionDrawing.rig("Rabbit"))
        CompanionDrawing.assetDirectory = nil

        var motion = CompanionMotion()
        XCTAssertTrue((0..<16).contains(CompanionDrawing.frameIndex(animal: "Unknown", motion: motion)))
        motion.velocity = 0.01
        XCTAssertTrue((0..<8).contains(CompanionDrawing.frameIndex(animal: "Fox", motion: motion)))

        CompanionDrawing.draw(animal: "Fox", motion: motion, in: CGRect(x: 0, y: 0, width: 200, height: 120))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 120, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        for (animal, facing, reduced) in [("Rabbit", 1.0, false), ("Cow", -1.0, true), ("Fox", 1.0, false), ("Unknown", 1.0, false)] {
            motion.facing = facing
            CompanionDrawing.draw(animal: animal, motion: motion, in: CGRect(x: 0, y: 0, width: 200, height: 120), reducedMotion: reduced)
        }
    }

    func testSpriteSceneClock() {
        let missing = CompanionSpriteScene(size: CGSize(width: 800, height: 400))
        missing.animal = "Unavailable animal"
        missing.playroom = true
        missing.advance(0.1)
        XCTAssertTrue(missing.sprite.isHidden, "Missing artwork must leave an empty room without crashing")
        XCTAssertTrue(missing.motion.x.isFinite)
        missing.animal = "Fox"
        missing.advance(0.1)
        XCTAssertFalse(missing.sprite.isHidden, "Selecting available artwork must recover the same scene")
        let scene = CompanionSpriteScene(size: CGSize(width: 250, height: 180))
        scene.update(10)
        scene.update(10.5)
        scene.animal = "Dragon"
        var prior = scene.frameIndex
        for _ in 0..<120 {
            scene.advance(1.0 / 60)
            XCTAssertLessThanOrEqual((scene.frameIndex - prior + 8) % 8, 1)
            prior = scene.frameIndex
        }
        scene.reducedMotion = true
        scene.advance(0)
        let still = scene.sprite.position
        scene.advance(1)
        XCTAssertEqual(scene.sprite.position, still)
        XCTAssertEqual(scene.sprite.yScale, 1)
        scene.resetClock()
        scene.update(11)
        XCTAssertTrue((0..<16).contains(scene.frameIndex))
    }

    func testSpriteStageVisibilityAndInput() {
        let stage = CompanionStage(frame: NSRect(x: 0, y: 0, width: 250, height: 180))
        stage.animal = "Fox"; stage.resting = true
        XCTAssertEqual(stage.animal, "Fox"); XCTAssertTrue(stage.resting)
        XCTAssertNil(stage.hitTest(NSPoint(x: 10, y: 10)))
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 250, height: 180), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = stage
        window.orderFront(nil)
        stage.isHidden = true
        XCTAssertTrue(stage.isPaused)
        stage.isHidden = false
        for name in [NSWindow.didChangeOcclusionStateNotification, NSApplication.didUnhideNotification] { NotificationCenter.default.post(name: name, object: window) }
        // A briefly visible, transparent window exercises the unpaused path.
        window.alphaValue = 0.01
        window.setFrameOrigin(NSPoint(x: 0, y: 0))
        window.orderFrontRegardless()
        IntegrationsUI.wait(1) { window.occlusionState.contains(.visible) }
        stage.refreshScene()
        window.level = .floating
        stage.refreshScene()
        XCTAssertFalse(stage.isPaused, "A visible floating Dock must animate")
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        XCTAssertTrue(stage.isPaused, "A retained playroom must stop rendering as soon as it closes")
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertFalse(stage.isPaused, "Reopening the retained window resumes its companion")
        window.orderOut(nil)
        stage.refreshScene()
        XCTAssertTrue(stage.isPaused, "A hidden Dock must stop rendering")
        window.contentView = nil
    }
}

// MARK: - Codex usage

final class IntegrationsCodexUsageTests: XCTestCase {
    func testLimitPresentation() throws {
        XCTAssertEqual(LimitWindow(usedPercent: 1, windowDurationMins: 90, resetsAt: nil).title, "90 min")
        XCTAssertEqual(LimitWindow(usedPercent: 1, windowDurationMins: nil, resetsAt: nil).resetDescription, "Reset time unavailable")
        XCTAssertEqual(LimitWindow(usedPercent: 1, windowDurationMins: nil, resetsAt: 1).resetDescription, "Awaiting reset refresh")
        XCTAssertTrue(LimitWindow(usedPercent: 1, windowDurationMins: nil, resetsAt: Date().addingTimeInterval(7200).timeIntervalSince1970).resetDescription.hasPrefix("Resets "))
        XCTAssertEqual(LimitBucket(limitId: nil, limitName: "Named", primary: nil, secondary: nil, planType: nil).title, "Named")
        XCTAssertEqual(LimitBucket(limitId: "codex", limitName: nil, primary: nil, secondary: nil, planType: nil).title, "Codex")
        XCTAssertEqual(LimitBucket(limitId: "other", limitName: nil, primary: nil, secondary: nil, planType: nil).title, "other")
        XCTAssertEqual(LimitBucket(limitId: nil, limitName: nil, primary: nil, secondary: nil, planType: nil).title, "Plan usage")
        let sorted = try JSONDecoder().decode(UsageResponse.self, from: Data(#"{"rateLimitsByLimitId":{"b":{},"codex":{},"a":{},"c":{}}}"#.utf8))
        XCTAssertEqual(sorted.buckets.map(\.0), ["codex", "a", "b", "c"])
        let single = try JSONDecoder().decode(UsageResponse.self, from: Data(#"{"rateLimits":{}}"#.utf8))
        XCTAssertEqual(single.buckets.map(\.0), ["default"])
        XCTAssertTrue(try JSONDecoder().decode(UsageResponse.self, from: Data("{}".utf8)).buckets.isEmpty)
        for error in [UsageError.missingCLI, .timeout, .disconnected, .service, .noWindows] { XCTAssertFalse(error.errorDescription!.isEmpty) }
    }

    func testAppServerFailureModes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DockGroveIntegrations." + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func codex(_ mode: String) throws -> String {
            let path = folder.appendingPathComponent("codex-" + mode).path
            try FileManager.default.copyItem(atPath: try Fixtures.path("CodexFixture"), toPath: path)
            return path
        }
        let buckets = try UsageClient.fetch(custom: try codex("buckets"))
        XCTAssertEqual(buckets.buckets.map(\.0), ["codex", "alpha", "beta", "zeta"])
        for (mode, expected) in [("exit", UsageError.disconnected), ("error", .service), ("nowindows", .noWindows), ("flood", .service)] {
            XCTAssertThrowsError(try UsageClient.fetch(custom: try codex(mode))) { error in
                XCTAssertEqual((error as? UsageError).map { "\($0)" }, "\(expected)", mode)
            }
        }
        XCTAssertThrowsError(try UsageClient.fetch(custom: try codex("hang"), timeout: 0.3)) { XCTAssertEqual(($0 as? UsageError).map { "\($0)" }, "timeout") }
        Thread.sleep(forTimeInterval: 1.3) // Lets the delayed SIGKILL check run.
    }
}

// MARK: - Weather

@MainActor final class IntegrationsWeatherTests: XCTestCase {
    private let reading = WeatherReading(temperature: Measurement(value: 20, unit: .celsius), apparentTemperature: Measurement(value: 19, unit: .celsius),
                                         condition: "Clear", symbolName: "sun.max", date: Date(timeIntervalSince1970: 1_800_000_000),
                                         attributionURL: URL(string: "https://weatherkit.apple.com/legal")!, lightMarkURL: URL(string: "https://example.com/light.png")!, darkMarkURL: URL(string: "https://example.com/dark.png")!)

    private func place(_ address: [String: String]) -> CLPlacemark {
        let postal = CNMutablePostalAddress()
        postal.city = address["city"] ?? ""; postal.state = address["state"] ?? ""; postal.country = address["country"] ?? ""
        return MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3, longitude: -122.0), postalAddress: postal)
    }

    func testFetchNamesPlacesAndRejectsMissingCities() async throws {
        let reading = reading
        let snapshot = try await AppleWeatherClient.fetch(city: "cupertino", geocode: { _ in [self.place(["city": "Cupertino", "state": "CA", "country": "United States"])] }, current: { _ in reading })
        XCTAssertEqual(snapshot.city, "Cupertino, CA, United States")
        XCTAssertEqual(snapshot.condition, "Clear"); XCTAssertEqual(snapshot.darkMarkURL.lastPathComponent, "dark.png")
        let deduplicated = try await AppleWeatherClient.fetch(city: "x", geocode: { _ in [self.place(["city": "Singapore", "state": "Singapore", "country": "Singapore"])] }, current: { _ in reading })
        XCTAssertEqual(deduplicated.city, "Singapore")
        let unnamed = try await AppleWeatherClient.fetch(city: "typed city", geocode: { _ in [self.place([:])] }, current: { _ in reading })
        XCTAssertFalse(unnamed.city.isEmpty)
        do { _ = try await AppleWeatherClient.fetch(city: "nowhere", geocode: { _ in [] }, current: { _ in reading }); XCTFail("Missing city accepted") }
        catch { XCTAssertTrue(error is WeatherLookupError) }

        do { _ = try await AppleWeatherClient.fetch(city: "nowhere", geocode: { _ in throw CLError(.geocodeFoundNoResult) }, current: { _ in reading }); XCTFail("Geocoder missing city accepted") }
        catch { XCTAssertTrue(error is WeatherLookupError) }
        let geocode = AppleWeatherClient.geocode, current = AppleWeatherClient.current
        defer { AppleWeatherClient.geocode = geocode; AppleWeatherClient.current = current }
        AppleWeatherClient.geocode = { city in XCTAssertEqual(city, "Paris"); return [self.place(["city": "Paris", "country": "France"])] }
        AppleWeatherClient.current = { _ in reading }
        let paris = try await AppleWeatherClient.fetch(city: "Paris")
        XCTAssertEqual(paris.city, "Paris, France")
    }
}

