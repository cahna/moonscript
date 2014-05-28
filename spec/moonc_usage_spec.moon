
lfs = require "lfs"

import insert, pack, concat from table

moonc_exec = loadfile "bin/moonc"

TEST_ROOT = "./spec"
INPUTS = TEST_ROOT.."/inputs"
OUTPUTS = TEST_ROOT.."/outputs"

file_exists = (fname) ->
  _, handle, err = pcall io.open, fname, "r"

  if (handle != nil) and (type(handle) == "userdata")
    handle\close!
    return err == nil

  false

clean_file = (fname) ->
  os.remove(fname) if file_exists fname

clean_dir = (dirname) ->
  mode, err = lfs.attributes dirname, "mode"

  if (not err) and mode == "directory"
    success, err = lfs.rmdir dirname
    assert.is_true success

-- Emulate `moonc` usage (as if it were being run from a shell)
moonc = (...) ->
  arg_list = {
    [-1]: _G.arg[-1]
    [0]: "./bin/moonc"
  }

  for i,item in ipairs pack(...)
    arg_list[i] = item

  captured = out: {}, err: {}
  normal_print = print
  spy_print = (msg) ->
    insert captured.out, msg

  -- Spy on moonc's IO handles && process control
  sandbox = {
    arg: arg_list
    os: setmetatable {
      exit: (code) -> true if code == 0 else error code
    }, __index: os
    io: setmetatable {
      stderr: write: (msg) => insert captured.err, msg
      stdout: write: (msg) => insert captured.out, msg
    }, __index: io
    print: (msg) -> insert captured.out, msg
  }

  -- This actually creates the sandboxed scope
  setfenv moonc_exec, setmetatable sandbox, __index: _G

  unless moonc_exec and type(moonc_exec) == "function"
    error "syntax error"

  -- print() appears immune to the sandbox. use the force.
  _G.print = spy_print

  err_handler = (e) ->
    debug.traceback e

  success, message = xpcall moonc_exec, err_handler

  -- Revert print() injection
  _G.print = normal_print

  -- Success is the return status of xpall, not (necessarily) the bin/moonc return status
  success, message, captured

describe "bin/moonc integration tests", ->
  describe "given no input file", ->
    it "errors and displays usage", ->
      success, message, captured = moonc nil
      assert.is_false success

      err_output = concat captured.err, ''
      assert.is_truthy err_output\match "^Error: No files specified.+Usage"

    describe "with '-v' flag", ->
      it "displays the version and exists", ->
        success, message, captured = moonc "-v"
        assert.is_false success
        assert.are_equal "MoonScript version 0.2.5", concat(captured.out, '')

  describe "given a valid .moon input file", ->
    describe "with no options given", ->
      local success, message, captured, in_file, out_file

      in_file  = INPUTS.."/class.moon"
      out_file = INPUTS.."/class.lua"

      it "can read the given file", ->
        assert.is_true file_exists in_file

      it "compiles a corresponding .lua output file", ->
        success, message, captured = moonc in_file
        assert.is_true success

      it "displays expected output", ->
        err_output = concat captured.err, ''
        assert.is_true 1 < err_output\len!
        assert.is_truthy err_output\match "^Built ./#{in_file}.$"

      it "generates the expected file", ->
        assert.is_true file_exists out_file
        finally -> clean_file out_file

    describe "with '-p'", ->
      pending "writes compiled lua to stdout instead of to a file"

    describe "with '-o file'", ->
      local success, message, captured, in_file, out_file

      in_file  = INPUTS.."/class.moon"
      out_file = OUTPUTS.."/class.manualname.lua"

      it "successfully compiles the file", ->
        success, message, captured = moonc "-o", out_file, in_file
        assert.is_true success
        assert.is_truthy concat(captured.err, '')\match "^Built ./#{in_file}.$"

      it "writes the compiled file to the '-o file' location", ->
        assert.is_true file_exists out_file
        finally -> clean_file out_file

    describe "with '-t path'", ->
      local success, message, captured, in_file, out_file

      in_file  = INPUTS.."/class.moon"
      out_file = OUTPUTS.."/class.lua"

      it "can read the given file", ->
        assert.is_true file_exists in_file

      it "successfully compiles the file", ->
        success, message, captured = moonc "-t", OUTPUTS, in_file
        assert.is_true success
        assert.is_truthy concat(captured.err, '')\match "^Built ./#{in_file}.$"

      -- TODO: Currently, `moonc -t spec/outputs spec/inputs/class.moon`
      -- will compile to spec/outputs/spec/inputs/class.lua
      pending "writes the file to the given output path", ->
        assert.is_true file_exists out_file
        finally -> clean_file out_file

      -- For the sake of more-complete testing, here's the current expected behavior:
      it "writes the file to #{OUTPUTS}/#{INPUTS}/class.lua", ->
        assert.is_true file_exists "#{OUTPUTS}/#{INPUTS}/class.lua"
        finally ->
          clean_file "#{OUTPUTS}/#{INPUTS}/class.lua"
          clean_dir OUTPUTS.."/spec/inputs/"
          clean_dir OUTPUTS.."/spec/"

  describe "given a non-existant input file", ->
    local success, message, captured, in_file, out_file

    in_file  = INPUTS.."/dummy.moon"
    out_file = INPUTS.."/dummy.lua"

    it "can't read the given file", ->
      assert.is_false file_exists in_file

    it "errors attempting to compile", ->
      success, message, captured = moonc in_file
      assert.are_equal "table", type(captured)

    it "displays expected output", ->
      err_output = concat captured.err
      assert.is_true 1 < err_output\len!
      assert.is_falsy err_output\match "^Built #{out_file}.$"

    it "does not generate an output file", ->
      assert.is_false file_exists out_file

  describe "given wildcard filepath", ->
    pending "compiles all files matching the pattern"

  describe "given a directory path", ->
    pending "with '-w' argument"

