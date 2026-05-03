-- Dictate Hammerspoon building block
-- Install this by copying or requiring it from ~/.hammerspoon/init.lua.
-- Hotkey: Cmd+Alt+Ctrl+Space. Menu button: 🎙 / 🔴.

local menubar = hs.menubar.new()
local isRecording = false
local ffmpegTask = nil
local targetApp = nil

local projectDir = "/Users/ashish/Projects/MLX/whisper-exploration/dictate"
local audioFile = "/tmp/dictate.m4a"
local jsonFile = "/tmp/dictate.json"
local txtFile = "/tmp/dictate.txt"
local logFile = "/tmp/dictate.log"

-- Change after running: ffmpeg -f avfoundation -list_devices true -i ""
local micDevice = ":0"

local ffmpegPath = "/opt/homebrew/bin/ffmpeg"
local uvPath = "/Users/ashish/.local/bin/uv"
local selectedModel = "ifw_mlx_tiny"

local function notify(title, text)
  hs.notify.new({ title = title, informativeText = text }):send()
end

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*all")
  f:close()
  return text
end

local function pasteText(text)
  text = string.gsub(text or "", "^%s+", "")
  text = string.gsub(text, "%s+$", "")
  if text == "" then
    notify("Whisper", "Transcript was empty")
    return
  end

  hs.pasteboard.setContents(text)
  if targetApp then targetApp:activate() end
  hs.timer.doAfter(0.2, function()
    hs.eventtap.keyStroke({"cmd"}, "v")
  end)
  notify("Whisper", "Transcript pasted")
end

local function transcribeAndPaste()
  menubar:setTitle("⏳")
  notify("Whisper", "Transcribing with " .. selectedModel .. "...")

  local command = string.format([[cd "%s" && "%s" run --python 3.12 dictate transcribe "%s" --model "%s" --output-json "%s" --output-text "%s"]],
    projectDir, uvPath, audioFile, selectedModel, jsonFile, txtFile)

  hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
    menubar:setTitle("🎙")
    if exitCode == 0 then
      pasteText(readFile(txtFile) or stdOut)
    else
      local err = stdErr or stdOut or "transcription failed"
      notify("Whisper error", string.sub(err, 1, 500))
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
  menubar:setTitle("🔴")
  notify("Whisper", "Recording started")
end

local function stopRecording()
  if ffmpegTask then
    ffmpegTask:terminate()
    ffmpegTask = nil
  end
  isRecording = false
  menubar:setTitle("⏳")
  notify("Whisper", "Recording stopped")
  hs.timer.doAfter(0.7, transcribeAndPaste)
end

local function toggleRecording()
  if isRecording then stopRecording() else startRecording() end
end

local function chooseModel()
  local choices = {
    {text = "ifw_mlx_tiny", subText = "Fastest first test"},
    {text = "ifw_mlx_large_v3", subText = "More accurate Whisper Large v3"},
    {text = "ifw_mlx_parakeet", subText = "Parakeet MLX"},
  }
  local chooser = hs.chooser.new(function(choice)
    if choice then
      selectedModel = choice.text
      notify("Whisper", "Selected " .. selectedModel)
    end
  end)
  chooser:choices(choices)
  chooser:show()
end

menubar:setTitle("🎙")
menubar:setTooltip("Dictate")
menubar:setMenu({
  { title = "Start/stop recording", fn = toggleRecording },
  { title = "Choose model", fn = chooseModel },
  { title = "Current model: " .. selectedModel, disabled = true },
})
menubar:setClickCallback(toggleRecording)

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "space", toggleRecording)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "M", chooseModel)
