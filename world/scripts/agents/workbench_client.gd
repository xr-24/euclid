extends HTTPRequest
## Workbench transport. The panel owns presentation and the gateway owns source operations.

var _url: String
var _headers: PackedStringArray

func configure(url: String, token: String, capability: String) -> void:
	_url = url + "/v1/workbench/"
	_headers = ["Authorization: Bearer " + token, "X-Euclid-Workbench: " + capability, "Content-Type: application/json"]
	timeout = 85.0
	body_size_limit = 524288

func send(action: String, arguments := {}) -> Dictionary:
	if request(_url + action, _headers, HTTPClient.METHOD_POST, JSON.stringify(arguments)) != OK:
		return {"error": "The workbench could not reach its local gateway."}
	var response: Array = await request_completed
	if response[0] != RESULT_SUCCESS:
		return {"error": "The workbench request timed out or lost its gateway."}
	var data: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	return data if data is Dictionary else {"error": "The gateway returned an invalid workbench response."}
