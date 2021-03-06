#!/usr/bin/env coffee

# http://nodejs.org/api/child_process.html#child_process_child_process_spawn_command_args_options
child_process = require 'child_process'
fs = require 'fs'

# https://github.com/caolan/async/
async = require 'async'

argv = require('optimist').posix()
  .boolean('p', 't', 'x').string('E').argv

n = Infinity
if +argv.n
  n = 0|argv.n
s = 0|argv.s
if argv.p
  argv.t = true
utility = 'echo'
if argv._.length >= 1
  utility = argv._[0]
utility_args = argv._[1..]

if /utility/.test process.env.XARGS_DEBUG
  console.warn "utility", utility, utility_args

if argv.E == ''
  argv.E = null

byte_length = (a) ->
  # :todo: doesn't yet work for non-ASCII strings.
  a.length + 1

utility_byte_length = 0
for a in [utility].concat utility_args
  utility_byte_length += byte_length a
arg_list = []
# Length in bytes of arg_list (when each item is treated as
# a NUL-terminated utf-8 string).
arg_byte_length = utility_byte_length
arg1 = (arg, cb) ->
  # Unquote the arg.
  arg = arg.replace /'[^']*'|"[^"]*"|\\(?:.|\n)|[^ \n\\'"]/g, (x) ->
    if /^['"]/.test x
      return x[1..-2]
    if x[0] == '\\'
      return x[1]
    return x
  if arg == argv.E
    if arg_list.length
      return invoke () -> cb 'eof'
    else
      return setTimeout () -> cb 'eof', 0
  blen = byte_length arg
  if s and arg_byte_length + blen >= s
    if argv.x
      console.warn "Cannot meet -n and -s constraints"
      process.exit 24
    invoke cb
  arg_list.push arg
  arg_byte_length += blen
  if arg_list.length >= n
    return invoke cb
  else
    return setTimeout cb, 0
invoke = (cb) ->
  if arg_list.length == 0
    return setTimeout cb, 0
  args = utility_args.concat(arg_list)
  if argv.t
    trace = [utility].concat(args).join ' '
    if argv.p
      trace += '?...'
    console.warn trace
  # Prompt if necessary.
  if not argv.p
    return goChild cb
  tty = fs.createReadStream '/dev/tty'
  decided = false
  tty.on 'data', (data) ->
    decided = true
    tty.close()
    if /^y/i.test data
      # Affirmitive response
      return goChild cb
    else
      arg_list = []
      arg_byte_length = utility_byte_length
      return cb()
  tty.on 'end', () ->
    if not decided
      cb()

EXIT_STATUS = 0
goChild = (cb) ->
  args = utility_args.concat(arg_list)
  stdio = [ 'ignore', 1, 2]
  child = child_process.spawn utility, args, stdio: stdio
  arg_list = []
  arg_byte_length = utility_byte_length
  child.on 'error', (err) ->
    cb()
  child.on 'exit', (code, signal) ->
    if /exit/.test process.env.XARGS_DEBUG
      console.warn "Utility #{utility} exited with code #{code}"
    if code == 255
      console.warn "Utility #{utility} exited with code #{code}"
      process.exit 55
    EXIT_STATUS = Math.max EXIT_STATUS, code
    cb()

# Slightly complicated state handling to deal with case
# when we get the stdin 'end' event while we are in
# a 'data' event.
readingData = false
ended = false

# Input buffer.
input = ''
process.stdin.on 'data', (data) ->
  readingData = true
  input += data
  re = /[ \n]*((?:'[^']*'|"[^"]*"|\\(?:.|\n)|[^ \n\\'"])+)[ \n]+/gm
  args = []
  # When loop is finished, remove initial *trim* characters of *input*.
  trim = 0
  while true
    group = re.exec input
    if not group
      break
    args.push group[1]
    trim = re.lastIndex
  if trim
    input = input[trim..]
  process.stdin.pause()
  async.eachSeries args, arg1, ->
    readingData = false
    process.stdin.resume()
    if ended
      # got stdin 'end' while we were in the async call
      invoke EXIT

process.stdin.on 'end', ->
  if readingData
    ended = true
  else
    invoke EXIT

EXIT = -> process.exit EXIT_STATUS

# Could compute these values once at install time.
LINE_MAX = ''
ARG_MAX = ''
child = child_process.spawn 'getconf', ['LINE_MAX']
child.stdout.on 'data', (data) ->
  LINE_MAX += data
child.on 'exit', () ->
  LINE_MAX = Number(LINE_MAX)
  if isNaN LINE_MAX
    LINE_MAX = 2048
  child = child_process.spawn 'getconf', ['ARG_MAX']
  child.stdout.on 'data', (data) ->
    ARG_MAX += data
  child.on 'exit', () ->
    ARG_MAX = Number(ARG_MAX)
    if isNaN ARG_MAX
      ARG_MAX = 2e6
  process.stdin.resume()
