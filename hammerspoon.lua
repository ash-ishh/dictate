-- Dictate Hammerspoon integration.
-- Install with: dofile("/path/to/dictate/hammerspoon.lua")
-- Hotkey: Cmd+S. Menu button: custom Dictate icon / REC.

local menubar = hs.menubar.new()
local isRecording = false
local ffmpegTask = nil
local targetApp = nil
local recordingAlert = nil
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
local toggleRecording
local chooseModel

local function loadIcon(fileName, template)
  local image = hs.image.imageFromPath(projectDir .. "/assets/" .. fileName)
  if image and template then image:setTemplate(true) end
  return image
end

local idleIcon = loadIcon("dictate-idle.png", true)
local recordingIcon = loadIcon("dictate-recording.png", false)

local function setIdleStatus()
  if idleIcon then
    menubar:setIcon(idleIcon)
    menubar:setTitle("")
  else
    menubar:setTitle("Dictate")
  end
end

local function setRecordingStatus()
  if recordingIcon then menubar:setIcon(recordingIcon) end
  menubar:setTitle("REC")
end

local function setTranscribingStatus()
  if idleIcon then menubar:setIcon(idleIcon) end
  menubar:setTitle("…")
end

local function notify(title, text)
  hs.notify.new({ title = title, informativeText = text }):send()
end

local function showRecordingIndicator()
  if recordingAlert then hs.alert.closeSpecific(recordingAlert) end
  recordingAlert = hs.alert.show(
    "🔴 Dictate recording — press Cmd+S to stop",
    {
      textSize = 22,
      radius = 12,
      fillColor = { red = 0.75, green = 0.05, blue = 0.05, alpha = 0.90 },
      textColor = { white = 1, alpha = 1 },
      strokeColor = { white = 1, alpha = 0.25 },
      strokeWidth = 2,
    },
    hs.screen.mainScreen(),
    999999
  )
end

local function hideRecordingIndicator()
  if recordingAlert then
    hs.alert.closeSpecific(recordingAlert)
    recordingAlert = nil
  end
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
    { title = "Start/stop recording", fn = toggleRecording },
    { title = "Choose model", fn = chooseModel },
    { title = "Current model: " .. selectedModel, disabled = true },
  }

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
    notify("Dictate", "Transcript was empty")
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
  notify("Dictate", "Transcribing with " .. selectedModel .. "...")

  local command = string.format([[cd "%s" && "%s" run --python 3.12 dictate transcribe "%s" --model "%s" --output-json "%s" --output-text "%s"]],
    projectDir, uvPath, audioFile, selectedModel, jsonFile, txtFile)

  hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
    setIdleStatus()
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

chooseModel = function()
  local choices = {
    {text = "ifw_mlx_tiny", subText = "Fastest first test"},
    {text = "ifw_mlx_large_v3", subText = "More accurate Whisper Large v3"},
    {text = "ifw_mlx_parakeet", subText = "Parakeet MLX"},
  }
  local chooser = hs.chooser.new(function(choice)
    if choice then
      selectedModel = choice.text
      notify("Dictate", "Selected " .. selectedModel)
    end
  end)
  chooser:choices(choices)
  chooser:show()
end

setIdleStatus()
menubar:setTooltip("Dictate")
rebuildMenu()
menubar:setClickCallback(toggleRecording)

hs.hotkey.bind({"cmd"}, "S", toggleRecording)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "M", chooseModel)
