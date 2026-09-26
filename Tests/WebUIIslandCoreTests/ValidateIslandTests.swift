import Testing
import Foundation
import WebUIIslandCore
// ClientFieldValidator lives in the zero-dep shared core leaf; it used to be
// reachable through the (now deleted) wasm client runtime.
import WebUISharedCore

// MARK: - Validate island (next architecture d3)

@Test("rule json decodes to client validation rules")
func decodeRulesJson() {
	let rules = ValidateIsland.decodeRules(
		json: "{\"rules\":[{\"rule\":\"required\"},{\"rule\":\"minLength\",\"arg\":4},{\"rule\":\"email\"}]}"
	)
	#expect(rules == [.required, .minLength(4), .email])
}

@Test("malformed rule json degrades to nil")
func malformedRuleJson() {
	#expect(ValidateIsland.decodeRules(json: "{\"rules\":[{\"rule\":\"nope\"}]}") == nil)
	#expect(ValidateIsland.decodeRules(json: "not json") == nil)
}

@Test("evaluate returns first failing message — parity with ClientFieldValidator")
func evaluateParity() {
	let json = "{\"value\":\"ab\",\"rules\":[{\"rule\":\"minLength\",\"arg\":4}]}"
	let result = ValidateIsland.evaluate(json: json)
	#expect(result.ok == false)
	#expect(result.message == "at least 4 characters")
	let ok = ValidateIsland.evaluate(json: "{\"value\":\"hello@example.com\",\"rules\":[{\"rule\":\"email\"}]}")
	#expect(ok.ok == true && ok.message.isEmpty)
	let direct = ClientFieldValidator(rules: [.minLength(4)]).validate("ab")
	#expect(result.message == direct)
}

@Test("region html escapes and stamps the status")
func regionHTML() {
	let bad = ValidateIsland.regionHTML(argsJSON: "{\"value\":\"\",\"rules\":[{\"rule\":\"required\"}]}")
	#expect(bad.contains("island--error"))
	#expect(bad.contains("role=\"status\""))
	#expect(bad.contains("this field is required"))
	let escaped = ValidateIsland.regionHTML(argsJSON: "{\"value\":\"ab\",\"rules\":[{\"rule\":\"contains\",\"arg\":\"<x>\"}]}")
	#expect(escaped.contains("island--error"))
	#expect(!escaped.contains("<x>"))
	#expect(escaped.contains("&lt;x&gt;"))
	let good = ValidateIsland.regionHTML(argsJSON: "{\"value\":\"ok\",\"rules\":[{\"rule\":\"required\"}]}")
	#expect(good.contains("island--ok"))
	#expect(good.contains(">valid<"))
}
