-- Access the Lightroom SDK namespaces.
local LrDialogs = import 'LrDialogs'
local LrLogger = import 'LrLogger'
local LrView = import 'LrView'
local LrDialogs = import 'LrDialogs'
local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'

-- Other Libaries
local Info = require 'Info'
local MediaWikiUtils = require 'MediaWikiUtils'
local json = require 'JSON'
local u = require 'utils'

-- Functions -------------------------------------------------------------------

-- Treat user input literally, not as a Lua pattern: escape all pattern magic
-- characters in the search string. Without this, a search ending in "%"
-- (e.g. "50%") or containing an unmatched "[" throws a runtime error
-- mid-batch, and characters such as ( ) . * + - ? ^ $ silently change the
-- matching semantics (e.g. "(Test)" never matches the literal text).
local function escapePattern(s)
    return (s:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%0'))
end

-- In the replacement string only '%' is special (%0, %1, ...); escape it.
local function escapeReplacement(s)
    return (s:gsub('%%', '%%%%'))
end

local function searchAndReplaceTitle( photo, searchStr, replaceStr )
    -- Strip the real file extension instead of blindly cutting the last four
    -- characters (which mangled names with 4-letter extensions like .jpeg
    -- or without any extension).
    local fileName = tostring(photo:getFormattedMetadata('fileName'))
    local filename = fileName:match('^(.*)%.[^.]+$') or fileName

    replaceStr = replaceStr or ""

    local title = filename
    title = title:gsub(escapePattern(searchStr), escapeReplacement(replaceStr))

    return title
end

local LrView = import "LrView"

LrFunctionContext.callWithContext( 'dialogExample', function( context )
    local properties = LrBinding.makePropertyTable( context )
    properties.str = '_'
    properties.replaceStr = ''

    local f = LrView.osFactory()
    local contents = f:view { 
        bind_to_object = properties,
        f:row { 
            f:static_text {
                title = "Search for",
            },
        },
        f:row { 
            f:edit_field { 
                fill_horizonal = 1,
                width_in_chars = 40,
                height_in_lines = 3,
                immediate = true,
                placeholder_string = 'string to search for',
                value = LrView.bind( 'str' ),
                wraps = true,
            },
        },
        f:row { 
            margin_top = 10,
            f:static_text {
                title = "and replace with",
            },
        },
        f:row { 
            f:edit_field { 
                fill_horizonal = 1,
                width_in_chars = 40, 
                height_in_lines = 3,
                immediate = true,
                placeholder_string = 'replace string',
                value = LrView.bind( 'replaceStr' ),
            },
        }
    }

    local inputOk = LrDialogs.presentModalDialog(  -- invoke a dialog box
        {
            resizable = true,
            title = "Adjust file title with Search and Replace", 
            contents = contents,   -- with the UI element
            actionVerb = "Adjust title",   -- label for the action button
        }
    )

    if inputOk ~= "cancel" then

        -- Guard: an empty search string would make gsub insert the
        -- replacement between every character of the title.
        if MediaWikiUtils.isStringEmpty(properties.str) then
            LrDialogs.message("Search and Replace", "The search string is empty – nothing to do.", "info")
            return
        end

        local catalog = LrApplication.activeCatalog()
        local photo = catalog:getTargetPhoto()
        local photos = catalog:getTargetPhotos()
        local data = LrTasks.startAsyncTask(function()
            local data = ''

            -- One write transaction for the whole batch (instead of one per
            -- photo): faster and a single undo step.
            catalog:withWriteAccessDo('Set Filename', function()
                for key,photo in pairs(photos) do
                    -- local persons = getPersons(photo)
                    local title = searchAndReplaceTitle(photo, properties.str, properties.replaceStr)
                    --text = text:gsub(", ", " and ")

                    photo:setRawMetadata( 'title', title )
                    --photo:setRawMetadata( 'copyName', title .. '.CR2') 
                end
            end)
            --utils.log(tostring(data))

            return data
        end )
    end

end )