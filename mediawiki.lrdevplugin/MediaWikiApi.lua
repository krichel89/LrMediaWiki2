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
	userAgent = string.format('LrMediaWiki %d.%d', Info.VERSION.major, Info.VERSION.minor),
	apiPath = nil,
	githubApiVersion = 'https://api.github.com/repos/Hasenlaeufer/LrMediaWiki/releases',
	cachedEditToken = nil, -- cached CSRF token to avoid repeated token requests
}

function MediaWikiApi.httpError(status)
	LrErrors.throwUserError(LOC("$$$/LrMediaWiki/Api/HttpError=Received HTTP status ^1.", status))
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
	MediaWikiUtils.trace('Request body:');
	MediaWikiUtils.trace(requestBody);

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

	MediaWikiUtils.trace('Result body:');
	MediaWikiUtils.trace(resultBody);

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

	MediaWikiUtils.tracef('logintoken 1: %s', logintoken)

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
	MediaWikiUtils.tracef('logintoken 2: %s', logintoken)
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

	local requestHeaders = {
		{
			field = 'User-Agent',
			value = MediaWikiApi.userAgent,
		},
	}
	-- Build the index.php?action=raw URL from the api path
	-- e.g. https://commons.wikimedia.org/w/api.php -> https://commons.wikimedia.org/w/index.php
	local indexPath = MediaWikiApi.apiPath:gsub('api%.php', 'index.php')
	local url = indexPath .. '?action=raw&title=' .. MediaWikiApi.urlEncode(page)

	local LrHttp = import 'LrHttp'
	local resultBody, resultHeaders = LrHttp.get(url, requestHeaders)
	if resultHeaders and resultHeaders.status == 200 and resultBody then
		return resultBody
	else
		return nil -- page does not exist or error
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
	local labelsJson = '{'
	local first = true
	for lang, val in pairs(labelsTable) do
		if not first then labelsJson = labelsJson .. ',' end
		labelsJson = labelsJson .. '"' .. lang .. '":{"language":"' .. lang .. '","value":"' .. val:gsub('"', '\\"') .. '"}'
		first = false
	end
	labelsJson = labelsJson .. '}'

	local claimsJson = '['
	for i, claim in ipairs(claimsTable) do
		if i > 1 then claimsJson = claimsJson .. ',' end
		local numericId = claim.value:match('^Q(%d+)$')
		claimsJson = claimsJson .. '{"mainsnak":{"snaktype":"value","property":"' .. claim.property .. '","datavalue":{"type":"wikibase-entityid","value":{"entity-type":"item","numeric-id":' .. numericId .. ',"id":"' .. claim.value .. '"}}},"type":"statement","rank":"' .. (claim.rank or 'normal') .. '"}'
	end
	claimsJson = claimsJson .. ']'

	local dataJson = '{"labels":' .. labelsJson .. ',"claims":' .. claimsJson .. '}'
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
	local requestHeaders = {
		{
			field = 'User-Agent',
			value = MediaWikiApi.userAgent,
		},
	}
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

	local resultXml = MediaWikiApi.parseXmlDom(LrXml.parseXml(resultBody))
	if resultXml.error then
		MediaWikiApi.mediaWikiError(resultXml.error.code, resultXml.error.info)
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
