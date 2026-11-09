extends HTTPRequest
## Transport for one user-initiated Grid request. The world owns placement and edits.

var _url := ""
var _token := ""

func configure(url: String, token: String) -> void:
	_url = url
	_token = token
	timeout = 85.0
	body_size_limit = 65536

func plan(prompt: String, context := {}) -> Dictionary:
	if _url.is_empty() or _token.is_empty():
		return {"error": "Open Euclid through its launcher to connect Codex."}
	var route := "/v1/grid/plan" if context.is_empty() else "/v1/companion/plan"
	var started := request(_url + route,
		["Authorization: Bearer " + _token, "Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify({"prompt": prompt, "context": context}))
	if started != OK:
		return {"error": "The Grid agent is busy or the gateway could not be reached."}
	var response: Array = await request_completed
	var code: int = response[1]
	if response[0] != RESULT_SUCCESS:
		return {"error": "The Grid agent request could not reach the gateway or timed out."}
	if code == 404:
		return {"error": "Reopen Euclid through its launcher to update the local gateway."}
	var data: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if not data is Dictionary:
		return {"error": "The gateway returned an invalid Grid response."}
	if code != 200:
		return {"error": str(data.get("error", "The Grid agent request failed."))}
	if data.get("agent_id") != "local-codex" or not data.get("plan") is Dictionary:
		return {"error": "The gateway returned an invalid Grid plan."}
	return data
