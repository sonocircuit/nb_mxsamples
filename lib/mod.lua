-- mx samples - nb edition v1.0 @sonoCircuit
-- infinite thanks @infinitedigits!

local fs = require 'fileselect'
local tx = require 'textentry'
local mu = require 'musicutil'
local md = require 'core/mods'
local vx = require 'voice'

local samples_dir = "/home/we/dust/audio/mx.samples/"
local preset_path = "/home/we/dust/data/nb_mxsamples/mxsamples_patches"
local current_preset = ""
local is_active = false

local NUM_VOICES = 12
local LOG2 = math.log10(2)

local mx = {}
mx.instruments = {}
mx.instrument = {}
mx.buffers_used = {}
mx.buffer = 0

mx.selected = ""
mx.transpose_midi = 0
mx.transpose_sample = 0
mx.tune_sample = 0
mx.velocity_sens = 2

local velcurve = {}
velcurve[1] = {1,4,7,10,13,16,19,22,25,28,31,34,38,41,43,46,49,52,55,57,60,62,64,66,68,70,71,73,74,76,77,79,80,81,83,84,85,86,87,89,90,91,92,93,94,95,95,96,97,98,99,99,100,101,102,102,103,104,104,105,105,106,106,107,107,108,108,109,109,109,110,110,111,111,111,112,112,112,112,113,113,113,114,114,114,114,115,115,115,115,115,116,116,116,116,116,117,117,117,117,118,118,118,118,118,119,119,119,120,120,120,120,121,121,121,122,122,122,123,123,124,124,124,125,125,126,126,127}
velcurve[2] = {0,2,3,4,6,7,8,10,11,13,14,15,17,18,19,21,22,23,25,26,27,29,30,31,33,34,35,37,38,39,40,42,43,44,45,47,48,49,50,52,53,54,55,57,58,59,60,61,62,64,65,66,67,68,69,70,71,72,73,75,76,77,78,79,80,81,82,83,83,84,85,86,87,88,89,90,91,92,92,93,94,95,96,97,97,98,99,100,100,101,102,103,103,104,105,106,106,107,108,109,109,110,111,111,112,113,113,114,115,115,116,117,117,118,119,119,120,120,121,122,122,123,124,124,125,126,126,127}
velcurve[3] = {1,1,1,1,1,2,2,2,2,2,2,3,3,3,3,3,4,4,4,4,5,5,5,5,6,6,6,6,7,7,7,8,8,8,9,9,9,10,10,11,11,12,12,13,13,14,14,15,15,16,16,17,18,18,19,20,20,21,22,23,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,42,43,44,45,47,48,49,51,52,54,55,57,58,60,62,63,65,66,68,70,72,73,75,77,79,80,82,84,86,88,90,92,94,95,97,99,101,103,105,107,109,111,113,115,117,119,121,123,125,127}
velcurve[4] = {}
for i = 1, 128 do
  table.insert(velcurve[4], 64)
end

local paramlist = {
  "amp", "pan", "send_a", "send_b",
  "instrument", "pitchbend", "trsp_midi", "trsp_smpl", "tune_smpl", "smpl_start",
  "velocity", "lpf_cutoff", "hpf_cutoff", "attack", "decay", "sustain", "release",
  "lpf_cutoff_mod", "hpf_cutoff_mod", "send_a_mod", "send_b_mod",
}


--------------------------- osc msgs ---------------------------

local function init_nb_mxsamples()
  osc.send({ "localhost", 57120 }, "/nb_mxsamples/init")
end

local function free_nb_mxsamples()
  osc.send({ "localhost", 57120 }, "/nb_mxsamples/free")
end

local function free_buffers()
  osc.send({ "localhost", 57120 }, "/nb_mxsamples/free_buffers")
end

local function load_samples(buf_num, path)
  osc.send({ "localhost", 57120 }, "/nb_mxsamples/load_sample", {buf_num, path})
end

local function free_sample(buf_num)
  osc.send({ "localhost", 57120 }, "/nb_mxsamples/clear_sample", {buf_num})
end

local function note_on(voice, buf_num, rate, vel)
  osc.send({ "localhost", 57120 }, "/nb_mxsamples/note_on", {voice, buf_num, rate, vel})
end

local function note_off(voice)
  osc.send({ "localhost", 57120 }, "/nb_mxsamples/note_off", {voice})
end

local function set_param(key, val)
  osc.send({ "localhost", 57120 }, "/nb_mxsamples/set_param", {key, val})
end

local function dont_panic()
  osc.send({ "localhost", 57120 }, "/nb_mxsamples/panic")
end


--------------------------- utils ---------------------------

local function round_form(param, quant, form)
  return(util.round(param, quant)..form)
end

local function pan_display(param)
  if param < -0.01 then
    return ("L < "..math.abs(util.round(param * 100, 1)))
  elseif param > 0.01 then
    return (math.abs(util.round(param * 100, 1)).." > R")
  else
    return "> <"
  end
end

local function format_freq(freq)
  if freq < 0.1 then
    freq = round_form(freq, 0.001, "Hz")
  elseif freq < 100 then
    freq = round_form(freq, 0.01, "Hz")
  elseif util.round(freq, 1) < 1000 then
    freq = round_form(freq, 1, "Hz")
  else
    freq = round_form(freq / 1000, 0.01, "kHz")
  end
  return freq
end

local function _list_files(d, files, recursive)
  -- list files in a flat table
  if d == "." or d == "./" then
    d = ""
  end
  if d ~= "" and string.sub(d, -1) ~= "/" then
    d = d.."/"
  end

  if recursive then
    local cmd = "ls -ad "..d.."*/ 2>/dev/null"
    local f = assert(io.popen(cmd, 'r'))
    local out = assert(f:read('*a'))
    f:close()
    for s in out:gmatch("%S+") do
      if not (string.match(s, "ls: ") or s == "../" or s == "./") then
        files = _list_files(s, files, recursive)
      end
    end
  end
  do
    local cmd = "ls -p "..d
    local f = assert(io.popen(cmd, 'r'))
    local out = assert(f:read('*a'))
    f:close()
    for s in out:gmatch("%S+") do
      table.insert(files, d..s)
    end
  end
  return files
end

local function list_files(d, recurisve)
  if recursive == nil then
    recursive = false
  end
  return _list_files(d, {}, recursive)
end

local function split_str(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr,"([^"..sep.."]+)") do
    table.insert(t, str)
  end
  return t
end

local function list_instruments()
  local names = {}
  for name, _ in pairs(mx.instrument) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

local function hzmidi(freq)
  return 12 * math.log10(freq / 440) / LOG2 + 69
end

local function midihz(note_num)
  return 13.75 * (2 ^ ((note_num - 9) / 12))
end


--------------------------- mx.funcs ---------------------------

local function mx_add_folder(sample_folder_path)
  local _, sample_folder, _ = string.match(sample_folder_path, "(.-)([^\\/]-%.?([^%.\\/]*))/$")
  -- make sure it doesn't exist
  if tab.contains(mx.instrument, sample_folder) then
    do return end
  else
    local name = sample_folder:gsub(" ","_")
    mx.instrument[name] = {}
  end
  -- add file data
  local files = list_files(sample_folder_path)
  for _, fname in ipairs(files) do
    if string.find(fname, ".wav") then
      local _, filename, _ = string.match(fname, "(.-)([^\\/]-%.?([^%.\\/]*))$")
      -- extract data from filename and add to pool
      local foo = split_str(filename, ".")
      local s = {
        name = sample_folder,
        filename = fname,
        midi = tonumber(foo[1]),
        dynamic = tonumber(foo[2]),
        dynamics = tonumber(foo[3]),
        variation = tonumber(foo[4]),
        is_release = foo[5] == "1" and true or false,
        buffer = -1
      }
      table.insert(mx.instrument[sample_folder], s)
    end
  end
end

function init_mx_instruments()
  if util.file_exists(samples_dir) then
    local sample_folders = list_files(samples_dir)
    for _, sample_folder_path in ipairs(sample_folders) do
      mx_add_folder(sample_folder_path)
    end
    mx.instruments = list_instruments()
  else
    mx.instruments = {"no instruments"}
  end
end

function mx_on(voice, name, note_num, velocity)
  local velocity = velocity or 0.8
  local dynamic = 1
  local rate = 1

  if mx.velocity_sens < 4 then
    velocity = util.linlin(0, 127, 0, 1, velcurve[mx.velocity_sens][math.floor(velocity * 128)])
  else
    velocity = 0.8
  end

  if mx.instrument[name][1].dynamics > 1 then
    dynamic = math.floor(util.linlin(0, 1, 1, mx.instrument[name][1].dynamics + 0.999, velocity))
  end

  -- transpose midi before finding sample
  note_num = note_num + mx.transpose_midi
  -- for z_tuning compatibility
  local note_num_z = hzmidi(mu.note_num_to_freq(note_num))

  -- find the sample that is closest to the midi with the specified dynamic
  local sample_closest = {buffer = -2, midi = -10000}
  local sample_closest_loaded = {buffer = -2, midi = -10000}

  -- make random voice index table...
  local rnd_idx = {}
  for i = 1, #mx.instrument[name] do
    local pos = math.random(1, #rnd_idx + 1)
    table.insert(rnd_idx, pos, i)
  end
  -- ... and go through the samples randomly
  for _, i in ipairs(rnd_idx) do
    local sample = mx.instrument[name][i]
    if dynamic == sample.dynamic and not sample.is_release then
      local note_diff = math.abs(sample.midi - note_num_z)
      if note_diff < math.abs(sample_closest.midi - note_num_z) then
        sample_closest = sample
        sample_closest.i = i
      end
      if note_diff < math.abs(sample_closest_loaded.midi - note_num_z) and sample.buffer > -1 then
        sample_closest_loaded = sample
      end
    end
  end

  -- play sample if loaded
  if sample_closest_loaded.buffer > -1 then
    local hz = mu.note_num_to_freq(note_num)
    local hz_transpose = (mu.note_num_to_freq(note_num + mx.transpose_sample) / hz)
    rate = hz / midihz(sample_closest_loaded.midi) * hz_transpose
    rate = rate * math.pow(2, mx.tune_sample / 1200)
    note_on(voice, sample_closest_loaded.buffer, rate, velocity)
  end

  -- load sample if not loaded
  if sample_closest.buffer == -1 then
    mx.instrument[name][sample_closest.i].buffer = mx.buffer
    mx.buffers_used[mx.buffer] = {name = name, i = sample_closest.i}
    load_samples(mx.buffer, sample_closest.filename)
    mx.buffer = mx.buffer + 1
    if mx.buffer > 79 then
      mx.buffer = 0
    end
    -- if this next buffer is being used, get it ready to be overridden
    if mx.buffers_used[mx.buffer] ~= nil then
      mx.instrument[mx.buffers_used[mx.buffer].name][mx.buffers_used[mx.buffer].i].buffer = -1
    end
  end
end


--------------------------- save and load ---------------------------

local function save_preset(txt)
  if txt then
    local patch = {}
    for _, v in pairs(paramlist) do
      if v == "instrument" then
        patch[v] = mx.selected
      else
        patch[v] = params:get("nb_mxsamples_"..v)
      end
    end
    clock.run(function()
      clock.sleep(0.4)
      tab.save(patch, preset_path.."/"..txt..".mxps")
      print("saved mxsamples: "..txt)
    end)
    current_preset = txt
  end
end

local function load_preset(path)
  if path ~= "cancel" and path ~= "" then
    dont_panic()
    if path:match("^.+(%..+)$") == ".mxps" then
      local patch = tab.load(path)
      if patch ~= nil then
        for k, v in pairs(patch) do
          if k == "instrument" then
            params:set("nb_mxsamples_"..k, tab.key(mx.instruments, v))
          else
            params:set("nb_mxsamples_"..k, v)
          end
        end
        local name = path:match("[^/]*$")
        current_preset = name:gsub(".mxps", "")
        print("loaded mxsamples: "..current_preset)
      else
        print("error: mxsamples patch not found", path)
      end
    else
      print("error: not a mxsamples patch file")
    end
  end
end


--------------------------- params ---------------------------

local function add_params()
  params:add_group("nb_mxsamples_group", "mxsamples", 31)
  params:hide("nb_mxsamples_group")

  params:add_separator("nb_mxsamples_presets", "presets")

  params:add_trigger("nb_mxsamples_load", ">> load")
  params:set_action("nb_mxsamples_load", function() fs.enter(preset_path, load_preset) end)

  params:add_trigger("nb_mxsamples_save", "<< save")
  params:set_action("nb_mxsamples_save", function() tx.enter(save_preset, current_preset) end)

  params:add_separator("nb_mxsamples_sound", "sound")
  params:add_option("nb_mxsamples_instrument", "instrument", mx.instruments, 1)
  params:set_action("nb_mxsamples_instrument", function(idx) mx.selected = mx.instruments[idx] end)

  params:add_separator("nb_mxsamples_levels", "levels")
  params:add_control("nb_mxsamples_amp", "amp", controlspec.new(0, 2, "lin", 0, 0.8), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_mxsamples_amp", function(val) set_param('amp', val) end)

  params:add_control("nb_mxsamples_pan", "pan", controlspec.new(-1, 1, "lin", 0, 0), function(param) return pan_display(param:get()) end)
  params:set_action("nb_mxsamples_pan", function(val) set_param('pan', val) end)

  params:add_control("nb_mxsamples_send_a", "send a", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_mxsamples_send_a", function(val) set_param('sendA', val) end)
  
  params:add_control("nb_mxsamples_send_b", "send b", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_mxsamples_send_b", function(val) set_param('sendB', val) end)

  params:add_option("nb_mxsamples_velocity", "velocity", {"delicate", "normal", "stiff", "fixed"}, 2)
  params:set_action("nb_mxsamples_velocity", function(val) mx.velocity_sens = val end)

  params:add_separator("nb_mxsamples_playback", "playback")
  params:add_number("nb_mxsamples_pitchbend", "pitchbend", 1, 24, 7, function(param) return param:get().."st" end)
  params:set_action("nb_mxsamples_pitchbend", function(val) set_param('bndAmt', val) end)

  params:add_number("nb_mxsamples_trsp_midi", "transpose root", -24, 24, 0, function(param) return param:get().."st" end)
  params:set_action("nb_mxsamples_trsp_midi", function(val) mx.transpose_midi = val end)

  params:add_number("nb_mxsamples_trsp_smpl", "transpose sample", -24, 24, 0, function(param) return param:get().."st" end)
  params:set_action("nb_mxsamples_trsp_smpl", function(val) mx.transpose_sample = val end)

  params:add_number("nb_mxsamples_tune_smpl", "tune sample", -100, 100, 0, function(param) return param:get().."ct" end)
  params:set_action("nb_mxsamples_tune_smpl", function(val) mx.tune_sample = val end)

  params:add_number("nb_mxsamples_smpl_start", "sample start", 0, 1000, 0, function(param) return param:get().."ms" end)
  params:set_action("nb_mxsamples_smpl_start", function(val) set_param('smpStart', val / 1000) end)

  params:add_separator("nb_mxsamples_filter", "filter")

  params:add_control("nb_mxsamples_lpf_cutoff", "lpf cutoff", controlspec.new(20, 20000, "exp", 0, 20000), function(param) return format_freq(param:get()) end)
  params:set_action("nb_mxsamples_lpf_cutoff", function(val) set_param("lpfHz", val) end)

  params:add_control("nb_mxsamples_hpf_cutoff", "hpf cutoff", controlspec.new(20, 8000, "exp", 0, 20), function(param) return format_freq(param:get()) end)
  params:set_action("nb_mxsamples_hpf_cutoff", function(val) set_param("hpfHz", val) end)

  params:add_separator("nb_mxsamples_env", "envelope")

  params:add_control("nb_mxsamples_attack", "attack", controlspec.new(0.001, 10, "exp", 0, 0.001), function(param) return (round_form(param:get(), 0.01, "s")) end)
  params:set_action("nb_mxsamples_attack", function(val) set_param('attack', val) end)

  params:add_control("nb_mxsamples_decay", "decay", controlspec.new(0.01, 10, "exp", 0, 1.2), function(param) return (round_form(param:get(), 0.01, "s")) end)
  params:set_action("nb_mxsamples_decay", function(val) set_param('decay', val) end)

  params:add_control("nb_mxsamples_sustain", "sustain", controlspec.new(0, 1, "lin", 0, 0.8), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_mxsamples_sustain", function(val) set_param('sustain', val) end)

  params:add_control("nb_mxsamples_release", "release", controlspec.new(0.01, 10, "exp", 0, 2.2), function(param) return (round_form(param:get(), 0.01, "s")) end)
  params:set_action("nb_mxsamples_release", function(val) set_param('release', val) end)

  params:add_separator("nb_mxsamples_modmods", "modulation")

  params:add_control("nb_mxsamples_mod_amt", "mod amt [map me]", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_mxsamples_mod_amt", function(val) set_param('modDepth', val) end)
  params:set_save("nb_mxsamples_mod_amt", false)

  params:add_control("nb_mxsamples_lpf_cutoff_mod", "lpf cutoff", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_mxsamples_lpf_cutoff_mod", function(val) set_param('lpfHzMod', val) end)
  
  params:add_control("nb_mxsamples_hpf_cutoff_mod", "hpf cutoff", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_mxsamples_hpf_cutoff_mod", function(val) set_param('hpfHzMod', val) end)

  params:add_control("nb_mxsamples_send_a_mod", "send a", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_mxsamples_send_a_mod", function(val) set_param('sendAMod', val) end)
  
  params:add_control("nb_mxsamples_send_b_mod", "send b", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_mxsamples_send_b_mod", function(val) set_param('sendBMod', val) end)

  for _, prm in ipairs(paramlist) do
    local p = params:lookup_param("nb_mxsamples_"..prm)
    p:bang()
  end
end


--------------------------- nb player ---------------------------

function add_nb_mxsamples_player()
  local player = {
    alloc = vx.new(NUM_VOICES, 2),
    slot = {},
    clk = nil
  }

  function player:describe()
    return {
      name = "nb_mxsamples",
      supports_bend = true,
      supports_slew = false
    }
  end
  
  function player:active()
    if self.name ~= nil then
      if self.clk ~= nil then
        clock.cancel(self.clk)
      end
      self.clk = clock.run(function()
        clock.sleep(0.2)
        if not is_active then
          is_active = true
          params:show("nb_mxsamples_group")
          if md.is_loaded("fx") == false then
            params:hide("nb_mxsamples_send_a")
            params:hide("nb_mxsamples_send_b")
            params:hide("nb_mxsamples_send_a_mod")
            params:hide("nb_mxsamples_send_b_mod")
          end
          _menu.rebuild_params()
        end
      end)
    end
  end

  function player:inactive()
    if self.name ~= nil then
      if self.clk ~= nil then
        clock.cancel(self.clk)
      end
      self.clk = clock.run(function()
        clock.sleep(0.2)
        if is_active then
          is_active = false
          dont_panic()
          free_buffers()
          params:hide("nb_mxsamples_group")
          _menu.rebuild_params()
        end
      end)
    end
  end

  function player:stop_all()
    dont_panic()
  end

  function player:modulate(val)
    params:set("nb_mxsamples_mod_amt", val)
  end

  function player:set_slew(s)
  end

  function player:pitch_bend(note, val)
    set_param('bndDepth', val)
  end

  function player:modulate_note(note, key, value)
  end

  function player:note_on(note, vel)
    local slot = self.slot[note]
    if slot == nil then
      slot = self.alloc:get()
    end
    local voice = slot.id - 1 -- sc is zero indexed!
    local name = mx.selected:gsub(" ","_")
    slot.on_release = function()
      note_off(voice)
    end
    self.slot[note] = slot
    mx_on(voice, name, note, vel)
  end

  function player:note_off(note)
    local slot = self.slot[note]
    if slot ~= nil then
      self.alloc:release(slot)
    end
    self.slot[note] = nil
  end

  function player:add_params()
    add_params()
  end

  if note_players == nil then
    note_players = {}
  end

  note_players["mxsamples"] = player
end


--------------------------- mod zone ---------------------------

local function post_system()
  if util.file_exists(preset_path) == false then
    util.make_dir(preset_path)
  end
end

local function pre_init()
  init_nb_mxsamples()
  init_mx_instruments()
  add_nb_mxsamples_player()
end

local function post_cleanup()
  free_buffers()
end

md.hook.register("system_post_startup", "nb mxsamples post startup", post_system)
md.hook.register("script_pre_init", "nb mxsamples pre init", pre_init)
md.hook.register("script_post_cleanup", "nb mxsamples cleanup", post_cleanup)
