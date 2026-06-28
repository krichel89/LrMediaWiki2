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

local function searchAndReplaceMetadata( photo, metadataName, searchStr, replaceStr )
    local filename = string.sub( tostring(photo:getFormattedMetadata('fileName')),  0, -5)
    --underscore, num, oldlabel = string.match(filename, 'MJK(_*)(%d*)(.*)')

    replaceStr = replaceStr or ""
    
    local str = photo:getPropertyForPlugin( _PLUGIN, 'metadataName')
    str = str:gsub(searchStr, replaceStr)

    photo:getPropertyForPlugin( _PLUGIN, 'metadataName', str)

    return str
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
                            v = v:gsub(props.str, props.replaceStr)   
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