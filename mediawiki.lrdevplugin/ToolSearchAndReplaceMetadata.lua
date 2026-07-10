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
local metadataProvider = require 'MediaWikiMetadataProvider'

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

local LrView = import "LrView"

LrFunctionContext.callWithContext( 'dialogExample', function( context )

    local prefs = import 'LrPrefs'.prefsForPlugin()

    prefs.searchAndReplaceMetadata = prefs.searchAndReplaceMetadata or {
        str = "..", 
        replaceStr = "--",
    }

    local props = u.copyProps(prefs.searchAndReplaceMetadata, LrBinding.makePropertyTable( context ))

    --u.log(metadataProvider.title);
    --u.log( json:encode_pretty(metadataProvider) )

    local f = LrView.osFactory()
    local contents = f:view { 
        bind_to_object = props,
        f:row { 
            f:static_text {
                title = "Search for",
            },
        },
        f:row { 
            --f:popup_menu {
            --    items = LrView.bind 'websiteChoices',
            --    value = LrView.bind 'websiteChosen',
            --},
            f:edit_field { 
                fill_horizonal = 1,
                width_in_chars = 40,
                height_in_lines = 2,
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
                height_in_lines = 2,
                immediate = true,
                placeholder_string = 'replace string',
                value = LrView.bind( 'replaceStr' ),
            },
        }
    }

    local inputOk = LrDialogs.presentModalDialog(  -- invoke a dialog box
        {
            resizable = true,
            title = "Adjust MediaWiki Metadata with Search and Replace", 
            contents = contents,   -- with the UI element
            actionVerb = "Adjust Metadata",   -- label for the action button
        }
    )

    if inputOk ~= "cancel" then

        -- Guard: an empty search string would make gsub insert the
        -- replacement between every character of every field.
        if MediaWikiUtils.isStringEmpty(props.str) then
            LrDialogs.message("Search and Replace", "The search string is empty – nothing to do.", "info")
            return
        end
        local searchPattern = escapePattern(props.str)
        local replacement = escapeReplacement(props.replaceStr or '')

        local catalog = LrApplication.activeCatalog()
        local photo = catalog:getTargetPhoto()
        local photos = catalog:getTargetPhotos()
        local data = LrTasks.startAsyncTask(function()
            local data = ''

            catalog:withWriteAccessDo('Set MetaData', function()
            
                for key,photo in pairs(photos) do 
                    
                    local v
                    for key,md in pairs(metadataProvider.metadataFieldsForPhotos) do
                        v = photo:getPropertyForPlugin( _PLUGIN, md.id )
                        if v ~= nil then
                            v = v:gsub(searchPattern, replacement)
                            photo:setPropertyForPlugin( _PLUGIN, md.id, v )
                        end
                    end
                end

            end)
            --utils.log(tostring(data))

            return data
        end )
    end

end )