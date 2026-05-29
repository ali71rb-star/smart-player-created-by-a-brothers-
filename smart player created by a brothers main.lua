-- Smart player created by a brothers
-- UI Language: English

require "import"
import "android.app.AlertDialog"
import "android.content.DialogInterface"
import "android.media.MediaPlayer"
import "java.io.File"
import "android.net.Uri"
import "android.content.Intent"
import "android.view.WindowManager"
import "android.os.Handler"
import "android.os.Looper"
import "java.lang.Runnable"
import "android.view.View"
import "android.widget.LinearLayout"
import "android.widget.TextView"
import "android.widget.SeekBar"
import "android.widget.Button"
import "android.widget.EditText"
import "android.text.InputType"
import "android.view.Gravity"
import "android.os.StrictMode"
import "android.app.NotificationManager"
import "android.app.NotificationChannel"
import "android.app.Notification"
import "android.app.PendingIntent"
import "android.content.Context"
import "android.content.IntentFilter"
import "android.media.audiofx.LoudnessEnhancer"
import "android.provider.MediaStore"
import "android.widget.ScrollView"
import "android.os.Environment"
import "android.view.SurfaceView"
import "android.view.SurfaceHolder"

-- Truly Persistent Global Player Instance & States
if not _G.smart_media_player then
    _G.smart_media_player = MediaPlayer()
    _G.smart_player_current_path = ""
    _G.smart_player_is_prepared = false
end
local player = _G.smart_media_player

local currentPlaylist = {}
local currentIndex = 1
local currentFilePath = ""
local currentSavedFolder = "/storage/emulated/0"
local currentSavedMediaType = "audio"
local lastPlayedPosition = 0
local ffRwDuration = 10000
local backgroundPlay = "on"
local autoPlay = "on"
local currentBoostStage = 1
local loudnessEnhancer = nil
local currentPlaybackSpeed = 1.0
local currentCustomSpeedSet = nil
local showWhatsAppMediaToggle = "on"
local showVolumeBoostToggle = "on"
local showSleepTimerToggle = "on"

-- Search, Sort & Browse Engine States
local currentSortMethod = "A-Z"
local currentSearchQuery = ""
local currentBrowseMode = "folders" 

-- Sleep Timer Engine Variables
local sleepHandler = Handler(Looper.getMainLooper())
local sleepRunnable = nil
local sleepModeActive = "off"
local sleepDurationMs = 0

-- Configuration File Path
local configPath = "/sdcard/smart_player_config.txt"
local NOTIF_ID = 9923
local CHANNEL_ID = "smart_player_channel"
local mediaReceiver = nil

-- UI References
local controlsDialog = nil
local txtTitleRef = nil
local txtTimeRef = nil
local seekBarRef = nil
local btnVolumeBoostRef = nil
local btnSleepToggleRef = nil
local btnPlayPauseRef = nil

local function showToast(text)
    service.speak(text)
end

-- Native Playback Speed Applier
local function applyPlaybackSpeed()
    if not player then return end
    pcall(function()
        local params = player.getPlaybackParams()
        params.setSpeed(currentPlaybackSpeed)
        player.setPlaybackParams(params)
    end)
end

-- Native Volume Boost Applier
local function applyVolumeBoost(silent)
    if not player then return end
    pcall(function()
        if not loudnessEnhancer then
            loudnessEnhancer = LoudnessEnhancer(player.getAudioSessionId())
        end
        loudnessEnhancer.setEnabled(true)
        if currentBoostStage == 1 then
            loudnessEnhancer.setTargetGain(0)
            if btnVolumeBoostRef then btnVolumeBoostRef.setText("Volume Boost: Normal") end
            if not silent then showToast("Volume Boost: Normal") end
        elseif currentBoostStage == 2 then
            loudnessEnhancer.setTargetGain(1200)
            if btnVolumeBoostRef then btnVolumeBoostRef.setText("Volume Boost: 1.5x") end
            if not silent then showToast("Volume Boost: 1.5x") end
        elseif currentBoostStage == 3 then
            loudnessEnhancer.setTargetGain(2500)
            if btnVolumeBoostRef then btnVolumeBoostRef.setText("Volume Boost: 2.0x") end
            if not silent then showToast("Volume Boost: 2.0x") end
        elseif currentBoostStage == 4 then
            loudnessEnhancer.setTargetGain(4000)
            if btnVolumeBoostRef then btnVolumeBoostRef.setText("Volume Boost: 3.0x") end
            if not silent then showToast("Volume Boost: 3.0x") end
        end
    end)
end

-- Notification Controller Engine
local function showNotification(title)
    pcall(function()
        local ns = Context.NOTIFICATION_SERVICE
        local nm = service.getSystemService(ns)
        if android.os.Build.VERSION.SDK_INT >= 26 then
            local channel = NotificationChannel(CHANNEL_ID, "Smart Player Playback", NotificationManager.IMPORTANCE_LOW)
            nm.createNotificationChannel(channel)
        end
        local builder
        if android.os.Build.VERSION.SDK_INT >= 26 then
            builder = Notification.Builder(service, CHANNEL_ID)
        else
            builder = Notification.Builder(service)
        end
        if not mediaReceiver then
            mediaReceiver = luajava.createProxy("android.content.BroadcastReceiver", {
                onReceive = function(context, intent)
                    if intent.getAction() == "com.smartplayer.TOGGLE" then
                        if player.isPlaying() then
                            player.pause()
                            if btnPlayPauseRef then btnPlayPauseRef.setText("Play") end
                        else
                            player.start()
                            applyPlaybackSpeed()
                            if btnPlayPauseRef then btnPlayPauseRef.setText("Pause") end
                        end
                        showNotification(File(currentFilePath).getName())
                    end
                end
            })
            local filter = IntentFilter("com.smartplayer.TOGGLE")
            service.registerReceiver(mediaReceiver, filter)
        end
        local toggleIntent = Intent("com.smartplayer.TOGGLE")
        local flags = 134217728
        if android.os.Build.VERSION.SDK_INT >= 23 then
            flags = flags + 67108864
        end
        local pToggle = PendingIntent.getBroadcast(service, 0, toggleIntent, flags)
        local appInfo = service.getApplicationInfo()
        builder.setContentTitle("Smart player created by a brothers")
        builder.setContentText(title)
        builder.setSmallIcon(appInfo.icon)
        builder.setOngoing(player.isPlaying())
        local actionText = player.isPlaying() and "Pause" or "Play"
        if android.os.Build.VERSION.SDK_INT >= 20 then
            local action = Notification.Action.Builder(appInfo.icon, actionText, pToggle).build()
            builder.addAction(action)
        else
            builder.addAction(appInfo.icon, actionText, pToggle)
        end
        nm.notify(NOTIF_ID, builder.build())
    end)
end

local function cancelNotification()
    pcall(function()
        local ns = Context.NOTIFICATION_SERVICE
        local nm = service.getSystemService(ns)
        nm.cancel(NOTIF_ID)
    end)
end

-- Persistent Storage: Save State
local function saveState()
    pcall(function()
        local f = io.open(configPath, "w")
        if f then
            f:write((currentSavedFolder or "/storage/emulated/0") .. "\n")
            f:write((currentSavedMediaType or "audio") .. "\n")
            f:write((currentFilePath or "") .. "\n")
            local pos = 0
            if player and currentFilePath ~= "" then pcall(function() pos = player.getCurrentPosition() end) end
            if pos == 0 and lastPlayedPosition > 0 then pos = lastPlayedPosition end
            f:write(tostring(pos) .. "\n")
            f:write(tostring(ffRwDuration) .. "\n")
            f:write((backgroundPlay or "on") .. "\n")
            f:write((autoPlay or "on") .. "\n")
            f:write(tostring(sleepDurationMs or 0) .. "\n")
            f:write(tostring(currentPlaybackSpeed or 1.0) .. "\n")
            f:write((showWhatsAppMediaToggle or "on") .. "\n")
            f:write((currentSortMethod or "A-Z") .. "\n")
            f:write((currentBrowseMode or "folders") .. "\n")
            f:write((showVolumeBoostToggle or "on") .. "\n")
            f:write((showSleepTimerToggle or "on") .. "\n")
            f:close()
        end
    end)
end

-- Persistent Storage: Load State
local function loadState()
    pcall(function()
        local f = io.open(configPath, "r")
        if f then
            currentSavedFolder = f:read("*l") or "/storage/emulated/0"
            currentSavedMediaType = f:read("*l") or "audio"
            currentFilePath = f:read("*l") or ""
            lastPlayedPosition = tonumber(f:read("*l")) or 0
            ffRwDuration = tonumber(f:read("*l")) or 10000
            backgroundPlay = f:read("*l") or "on"
            autoPlay = f:read("*l") or "on"
            sleepDurationMs = tonumber(f:read("*l")) or 0
            currentPlaybackSpeed = tonumber(f:read("*l")) or 1.0
            showWhatsAppMediaToggle = f:read("*l") or "on"
            currentSortMethod = f:read("*l") or "A-Z"
            currentBrowseMode = f:read("*l") or "folders"
            showVolumeBoostToggle = f:read("*l") or "on"
            showSleepTimerToggle = f:read("*l") or "on"
            f:close()
        end
    end)
end

-- Safe Dialog UI Launcher
local function showDialogSafe(builder, onBackHandler)
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            local dialog = builder.create()
            dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            if onBackHandler then
                import "android.view.KeyEvent"
                dialog.setOnKeyListener(DialogInterface.OnKeyListener({
                    onKey = function(d, keyCode, event)
                        if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
                            dialog.dismiss()
                            onBackHandler()
                            return true
                        end
                        return false
                    end
                }))
            end
            dialog.show()
        end
    }))
end

-- Enhanced Format Filter Logic
local function matchesFormat(name, mediaType)
    local lower = name:lower()
    if mediaType == "audio" then
        return lower:find("%.mp3$") or lower:find("%.m4a$") or lower:find("%.wav$") or lower:find("%.ogg$") or lower:find("%.amr$") or lower:find("%.opus$")
    elseif mediaType == "video" then
        return lower:find("%.mp4$") or lower:find("%.mkv$") or lower:find("%.3gp$")
    end
    return false
end

-- MediaStore helper
local function getMediaStoreDirsAndFiles(rootPath, mediaType)
    local dirs = {}
    local files = {}
    local resolver = service.getContentResolver()
    local uri = MediaStore.Files.getContentUri("external")
    local projection = {MediaStore.Files.FileColumns.DATA}
    local selection = MediaStore.Files.FileColumns.DATA .. " LIKE ?"
    local selArgs = {rootPath .. "/%"}
    local cursor = resolver.query(uri, projection, selection, selArgs, nil)
    if cursor then
        while cursor.moveToNext() do
            local data = cursor.getString(cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA))
            if data and data:sub(1, rootPath:len()) == rootPath then
                local relativePath = data:sub(rootPath:len() + 2)
                if relativePath and relativePath ~= "" then
                    local slashPos = relativePath:find("/")
                    if slashPos then
                        local dirName = relativePath:sub(1, slashPos - 1)
                        if dirName ~= "" and not dirName:find("^%.") then
                            dirs[dirName] = true
                        end
                    else
                        local name = relativePath
                        if matchesFormat(name, mediaType) then
                            table.insert(files, {name = name, path = data, isDir = false})
                        end
                    end
                end
            end
        end
        cursor.close()
    end
    local dirList = {}
    for dirName, _ in pairs(dirs) do
        table.insert(dirList, {name = dirName, path = rootPath .. "/" .. dirName, isDir = true})
    end
    table.sort(dirList, function(a,b) return a.name:lower() < b.name:lower() end)
    table.sort(files, function(a,b) return a.name:lower() < b.name:lower() end)
    return dirList, files
end

-- Recursive Scanner Engine
local function getAllRecursiveFiles(rootPath, mediaType)
    local files = {}
    local resolver = service.getContentResolver()
    local uri = MediaStore.Files.getContentUri("external")
    local projection = {MediaStore.Files.FileColumns.DATA, MediaStore.Files.FileColumns.DATE_MODIFIED}
    local selection = MediaStore.Files.FileColumns.DATA .. " LIKE ?"
    local selArgs = {rootPath .. "/%"}
    local cursor = nil
    pcall(function() cursor = resolver.query(uri, projection, selection, selArgs, nil) end)
    if cursor then
        while cursor.moveToNext() do
            local data = cursor.getString(cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA))
            if data then
                local fileObj = File(data)
                local name = fileObj.getName()
                if not name:find("^%.") and matchesFormat(name, mediaType) then
                    local time = 0
                    pcall(function() time = cursor.getLong(cursor.getColumnIndex(MediaStore.Files.FileColumns.DATE_MODIFIED)) * 1000 end)
                    table.insert(files, {name = name, path = data, isDir = false, time = time})
                end
            end
        end
        cursor.close()
    end
    if #files == 0 then
        local function scanDir(dir)
            local list = nil
            pcall(function() list = dir.listFiles() end)
            if not list then return end
            for i = 0, #list - 1 do
                local f = list[i]
                local name = f.getName()
                if not name:find("^%.") then
                    local isDir = false
                    pcall(function() isDir = f.isDirectory() end)
                    if isDir then
                        scanDir(f)
                    else
                        if matchesFormat(name, mediaType) then
                            local time = 0
                            pcall(function() time = f.lastModified() end)
                            table.insert(files, {name = name, path = f.getAbsolutePath(), isDir = false, time = time})
                        end
                    end
                end
            end
        end
        scanDir(File(rootPath))
    end
    return files
end

-- Smart Filter
local function hasMedia(fileObj, mediaType, depth)
    if depth > 10 then return false end
    local list = nil
    pcall(function() list = fileObj.listFiles() end)
    if not list then return false end
    for i = 0, #list - 1 do
        local child = list[i]
        local name = child.getName()
        if not name:find("^%.") then
            local isDir = false
            pcall(function() isDir = child.isDirectory() end)
            if isDir then
                if hasMedia(child, mediaType, depth + 1) then return true end
            else
                if matchesFormat(name, mediaType) then return true end
            end
        end
    end
    return false
end

-- Helper to find SD card path
local function getSdCardPathViaMediaStore()
    local resolver = service.getContentResolver()
    local uri = MediaStore.Files.getContentUri("external")
    local projection = {MediaStore.Files.FileColumns.DATA}
    local selection = MediaStore.Files.FileColumns.DATA .. " LIKE ?"
    local selArgs = {"/storage/%"}
    local cursor = nil
    pcall(function()
        cursor = resolver.query(uri, projection, selection, selArgs, nil)
    end)
    if cursor then
        while cursor.moveToNext() do
            local data = cursor.getString(cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA))
            if data and data:sub(1, 9) == "/storage/" then
                local relativePath = data:sub(10)
                local slashPos = relativePath:find("/")
                if slashPos then
                    local volume = relativePath:sub(1, slashPos - 1)
                    if volume ~= "emulated" and volume ~= "self" and volume ~= "sdcard0" then
                        cursor.close()
                        return "/storage/" .. volume
                    end
                end
            end
        end
        cursor.close()
    end
    return nil
end

-- Robust SD card path detection
local function getExternalSdCardPath()
    local storageDir = File("/storage")
    local list = storageDir.listFiles()
    if list then
        for i = 0, #list - 1 do
            local f = list[i]
            local name = f.getName()
            if not name:find("^%.") and name ~= "emulated" and name ~= "self" and name ~= "sdcard0" then
                local isDir = false
                pcall(function() isDir = f.isDirectory() end)
                if isDir then
                    return f.getAbsolutePath()
                end
            end
        end
    end
    local secondary = os.getenv("SECONDARY_STORAGE")
    if secondary and secondary ~= "" then
        local dir = File(secondary)
        if dir.exists() and dir.isDirectory() then
            return secondary
        end
    end
    local msPath = getSdCardPathViaMediaStore()
    if msPath then
        return msPath
    end
    local mediaRw = File("/mnt/media_rw")
    local listRw = mediaRw.listFiles()
    if listRw then
        for i = 0, #listRw - 1 do
            local f = listRw[i]
            local name = f.getName()
            if not name:find("^%.") and name ~= "emulated" and name ~= "self" then
                local isDir = false
                pcall(function() isDir = f.isDirectory() end)
                if isDir then
                    return f.getAbsolutePath()
                end
            end
        end
    end
    return "/storage"
end

local showMainMenu, showStorageMenu, showWhatsAppMenu, showMediaTypeMenu, showBrowseModeMenu, renderMediaList, playMedia, showPlayerControls, showMoreOptions, startSeekBarUpdate, showSettingsMenu, showAudioSettingsMenu, showSleepTimerDialog, showPlaybackSpeedMenu

-- 1. Main Menu
showMainMenu = function()
    local items = {}
    local actions = {}
    table.insert(items, "Scan")
    table.insert(actions, "scan")
    if showWhatsAppMediaToggle == "on" then
        table.insert(items, "WhatsApp Media")
        table.insert(actions, "whatsapp")
    end
    table.insert(items, "Settings")
    table.insert(actions, "settings")
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Smart player created by a brothers")
    builder.setItems(items, function(dialog, which)
        local action = actions[which + 1]
        if action == "scan" then
            showStorageMenu()
        elseif action == "whatsapp" then
            showWhatsAppMenu()
        elseif action == "settings" then
            showSettingsMenu()
        end
    end)
    builder.setNegativeButton("Close", nil)
    showDialogSafe(builder)
end

-- WhatsApp Media Shortcut
showWhatsAppMenu = function()
    local items = {"WhatsApp Audio", "WhatsApp Voice Notes", "WhatsApp Video"}
    local builder = AlertDialog.Builder(service)
    builder.setTitle("WhatsApp Media Center")
    builder.setItems(items, function(dialog, which)
        local baseDir = "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/"
        local selectedPath = ""
        local mediaType = "audio"
        if which == 0 then
            selectedPath = baseDir .. "WhatsApp Audio"
        elseif which == 1 then
            selectedPath = baseDir .. "WhatsApp Voice Notes"
        elseif which == 2 then
            selectedPath = baseDir .. "WhatsApp Video"
            mediaType = "video"
        end
        local checkFile = File(selectedPath)
        if checkFile.exists() and checkFile.isDirectory() then
            currentBrowseMode = "folders"
            currentSearchQuery = ""
            saveState()
            renderMediaList(selectedPath, mediaType)
        else
            showToast("WhatsApp directory not found or empty.")
            showMainMenu()
        end
    end)
    builder.setNegativeButton("Back", function() showMainMenu() end)
    showDialogSafe(builder, function() showMainMenu() end)
end

-- 2. Master Settings Menu
showSettingsMenu = function()
    local items = {
        "Audio Settings",
        "Show WhatsApp Media in Main Menu: " .. showWhatsAppMediaToggle:upper()
    }
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Settings")
    builder.setItems(items, function(dialog, which)
        if which == 0 then
            showAudioSettingsMenu()
        elseif which == 1 then
            if showWhatsAppMediaToggle == "on" then
                showWhatsAppMediaToggle = "off"
            else
                showWhatsAppMediaToggle = "on"
            end
            saveState()
            showToast("WhatsApp Media Visibility: " .. showWhatsAppMediaToggle:upper())
            showSettingsMenu()
        end
    end)
    builder.setNegativeButton("Back", function() showMainMenu() end)
    showDialogSafe(builder, function() showMainMenu() end)
end

-- Audio Settings Sub-Menu
showAudioSettingsMenu = function()
    local currentSec = math.floor(ffRwDuration / 1000)
    local items = {
        "Fast Forward and Rewind Changing Time: " .. currentSec .. " Seconds",
        "Background Playback: " .. backgroundPlay:upper(),
        "Auto Play Next File: " .. autoPlay:upper(),
        "Playback Speed: " .. currentPlaybackSpeed .. "x",
        "Set Sleep Timer Duration",
        "Show Volume Boost on Player: " .. showVolumeBoostToggle:upper(),
        "Show Sleep Timer on Player: " .. showSleepTimerToggle:upper()
    }
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Audio Settings")
    builder.setItems(items, function(dialog, which)
        if which == 0 then
            local durItems = {"5 Seconds", "10 Seconds", "20 Seconds", "30 Seconds", "60 Seconds", "Custom..."}
            local durBuilder = AlertDialog.Builder(service)
            durBuilder.setTitle("Select Fast Forward and Rewind Duration")
            durBuilder.setItems(durItems, function(d, w)
                if w == 5 then
                    Handler(Looper.getMainLooper()).post(Runnable({
                        run = function()
                            local inputField = EditText(service)
                            inputField.setHint("Enter seconds (e.g., 25)")
                            inputField.setInputType(InputType.TYPE_CLASS_NUMBER)
                            inputField.setText(tostring(math.floor(ffRwDuration / 1000)))
                            
                            local customDurBuilder = AlertDialog.Builder(service)
                            customDurBuilder.setTitle("Enter Custom Duration")
                            customDurBuilder.setView(inputField)
                            customDurBuilder.setPositiveButton("Set", function()
                                local val = tonumber(tostring(inputField.getText()))
                                if val and val > 0 then
                                    ffRwDuration = val * 1000
                                    saveState()
                                    showToast("Duration set to " .. val .. " seconds")
                                else
                                    showToast("Invalid duration")
                                end
                                showAudioSettingsMenu()
                            end)
                            customDurBuilder.setNegativeButton("Cancel", function()
                                showAudioSettingsMenu()
                            end)
                            showDialogSafe(customDurBuilder, function() showAudioSettingsMenu() end)
                        end
                    }))
                else
                    if w == 0 then ffRwDuration = 5000
                    elseif w == 1 then ffRwDuration = 10000
                    elseif w == 2 then ffRwDuration = 20000
                    elseif w == 3 then ffRwDuration = 30000
                    elseif w == 4 then ffRwDuration = 60000 end
                    saveState()
                    showToast("Duration updated")
                    showAudioSettingsMenu()
                end
            end)
            durBuilder.setNegativeButton("Back", function() showAudioSettingsMenu() end)
            showDialogSafe(durBuilder, function() showAudioSettingsMenu() end)
        elseif which == 1 then
            if backgroundPlay == "on" then backgroundPlay = "off" cancelNotification() else backgroundPlay = "on" end
            saveState()
            showToast("Background playback " .. backgroundPlay)
            showAudioSettingsMenu()
        elseif which == 2 then
            if autoPlay == "on" then autoPlay = "off" else autoPlay = "on" end
            saveState()
            showToast("Auto Play " .. autoPlay)
            showAudioSettingsMenu()
        elseif which == 3 then
            showPlaybackSpeedMenu("settings")
        elseif which == 4 then
            showSleepTimerDialog()
        elseif which == 5 then
            showVolumeBoostToggle = (showVolumeBoostToggle == "on") and "off" or "on"
            saveState()
            showToast("Volume Boost visibility updated")
            showAudioSettingsMenu()
        elseif which == 6 then
            showSleepTimerToggle = (showSleepTimerToggle == "on") and "off" or "on"
            saveState()
            showToast("Sleep Timer visibility updated")
            showAudioSettingsMenu()
        end
    end)
    builder.setNegativeButton("Back", function() showSettingsMenu() end)
    showDialogSafe(builder, function() showSettingsMenu() end)
end

-- Playback Speed Menu
showPlaybackSpeedMenu = function(parentMenu)
    local baseSpeeds = {0.5, 1.0, 1.5, 2.0}
    local items = {"0.5x", "1.0x (Normal)", "1.5x", "2.0x"}
    
    local isCustomActive = true
    for _, v in ipairs(baseSpeeds) do
        if math.abs(currentPlaybackSpeed - v) < 0.01 then
            isCustomActive = false
            break
        end
    end
    
    if isCustomActive then
        table.insert(items, string.format("%.2fx (Custom)", currentPlaybackSpeed))
        table.insert(baseSpeeds, currentPlaybackSpeed)
    end
    
    if parentMenu == "settings" then
        table.insert(items, "Set Custom Speed...")
    end
    
    local speedBuilder = AlertDialog.Builder(service)
    speedBuilder.setTitle("Playback Speed")
    speedBuilder.setItems(items, function(d, w)
        local idx = w + 1
        if parentMenu == "settings" and idx == #items then
            Handler(Looper.getMainLooper()).post(Runnable({
                run = function()
                    local inputField = EditText(service)
                    inputField.setHint("e.g. 1.25 or 1.75")
                    inputField.setInputType(InputType.TYPE_CLASS_NUMBER + InputType.TYPE_NUMBER_FLAG_DECIMAL)
                    inputField.setText(tostring(currentPlaybackSpeed))
                    
                    local customBuilder = AlertDialog.Builder(service)
                    customBuilder.setTitle("Enter Custom Speed")
                    customBuilder.setView(inputField)
                    customBuilder.setPositiveButton("Set", function()
                        local val = tonumber(tostring(inputField.getText()))
                        if val and val > 0 and val <= 4.0 then
                            currentPlaybackSpeed = val
                            applyPlaybackSpeed()
                            saveState()
                            showToast("Speed set to " .. val .. "x")
                        else
                            showToast("Invalid speed. Enter between 0.1 and 4.0")
                        end
                        showAudioSettingsMenu()
                    end)
                    customBuilder.setNegativeButton("Cancel", function()
                        showAudioSettingsMenu()
                    end)
                    showDialogSafe(customBuilder, function() showAudioSettingsMenu() end)
                end
            }))
        else
            currentPlaybackSpeed = baseSpeeds[idx]
            applyPlaybackSpeed()
            saveState()
            showToast("Playback speed changed: " .. currentPlaybackSpeed .. "x")
            if parentMenu == "settings" then showAudioSettingsMenu() else showMoreOptions() end
        end
    end)
    local backFunc = function()
        if parentMenu == "settings" then showAudioSettingsMenu() else showMoreOptions() end
    end
    speedBuilder.setNegativeButton("Back", backFunc)
    showDialogSafe(speedBuilder, backFunc)
end

-- Sleep Timer Dialog
showSleepTimerDialog = function()
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            local context = service
            local layout = LinearLayout(context)
            layout.setOrientation(LinearLayout.VERTICAL)
            layout.setPadding(50, 40, 50, 40)
            local txtMsg = TextView(context)
            txtMsg.setText("Select Your Sleep Mode Time Duration:")
            txtMsg.setTextSize(16)
            txtMsg.setPadding(0, 0, 0, 20)
            layout.addView(txtMsg)
            local etHours = EditText(context)
            etHours.setHint("Enter Hours")
            etHours.setInputType(InputType.TYPE_CLASS_NUMBER)
            layout.addView(etHours)
            local etMinutes = EditText(context)
            etMinutes.setHint("Enter Minutes")
            etMinutes.setInputType(InputType.TYPE_CLASS_NUMBER)
            layout.addView(etMinutes)
            local etSeconds = EditText(context)
            etSeconds.setHint("Enter Seconds")
            etSeconds.setInputType(InputType.TYPE_CLASS_NUMBER)
            layout.addView(etSeconds)
            local builder = AlertDialog.Builder(context)
            builder.setTitle("Sleep Timer Manager")
            builder.setView(layout)
            builder.setPositiveButton("Set Timer", DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    local h = tonumber(tostring(etHours.getText())) or 0
                    local m = tonumber(tostring(etMinutes.getText())) or 0
                    local s = tonumber(tostring(etSeconds.getText())) or 0
                    local totalMs = ((h * 3600) + (m * 60) + s) * 1000
                    if totalMs > 0 then
                        sleepDurationMs = totalMs
                        sleepModeActive = "on"
                        saveState()
                        if btnSleepToggleRef then btnSleepToggleRef.setText("Sleep Mode: ON") end
                        if sleepRunnable then sleepHandler.removeCallbacks(sleepRunnable) end
                        sleepRunnable = Runnable({
                            run = function()
                                pcall(function()
                                    if player and player.isPlaying() then player.pause() end
                                    if player then lastPlayedPosition = player.getCurrentPosition() end
                                    _G.smart_player_is_prepared = true
                                    _G.smart_player_minimized = false
                                    saveState()
                                    cancelNotification()
                                    if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                                end)
                            end
                        })
                        sleepHandler.postDelayed(sleepRunnable, sleepDurationMs)
                        showToast("Sleep mode activated successfully.")
                    else
                        showToast("Invalid time duration entered.")
                    end
                end
            }))
            builder.setNegativeButton("Cancel", DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    showAudioSettingsMenu()
                end
            }))
            local dialog = builder.create()
            dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            import "android.view.KeyEvent"
            dialog.setOnKeyListener(DialogInterface.OnKeyListener({
                onKey = function(d, keyCode, event)
                    if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
                        dialog.dismiss()
                        showAudioSettingsMenu()
                        return true
                    end
                    return false
                end
            }))
            dialog.show()
        end
    }))
end

-- 3. Storage Selection
showStorageMenu = function()
    local items = {"Internal Storage", "SD Card"}
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Choose Your Storage")
    builder.setItems(items, function(dialog, which)
        local selectedStorage = "/storage/emulated/0"
        if which == 1 then
            selectedStorage = getExternalSdCardPath()
        end
        showMediaTypeMenu(selectedStorage)
    end)
    builder.setNegativeButton("Back", function() showMainMenu() end)
    showDialogSafe(builder, function() showMainMenu() end)
end

-- 4. Media Type Selection
showMediaTypeMenu = function(storagePath)
    local items = {"Audio", "Video"}
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Choose Your Selection")
    builder.setItems(items, function(dialog, which)
        local mediaType = (which == 0) and "audio" or "video"
        showBrowseModeMenu(storagePath, mediaType)
    end)
    builder.setNegativeButton("Back", function() showStorageMenu() end)
    showDialogSafe(builder, function() showStorageMenu() end)
end

-- 5. Selection Mode Menu
showBrowseModeMenu = function(storagePath, mediaType)
    local items = {"All Files", "Browse Folders"}
    local builder = AlertDialog.Builder(service)
    builder.setTitle("Select Mode")
    builder.setItems(items, function(dialog, which)
        if which == 0 then
            currentBrowseMode = "all_files"
        else
            currentBrowseMode = "folders"
        end
        currentSearchQuery = ""
        saveState()
        renderMediaList(storagePath, mediaType)
    end)
    builder.setNegativeButton("Back", function() showMediaTypeMenu(storagePath) end)
    showDialogSafe(builder, function() showMediaTypeMenu(storagePath) end)
end

-- 6. Unified Media List Engine
renderMediaList = function(currentPath, mediaType)
    if currentPath == "/storage" then
        local autoSd = getExternalSdCardPath()
        if autoSd and autoSd ~= "/storage" then currentPath = autoSd else currentPath = "/storage/emulated/0" end
    end
    if currentPath == "/storage/emulated" then currentPath = "/storage/emulated/0" end

    currentSavedFolder = currentPath
    currentSavedMediaType = mediaType
    saveState()

    local rawItems = {}

    if currentBrowseMode == "all_files" then
        showToast("Scanning files, please wait...")
        rawItems = getAllRecursiveFiles(currentPath, mediaType)
    else
        local file = File(currentPath)
        local list = nil
        pcall(function() list = file.listFiles() end)
        local isStorageRoot = (currentPath == "/storage")

        if list and #list > 0 then
            for i = 0, #list - 1 do
                local f = list[i]
                local name = f.getName()
                if not name:find("^%.") and name ~= "emulated" and name ~= "self" and name ~= "sdcard0" and name ~= "0" then
                    if not (isStorageRoot and name:find("^%w+-%w+$")) then
                        local isDir = false
                        pcall(function() isDir = f.isDirectory() end)
                        local time = 0
                        pcall(function() time = f.lastModified() end)
                        if isDir then
                            if currentPath == "/storage" or hasMedia(f, mediaType, 1) then
                                table.insert(rawItems, {name = name, path = f.getAbsolutePath(), isDir = true, time = time})
                            end
                        else
                            if matchesFormat(name, mediaType) then
                                table.insert(rawItems, {name = name, path = f.getAbsolutePath(), isDir = false, time = time})
                            end
                        end
                    end
                end
            end
        else
            local dirs, files = getMediaStoreDirsAndFiles(currentPath, mediaType)
            for _, d in ipairs(dirs) do
                if d.name ~= "emulated" and d.name ~= "self" and d.name ~= "sdcard0" and d.name ~= "0" then
                    local time = 0
                    pcall(function() time = File(d.path).lastModified() end)
                    table.insert(rawItems, {name = d.name, path = d.path, isDir = true, time = time})
                end
            end
            for _, f in ipairs(files) do
                local time = 0
                pcall(function() time = File(f.path).lastModified() end)
                table.insert(rawItems, {name = f.name, path = f.path, isDir = false, time = time})
            end
        end
    end

    local filteredList = {}
    for _, item in ipairs(rawItems) do
        local keeps = true
        if currentSearchQuery ~= "" then
            if not item.name:lower():find(currentSearchQuery:lower(), 1, true) then
                keeps = false
            end
        end
        if keeps then table.insert(filteredList, item) end
    end

    if currentSortMethod == "A-Z" then
        table.sort(filteredList, function(a, b)
            if a.isDir ~= b.isDir then return a.isDir end
            return a.name:lower() < b.name:lower()
        end)
    elseif currentSortMethod == "Z-A" then
        table.sort(filteredList, function(a, b)
            if a.isDir ~= b.isDir then return a.isDir end
            return a.name:lower() > b.name:lower()
        end)
    elseif currentSortMethod == "Newest" then
        table.sort(filteredList, function(a, b)
            if a.isDir ~= b.isDir then return a.isDir end
            return (a.time or 0) > (b.time or 0)
        end)
    elseif currentSortMethod == "Oldest" then
        table.sort(filteredList, function(a, b)
            if a.isDir ~= b.isDir then return a.isDir end
            return (a.time or 0) < (b.time or 0)
        end)
    end

    local items = {}
    local actions = {}

    local searchString = "Search"
    if currentSearchQuery ~= "" then searchString = "Search: " .. currentSearchQuery end
    table.insert(items, searchString)
    table.insert(actions, {type = "control", target = "search"})

    local sortMethodsTranslations = {["A-Z"] = "A-Z", ["Z-A"] = "Z-A", ["Newest"] = "Newest First", ["Oldest"] = "Oldest First"}
    table.insert(items, "Sort By: " .. (sortMethodsTranslations[currentSortMethod] or currentSortMethod))
    table.insert(actions, {type = "control", target = "sort"})

    if currentSearchQuery ~= "" then
        table.insert(items, "Clear Search")
        table.insert(actions, {type = "control", target = "clear_search"})
    end

    for _, item in ipairs(filteredList) do
        if item.isDir then
            table.insert(items, "[Folder] " .. item.name)
        else
            table.insert(items, (mediaType == "audio" and "" or "🎬 ") .. item.name)
        end
        table.insert(actions, {type = "media", data = item})
    end

    if #filteredList == 0 and currentSearchQuery == "" then
        showToast("No files found.")
        showMainMenu()
        return
    end

    local builder = AlertDialog.Builder(service)
    builder.setTitle(currentBrowseMode == "all_files" and "All Files" or "Browse Folders")
    builder.setItems(items, function(dialog, which)
        local selectionAction = actions[which + 1]
        if selectionAction.type == "control" then
            if selectionAction.target == "search" then
                Handler(Looper.getMainLooper()).post(Runnable({
                    run = function()
                        local inputField = EditText(service)
                        inputField.setHint("Search...")
                        if currentSearchQuery ~= "" then inputField.setText(currentSearchQuery) end
                        local searchDialog = AlertDialog.Builder(service)
                        searchDialog.setTitle("Search")
                        searchDialog.setView(inputField)
                        searchDialog.setPositiveButton("Search", function()
                            currentSearchQuery = tostring(inputField.getText())
                            renderMediaList(currentPath, mediaType)
                        end)
                        searchDialog.setNegativeButton("Cancel", function()
                            renderMediaList(currentPath, mediaType)
                        end)
                        showDialogSafe(searchDialog, function() renderMediaList(currentPath, mediaType) end)
                    end
                }))
            elseif selectionAction.target == "sort" then
                local sortOptions = {"A-Z", "Z-A", "Newest First", "Oldest First"}
                local sortOptionBuilder = AlertDialog.Builder(service)
                sortOptionBuilder.setTitle("Sort By")
                sortOptionBuilder.setItems(sortOptions, function(d, w)
                    if w == 0 then currentSortMethod = "A-Z"
                    elseif w == 1 then currentSortMethod = "Z-A"
                    elseif w == 2 then currentSortMethod = "Newest"
                    elseif w == 3 then currentSortMethod = "Oldest" end
                    saveState()
                    renderMediaList(currentPath, mediaType)
                end)
                showDialogSafe(sortOptionBuilder, function() renderMediaList(currentPath, mediaType) end)
            elseif selectionAction.target == "clear_search" then
                currentSearchQuery = ""
                renderMediaList(currentPath, mediaType)
            end
        elseif selectionAction.type == "media" then
            local selectedMedia = selectionAction.data
            if selectedMedia.isDir then
                renderMediaList(selectedMedia.path, mediaType)
            else
                currentPlaylist = {}
                for _, innerObj in ipairs(filteredList) do
                    if not innerObj.isDir then
                        table.insert(currentPlaylist, innerObj.path)
                        if innerObj.path == selectedMedia.path then
                            currentIndex = #currentPlaylist
                        end
                    end
                end
                lastPlayedPosition = 0
                playMedia(selectedMedia.path, true) -- Force Play when explicitly selected from list
            end
        end
    end)

    local backFunc = function()
        if currentBrowseMode == "all_files" then
            showBrowseModeMenu(currentPath, mediaType)
        else
            local parentDir = File(currentPath).getParent()
            if parentDir and parentDir ~= "/storage" and parentDir ~= "/storage/emulated" and parentDir ~= "/storage/emulated/0" then
                renderMediaList(parentDir, mediaType)
            else
                showBrowseModeMenu(currentPath, mediaType)
            end
        end
    end
    builder.setNegativeButton("Back", backFunc)
    showDialogSafe(builder, backFunc)
end

-- 7. Media Playback Function (State-Aware Playback Engine)
playMedia = function(filePath, forcePlay)
    currentFilePath = filePath
    saveState()
    
    -- Smart State Logic: Determine if we should start playing or keep it paused
    local shouldStart = false
    if forcePlay ~= nil then
        shouldStart = forcePlay
    else
        -- If currently playing, next track will auto-play. If paused, next track will stay paused!
        pcall(function() shouldStart = player.isPlaying() end)
    end

    local success, err = pcall(function()
        player.reset()
        player.setDataSource(filePath)
        player.prepare()
        _G.smart_player_is_prepared = true
        _G.smart_player_current_path = filePath
        loudnessEnhancer = LoudnessEnhancer(player.getAudioSessionId())
        applyVolumeBoost(true)
        
        player.setOnCompletionListener(MediaPlayer.OnCompletionListener({
            onCompletion = function(mp)
                if autoPlay == "on" then
                    if currentIndex < #currentPlaylist then
                        currentIndex = currentIndex + 1
                        lastPlayedPosition = 0
                        playMedia(currentPlaylist[currentIndex], true) -- AutoPlay Next always forces start
                    else
                        cancelNotification()
                        if btnPlayPauseRef then btnPlayPauseRef.setText("Play") end
                    end
                else
                    cancelNotification()
                    if btnPlayPauseRef then btnPlayPauseRef.setText("Play") end
                end
            end
        }))
        
        if lastPlayedPosition > 0 then player.seekTo(lastPlayedPosition) end
        
        if shouldStart then
            player.start()
            applyPlaybackSpeed()
            if btnPlayPauseRef then btnPlayPauseRef.setText("Pause") end
            if backgroundPlay == "on" then showNotification(File(filePath).getName()) end
        else
            if btnPlayPauseRef then btnPlayPauseRef.setText("Play") end
            cancelNotification()
        end
    end)
    if not success then showToast("Playback Error.") end
    showPlayerControls()
end

-- 8. Custom Player Window
showPlayerControls = function()
    if controlsDialog and controlsDialog.isShowing() then
        txtTitleRef.setText(File(currentFilePath).getName())
        return
    end
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            local context = service
            local scrollView = ScrollView(context)
            local layout = LinearLayout(context)
            layout.setOrientation(LinearLayout.VERTICAL)
            layout.setPadding(45, 45, 45, 45)

            txtTitleRef = TextView(context)
            txtTitleRef.setText(File(currentFilePath).getName())
            txtTitleRef.setTextSize(18)
            txtTitleRef.setGravity(Gravity.CENTER)
            txtTitleRef.setPadding(0, 10, 0, 15)
            layout.addView(txtTitleRef)

            txtTimeRef = TextView(context)
            txtTimeRef.setText("00:00 / 00:00")
            txtTimeRef.setTextSize(15)
            txtTimeRef.setGravity(Gravity.CENTER)
            txtTimeRef.setPadding(0, 0, 0, 15)
            layout.addView(txtTimeRef)

            if currentSavedMediaType == "video" then
                local surfaceView = SurfaceView(context)
                local lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 550)
                lp.setMargins(0, 10, 0, 15)
                surfaceView.setLayoutParams(lp)
                layout.addView(surfaceView)
                
                local holder = surfaceView.getHolder()
                holder.addCallback(SurfaceHolder.Callback({
                    surfaceCreated = function(h)
                        pcall(function() player.setDisplay(h) end)
                    end,
                    surfaceChanged = function(h, format, width, height) end,
                    surfaceDestroyed = function(h)
                        pcall(function() player.setDisplay(nil) end)
                    end
                }))
            end

            seekBarRef = SeekBar(context)
            layout.addView(seekBarRef)
            seekBarRef.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener({
                onProgressChanged = function(sBar, progress, fromUser)
                    if fromUser then player.seekTo(math.floor(progress)) saveState() end
                end,
                onStartTrackingTouch = function(sBar) end,
                onStopTrackingTouch = function(sBar) end
            }))

            local spaceBeforeRow = TextView(context)
            spaceBeforeRow.setPadding(0, 0, 0, 10)
            layout.addView(spaceBeforeRow)

            -- Dynamic Buttons Layout (Sleep Mode & Volume Boost)
            local rowBoostSleep = LinearLayout(context)
            rowBoostSleep.setOrientation(LinearLayout.HORIZONTAL)
            rowBoostSleep.setGravity(Gravity.CENTER)
            
            local hasSleepBtn = (showSleepTimerToggle == "on")
            local hasBoostBtn = (showVolumeBoostToggle == "on")

            if hasSleepBtn then
                btnSleepToggleRef = Button(context)
                btnSleepToggleRef.setText("Sleep Mode: " .. sleepModeActive:upper())
                local lpSleep = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
                btnSleepToggleRef.setLayoutParams(lpSleep)
                btnSleepToggleRef.setOnClickListener(View.OnClickListener({
                    onClick = function(v)
                        if sleepModeActive == "on" then
                            sleepModeActive = "off"
                            if sleepRunnable then sleepHandler.removeCallbacks(sleepRunnable) end
                            btnSleepToggleRef.setText("Sleep Mode: OFF")
                            showToast("Sleep Mode OFF")
                        else
                            sleepModeActive = "on"
                            btnSleepToggleRef.setText("Sleep Mode: ON")
                            if sleepDurationMs and sleepDurationMs > 0 then
                                if sleepRunnable then sleepHandler.removeCallbacks(sleepRunnable) end
                                sleepRunnable = Runnable({
                                    run = function()
                                        pcall(function()
                                            if player and player.isPlaying() then player.pause() end
                                            if player then lastPlayedPosition = player.getCurrentPosition() end
                                            _G.smart_player_is_prepared = true
                                            _G.smart_player_minimized = false
                                            saveState()
                                            cancelNotification()
                                            if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                                        end)
                                    end
                                })
                                sleepHandler.postDelayed(sleepRunnable, sleepDurationMs)
                                showToast("Sleep Mode ON")
                            else
                                showToast("Sleep Mode ON")
                            end
                        end
                    end
                }))
                rowBoostSleep.addView(btnSleepToggleRef)
            end

            if hasBoostBtn then
                btnVolumeBoostRef = Button(context)
                local bLabels = {"Normal", "1.5x", "2.0x", "3.0x"}
                btnVolumeBoostRef.setText("Volume Boost: " .. bLabels[currentBoostStage])
                local lpBoost = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
                btnVolumeBoostRef.setLayoutParams(lpBoost)
                btnVolumeBoostRef.setOnClickListener(View.OnClickListener({
                    onClick = function(v)
                        currentBoostStage = currentBoostStage + 1
                        if currentBoostStage > 4 then currentBoostStage = 1 end
                        applyVolumeBoost()
                    end
                }))
                rowBoostSleep.addView(btnVolumeBoostRef)
            end

            if hasSleepBtn or hasBoostBtn then
                layout.addView(rowBoostSleep)
            end

            local spacer = TextView(context)
            spacer.setPadding(0, 0, 0, 20)
            layout.addView(spacer)

            local btnPrev = Button(context)
            btnPrev.setText("Previous")
            btnPrev.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    if currentIndex > 1 then
                        currentIndex = currentIndex - 1
                        lastPlayedPosition = 0
                        playMedia(currentPlaylist[currentIndex]) -- Inherits current playback state
                    else showToast("First file.") end
                end
            }))
            layout.addView(btnPrev)

            local btnRewind = Button(context)
            btnRewind.setText("Rewind <<")
            btnRewind.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    local currentPos = player.getCurrentPosition()
                    local targetPos = math.floor(currentPos - ffRwDuration)
                    if targetPos < 0 then targetPos = 0 end
                    player.seekTo(targetPos)
                    saveState()
                    showToast("Rewind " .. math.floor(ffRwDuration / 1000))
                end
            }))
            layout.addView(btnRewind)

            -- Play / Pause Button
            local btnPlayPause = Button(context)
            btnPlayPauseRef = btnPlayPause
            local isPlaying = false
            pcall(function() isPlaying = player.isPlaying() end)
            btnPlayPause.setText(isPlaying and "Pause" or "Play")
            
            btnPlayPause.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    if player and player.isPlaying() then
                        player.pause() 
                        saveState() 
                        btnPlayPause.setText("Play")
                        if backgroundPlay == "on" then showNotification(File(currentFilePath).getName()) end
                    else
                        player.start()
                        applyPlaybackSpeed()
                        btnPlayPause.setText("Pause")
                        if backgroundPlay == "on" then showNotification(File(currentFilePath).getName()) end
                    end
                end
            }))
            layout.addView(btnPlayPause)

            local btnFF = Button(context)
            btnFF.setText("Fast Forward >>")
            btnFF.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    local currentPos = player.getCurrentPosition()
                    local totalDur = player.getDuration()
                    local targetPos = math.floor(currentPos + ffRwDuration)
                    if targetPos > totalDur then targetPos = totalDur - 1000 end
                    player.seekTo(targetPos)
                    saveState()
                    showToast("Fast Forward " .. math.floor(ffRwDuration / 1000))
                end
            }))
            layout.addView(btnFF)

            local btnNext = Button(context)
            btnNext.setText("Next")
            btnNext.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    if currentIndex < #currentPlaylist then
                        currentIndex = currentIndex + 1
                        lastPlayedPosition = 0
                        playMedia(currentPlaylist[currentIndex]) -- Inherits current playback state
                    else showToast("Last file.") end
                end
            }))
            layout.addView(btnNext)

            local btnMore = Button(context)
            btnMore.setText("More Options")
            btnMore.setOnClickListener(View.OnClickListener({
                onClick = function(v) showMoreOptions() end
            }))
            layout.addView(btnMore)

            local btnFolder = Button(context)
            btnFolder.setText("Choose Your Folder")
            btnFolder.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    saveState()
                    if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                    renderMediaList(currentSavedFolder, currentSavedMediaType)
                end
            }))
            layout.addView(btnFolder)

            local btnMinimize = Button(context)
            btnMinimize.setText("Minimize Player")
            btnMinimize.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    saveState()
                    if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                    _G.smart_player_minimized = true
                    if backgroundPlay == "on" then
                        showNotification(File(currentFilePath).getName())
                    else
                        pcall(function() if player.isPlaying() then player.pause() end lastPlayedPosition = player.getCurrentPosition() end)
                        _G.smart_player_is_prepared = true
                        saveState() cancelNotification()
                    end
                end
            }))
            layout.addView(btnMinimize)

            local btnExit = Button(context)
            btnExit.setText("Exit")
            btnExit.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    pcall(function() player.reset() end)
                    currentFilePath = ""
                    lastPlayedPosition = 0
                    currentSavedFolder = "" 
                    _G.smart_player_is_prepared = false
                    _G.smart_player_current_path = ""
                    _G.smart_player_minimized = false
                    saveState()
                    cancelNotification()
                    if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                end
            }))
            layout.addView(btnExit)

            scrollView.addView(layout)
            local builder = AlertDialog.Builder(context)
            builder.setView(scrollView)
            controlsDialog = builder.create()
            controlsDialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            
            import "android.view.KeyEvent"
            controlsDialog.setOnKeyListener(DialogInterface.OnKeyListener({
                onKey = function(dialog, keyCode, event)
                    if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
                        controlsDialog.dismiss()
                        controlsDialog = nil
                        saveState()
                        _G.smart_player_minimized = true
                        if backgroundPlay == "on" then
                            showNotification(File(currentFilePath).getName())
                        else
                            pcall(function() if player.isPlaying() then player.pause() end lastPlayedPosition = player.getCurrentPosition() end)
                            _G.smart_player_is_prepared = true
                            saveState() cancelNotification()
                        end
                        return true
                    end
                    return false
                end
            }))
            
            controlsDialog.show()
            startSeekBarUpdate()
        end
    }))
end

-- 9. Optimized SeekBar & Text Sync Thread (Prevents TalkBack double-click bugs)
local isUpdating = false
startSeekBarUpdate = function()
    if isUpdating then return end
    isUpdating = true
    local handler = Handler(Looper.getMainLooper())
    local updateRunnable
    local cycleCount = 0
    updateRunnable = Runnable({
        run = function()
            if controlsDialog and controlsDialog.isShowing() and player then
                local isPlaying = false
                local current = 0
                local total = 0
                
                local ok = pcall(function()
                    isPlaying = player.isPlaying()
                    current = player.getCurrentPosition()
                    total = player.getDuration()
                end)

                if ok and total > 0 then
                    if btnPlayPauseRef then
                        -- Fixed: Replaced .toString() with tostring(...) for stable Lua bridging
                        local expectedText = isPlaying and "Pause" or "Play"
                        if tostring(btnPlayPauseRef.getText()) ~= expectedText then
                            btnPlayPauseRef.setText(expectedText)
                        end
                    end
                    seekBarRef.setMax(total)
                    seekBarRef.setProgress(current)
                    
                    local curSec = math.floor(current / 1000)
                    local curMin = math.floor(curSec / 60)
                    curSec = curSec % 60
                    
                    local totSec = math.floor(total / 1000)
                    local totMin = math.floor(totSec / 60)
                    totSec = totSec % 60
                    
                    txtTimeRef.setText(string.format("%02d:%02d / %02d:%02d", curMin, curSec, totMin, totSec))
                    cycleCount = cycleCount + 1
                    if cycleCount >= 5 then cycleCount = 0 saveState() end
                else
                    if btnPlayPauseRef then
                        local expectedText = isPlaying and "Pause" or "Play"
                        if tostring(btnPlayPauseRef.getText()) ~= expectedText then
                            btnPlayPauseRef.setText(expectedText)
                        end
                    end
                    txtTimeRef.setText("00:00 / 00:00")
                end
                handler.postDelayed(updateRunnable, 1000)
            else isUpdating = false end
        end
    })
    handler.post(updateRunnable)
end

-- 10. More Options Menu
showMoreOptions = function()
    local file = File(currentFilePath)
    local options = {"Delete", "Share", "Playback Speed"}
    local builder = AlertDialog.Builder(service)
    builder.setItems(options, function(dialog, which)
        if which == 0 then
            if file.isDirectory() then showToast("Cannot delete folders.") return end
            local confirm = AlertDialog.Builder(service)
            confirm.setTitle("Delete File?")
            confirm.setMessage("Are you sure you want to permanently delete this file?")
            confirm.setPositiveButton("Yes", function()
                player.reset() cancelNotification()
                _G.smart_player_is_prepared = false
                _G.smart_player_current_path = ""
                if file.delete() then
                    showToast("File deleted successfully.")
                    currentFilePath = "" lastPlayedPosition = 0 saveState()
                    if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end
                    renderMediaList(currentSavedFolder, currentSavedMediaType)
                else showToast("Failed to delete file.") end
            end)
            confirm.setNegativeButton("Cancel", nil)
            showDialogSafe(confirm, function() showMoreOptions() end)
        elseif which == 1 then
            saveState()
            local originalPackage = ""
            pcall(function()
                local root = service.getRootInActiveWindow()
                if root then originalPackage = tostring(root.getPackageName()) end
            end)
            if originalPackage == "" or originalPackage == "android" or originalPackage == "com.android.intentresolver" then
                originalPackage = "com.android.launcher3"
            end
            if dialog then dialog.dismiss() end
            if controlsDialog then controlsDialog.dismiss() controlsDialog = nil end

            pcall(function()
                local context = service
                local shareUri = nil
                pcall(function()
                    local resolver = context.getContentResolver()
                    local projection = {MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DATA}
                    local selection = MediaStore.MediaColumns.DATA .. "=?"
                    local selArgs = {currentFilePath}
                    local cursor = resolver.query(MediaStore.Files.getContentUri("external"), projection, selection, selArgs, nil)
                    if cursor and cursor.moveToFirst() then
                        local id = cursor.getLong(cursor.getColumnIndex(MediaStore.MediaColumns._ID))
                        shareUri = MediaStore.Files.getContentUri("external", id)
                        cursor.close()
                    end
                end)
                if not shareUri then
                    local policy = StrictMode.VmPolicy.Builder().build()
                    StrictMode.setVmPolicy(policy)
                    shareUri = Uri.fromFile(file)
                end
                local intent = Intent(Intent.ACTION_SEND)
                intent.setType("*/*")
                intent.putExtra(Intent.EXTRA_STREAM, shareUri)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                local chooser = Intent.createChooser(intent, "Share File")
                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(chooser)
            end)

            local monitorHandler = Handler(Looper.getMainLooper())
            local monitorRunnable
            local loopCount = 0
            
            monitorRunnable = Runnable({
                run = function()
                    loopCount = loopCount + 1
                    local currentPkg = ""
                    pcall(function()
                        local root = service.getRootInActiveWindow()
                        if root then currentPkg = tostring(root.getPackageName()) end
                    end)
                    local currentPkgLower = currentPkg:lower()
                    if currentPkg == originalPackage or currentPkgLower:find("launcher") or currentPkgLower:find("home") then
                        Handler(Looper.getMainLooper()).post(Runnable({
                            run = function() showPlayerControls() end
                        }))
                    elseif loopCount < 120 then
                        monitorHandler.postDelayed(monitorRunnable, 1000)
                    end
                end
            })
            monitorHandler.postDelayed(monitorRunnable, 1000)
        elseif which == 2 then
            showPlaybackSpeedMenu("more_options")
        end
    end)
    builder.setNegativeButton("Back", nil)
    showDialogSafe(builder, function() showPlayerControls() end)
end

----------------------------------------------------------------------
-- Boot Initialization Engine (Forced Fresh Preparation)
----------------------------------------------------------------------
loadState()
_G.smart_player_minimized = false

if currentFilePath and currentFilePath ~= "" and File(currentFilePath).exists() then
    -- Reload and extract exact file duration metadata instantly
    pcall(function()
        player.reset()
        player.setDataSource(currentFilePath)
        player.prepare()
        _G.smart_player_is_prepared = true
        _G.smart_player_current_path = currentFilePath
        
        if lastPlayedPosition > 0 then player.seekTo(lastPlayedPosition) end
        loudnessEnhancer = LoudnessEnhancer(player.getAudioSessionId())
        applyVolumeBoost(true)
        applyPlaybackSpeed()
    end)
    
    player.setOnCompletionListener(MediaPlayer.OnCompletionListener({
        onCompletion = function(mp)
            if autoPlay == "on" then
                if currentIndex < #currentPlaylist then
                    currentIndex = currentIndex + 1
                    lastPlayedPosition = 0
                    playMedia(currentPlaylist[currentIndex], true)
                else
                    cancelNotification()
                    if btnPlayPauseRef then btnPlayPauseRef.setText("Play") end
                end
            else
                cancelNotification()
                if btnPlayPauseRef then btnPlayPauseRef.setText("Play") end
            end
        end
    }))
    
    showPlayerControls()
    
    -- Sync Playlist in Background Thread
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            pcall(function()
                local rawFiles = {}
                if currentBrowseMode == "all_files" then
                    rawFiles = getAllRecursiveFiles(currentSavedFolder, currentSavedMediaType)
                else
                    local folderFile = File(currentSavedFolder)
                    local list = folderFile.listFiles()
                    if list then
                        for i = 0, #list - 1 do
                            local f = list[i]
                            local name = f.getName()
                            if not name:find("^%.") and not f.isDirectory() and matchesFormat(name, currentSavedMediaType) then
                                local time = 0
                                pcall(function() time = f.lastModified() end)
                                table.insert(rawFiles, {name = name, path = f.getAbsolutePath(), time = time})
                            end
                        end
                    end
                end
                
                if currentSortMethod == "A-Z" then
                    table.sort(rawFiles, function(a, b) return a.name:lower() < b.name:lower() end)
                elseif currentSortMethod == "Z-A" then
                    table.sort(rawFiles, function(a, b) return a.name:lower() > b.name:lower() end)
                elseif currentSortMethod == "Newest" then
                    table.sort(rawFiles, function(a, b) return (a.time or 0) > (b.time or 0) end)
                elseif currentSortMethod == "Oldest" then
                    table.sort(rawFiles, function(a, b) return (a.time or 0) < (b.time or 0) end)
                end

                currentPlaylist = {}
                for _, fObj in ipairs(rawFiles) do
                    table.insert(currentPlaylist, fObj.path)
                end

                for idx, path in ipairs(currentPlaylist) do
                    if path == currentFilePath then
                        currentIndex = idx
                        break
                    end
                end
            end)
        end
    }))
else
    showMainMenu()
end
