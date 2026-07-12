-- LuxyHub production loader bootstrap
-- Runtime: loader-runtime-v1
-- Payloads are fetched through one-time delivery sessions and are not embedded here.

local LUXY_BASE_URL = "https://www.luxyhub.space"
local LUXY_SLUG = "luxyhub"
local RUNTIME_VERSION = "loader-runtime-v1"
local SUPPORTED_RUNTIME_FORMAT_VERSION = "runtime-v1"
local SUPPORTED_BUILD_VERSION = "delivery-build-v1"

local HttpService = game:GetService("HttpService")

local function fail()
  error("LuxyHub loader failed", 0)
end

local function getRequest()
  return (syn and syn.request)
    or http_request
    or request
    or (http and http.request)
end

local function postJson(path, body)
  local requestImpl = getRequest()
  if type(requestImpl) ~= "function" then
    fail()
  end

  local response = requestImpl({
    Url = LUXY_BASE_URL .. path,
    Method = "POST",
    Headers = {
      ["Content-Type"] = "application/json",
      ["Cache-Control"] = "no-store",
    },
    Body = HttpService:JSONEncode(body),
  })

  if type(response) ~= "table" then
    fail()
  end

  local status = response.StatusCode or response.status_code or response.status
  if type(status) ~= "number" or status < 200 or status >= 300 then
    fail()
  end

  local responseBody = response.Body or response.body
  if type(responseBody) ~= "string" or #responseBody == 0 then
    fail()
  end

  local ok, decoded = pcall(function()
    return HttpService:JSONDecode(responseBody)
  end)

  if not ok or type(decoded) ~= "table" then
    fail()
  end

  return decoded
end

local function validateDelivery(delivery)
  if type(delivery) ~= "table" then
    fail()
  end

  if type(delivery.runtime_payload) ~= "string" or #delivery.runtime_payload == 0 then
    fail()
  end

  if delivery.build_version ~= SUPPORTED_BUILD_VERSION then
    fail()
  end

  if type(delivery.version_id) ~= "string" or #delivery.version_id == 0 then
    fail()
  end

  if delivery.runtime_format_version ~= SUPPORTED_RUNTIME_FORMAT_VERSION then
    fail()
  end

  return delivery
end

local function createRuntime()
  local Runtime = {
    version = RUNTIME_VERSION,
  }

  function Runtime.consume(delivery)
    local runtime = validateDelivery(delivery)
    local chunk = loadstring(runtime.runtime_payload)
    if type(chunk) ~= "function" then
      fail()
    end

    return chunk()
  end

  return Runtime
end

if type(_G.LuxyHubLoaderRuntimeV1) ~= "table" then
  _G.LuxyHubLoaderRuntimeV1 = createRuntime()
end

local Runtime = _G.LuxyHubLoaderRuntimeV1
if type(Runtime) ~= "table" or Runtime.version ~= RUNTIME_VERSION or type(Runtime.consume) ~= "function" then
  fail()
end

local session = postJson("/api/delivery/session", {
  slug = LUXY_SLUG,
})

if type(session.session_token) ~= "string" or #session.session_token == 0 then
  fail()
end

local delivery = postJson("/api/delivery/fetch", {
  session_token = session.session_token,
})

validateDelivery(delivery)

-- ==== DEBUG: dump the fetched payload locally for inspection ====
print("[LuxyHub] version_id:", delivery.version_id)
print("[LuxyHub] build_version:", delivery.build_version)
print("[LuxyHub] payload length:", #delivery.runtime_payload)

if type(writefile) == "function" then
  writefile("luxy_fetched_payload.lua", delivery.runtime_payload)
  print("[LuxyHub] wrote payload to luxy_fetched_payload.lua")
else
  warn("[LuxyHub] writefile not available in this executor")
end
-- ================================================================

return Runtime.consume({
  runtime_payload = delivery.runtime_payload,
  build_version = delivery.build_version,
  version_id = delivery.version_id,
  runtime_format_version = delivery.runtime_format_version,
  runtime_version = RUNTIME_VERSION,
})