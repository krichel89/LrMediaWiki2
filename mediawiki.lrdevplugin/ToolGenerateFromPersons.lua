-- Access the Lightroom SDK namespaces.
local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrLogger = import 'LrLogger'
local LrPathUtils = import 'LrPathUtils'
local LrPrefs = import 'LrPrefs'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'
local LrXml = import 'LrXml'

-- Other Libraries
local Info = require 'Info'
local MediaWikiUtils = require 'MediaWikiUtils'
local json = require 'JSON'
local u = require 'utils'

LrFunctionContext.callWithContext('DescriptionFromPersonsDialog',
                                  function(context)

    local prefs = import'LrPrefs'.prefsForPlugin()

    prefs.generatorPresets = prefs.generatorPresets or {
        -- prefs.generatorPresets = {
        {
            title = "empty",
            value = {
                title = '{{f}} {{p}}',
                title_sans = '{{f}}',
                title_de = true,
                description_de = '{{p}}',
                description_en = '{{p}}',
                categories = '{{p}}',
                v1 = '',
                v2 = '',
                v3 = ''
            }
        }
    }

    prefs.nicknameList = prefs.nicknameList or {}
    prefs.generator = prefs.generator or prefs.generatorPresets[1].value
    -- prefs.generator = prefs.generatorPresets[1].value

    local u = require 'utils'
    local LrBinding = import 'LrBinding'

    local props = u.copyProps(prefs.generator,
                              LrBinding.makePropertyTable(context))
    local catalog = LrApplication.activeCatalog()
    local photos = catalog:getTargetPhotos()
    -- local photo = catalog:getTargetPhoto()

    local varInfo =
        "Use {{f}} for filename, \n{{p}} for person name(s), \n{{n}} for file number, \n{{y}} for year, \n{{m}} for month, \n{{d}} for day, \n{{hl}} for metadata headline, \n{{cap}} for metadata caption"

    local f = LrView.osFactory()
    local bind = LrView.bind
    local contents = f:view{
        bind_to_object = props,
        f:row{
            margin_bottom = 10,
            f:static_text{
                title = "Generate filename und description for " ..
                    ((#photos == 1) and "one photo" or (#photos .. " photos")) ..
                    " from face recognition data."
            }
        },
        f:separator{fill_horizontal = 1},
        f:row{
            margin_top = 20,
            f:static_text{
                width = LrView.share "label_width",
                title = "Title",
                tooltip = varInfo
            },
            f:edit_field{
                fill_horizonal = 1,
                width_in_chars = 36,
                height_in_lines = 1,
                immediate = true,
                placeholder_string = 'filename prefix (incl. no) = {{f}}, fileumber = {{n}}, persons = {{p}}',
                value = bind 'title',
                wraps = false,
                tooltip = varInfo
            },
            f:checkbox{title = 'de, ', value = bind 'title_de'},
            f:checkbox{title = '', value = bind 'title_change'}
        },
        f:row{
            margin_top = 20,
            f:static_text{
                width = LrView.share "label_width",
                title = "Title without names",
                tooltip = varInfo
            },
            f:edit_field{
                fill_horizonal = 1,
                width_in_chars = 40,
                height_in_lines = 1,
                immediate = true,
                value = bind 'title_sans',
                wraps = false,
                tooltip = "The title that is used if there aren't any names found"
            },
            f:checkbox{title = '', value = bind 'title_sans_change'}
        },
        f:row{
            margin_top = 10,
            f:static_text{
                width = LrView.share "label_width",
                title = "Description (en)"
            },
            f:edit_field{
                fill_horizonal = 1,
                width_in_chars = 40,
                height_in_lines = 5,
                immediate = true,
                placeholder_string = 'type {{p}} to insert person names',
                value = LrView.bind('description_en'),
                tooltip = "The english description is also used as caption with striped WikiLinks\n" ..
                    varInfo
            },
            f:checkbox{
                title = '',
                value = LrView.bind('description_en_change'),
                checked_value = true,
                unchecked_value = false
            }
        },
        f:row{
            margin_top = 10,
            f:static_text{
                width = LrView.share "label_width",
                title = "Description (de)"
            },
            f:edit_field{
                fill_horizonal = 1,
                width_in_chars = 40,
                height_in_lines = 5,
                immediate = true,
                placeholder_string = 'type {{p}} to insert person names',
                value = LrView.bind('description_de'),
                wraps = true
            },
            f:checkbox{
                title = '',
                value = LrView.bind('description_de_change'),
                checked_value = true,
                unchecked_value = false
            }
        },
        f:row{
            margin_top = 10,
            margin_bottom = 20,
            f:static_text{
                width = LrView.share "label_width",
                title = "Category"
            },
            f:edit_field{
                fill_horizonal = 1,
                width_in_chars = 40,
                immediate = true,
                placeholder_string = 'Categories seperated with ";", type {{p}} to insert person categories',
                value = LrView.bind('categories'),
                tooltip = "Categories seperated by ;"
            },
            f:checkbox{
                title = '',
                value = LrView.bind('categories_change'),
                checked_value = true,
                unchecked_value = false
            }
        },
        f:row{
            margin_top = 10,
            margin_bottom = 20,
            f:static_text{
                width = LrView.share "label_width",
                title = "Custom variables"
            },
            f:static_text{width = 14, title = "v1"},
            f:edit_field{
                fill_horizonal = 1,
                width_in_chars = 11,
                immediate = true,
                placeholder_string = '{{v1}}',
                value = LrView.bind('v1'),
                tooltip = "Text to replace {{v1}} in the fields above"
            },
            f:static_text{width = 14, title = "v2"},
            f:edit_field{
                fill_horizonal = 1,
                width_in_chars = 11,
                immediate = true,
                placeholder_string = '{{v2}}',
                value = LrView.bind('v2'),
                tooltip = "Text to replace {{v2}} in the fields above"
            },
            f:static_text{width = 14, title = "v3"},
            f:edit_field{
                fill_horizonal = 1,
                width_in_chars = 11,
                immediate = true,
                placeholder_string = '{{v3}}',
                value = LrView.bind('v3'),
                tooltip = "Text to replace {{v3}} in the fields above"
            }
        },
        f:separator{fill_horizontal = 1},
        f:row{
            margin_top = 20,
            f:static_text{width = LrView.share "label_width", title = "Preset"},
            f:popup_menu{
                width_in_chars = 30,
                value = LrView.bind('preset'),
                items = prefs.generatorPresets,
                action = function()
                    local selectedPreset = props.preset
                    if selectedPreset then
                        u.copyProps(selectedPreset, props, {stringsOnly = false})
                    end
                end
            },
            f:push_button{
                title = 'load',
                action = function(args)
                    u.copyProps(props.preset, props, {stringsOnly = false})
                    -- u.log( json:encode(props.preset))
                end
            },
            f:push_button{
                title = 'update',
                action = function(args)
                    for key, value in pairs(prefs.generator) do
                        props.preset[key] = props[key]
                    end
                    -- u.log( json:encode(props.preset))
                end
            }
        },
        f:row{
            margin_top = 10,
            margin_bottom = 10,
            f:static_text{
                width = LrView.share "label_width",
                title = "New preset name"
            },
            f:edit_field{
                fill_horizonal = 1,
                width_in_chars = 37,
                height_in_lines = 1,
                immediate = true,
                placeholder_string = 'Preset name',
                value = LrView.bind('preset_name'),
                wraps = true
            },
            f:push_button{
                title = 'save',
                action = function()

                    -- prefs.generatorPresets[ #prefs.generatorPresets ] 
                    -- u.log('a')

                    local v = {}
                    for key, value in pairs(prefs.generator) do
                        v[key] = props[key]
                    end

                    local ob = {
                        title = props.preset_name,
                        value = v -- u.copyProps(props, {}, { stringsOnly = true }),
                    }

                    -- u.log( json:encode(ob) )
                    table.insert(prefs.generatorPresets, ob);
                    -- u.log( json:encode(prefs.generatorPresets) )
                end
            }
        },
        f:row{
            margin_top = 10,
            margin_bottom = 20,
            f:push_button{
                title = 'export all Presets',
                action = function(args)

                    local file = LrDialogs.runSavePanel({
                        title = 'Export Presets as JSON file to..',
                        prompt = 'Save Presets',
                        fileName = 'LrMediaWiki_PersonPresets_' ..
                            os.date('%y%m%d') .. '.json',
                        requiredFileType = 'json',
                        canCreateDirectories = true
                    })

                    local f = io.open(file, "w")
                    f:write(json:encode(prefs.generatorPresets))
                    io.close(f)

                end
            },
            f:push_button{
                title = 'import new Presets',
                action = function(args)

                    local file = LrDialogs.runOpenPanel({
                        title = 'Import new Presets as JSON file from..',
                        prompt = 'Open Presets',
                        canChooseFiles = true,
                        allowsMultipleSelection = false,
                        fileTypes = 'json'
                    })

                    local str = LrFileUtils.readFile(file[1])
                    local data = json:decode(str)

                    if data then

                        -- empty table
                        for k, v in pairs(prefs.generatorPresets) do
                            prefs.generatorPresets[k] = nil
                        end

                        for k, v in pairs(data) do
                            table.insert(prefs.generatorPresets, v)
                        end
                        -- u.log(json:encode(prefs.generatorPresets))
                    end
                end
            },
            f:separator{fill_vertical = 1},
            f:push_button{
                title = 'import Nicknames',
                action = function(args)

                    local file = LrDialogs.runOpenPanel({
                        title = 'Import Nickname List as JSON file from..',
                        prompt = 'Open Nickname List',
                        canChooseFiles = true,
                        allowsMultipleSelection = false,
                        fileTypes = 'json'
                    })

                    local str = LrFileUtils.readFile(file[1])
                    local data = json:decode(str)

                    if data then prefs.nicknameList = data end
                end
            },
            f:checkbox{
                title = 'use Nicknames',
                value = bind 'useNicknames',
                checked_value = true,
                unchecked_value = false
            }
        },
        f:separator{fill_horizontal = 1}
    }

    local inputOk = LrDialogs.presentModalDialog( -- invoke a dialog box
    {
        resizable = true,
        title = "Generator",
        contents = contents, -- with the UI element
        actionVerb = "Generate titel and Metadata", -- label for the action button
        cancelVerb = "Cancel"
    })

    if inputOk ~= "cancel" then

        for key, str in pairs(prefs.generator) do
            prefs.generator[key] = props[key]
        end

        local data = LrTasks.startAsyncTask(function()
            local data = ''

            for key, photo in pairs(photos) do

                local regions = u.getRegions(photo)
                local fname = u.getNameParts(photo)

                -- filter "_" names

                for i = #regions, 1, -1 do
                    local namePreset
                    local region = regions[i]
                    local firstChar = string.sub(region.name or '_', 1, 1)

                    if firstChar:match("%:") then
                        region.name = string.sub(region.name, 2) -- remove first char        
                        region.link = 'User:' .. region.name
                        firstChar = 'User'
                    end

                    if not firstChar:match("[%w]") then
                        table.remove(regions, i)
                    else
                        region.link = region.link or region.name

                        region.paratheses = region.name:match(" %(([^)]+)%)")
                        if region.paratheses then
                            if string.match(region.paratheses, "^:") then
                                region.paratheses = 'User' .. region.paratheses
                            end
                            -- region.link = 'test>' .. region.paratheses
                            if string.match(region.paratheses, "^(User:)") or
                                -- The pattern below was "^(Benutzerin:" – an
                                -- UNCLOSED capture that raised "unfinished
                                -- capture" at runtime for every name with a
                                -- parenthesized part that was not "User:…".
                                string.match(region.paratheses, "^(Benutzerin:)") or
                                string.match(region.paratheses, "^(Benutzer:)") then
                                region.link = region.paratheses
                            end
                        end
                        region.name = string.gsub(region.name, " %b()", "")

                        if props.useNicknames == true then
                            namePreset = prefs.nicknameList[region.name]
                            if namePreset then
                                region.name = namePreset.nickname or region.name
                            end
                        end

                    end
                end

                -- u.log( json:encode( regions ) )
                -- u.log( nDescription:attributes() )
                -- local data = json.encode( u.findNodeByName(regionsList, "Area"):attributes() )
                -- if regionsList then u.log( regionsList )
                -- u.log( tostring( xmpData:childAtIndex(xmpData:childCount() - 1):name() == "Regions" ));

                catalog:withWriteAccessDo('Set Filename', function()
                    -- catalog:withPrivateWriteAccessDo('Set Filename', function()

                    local data = {
                        v1 = props.v1 or '',
                        v2 = props.v2 or '',
                        v3 = props.v3 or '',
                        f = fname.preName or '',
                        y = '',
                        m = '',
                        d = '',
                        hl = photo:getFormattedMetadata('headline') or '',
                        cap = photo:getFormattedMetadata('caption') or ''
                    }

                    local timestamp = photo:getRawMetadata('dateTimeOriginal') +
                                          978307200 -- Unix epoch in Mac epoch time
                    u.log("Timestamp: " .. tostring(timestamp))
                    if timestamp then
                        data.y = tostring(os.date('%Y', timestamp)) or ''
                        data.m = tostring(os.date('%m', timestamp)) or ''
                        data.d = tostring(os.date('%d', timestamp)) or ''
                    end

                    local des
                    local titleNames = u.getNames(regions, {
                        last = (props.title_de and " und ") or " and ",
                        inter = ", "
                    });

                    des = '{{f}}'

                    if titleNames ~= '' and (#regions < 6) and props.title then
                        data.p = titleNames;
                        des = props.title;
                    elseif props.title_sans then
                        des = props.title_sans
                    end

                    des = u.renderMustache(des, data)

                    photo:setRawMetadata('title', des);
                    -- fname.preName is derived from the FILE NAME and must be
                    -- treated as a literal, not as a pattern. Measured with
                    -- real names: parentheses or a '-' make the pattern miss
                    -- its own text (caption silently keeps the prefix), and a
                    -- name ending in '%' raises "malformed pattern". preName
                    -- may also be nil for names without digits; the resulting
                    -- empty pattern leaves des unchanged.
                    photo:setRawMetadata('caption', des:gsub(u.escapePattern(fname.preName), '')
                                             :match('^%s*(.*%S)') or '');

                    if props.description_de then

                        data.p = u.getNames(regions, {
                            last = " und ",
                            inter = ", ",
                            lang = "de",
                            before = "[[:de:",
                            after = "|]]"
                        })

                        des = u.renderMustache(props.description_de, data)
                        photo:setPropertyForPlugin(_PLUGIN, 'description_de',
                                                   des)
                    end

                    if props.description_en then

                        -- caption
                        data.p = u.getNames(regions,
                                            {last = " and ", inter = ", "})

                        des = u.renderMustache(props.description_en, data)
                        photo:setPropertyForPlugin(_PLUGIN, 'caption_en',
                                                   u.stripWikiLinks(des))

                        data.p = u.getNames(regions, {
                            last = " and ",
                            inter = ", ",
                            lang = "en",
                            before = "[[:en:",
                            after = "|]]"
                        })
                        des = u.renderMustache(props.description_en, data)
                        photo:setPropertyForPlugin(_PLUGIN, 'description_en',
                                                   des)
                    end

                    if props.categories then
                        data.p = u.getNames(regions, {
                            inter = "",
                            after = ";",
                            returnLink = true
                        })

                        des = u.renderMustache(props.categories, data)
                        photo:setPropertyForPlugin(_PLUGIN, 'categories', des)
                    end

                    -- NOTE: the original plug-in wrote image notes for multi-
                    -- person photos into the 'otherFields' metadata field.
                    -- This fork does not declare that field; writing to an
                    -- undeclared property is a hard error that aborts the
                    -- tool ("Attempt to access property ... not declared").
                    -- The image-notes feature is therefore disabled until the
                    -- field (or a replacement) is declared again.

                end)
            end

            return data
        end)
    end
end)
