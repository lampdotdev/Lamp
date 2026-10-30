import JavaScriptCore
import XCTest
@testable import Lamp

/// Home HQ's writes for Ask (Web/js/actions.js in its tree), run on the starter's own data and app scripts
/// with a stand-in page: what a write finds when the family's list has the same item at two stores.
@MainActor
final class HomeHQAskTests: XCTestCase {
    private var web: URL { get throws { try StarterTrees.tree("homehq").appendingPathComponent("Web") } }

    private func page() throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, value in XCTFail(value?.toString() ?? "?") }
        context.evaluateScript("""
            var window = this, store = {};
            var console = { error: function () {}, log: function () {} };
            function el() { return { classList: { add: function () {}, remove: function () {}, toggle: function () {}, contains: function () { return false; } },
              style: { setProperty: function () {} }, addEventListener: function () {}, appendChild: function () {}, querySelector: function () { return null; },
              querySelectorAll: function () { return []; }, setAttribute: function () {}, getBoundingClientRect: function () { return { width: 1280, height: 800, left: 0, top: 0 }; } }; }
            var document = { addEventListener: function () {}, querySelector: el, querySelectorAll: function () { return []; }, getElementById: el, createElement: el, documentElement: el(), body: el() };
            window.localStorage = { getItem: function (k) { return k in store ? store[k] : null; }, setItem: function (k, v) { store[k] = String(v); }, removeItem: function (k) { delete store[k]; } };
            window.addEventListener = function () {}; window.removeEventListener = function () {};
            var navigator = { language: 'en-US' }, innerWidth = 1280, innerHeight = 800, location = { hash: '' };
            function matchMedia() { return { matches: false, addListener: function () {} }; }
            function setTimeout() { return 0; } function clearTimeout() {} function setInterval() { return 0; } function clearInterval() {}
            """)
        context.evaluateScript(DeviceSupport.webJS)
        for name in ["js/icons.js", "js/data.js", "js/app.js", "js/actions.js"] {
            context.evaluateScript(try String(contentsOf: web.appendingPathComponent(name), encoding: .utf8))
        }
        context.evaluateScript("""
            App.rerender = function () {};
            var W = App.write, n = 0;
            function call() { return { turn: 't1', key: 'k' + (++n), step: 1, id: 'c' }; }
            function rows(name) { return DATA.groceries.filter(function (g) { return !g.gone && g.name === name; }).map(function (g) { return g.store + ':' + g.qty + (g.done ? ':bought' : ''); }).sort(); }
            DATA.groceries = DATA.groceries.filter(function (g) { return g.name !== 'Milk'; });
            """)
        return context
    }

    private func value(_ c: JSContext, _ script: String) -> Any? {
        c.evaluateScript("JSON.stringify(\(script))")?.toString().flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8), options: .fragmentsAllowed) }
    }

    func testTheStoreAskedForPicksWhichRowChanges() throws {
        let c = try page()
        c.evaluateScript("""
            DATA.groceries.push({ id: 'g1', name: 'Milk', cat: 'Dairy & Eggs', qty: 1, store: 'grocer', done: false, note: '' });
            DATA.groceries.push({ id: 'g2', name: 'Milk', cat: 'Dairy & Eggs', qty: 1, store: 'costco', done: false, note: '' });
            W.addGrocery.run({ name: 'Milk', store: 'costco', qty: 1 }, call());
            """)
        XCTAssertEqual(value(c, "rows('Milk')") as? [String], ["costco:2", "grocer:1"])
    }

    func testTwoStoresAndNoneAskedForIsAQuestion() throws {
        let c = try page()
        c.evaluateScript("""
            DATA.groceries.push({ id: 'g1', name: 'Milk', cat: 'Dairy & Eggs', qty: 1, store: 'grocer', done: false, note: '' });
            DATA.groceries.push({ id: 'g2', name: 'Milk', cat: 'Dairy & Eggs', qty: 1, store: 'costco', done: false, note: '' });
            """)
        let why = value(c, "W.addGrocery.check({ name: 'milk', qty: 1 })") as? String
        XCTAssertTrue(why?.contains("which store") == true, why ?? "nil")
        XCTAssertNil(value(c, "W.addGrocery.check({ name: 'milk', store: 'costco' })") as? String)
    }

    func testAStoreWithoutTheItemGetsItsOwnRowAndABoughtOneElsewhereStaysBought() throws {
        let c = try page()
        c.evaluateScript("""
            DATA.groceries.push({ id: 'g1', name: 'Milk', cat: 'Dairy & Eggs', qty: 1, store: 'grocer', done: false, note: '' });
            DATA.groceries.push({ id: 'g3', name: 'Milk', cat: 'Dairy & Eggs', qty: 2, store: 'grocer', done: true, note: '' });
            W.addGrocery.run({ name: 'Milk', store: 'costco' }, call());
            """)
        XCTAssertEqual(value(c, "rows('Milk')") as? [String], ["costco:1", "grocer:1", "grocer:2:bought"])
    }
}
