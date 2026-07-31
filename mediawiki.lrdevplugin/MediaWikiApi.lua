-- This file is part of the LrMediaWiki project and distributed under the terms
-- of the MIT license (see LICENSE.txt file in the project root directory or
-- [0]).  See [1] for more information about LrMediaWiki.
--
-- Copyright (C) 2014 by the LrMediaWiki team (see CREDITS.txt file in the
-- project root directory or [2])
--
-- [0]  <https://raw.githubusercontent.com/ireas/LrMediaWiki/master/LICENSE.txt>
-- [1]  <https://commons.wikimedia.org/wiki/Commons:LrMediaWiki>
-- [2]  <https://raw.githubusercontent.com/ireas/LrMediaWiki/master/CREDITS.txt>

-- Code status:
-- doc:   partly
-- i18n:  complete

local LrErrors = import 'LrErrors'
local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrXml = import 'LrXml'

local JSON = require 'JSON'
local Info = require 'Info'
local MediaWikiUtils = require 'MediaWikiUtils'

local MediaWikiApi = {
	userAgent = string.format('LrMediaWiki2 %d.%d', Info.VERSION.major, Info.VERSION.minor),
	apiPath = nil,
	githubApiVersion = 'https://api.github.com/repos/krichel89/LrMediaWiki2/releases',
	cachedEditToken = nil, -- cached CSRF token to avoid repeated token requests
	-- OAuth 2.0 bearer token for the current session. nil = classic
	-- username/password login. Set by MediaWikiInterface.prepareUpload.
	accessToken = nil,
}

function MediaWikiApi.setAccessToken(token)
	MediaWikiApi.accessToken = token
	-- A bearer token identifies a different user than a previous cookie
	-- session might have, so any cached CSRF token is worthless now.
	MediaWikiApi.cachedEditToken = nil
end

-- Appends the OAuth Authorization header to a header list, if a token is set.
-- SECURITY: only ever call this for requests that go to MediaWikiApi.apiPath –
-- never for the GitHub version check, which must not see the token.
function MediaWikiApi.addAuthHeader(requestHeaders)
	if MediaWikiApi.accessToken and MediaWikiApi.accessToken ~= '' then
		requestHeaders[#requestHeaders + 1] = {
			field = 'Authorization',
			value = 'Bearer ' .. MediaWikiApi.accessToken,
		}
	end
	return requestHeaders
end

function MediaWikiApi.httpError(status)
	LrErrors.throwUserError(LOC("$$$/LrMediaWiki/Api/HttpError=Received HTTP status ^1.", status))
end

-- Keys whose values must never be written to the log file.
local SENSITIVE_KEYS = {
	password = true,
	lgpassword = true,
	token = true,
	logintoken = true,
	lgtoken = true,
}

-- Build a log-safe representation of the request arguments (values of
-- sensitive keys are replaced by '***'). The actual HTTP request is NOT
-- affected; this string is only used for tracing.
local function redactedArguments(arguments)
	local parts = {}
	for key, value in pairs(arguments) do
		if SENSITIVE_KEYS[key] then
			value = '***'
		end
		parts[#parts + 1] = tostring(key) .. '=' .. tostring(value)
	end
	return table.concat(parts, '&')
end

-- Mask token values in server responses before tracing (e.g.
-- logintoken="..." / csrftoken="..." in the XML result).
local function redactedResponse(body)
	if type(body) ~= 'string' then
		return body
	end
	return (body:gsub('(%a*token=")[^"]*(")', '%1***%2'))
end

function MediaWikiApi.mediaWikiError(code, info)
	LrErrors.throwUserError(LOC("$$$/LrMediaWiki/Api/MediaWikiError=The MediaWiki error ^1 occured: ^2", code, info))
end

--- URL-encode a string according to RFC 3986.
-- Based on http://lua-users.org/wiki/StringRecipes
-- @param str the string to encode
-- @return the URL-encoded string
function MediaWikiApi.urlEncode(str)
	if str then
		str = string.gsub(str, '\n', '\r\n')
		str = string.gsub (str, '([^%w %-%_%.%~])',
			function(c) return string.format('%%%02X', string.byte(c)) end)
		str = string.gsub(str, ' ', '+')
	end
	return str
end

--- Convert HTTP arguments to a URL-encoded request body.
-- @param arguments (table) the arguments to convert
-- @return (string) a request body created from the URL-encoded arguments
function MediaWikiApi.createRequestBody(arguments)
	local body = nil
	for key, value in pairs(arguments) do
		if body then
			body = body .. '&'
		else
			body = ''
		end
		body = body .. MediaWikiApi.urlEncode(key) .. '=' .. MediaWikiApi.urlEncode(value)
	end
	return body or ''
end

function MediaWikiApi.parseXmlDom(xmlDomInstance)
	local value = nil
	if xmlDomInstance:type() == 'element' then
		value = {}
		for key, attribute in pairs(xmlDomInstance:attributes()) do
			value[key] = attribute.value
		end
		local textContent = ''
		for i = 1, xmlDomInstance:childCount() do
			local child = xmlDomInstance:childAtIndex(i)
			local childName = child:name()
			if childName then
				value[childName] = MediaWikiApi.parseXmlDom(child)
			elseif child:type() == 'text' then
				-- Accumulate text nodes into a special key
				textContent = textContent .. (child:text() or '')
			end
		end
		-- Store accumulated text content under '*' (like MediaWiki XML convention)
		if textContent ~= '' then
			value['*'] = textContent
		end
	elseif xmlDomInstance:type() == 'text' then
		value = xmlDomInstance:text()
	end
	return value
end

function MediaWikiApi.performHttpRequest(path, arguments, requestHeaders, post)
	local requestBody = MediaWikiApi.createRequestBody(arguments)

	MediaWikiUtils.trace('Performing HTTP request');
	MediaWikiUtils.trace('Path:')
	MediaWikiUtils.trace(path)
	MediaWikiUtils.trace('Request body (credentials/tokens redacted):');
	MediaWikiUtils.trace(redactedArguments(arguments));

	local resultBody, resultHeaders
	if post then
		resultBody, resultHeaders = LrHttp.post(path, requestBody, requestHeaders)
	else
		resultBody, resultHeaders = LrHttp.get(path .. '?' .. requestBody, requestHeaders)
	end

	MediaWikiUtils.trace('Result status:');
	MediaWikiUtils.trace(resultHeaders.status);

	if not resultHeaders.status then
		LrErrors.throwUserError(LOC("$$$/LrMediaWiki/Api/NoConnection=No network connection."))
	elseif resultHeaders.status ~= 200 then
		MediaWikiApi.httpError(resultHeaders.status)
	end

	MediaWikiUtils.trace('Result body (tokens redacted):');
	MediaWikiUtils.trace(redactedResponse(resultBody));

	return resultBody
end

function MediaWikiApi.performRequest(arguments)
	arguments.format = 'xml'
	local requestHeaders = {
		{
			field = 'User-Agent',
			value = MediaWikiApi.userAgent,
		},
		{
			field = 'Content-Type',
			value = 'application/x-www-form-urlencoded',
		},
	}
	MediaWikiApi.addAuthHeader(requestHeaders)

	local resultBody = MediaWikiApi.performHttpRequest(MediaWikiApi.apiPath, arguments, requestHeaders, true)
	local resultXml = MediaWikiApi.parseXmlDom(LrXml.parseXml(resultBody))
	if resultXml.error then
		-- On CSRF token error: clear cached token and retry once with a fresh token
		if resultXml.error.code == 'badtoken' or resultXml.error.code == 'invalid-csrf-token' then
			MediaWikiUtils.trace('CSRF token invalid, fetching fresh token and retrying...')
			MediaWikiApi.cachedEditToken = nil
			if arguments.token then
				arguments.token = MediaWikiApi.getEditToken()
			end
			resultBody = MediaWikiApi.performHttpRequest(MediaWikiApi.apiPath, arguments, requestHeaders, true)
			resultXml = MediaWikiApi.parseXmlDom(LrXml.parseXml(resultBody))
			if resultXml.error then
				MediaWikiApi.mediaWikiError(resultXml.error.code, resultXml.error.info)
			end
		else
			MediaWikiApi.mediaWikiError(resultXml.error.code, resultXml.error.info)
		end
	end
	return resultXml
end

function MediaWikiApi.getCurrentPluginVersion()
	local requestHeaders = {
		{
			field = 'User-Agent',
			value = MediaWikiApi.userAgent,
		},
	}
	local resultBody = MediaWikiApi.performHttpRequest(MediaWikiApi.githubApiVersion, {}, requestHeaders, false)
	local resultJson = JSON:decode(resultBody)
	local firstKey = MediaWikiUtils.getFirstKey(resultJson)
	if firstKey ~= nil then
		return resultJson[firstKey].tag_name
	end
	return nil
end

function MediaWikiApi.login(username, password)
-- See https://www.mediawiki.org/wiki/API:Login
	-- Check if the credentials are a main-account or a bot-account.
	-- The different credentials need different login arguments.
	-- The existance of the character "@" inside of an username is an
	-- identicator if the credentials are a bot-account or a main-account.
	local credentials
	if string.find(username, '@') then
		credentials = 'bot-account'
	else
		credentials = 'main-account'
	end
	local msg = 'Credentials: ' .. credentials
	MediaWikiUtils.trace(msg)

	-- A login token needs to be retrieved prior of a login action:
	local arguments = {
		action = 'query',
		meta = 'tokens',
		type = 'login',
		format = 'xml',
	}
	local xml = MediaWikiApi.performRequest(arguments)
	local logintoken = xml.query.tokens.logintoken

	MediaWikiUtils.trace('logintoken received (redacted)')

	-- Perform login:
	if credentials == 'main-account' then
		arguments = {
			action = 'clientlogin',
			loginreturnurl = 'https://www.mediawiki.org', -- dummy; required parameter
			username = username,
			password = password,
			logintoken = logintoken,
		}
		xml = MediaWikiApi.performRequest(arguments)
		local loginResult = xml.clientlogin.status
		if loginResult == 'PASS' then
			return true
		else
			return xml.clientlogin.message
		end
	else -- credentials == bot-account
		assert(credentials == 'bot-account')
		-- Check if a user is logged in:
		arguments = {
			action = 'query',
			meta = 'userinfo',
			format = 'xml',
		}
		xml = MediaWikiApi.performRequest(arguments)
		local id = xml.query.userinfo.id
		local name = xml.query.userinfo.name
		if id == '0' then -- not logged in, name is the IP address
			MediaWikiUtils.trace('Not logged in, need to login')
		else -- id ~= '0' – logged in
			msg = 'Logged in as user \"' .. name .. '\" (ID: ' .. id .. ')'
			MediaWikiUtils.trace(msg)
			if name == username then -- user is already logged in
				MediaWikiUtils.trace('No new login needed (1)')
				return true
			else -- name ~= username
				-- Check if name is main-account name of bot-username
				local pattern = '(.*)@' -- all characters up to "@"
				if name == string.match(username, pattern) then
					MediaWikiUtils.trace('No new login needed (2)')
					return true
				end
				msg = 'Logout and new login needed with username \"' .. username .. '\".'
				MediaWikiUtils.trace(msg)
			end
		end

		arguments = {
			action = 'login',
			lgname = username,
			lgpassword = password,
			lgtoken = logintoken,
		}
		msg = 'Bot-Login needed with username \"' .. username .. '\".'
		MediaWikiUtils.trace(msg)
		xml = MediaWikiApi.performRequest(arguments)
		local loginResult = xml.login.result
		if loginResult == 'Success' then
			return true
		else
			return xml.login.reason
		end
	end
end

-- Returns the name of the user the current session (cookie or bearer token)
-- belongs to, or nil if the request is anonymous. Used to confirm an OAuth
-- login and to show the account name in the export dialog.
function MediaWikiApi.getLoggedInUser()
	local arguments = {
		action = 'query',
		meta = 'userinfo',
		format = 'xml',
	}
	local ok, xml = pcall(function() return MediaWikiApi.performRequest(arguments) end)
	if not ok or type(xml) ~= 'table' then
		return nil
	end
	if not (xml.query and xml.query.userinfo) then
		return nil
	end
	local id = xml.query.userinfo.id
	if id == nil or id == '0' then -- '0' = anonymous, name is the IP address
		return nil
	end
	return xml.query.userinfo.name
end

function MediaWikiApi.logout()
-- See https://www.mediawiki.org/wiki/API:Logout
	local arguments = {
		action = 'query',
		meta = 'tokens',
		type = 'login',
		format = 'xml',
	}
	local xml = MediaWikiApi.performRequest(arguments)
	local logintoken = xml.query.tokens.logintoken
	MediaWikiUtils.trace('logintoken received (redacted)')
	arguments = {
		action = 'logout',
		token = logintoken,
		-- format = 'xml',
	}
	MediaWikiApi.performRequest(arguments)
end

function MediaWikiApi.getEditToken()
-- See https://www.mediawiki.org/wiki/API:Tokens
-- Token is cached after first retrieval to reduce API requests
	if MediaWikiApi.cachedEditToken then
		return MediaWikiApi.cachedEditToken
	end
	local arguments = {
		action = 'query',
		meta = 'tokens',
		type = 'csrf'; -- default, see https://www.mediawiki.org/wiki/API:Tokens
		format = 'xml',
	}
	local xml = MediaWikiApi.performRequest(arguments)
	MediaWikiApi.cachedEditToken = xml.query.tokens.csrftoken
	return MediaWikiApi.cachedEditToken
end

function MediaWikiApi.clearEditToken()
-- Call this if a request fails with a token error, to force a fresh token
	MediaWikiApi.cachedEditToken = nil
end

function MediaWikiApi.getPageContent(page)
	-- Use action=raw via performHttpRequest to get wikitext directly as plain text
	-- Returns: content, httpStatus
	--   content is nil if the page is missing (404) OR on any other error;
	--   callers must check httpStatus to tell those cases apart (404 = missing).

	local requestHeaders = {
		{
			field = 'User-Agent',
			value = MediaWikiApi.userAgent,
		},
	}
	MediaWikiApi.addAuthHeader(requestHeaders)
	-- Build the index.php?action=raw URL from the api path
	-- e.g. https://commons.wikimedia.org/w/api.php -> https://commons.wikimedia.org/w/index.php
	local indexPath = MediaWikiApi.apiPath:gsub('api%.php', 'index.php')
	local url = indexPath .. '?action=raw&title=' .. MediaWikiApi.urlEncode(page)

	local LrHttp = import 'LrHttp'
	local resultBody, resultHeaders = LrHttp.get(url, requestHeaders)
	local status = resultHeaders and resultHeaders.status or nil
	if status == 200 and resultBody then
		return resultBody, status
	else
		return nil, status -- 404 = page does not exist; anything else = error
	end
end

function MediaWikiApi.appendToPage(page, section, text, comment)
	local arguments = {
		action = 'edit',
		title = page,
		section = 'new',
		sectiontitle = section,
		text = text,
		summary = comment,
		token = MediaWikiApi.getEditToken(),
	}
	MediaWikiApi.performRequest(arguments)
end

function MediaWikiApi.setPageContent(page, text, comment)
	local arguments = {
		action = 'edit',
		title = page,
		text = text,
		summary = comment,
		token = MediaWikiApi.getEditToken(),
	}
	MediaWikiApi.performRequest(arguments)
end

function MediaWikiApi.existsFile(fileName)
	local arguments = {
		action = 'query',
		titles = 'File:' .. fileName,
	}
	local xml = MediaWikiApi.performRequest(arguments)
	return xml.query and xml.query.pages and xml.query.pages.page and not xml.query.pages.page.missing
end

function MediaWikiApi.getPageID(fileName)
	local arguments = {
		action = 'query',
		titles = 'File:' .. fileName,
	}
	local xml = MediaWikiApi.performRequest(arguments)
	return xml.query.pages.page.pageid
end

function MediaWikiApi.wbEditEntity(pageID, labelsTable, claimsTable)
	-- Set all labels and claims in a single API call
	-- labelsTable: { en = "...", de = "...", ... }
	-- claimsTable: list of { property = "P170", value = "Q640" }
	--
	-- The data JSON is built with JSON:encode (never by string concatenation),
	-- so quotes, backslashes and control characters in caption values are
	-- escaped correctly and cannot break or inject into the JSON structure.
	local labels = {}
	for lang, val in pairs(labelsTable) do
		labels[lang] = { language = lang, value = val }
	end

	local claims = {}
	for _, claim in ipairs(claimsTable) do
		-- Normalize the value: trim surrounding whitespace and upper-case a
		-- leading "q" (q640 -> Q640). Only emit a claim whose value is then a
		-- single, well-formed QID (Q + digits); a malformed or empty value is
		-- skipped instead of breaking the whole request.
		local canonical = ''
		if claim.value then
			canonical = claim.value:gsub('^%s*(.-)%s*$', '%1')
			canonical = canonical:gsub('^[qQ](%d+)$', 'Q%1')
		end
		local numericId = tonumber(canonical:match('^Q(%d+)$'))
		if numericId then
			claims[#claims + 1] = {
				mainsnak = {
					snaktype = 'value',
					property = claim.property,
					datavalue = {
						type = 'wikibase-entityid',
						value = {
							['entity-type'] = 'item',
							['numeric-id'] = numericId,
							id = canonical,
						},
					},
				},
				type = 'statement',
				rank = claim.rank or 'normal',
			}
		end
	end

	-- Only include non-empty parts: JSON:encode would serialize an empty Lua
	-- table as [] (array), but the API expects "labels" to be an object.
	local dataTable = {}
	if next(labels) ~= nil then
		dataTable.labels = labels
	end
	if #claims > 0 then
		dataTable.claims = claims
	end
	if next(dataTable) == nil then
		return nil -- nothing valid to send; treat as no-op
	end
	local dataJson = JSON:encode(dataTable)

	local arguments = {
		action = 'wbeditentity',
		id = 'M' .. pageID,
		data = dataJson,
		token = MediaWikiApi.getEditToken(),
		format = 'xml',
	}
	local xml = MediaWikiApi.performRequest(arguments)
	return xml
end

function MediaWikiApi.wbSetLabel(pageID, caption, language)
	local arguments = {
		action = 'wbsetlabel',
		id = 'M' .. pageID,
		language = language or 'en',
		value = caption,
		token = MediaWikiApi.getEditToken(),
	}
	local xml = MediaWikiApi.performRequest(arguments)
	return xml
end

function MediaWikiApi.wbCreateClaim(pageID, property, value)
	-- value should be a Q-item ID like "Q640"
	-- Wikibase API requires value as JSON: {"entity-type":"item","id":"Q640"}
	local jsonValue
	if string.match(value, '^Q%d+$') then
		jsonValue = '{"entity-type":"item","id":"' .. value .. '"}'
	else
		jsonValue = value -- pass through as-is for other value types
	end
	local arguments = {
		action = 'wbcreateclaim',
		entity = 'M' .. pageID,
		snaktype = 'value',
		property = property,
		value = jsonValue,
		token = MediaWikiApi.getEditToken(),
		format = 'xml',
	}
	local xml = MediaWikiApi.performRequest(arguments)
	return xml
end

function MediaWikiApi.upload(fileName, sourceFilePath, text, comment, ignoreWarnings)
	local sourceFileName = LrPathUtils.leafName(sourceFilePath)

	local requestHeaders = {
		{
			field = 'User-Agent',
			value = MediaWikiApi.userAgent,
		},
	}
	MediaWikiApi.addAuthHeader(requestHeaders)

	-- The multipart upload does not go through performRequest, so it needs its
	-- own one-time retry on a stale CSRF token (long batches can outlive it).
	local resultXml
	for attempt = 1, 2 do
		local arguments = {
			action = 'upload',
			filename = fileName,
			text = text,
			comment = comment,
			token = MediaWikiApi.getEditToken(),
			format = 'xml',
		}
		if ignoreWarnings then
			arguments.ignorewarnings = 'true'
		end
		local requestBody = {}
		for key, value in pairs(arguments) do
			requestBody[#requestBody + 1] = {
				name = key,
				value = value,
			}
		end
		requestBody[#requestBody + 1] = {
			name = 'file',
			fileName = sourceFileName,
			filePath = sourceFilePath,
			contentType = 'application/octet-stream',
		}

		local resultBody, resultHeaders = LrHttp.postMultipart(MediaWikiApi.apiPath, requestBody, requestHeaders)

		if resultHeaders.status ~= 200 then
			MediaWikiApi.httpError(resultHeaders.status)
		end

		resultXml = MediaWikiApi.parseXmlDom(LrXml.parseXml(resultBody))
		if resultXml.error then
			local code = resultXml.error.code
			if attempt == 1 and (code == 'badtoken' or code == 'invalid-csrf-token') then
				MediaWikiUtils.trace('Upload: CSRF token invalid, fetching fresh token and retrying...')
				MediaWikiApi.clearEditToken()
			else
				MediaWikiApi.mediaWikiError(resultXml.error.code, resultXml.error.info)
			end
		else
			break -- success (or warning), leave the retry loop
		end
	end

	local uploadResult = resultXml.upload.result
	if uploadResult == 'Success' then
		return true
	elseif uploadResult == 'Warning' then
		local warnings = ''
		-- concatenate the keys of the warnings table (= MediaWiki name of the warning)
		for warning in pairs(resultXml.upload.warnings) do
			if warnings ~= '' then
				warnings = warnings .. ', '
			end
			warnings = warnings .. warning
		end
		return warnings
	else
		return uploadResult
	end
end

return MediaWikiApi
