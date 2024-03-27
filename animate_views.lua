label = "Animate Views as GIF"
about = [[
Ipelet to generate an animated GIF from IPE views

By Marian Braendle
]]


local function animateViewsAsGif(model)
    local function onCheckboxRepeatFirstFrame(d)
        local enabled = d:get("check_repeatFirstFrame")
        d:setEnabled("input_repeatFirstFrame", enabled)
        d:setEnabled("unit_repeatFirstFrame", enabled)
    end

    local function onCheckboxRepeatLastFrame(d)
        local enabled = d:get("check_repeatLastFrame")
        d:setEnabled("input_repeatLastFrame", enabled)
        d:setEnabled("unit_repeatLastFrame", enabled)
    end

    local dialog = ipeui.Dialog(model.ui:win(), "Generate GIF from views of current page")
    dialog:add("label_size", "label", {label="Maximum width or height:"}, 1, 1)
    dialog:add("input_size", "input", {}, 1, 2)
    dialog:set("input_size", "500")
    dialog:add("unit_size", "label", {label="px"}, 1, 3)

    dialog:add("label_fps", "label", {label="Framerate: "}, 2, 1)
    dialog:add("input_fps", "input", {}, 2, 2)
    dialog:set("input_fps", "10")
    dialog:add("unit_fps", "label", {label="fps"}, 2, 3)

    dialog:add("check_repeatFirstFrame", "checkbox", {label="Repeat first frame:", action=onCheckboxRepeatFirstFrame}, 3, 1, 1, 2)
    dialog:add("input_repeatFirstFrame", "input", {}, 3, 2);
    dialog:setEnabled("input_repeatFirstFrame", false)
    dialog:set("input_repeatFirstFrame", "0")
    dialog:add("unit_repeatFirstFrame", "label", {label="times"}, 3, 3);
    dialog:setEnabled("unit_repeatFirstFrame", false)

    dialog:add("check_repeatLastFrame", "checkbox", {label="Repeat last frame:", action=onCheckboxRepeatLastFrame}, 4, 1, 1, 2)
    dialog:add("input_repeatLastFrame", "input", {}, 4, 2);
    dialog:setEnabled("input_repeatLastFrame", false)
    dialog:set("input_repeatLastFrame", "0")
    dialog:add("unit_repeatLastFrame", "label", {label="times"}, 4, 3);
    dialog:setEnabled("unit_repeatLastFrame", false)

    dialog:add("check_transparent", "checkbox", {label="Transparent"}, 5, 1)
    dialog:set("check_transparent", false)

    dialog:add("check_crop", "checkbox", {label="Crop"}, 6, 1)
    dialog:set("check_crop", true)

    dialog:addButton("ok", "&Ok", "accept")
    dialog:addButton("cancel", "&Cancel", "reject")

    if not dialog:execute() then return end

    local function _tonumberChecked(x, predicate, errmsg)
        local d = tonumber(x)
        if d ~= nil and predicate(d) then return d end
        ipeui.messageBox(model.ui:win(), "warning", errmsg)
    end

    local maxSize = _tonumberChecked(dialog:get("input_size"), function (x) return x > 0 end, "Invalid size!")
    if maxSize == nil then return end

    local fps = _tonumberChecked(dialog:get("input_fps"), function (x) return x > 0 end, "Invalid frames per second!")
    if fps == nil then return end

    local repeatFirstFrame = 0
    if dialog:get("check_repeatFirstFrame") then
        repeatFirstFrame = _tonumberChecked(dialog:get("input_repeatFirstFrame"), function (x) return x >= 0 end, "Invalid repetition count for first frame")
        if repeatFirstFrame == nil then return end
    end

    local repeatLastFrame = 0
    if dialog:get("check_repeatLastFrame") then
        repeatLastFrame = _tonumberChecked(dialog:get("input_repeatLastFrame"), function (x) return x >= 0 end, "Invalid repetition count for last frame")
        if repeatLastFrame == nil then return end
    end

    local crop = dialog:get("check_crop")
    local transparent = dialog:get("check_transparent")

    local page = model:page()
    local scaleFactor = 1 -- Irrelevant, use imagemagick for specifying final size
    local dir = model.filename and model.file_name:match(prefs.dir_pattern) or prefs.save_as_directory

    -- Get output file path
    local outputFilePath
    repeat
        outputFilePath = ipeui.fileDialog(model.ui:win(), "save", "Save as animated GIF",
            { "GIF files (*.gif)", "*.gif" }, dir)
        if not outputFilePath then return end
        local ok = 1
        if config.toolkit ~= "cocoa" and ipe.fileExists(outputFilePath) then
            ok = _G.messageBox(model.ui:win(), "question", "File already exists!",
                "Do you wish to overwrite?\n\n" .. outputFilePath, "okcancel")
        end
    until ok == 1

    local convertArgs = {
        "-resize", maxSize .. "x" .. maxSize,
        "-background", transparent and "none" or "white",
        "-monitor",
        "-layers", "optimize",
        "-delay", tostring(100/fps),
        "-loop", "0",
    }
    convertArgs[#convertArgs+1] = "@-" -- Read file list from stdin
    if repeatFirstFrame > 0 then
        -- For now, I couldn't find a better way to duplicate the first image at the beginning from a stdin file list
        convertArgs[#convertArgs+1] = "-reverse -duplicate " .. tostring(repeatFirstFrame-1) .. " -reverse"
    end
    if repeatLastFrame > 0 then
        convertArgs[#convertArgs+1] = "-duplicate " .. tostring(repeatLastFrame-1)
    end
    convertArgs[#convertArgs+1] = "gif:" .. outputFilePath

    local fileList = {}
    local function _generate_svgs()
        for i = 1, page:countViews() do
            print("Rendering SVG for view " .. i)
            local filePath = _G.string.format("%s/animate_%04d.svg", config.latexdir, i)
            model.ui:renderPage(model.doc, model.pno, i, "svg", filePath, scaleFactor, transparent, not crop)
            fileList[#fileList + 1] = filePath
        end
    end
    ipeui.waitDialog(model.ui:win(), _generate_svgs, "Generating intermediate SVGs...\n\n" ..
        "Depending on the number of views and the output resolution, this process can take several seconds.\n" ..
        "See console output for detailed information on current progress.")

    local function _generate_gif()
        local cmd = "convert " .. table.concat(convertArgs, " ")
        print("Running command:", cmd)
        local handle, errmsg = _G.io.popen(cmd, "w")
        if handle == nil or errmsg then model:warning("couldn't start 'convert': ", errmsg) return end

        -- Send file list to imagemagick
        handle:write(table.concat(fileList, "\n"))
        handle:close()
    end
    ipeui.waitDialog(model.ui:win(), _generate_gif, "Generating final GIF...\n\n" ..
        "Depending on the number of views and the output resolution, this process can take several minutes.\n" ..
        "See console output for detailed information on current progress.")

    -- Cleanup temporary files
    for _, f in ipairs(fileList) do _G.os.remove(f) end
    _G.messageBox(model.ui:win(), "information", "Successfully generated " .. outputFilePath, nil, "ok")
end

------------------------------------------------------
function run(model)
    animateViewsAsGif(model)
end