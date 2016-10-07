ChildProcess = require 'child_process'
fs = require 'fs-plus'
path = require 'path'
os = require 'os'

appFolder = path.resolve(process.execPath, '..')
rootN1Folder = path.resolve(appFolder, '..')
updateDotExe = path.join(rootN1Folder, 'Update.exe')
exeName = path.basename(process.execPath)

# Spawn a command and invoke the callback when it completes with an error
# and the output from standard out.
spawn = (command, args, callback) ->
  stdout = ''

  try
    spawnedProcess = ChildProcess.spawn(command, args)
  catch error
    # Spawn can throw an error
    process.nextTick -> callback?(error, stdout)
    return

  spawnedProcess.stdout.on 'data', (data) -> stdout += data

  error = null
  spawnedProcess.on 'error', (processError) -> error ?= processError
  spawnedProcess.on 'close', (code, signal) ->
    error ?= new Error("Command failed: #{signal ? code}") if code isnt 0
    error?.code ?= code
    error?.stdout ?= stdout
    callback?(error, stdout)

# Spawn the Update.exe with the given arguments and invoke the callback when
# the command completes.
spawnUpdate = (args, callback) ->
  spawn(updateDotExe, args, callback)

# Create a desktop and start menu shortcut by using the command line API
# provided by Squirrel's Update.exe
createShortcuts = (callback) ->
  spawnUpdate(['--createShortcut', exeName], callback)

createRegistryEntries = (callback) ->
  escapeBackticks = (str) => str.replace(/\\/g, '\\')

  if process.env.SystemRoot
    regPath = path.join(process.env.SystemRoot, 'System32', 'reg.exe')
  else
    regPath = 'reg.exe'

  fs.readFile path.join(appFolder, 'resources', 'nylas-mailto.reg'), (err, data) =>
    return callback(err) if err or not data
    importTemplate = data.toString()
    console.log(importTemplate)
    importContents = importTemplate.replace(/{{PATH_TO_ROOT_FOLDER}}/g, escapeBackticks(rootN1Folder))
    console.log(importContents)
    importTempPath = path.join(os.tmpdir(), "nylas-reg-#{Date.now()}.reg")
    console.log(importTempPath)
    fs.writeFile importTempPath, importContents, (err) =>
      console.log('wrote to template file')
      return callback(err) if err
      console.log('spawning with args')
      console.log(['import', escapeBackticks(importTempPath)])
      spawn(regPath, ['import', escapeBackticks(importTempPath)], callback)

# Update the desktop and start menu shortcuts by using the command line API
# provided by Squirrel's Update.exe
updateShortcuts = (callback) ->
  if homeDirectory = fs.getHomeDirectory()
    desktopShortcutPath = path.join(homeDirectory, 'Desktop', 'N1.lnk')
    # Check if the desktop shortcut has been previously deleted and
    # and keep it deleted if it was
    fs.exists desktopShortcutPath, (desktopShortcutExists) ->
      createShortcuts ->
        if desktopShortcutExists
          callback()
        else
          # Remove the unwanted desktop shortcut that was recreated
          fs.unlink(desktopShortcutPath, callback)
  else
    createShortcuts(callback)

# Remove the desktop and start menu shortcuts by using the command line API
# provided by Squirrel's Update.exe
removeShortcuts = (callback) ->
  spawnUpdate(['--removeShortcut', exeName], callback)

exports.spawn = spawnUpdate

# Is the Update.exe installed with N1?
exports.existsSync = ->
  fs.existsSync(updateDotExe)

# Restart N1 using the version pointed to by the N1.cmd shim
exports.restartN1 = (app) ->
  app.once 'will-quit', ->
    spawnUpdate(['--processStart', exeName])
  app.quit()

# Handle squirrel events denoted by --squirrel-* command line arguments.
exports.handleStartupEvent = (app, squirrelCommand) ->
  switch squirrelCommand
    when '--squirrel-install'
      createRegistryEntries -> createShortcuts -> app.quit()
      true
    when '--squirrel-updated'
      createRegistryEntries -> updateShortcuts -> app.quit()
      true
    when '--squirrel-uninstall'
      removeShortcuts -> app.quit()
      true
    when '--squirrel-obsolete'
      app.quit()
      true
    else
      false
