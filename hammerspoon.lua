-- Dictate Hammerspoon integration.
-- Install with: dofile("/path/to/dictate/hammerspoon.lua")
-- Hotkey: Cmd+S. Menu button: custom Dictate icon / REC.

local menubar = hs.menubar.new()
_G.dictateMenubar = menubar
local isRecording = false
local ffmpegTask = nil
local targetApp = nil
local recordingAlert = nil
local statusCanvas = nil
local transcriptHistory = {}
local maxHistoryItems = 5

local source = debug.getinfo(1, "S").source
local projectDir = source:sub(1, 1) == "@" and source:sub(2):match("(.+)/[^/]+$") or "/Users/ashish/Projects/MLX/whisper-exploration/dictate"
local audioFile = "/tmp/dictate.m4a"
local jsonFile = "/tmp/dictate.json"
local txtFile = "/tmp/dictate.txt"
local logFile = "/tmp/dictate.log"

-- Change after running: ffmpeg -f avfoundation -list_devices true -i ""
local micDevice = ":0"

local function firstExistingPath(paths)
  for _, path in ipairs(paths) do
    if path and hs.fs.attributes(path) then return path end
  end
  return paths[1]
end

local home = os.getenv("HOME") or ""
local ffmpegPath = firstExistingPath({"/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"})
local uvPath = firstExistingPath({home .. "/.local/bin/uv", "/opt/homebrew/bin/uv", "/usr/local/bin/uv"})
local selectedModel = "ifw_mlx_tiny"
local modelOptions = {
  { key = "ifw_mlx_tiny", label = "Tiny", detail = "fastest" },
  { key = "ifw_mlx_large_v3", label = "Large v3", detail = "best accuracy" },
  { key = "ifw_mlx_turbo", label = "Turbo", detail = "fast large" },
  { key = "ifw_mlx_parakeet", label = "Parakeet", detail = "experimental" },
}
local toggleRecording
local chooseModel
local selectModel

local idleIconPath = projectDir .. "/assets/dictate-idle.png"
local recordingIconPath = projectDir .. "/assets/dictate-recording.png"

local function setIdleStatus()
  if hs.fs.attributes(idleIconPath) then
    menubar:setIcon(idleIconPath, true)
    menubar:setTitle("")
  else
    menubar:setTitle("◉")
  end
end

local function setRecordingStatus()
  if hs.fs.attributes(recordingIconPath) then menubar:setIcon(recordingIconPath, false) end
  menubar:setTitle("")
end

local function setTranscribingStatus()
  if hs.fs.attributes(idleIconPath) then menubar:setIcon(idleIconPath, true) end
  -- Keep an explicit processing indicator; it is easier to notice than icon-only.
  menubar:setTitle("…")
end

local function notify(title, text)
  hs.notify.new({ title = title, informativeText = text }):send()
end

local function hideStatusBanner()
  if recordingAlert then
    hs.alert.closeSpecific(recordingAlert)
    recordingAlert = nil
  end
  if statusCanvas then
    statusCanvas:delete()
    statusCanvas = nil
  end
end

local function showStatusBanner(text, mode, duration)
  hideStatusBanner()

  local screenFrame = hs.screen.mainScreen():frame()
  local width = 300
  local height = 42
  local frame = {
    x = screenFrame.x + (screenFrame.w - width) / 2,
    y = screenFrame.y + 56,
    w = width,
    h = height,
  }
  local fill = mode == "recording"
    and { red = 1.0, green = 0.23, blue = 0.19, alpha = 0.96 }
    or { red = 0.12, green = 0.12, blue = 0.13, alpha = 0.88 }

  statusCanvas = hs.canvas.new(frame)
  statusCanvas:level(hs.canvas.windowLevels.overlay)
  statusCanvas:behavior({ "canJoinAllSpaces", "transient", "ignoresCycle" })
  statusCanvas:appendElements(
    {
      type = "rectangle",
      action = "fill",
      roundedRectRadii = { xRadius = 12, yRadius = 12 },
      fillColor = fill,
    },
    {
      type = "text",
      text = text,
      textSize = 15,
      textAlignment = "center",
      textColor = { white = 1, alpha = 1 },
      frame = { x = 12, y = 10, w = width - 24, h = 22 },
    }
  )
  statusCanvas:show()

  if duration then
    hs.timer.doAfter(duration, hideStatusBanner)
  end
end

local function showRecordingIndicator()
  showStatusBanner("Recording — Cmd+S to stop", "recording")
end

local function hideRecordingIndicator()
  hideStatusBanner()
end

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*all")
  f:close()
  return text
end

local function shortText(text, maxLen)
  text = string.gsub(text or "", "%s+", " ")
  if string.len(text) <= maxLen then return text end
  return string.sub(text, 1, maxLen - 1) .. "…"
end

local function rebuildMenu()
  local menu = {
    { title = "Record / Stop", fn = toggleRecording },
    { title = "-" },
    { title = "Model", disabled = true },
  }

  for _, model in ipairs(modelOptions) do
    local active = model.key == selectedModel
    table.insert(menu, {
      title = (active and "✓ " or "   ") .. model.label .. " — " .. model.detail,
      fn = function() selectModel(model.key) end,
    })
  end

  table.insert(menu, { title = "-" })
  table.insert(menu, {
    title = "Play last recording",
    fn = function()
      if hs.fs.attributes(audioFile) then
        hs.execute("open " .. string.format("%q", audioFile))
      else
        notify("Dictate", "No recording found")
      end
    end,
  })
  if #transcriptHistory > 0 then
    table.insert(menu, { title = "-" })
    table.insert(menu, { title = "Recent transcripts", disabled = true })
    for i, item in ipairs(transcriptHistory) do
      table.insert(menu, {
        title = i .. ". " .. shortText(item.text, 70),
        fn = function()
          hs.pasteboard.setContents(item.text)
          notify("Dictate", "Transcript copied")
        end,
      })
    end
    table.insert(menu, {
      title = "Clear transcript history",
      fn = function()
        transcriptHistory = {}
        rebuildMenu()
      end,
    })
  end

  menubar:setMenu(menu)
end

local function addTranscriptToHistory(text)
  text = string.gsub(text or "", "^%s+", "")
  text = string.gsub(text, "%s+$", "")
  if text == "" then return end

  table.insert(transcriptHistory, 1, {
    text = text,
    time = os.date("%H:%M:%S"),
  })
  while #transcriptHistory > maxHistoryItems do
    table.remove(transcriptHistory)
  end
  rebuildMenu()
end

local function pasteText(text)
  text = string.gsub(text or "", "^%s+", "")
  text = string.gsub(text, "%s+$", "")
  if text == "" then
    notify("Dictate", "Transcript was empty. Use menu → Play last recording to check audio.")
    return
  end

  addTranscriptToHistory(text)
  hs.pasteboard.setContents(text)
  if targetApp then targetApp:activate() end
  hs.timer.doAfter(0.2, function()
    hs.eventtap.keyStroke({"cmd"}, "v")
  end)
  notify("Dictate", "Transcript pasted")
end

local function transcribeAndPaste()
  setTranscribingStatus()
  local modelForRun = selectedModel
  showStatusBanner("Transcribing with " .. modelLabel(modelForRun), "info")
  notify("Dictate", "Transcribing with " .. modelForRun .. "...")

  local command = string.format([[cd "%s" && "%s" run --python 3.12 dictate transcribe "%s" --model "%s" --output-json "%s" --output-text "%s"]],
    projectDir, uvPath, audioFile, modelForRun, jsonFile, txtFile)

  hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
    setIdleStatus()
    hideStatusBanner()
    if exitCode == 0 then
      pasteText(readFile(txtFile) or stdOut)
    else
      local err = stdErr or stdOut or "transcription failed"
      notify("Dictate error", string.sub(err, 1, 500))
      local f = io.open(logFile, "w")
      if f then
        f:write("STDOUT:\n" .. (stdOut or "") .. "\nSTDERR:\n" .. (stdErr or ""))
        f:close()
      end
    end
  end, {"-lc", command}):start()
end

local function startRecording()
  targetApp = hs.application.frontmostApplication()
  os.remove(audioFile)
  os.remove(jsonFile)
  os.remove(txtFile)
  os.remove(logFile)

  ffmpegTask = hs.task.new(ffmpegPath, nil, {
    "-f", "avfoundation",
    "-i", micDevice,
    "-ac", "1",
    "-ar", "16000",
    "-y", audioFile,
  })
  ffmpegTask:start()

  isRecording = true
  setRecordingStatus()
  showRecordingIndicator()
  notify("Dictate", "Recording started")
end

local function stopRecording()
  if ffmpegTask then
    ffmpegTask:terminate()
    ffmpegTask = nil
  end
  isRecording = false
  setTranscribingStatus()
  hideRecordingIndicator()
  notify("Dictate", "Recording stopped")
  hs.timer.doAfter(0.7, transcribeAndPaste)
end

toggleRecording = function()
  if isRecording then stopRecording() else startRecording() end
end

local function modelLabel(key)
  for _, model in ipairs(modelOptions) do
    if model.key == key then return model.label end
  end
  return key
end

selectModel = function(key)
  selectedModel = key
  rebuildMenu()
  showStatusBanner("Model: " .. modelLabel(key), "info", 0.9)
end

chooseModel = function()
  local choices = {}
  for _, model in ipairs(modelOptions) do
    local active = model.key == selectedModel
    table.insert(choices, {
      text = (active and "✓ " or "") .. model.label,
      subText = model.detail,
      modelKey = model.key,
    })
  end

  local chooser = hs.chooser.new(function(choice)
    if choice then selectModel(choice.modelKey) end
  end)
  chooser:placeholderText("Select Dictate model")
  chooser:searchSubText(true)
  chooser:rows(#choices)
  chooser:choices(choices)
  chooser:show()
end

setIdleStatus()
menubar:setTooltip("Dictate")
rebuildMenu()
menubar:setClickCallback(toggleRecording)

hs.hotkey.bind({"cmd"}, "S", toggleRecording)
-- Also bind Ctrl+S for testing/backup because Cmd+S can conflict with app Save shortcuts.
hs.hotkey.bind({"ctrl"}, "S", toggleRecording)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "M", chooseModel)

-- Uncomment while debugging config loading:
-- notify("Dictate", "Loaded. Press Cmd+S or Ctrl+S to record.")
-- hs.alert.show("Dictate loaded: Cmd+S or Ctrl+S")
