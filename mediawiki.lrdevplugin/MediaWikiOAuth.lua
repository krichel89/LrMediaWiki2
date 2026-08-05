-- This file is part of the LrMediaWiki2 project and distributed under the
-- terms of the MIT license (see LICENSE.txt file in the project root
-- directory).
--
-- OAuth 2.0 authorization code flow with PKCE and a loopback redirect,
-- for logging in to Wikimedia Commons without a BotPassword.
--
-- WHY THIS WORKS THE WAY IT DOES – empirical findings from the loopback
-- probe run on this Lightroom installation (do NOT re-guess these):
--   * LrDigest offers HMAC, MD4, MD5, SHA1, SHA256, SHA384, SHA512, so PKCE
--     with code_challenge_method=S256 is possible.
--   * LrSocket.bind{ functionContext, plugin, port, mode='receive', … } is
--     the valid signature. The returned object has send/close/reconnect.
--   * LrSocket delivers a real TCP stream LINE BY LINE: onMessage fires once
--     per line WITHOUT the CRLF – first the request line
--     ("GET /path?code=…&state=… HTTP/1.1"), then each header, and finally an
--     EMPTY STRING for the blank line that terminates the headers.
--   * LrSocket in 'receive' mode acknowledges every received line with "ok"
--     on the same connection. The browser therefore shows a page full of
--     "ok" and our own socket:send() does not reach it. The response page
--     CANNOT be styled – the success message has to be shown inside
--     Lightroom, and the user must be warned about the "ok" page beforehand.
--
-- Code status:
-- doc:   complete
-- i18n:  partly (user-visible strings via LOC where they existed)

local LrDate = import 'LrDate'
local LrDigest = import 'LrDigest'
local LrHttp = import 'LrHttp'
local LrPasswords = import 'LrPasswords'
local LrSocket = import 'LrSocket'
local LrTasks = import 'LrTasks'

local JSON = require 'JSON'
local MediaWikiUtils = require 'MediaWikiUtils'

local MediaWikiOAuth = {}

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

-- Client ID ("consumer key") of the registered OAuth 2.0 consumer.
-- PUBLIC CLIENT: there is deliberately NO client secret – a plug-in runs on a
-- machine the end user controls, so a secret could not be kept secret. PKCE
-- takes its place. This ID is not confidential: it travels in the query
-- string of every authorisation URL the browser opens, so shipping it in the
-- source is by design, not an oversight.
MediaWikiOAuth.clientId = '5d1ff738a1c29c3f0a8888c001248107'

-- Client secret ("consumer secret"). MUST STAY EMPTY: the consumer is
-- registered as a PUBLIC client, so the token endpoint expects PKCE and no
-- secret. Fill this in only if the consumer is ever re-registered as
-- CONFIDENTIAL – in that case Wikimedia rejects the exchange with
-- "invalid_client" until the secret is supplied. Note that a secret shipped
-- inside a plug-in is readable by anyone who installs it, which is exactly
-- why the public-client route was chosen.
MediaWikiOAuth.clientSecret = ''

-- Registered redirect URI. Wikimedia's OAuth 2.0 implementation matches this
-- EXACTLY (unlike OAuth 1.0a, there is no prefix mode), so the port is fixed
-- and the spelling here must match the registration character for character:
-- 127.0.0.1 (not "localhost"), no trailing slash difference.
MediaWikiOAuth.redirectUri = 'http://127.0.0.1:8128/lrmediawiki2/callback'
MediaWikiOAuth.port = 8128

-- OAuth is centralised on Meta; the resulting access token is valid for
-- Commons as well.
-- VERIFY: these two endpoint URLs are taken from the MediaWiki OAuth
-- documentation and have NOT been exercised against the live service yet. If
-- authorisation fails with a 404, check them first – they are deliberately
-- kept as plain constants so they can be corrected without touching logic.
MediaWikiOAuth.authorizeUrl = 'https://meta.wikimedia.org/w/rest.php/oauth2/authorize'
MediaWikiOAuth.tokenUrl = 'https://meta.wikimedia.org/w/rest.php/oauth2/access_token'

-- How long to wait for the browser redirect before giving up.
MediaWikiOAuth.timeoutSeconds = 300

-- Refresh the access token this many seconds before it actually expires.
local REFRESH_MARGIN = 300

--------------------------------------------------------------------------------
-- Pure helpers (no SDK use – copied verbatim into standalone Lua 5.1 tests)
--------------------------------------------------------------------------------

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

-- base64url without padding (RFC 4648 §5), as required for PKCE.
local function base64url(data)
	if data == nil or data == '' then return '' end
	local out = {}
	local n = #data
	local i = 1
	while i <= n do
		local a = data:byte(i)
		local b = data:byte(i + 1)
		local c = data:byte(i + 2)
		local v = a * 65536 + (b or 0) * 256 + (c or 0)
		local i1 = math.floor(v / 262144) % 64
		local i2 = math.floor(v / 4096) % 64
		local i3 = math.floor(v / 64) % 64
		local i4 = v % 64
		out[#out + 1] = B64:sub(i1 + 1, i1 + 1)
		out[#out + 1] = B64:sub(i2 + 1, i2 + 1)
		if b then out[#out + 1] = B64:sub(i3 + 1, i3 + 1) end
		if c then out[#out + 1] = B64:sub(i4 + 1, i4 + 1) end
		i = i + 3
	end
	local s = table.concat(out)
	s = s:gsub('%+', '-')
	s = s:gsub('/', '_')
	return s
end

-- Convert a lowercase/uppercase hex string to raw bytes.
local function hexToRaw(hex)
	if type(hex) ~= 'string' then return '' end
	local out = {}
	for pair in hex:gmatch('%x%x') do
		out[#out + 1] = string.char(tonumber(pair, 16))
	end
	return table.concat(out)
end

-- LrDigest's exact return format is not documented for this SDK version, so
-- normalise defensively: a string of 64 hex characters is a hex digest and is
-- converted to its 32 raw bytes; a 32-character string is already raw.
-- Anything else is returned unchanged (and will fail visibly rather than
-- silently producing a wrong challenge).
local function digestToRaw(digest)
	if type(digest) ~= 'string' then return nil end
	if #digest == 32 then
		return digest
	end
	if #digest == 64 and digest:match('^%x+$') then
		return hexToRaw(digest)
	end
	return digest
end

-- Percent-decode a query string component ('+' means space).
local function urlDecode(str)
	if type(str) ~= 'string' then return '' end
	str = str:gsub('+', ' ')
	str = str:gsub('%%(%x%x)', function(h)
		return string.char(tonumber(h, 16))
	end)
	return str
end

-- Percent-encode for use in a query string (unreserved set per RFC 3986).
local function urlEncode(str)
	if str == nil then return '' end
	str = tostring(str)
	str = str:gsub('[^%w%-%.%_%~]', function(ch)
		return string.format('%%%02X', string.byte(ch))
	end)
	return str
end

-- Parse an HTTP request line ("GET /path?a=1&b=2 HTTP/1.1") into the request
-- path and a table of decoded query parameters. Returns nil if the line is
-- not a GET request line, so that header lines are ignored. A request without
-- a query string yields an empty table (not nil).
local function parseRequestLine(line)
	if type(line) ~= 'string' then return nil end
	local target = line:match('^GET%s+(%S+)%s+HTTP/')
	if not target then return nil end
	local path = target:match('^([^%?]*)')
	local params = {}
	local query = target:match('%?(.*)$')
	if query then
		for pair in query:gmatch('[^&]+') do
			local key, value = pair:match('^([^=]*)=?(.*)$')
			if key and key ~= '' then
				params[urlDecode(key)] = urlDecode(value)
			end
		end
	end
	return params, path
end

-- Decides whether a parsed request is OUR callback. Browsers may hit the
-- port with other requests first (favicon.ico, speculative preconnects), and
-- accepting the first arbitrary GET would abort the login with "no code"
-- while the real redirect arrives a second later. Only a request to the
-- registered callback path that actually carries a code, an error, or a
-- state parameter counts; everything else is ignored and the listener keeps
-- waiting.
local function isCallbackRequest(params, path, callbackPath)
	if type(params) ~= 'table' or type(path) ~= 'string' then
		return false
	end
	if path ~= callbackPath then
		return false
	end
	return params.code ~= nil or params.error ~= nil or params.state ~= nil
end

-- Build the authorisation URL the browser is sent to.
local function buildAuthorizeUrl(base, clientId, redirectUri, state, challenge)
	return base
		.. '?response_type=code'
		.. '&client_id=' .. urlEncode(clientId)
		.. '&redirect_uri=' .. urlEncode(redirectUri)
		.. '&state=' .. urlEncode(state)
		.. '&code_challenge=' .. urlEncode(challenge)
		.. '&code_challenge_method=S256'
end

-- Turn a decoded token response into a stored-token table, or nil + message.
-- `now` is passed in so this stays pure and testable.
local function tokenFromResponse(decoded, now)
	if type(decoded) ~= 'table' then
		return nil, 'Antwort des Servers war kein gültiges JSON.'
	end
	if decoded.error then
		local msg = decoded.error_description or decoded.message or decoded.error
		return nil, tostring(msg)
	end
	if type(decoded.access_token) ~= 'string' or decoded.access_token == '' then
		return nil, 'Antwort enthielt kein access_token.'
	end
	local lifetime = tonumber(decoded.expires_in) or 14400
	return {
		accessToken = decoded.access_token,
		refreshToken = decoded.refresh_token, -- may be nil
		expiresAt = now + lifetime,
	}
end

-- Is the stored token still usable (with a safety margin)?
local function tokenIsFresh(token, now, margin)
	if type(token) ~= 'table' or type(token.accessToken) ~= 'string' then
		return false
	end
	if type(token.expiresAt) ~= 'number' then
		return false
	end
	return token.expiresAt - margin > now
end

--------------------------------------------------------------------------------
-- SDK-dependent helpers
--------------------------------------------------------------------------------

-- The exact call shape of LrDigest.SHA256 is not documented for this SDK
-- version, so try the plausible ones instead of guessing a single one. The
-- shape that works is traced, so it shows up in the log once and for all.
local function sha256Raw(text)
	local attempts = {
		{
			name = 'LrDigest.SHA256.digest(s)',
			run = function() return LrDigest.SHA256.digest(text) end,
		},
		{
			name = 'LrDigest.SHA256(s)',
			run = function() return LrDigest.SHA256(text) end,
		},
		{
			name = 'LrDigest.SHA256.new()/update/digest',
			run = function()
				local h = LrDigest.SHA256.new()
				h:update(text)
				return h:digest()
			end,
		},
	}
	for _, attempt in ipairs(attempts) do
		local ok, result = pcall(attempt.run)
		if ok and type(result) == 'string' and #result > 0 then
			MediaWikiUtils.trace('OAuth: SHA-256 via ' .. attempt.name)
			return digestToRaw(result)
		end
	end
	return nil
end

-- Random-ish, unguessable string. Not a cryptographic RNG – Lua 5.1's
-- math.random is not one – but the value is hashed together with several
-- changing sources, which is adequate for a PKCE verifier and a state value
-- that only ever live for a few seconds on the local machine.
-- Seeded once per module load: reseeding on every call within the same
-- second would restart the identical sequence.
local randomSeeded = false
local function randomToken()
	if not randomSeeded then
		randomSeeded = true
		math.randomseed(os.time() + math.floor(os.clock() * 100000))
	end
	local entropy = tostring(os.time()) .. '|' .. tostring(os.clock())
		.. '|' .. tostring({}) .. '|' .. tostring(math.random(1, 2 ^ 30))
		.. '|' .. tostring({})
	local raw = sha256Raw(entropy)
	if raw then
		return base64url(raw)
	end
	-- Fallback if SHA-256 is unavailable: still 43 characters from the
	-- unreserved set, just with weaker entropy.
	local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~'
	local out = {}
	for _ = 1, 43 do
		local i = math.random(1, #alphabet)
		out[#out + 1] = alphabet:sub(i, i)
	end
	return table.concat(out)
end

local function nowSeconds()
	-- LrDate.currentTime() counts from 2001-01-01; only differences matter
	-- here, so the epoch is irrelevant as long as it is used consistently.
	local ok, value = pcall(function() return LrDate.currentTime() end)
	if ok and type(value) == 'number' then
		return value
	end
	return os.time()
end

--------------------------------------------------------------------------------
-- Token storage
--------------------------------------------------------------------------------

-- Tokens are credentials and are stored in the OS keychain via LrPasswords,
-- never in preferences (which are plain files on disk) and never in export
-- presets.
local function storageKey(apiPath)
	return 'LrMediaWiki2#oauth2#' .. tostring(apiPath)
end

function MediaWikiOAuth.storeToken(apiPath, token)
	if token == nil then
		LrPasswords.store(storageKey(apiPath), '')
		return
	end
	local ok, encoded = pcall(function()
		return JSON:encode({
			access_token = token.accessToken,
			refresh_token = token.refreshToken,
			expires_at = token.expiresAt,
			username = token.username,
		})
	end)
	if ok then
		LrPasswords.store(storageKey(apiPath), encoded)
	end
end

function MediaWikiOAuth.loadToken(apiPath)
	local stored = LrPasswords.retrieve(storageKey(apiPath))
	if stored == nil or stored == '' then
		return nil
	end
	local ok, decoded = pcall(function() return JSON:decode(stored) end)
	if not ok or type(decoded) ~= 'table' or type(decoded.access_token) ~= 'string' then
		return nil
	end
	return {
		accessToken = decoded.access_token,
		refreshToken = decoded.refresh_token,
		expiresAt = tonumber(decoded.expires_at) or 0,
		username = decoded.username,
	}
end

function MediaWikiOAuth.clearToken(apiPath)
	MediaWikiOAuth.storeToken(apiPath, nil)
end

--------------------------------------------------------------------------------
-- Public state helpers
--------------------------------------------------------------------------------

function MediaWikiOAuth.isConfigured()
	return type(MediaWikiOAuth.clientId) == 'string' and MediaWikiOAuth.clientId ~= ''
end

function MediaWikiOAuth.getStoredUsername(apiPath)
	local token = MediaWikiOAuth.loadToken(apiPath)
	if token and type(token.username) == 'string' and token.username ~= '' then
		return token.username
	end
	return nil
end

--------------------------------------------------------------------------------
-- HTTP
--------------------------------------------------------------------------------

local function postForm(url, fields)
	local parts = {}
	for key, value in pairs(fields) do
		parts[#parts + 1] = urlEncode(key) .. '=' .. urlEncode(value)
	end
	local body = table.concat(parts, '&')
	local headers = {
		{ field = 'User-Agent', value = 'LrMediaWiki2 (https://github.com/krichel89/LrMediaWiki2)' },
		{ field = 'Content-Type', value = 'application/x-www-form-urlencoded' },
	}
	local resultBody, resultHeaders = LrHttp.post(url, body, headers)
	local status = resultHeaders and resultHeaders.status or nil
	if not status then
		return nil, 'Keine Netzwerkverbindung zum OAuth-Dienst.'
	end
	local ok, decoded = pcall(function() return JSON:decode(resultBody) end)
	if not ok or type(decoded) ~= 'table' then
		return nil, 'HTTP ' .. tostring(status) .. ': Antwort war kein gültiges JSON.'
	end
	return decoded, nil, status
end

--------------------------------------------------------------------------------
-- Loopback listener
--------------------------------------------------------------------------------

-- Waits for the browser redirect and returns the decoded query parameters.
-- Must be called from inside an async task AND inside a function context
-- (LrSocket.bind requires the latter).
--
-- Note on the response page: LrSocket answers every received line with "ok"
-- by itself, so the browser will show a short page of "ok" lines. That cannot
-- be changed from here – see the file header.
function MediaWikiOAuth.waitForRedirect(functionContext, port, timeoutSeconds)
	local state = {
		params = nil,
		bindError = nil,
	}
	-- Path component of the registered redirect URI, e.g.
	-- "/lrmediawiki2/callback". Kept in sync with redirectUri automatically.
	local callbackPath = MediaWikiOAuth.redirectUri:match('^https?://[^/]+(/.*)$') or '/'

	local ok, socket = pcall(function()
		return LrSocket.bind {
			functionContext = functionContext,
			plugin = _PLUGIN,
			port = port,
			mode = 'receive',

			onMessage = function(_, message)
				if state.params ~= nil then return end
				local params, path = parseRequestLine(message)
				if isCallbackRequest(params, path, callbackPath) then
					state.params = params
				end
			end,

			onError = function(_, err)
				MediaWikiUtils.trace('OAuth: socket error: ' .. tostring(err))
			end,
		}
	end)

	if not ok or socket == nil then
		return nil, LOC("$$$/LrMediaWiki/OAuth/PortBusy=Port ^1 could not be opened. Another program is probably using it – please close it and try again.", tostring(port))
	end

	local waited = 0
	while waited < timeoutSeconds and state.params == nil do
		LrTasks.sleep(0.5)
		waited = waited + 0.5
	end

	pcall(function() socket:close() end)

	if state.params == nil then
		return nil, LOC "$$$/LrMediaWiki/OAuth/Timeout=No response from the browser. The login was cancelled or took too long."
	end
	return state.params
end

--------------------------------------------------------------------------------
-- The flow
--------------------------------------------------------------------------------

-- Runs the full interactive authorisation. Returns true on success, or
-- false plus a message. Must run inside an async task and a function context.
function MediaWikiOAuth.authorize(functionContext, apiPath)
	if not MediaWikiOAuth.isConfigured() then
		return false, LOC "$$$/LrMediaWiki/OAuth/NoClientId=No OAuth client ID is configured in this build of the plug-in."
	end

	local verifier = randomToken()
	local stateValue = randomToken()
	local challengeRaw = sha256Raw(verifier)
	if not challengeRaw then
		return false, LOC "$$$/LrMediaWiki/OAuth/NoSha256=SHA-256 is not available in this Lightroom version, so the secure login cannot be used."
	end
	local challenge = base64url(challengeRaw)

	local url = buildAuthorizeUrl(MediaWikiOAuth.authorizeUrl, MediaWikiOAuth.clientId,
		MediaWikiOAuth.redirectUri, stateValue, challenge)

	MediaWikiUtils.trace('OAuth: opening browser for authorisation (state and verifier redacted)')
	-- n: wish 31.07.2026 - open the login in a browser of the user's choice
	-- (configured in the Plug-in Manager). LrTasks.execute must NOT sit in
	-- a pcall (Lua 5.1 cannot yield across pcall); we run inside the login
	-- task without one, so a plain call is correct here.
	local opened = false
	local browserCmd = MediaWikiUtils.loginBrowserCommand(url)
	if browserCmd then
		local rc = LrTasks.execute(browserCmd)
		if rc == 0 then
			opened = true
			MediaWikiUtils.trace('OAuth: opened login in the chosen browser')
		else
			MediaWikiUtils.trace('OAuth: chosen browser failed (rc '
				.. tostring(rc) .. '), falling back to the default browser')
		end
	end
	if not opened then
		pcall(function() LrHttp.openUrlInBrowser(url) end)
	end

	local params, err = MediaWikiOAuth.waitForRedirect(functionContext,
		MediaWikiOAuth.port, MediaWikiOAuth.timeoutSeconds)
	if not params then
		return false, err
	end

	if params.error then
		local detail = params.error_description or params.error
		return false, LOC("$$$/LrMediaWiki/OAuth/Denied=Authorisation was refused: ^1", tostring(detail))
	end
	if params.state ~= stateValue then
		-- Someone other than our own browser hit the port.
		return false, LOC "$$$/LrMediaWiki/OAuth/BadState=The response did not match this login attempt and was discarded."
	end
	if type(params.code) ~= 'string' or params.code == '' then
		return false, LOC "$$$/LrMediaWiki/OAuth/NoCode=The browser did not return an authorisation code."
	end

	local tokenFields = {
		grant_type = 'authorization_code',
		code = params.code,
		redirect_uri = MediaWikiOAuth.redirectUri,
		client_id = MediaWikiOAuth.clientId,
		code_verifier = verifier,
	}
	if MediaWikiOAuth.clientSecret ~= '' then
		tokenFields.client_secret = MediaWikiOAuth.clientSecret
	end
	local decoded, postErr = postForm(MediaWikiOAuth.tokenUrl, tokenFields)
	if not decoded then
		return false, postErr
	end

	local token, tokenErr = tokenFromResponse(decoded, nowSeconds())
	if not token then
		return false, tokenErr
	end

	MediaWikiOAuth.storeToken(apiPath, token)
	MediaWikiUtils.trace('OAuth: access token stored (redacted)')
	return true
end

-- Exchanges the refresh token for a new access token. Returns the new token
-- table, or nil plus a message.
function MediaWikiOAuth.refresh(apiPath, token)
	if type(token) ~= 'table' or type(token.refreshToken) ~= 'string' or token.refreshToken == '' then
		return nil, LOC "$$$/LrMediaWiki/OAuth/NoRefreshToken=The saved login has expired and there is no refresh token. Please log in again."
	end
	local refreshFields = {
		grant_type = 'refresh_token',
		refresh_token = token.refreshToken,
		client_id = MediaWikiOAuth.clientId,
	}
	if MediaWikiOAuth.clientSecret ~= '' then
		refreshFields.client_secret = MediaWikiOAuth.clientSecret
	end
	local decoded, postErr = postForm(MediaWikiOAuth.tokenUrl, refreshFields)
	if not decoded then
		return nil, postErr
	end
	local fresh, tokenErr = tokenFromResponse(decoded, nowSeconds())
	if not fresh then
		return nil, tokenErr
	end
	-- Wikimedia returns a new refresh token; keep the old one if it does not.
	if not fresh.refreshToken then
		fresh.refreshToken = token.refreshToken
	end
	fresh.username = token.username
	MediaWikiOAuth.storeToken(apiPath, fresh)
	MediaWikiUtils.trace('OAuth: access token refreshed (redacted)')
	return fresh
end

-- Returns a currently valid access token for apiPath, refreshing if needed,
-- or nil plus a message. Returns nil WITHOUT a message if no token is stored
-- at all (that is the normal "not logged in via OAuth" case).
function MediaWikiOAuth.getValidAccessToken(apiPath)
	local token = MediaWikiOAuth.loadToken(apiPath)
	if not token then
		return nil
	end
	if tokenIsFresh(token, nowSeconds(), REFRESH_MARGIN) then
		return token.accessToken
	end
	local fresh, err = MediaWikiOAuth.refresh(apiPath, token)
	if not fresh then
		return nil, err
	end
	return fresh.accessToken
end

-- Records the Commons user name belonging to the stored token, so the export
-- dialog can show who is logged in.
function MediaWikiOAuth.setStoredUsername(apiPath, username)
	local token = MediaWikiOAuth.loadToken(apiPath)
	if token then
		token.username = username
		MediaWikiOAuth.storeToken(apiPath, token)
	end
end

-- Exposed for the standalone tests.
MediaWikiOAuth._internal = {
	base64url = base64url,
	hexToRaw = hexToRaw,
	digestToRaw = digestToRaw,
	urlDecode = urlDecode,
	urlEncode = urlEncode,
	parseRequestLine = parseRequestLine,
	isCallbackRequest = isCallbackRequest,
	buildAuthorizeUrl = buildAuthorizeUrl,
	tokenFromResponse = tokenFromResponse,
	tokenIsFresh = tokenIsFresh,
}

return MediaWikiOAuth
