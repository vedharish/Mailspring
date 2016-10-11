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

createRegistryEntries = ({allowEscalation, registerDefaultIfPossible}, callback) ->
  escapeBackticks = (str) => str.replace(/\\/g, '\\\\')

  isWindows7 = os.release().startsWith('6.1')
  requiresLocalMachine = isWindows7

  # On Windows 7, we must write to LOCAL_MACHINE and need escalated privileges.
  # Don't do it at install time - wait for the user to ask N1 to be the default.
  if requiresLocalMachine and !allowEscalation
    return callback()

  if process.env.SystemRoot
    regPath = path.join(process.env.SystemRoot, 'System32', 'reg.exe')
  else
    regPath = 'reg.exe'

  if requiresLocalMachine
    regPath = '"' + path.join(appFolder, 'resources', 'elevate.cmd') + '" ' + regPath

  fs.readFile path.join(appFolder, 'resources', 'nylas-mailto-registration.reg'), (err, data) =>
    return callback(err) if err or not data
    importTemplate = data.toString()
    importContents = importTemplate.replace(/{{PATH_TO_ROOT_FOLDER}}/g, escapeBackticks(rootN1Folder))
    importContents = importContents.replace(/{{PATH_TO_APP_FOLDER}}/g, escapeBackticks(appFolder))
    if requiresLocalMachine
      importContents = importContents.replace(/{{HKEY_ROOT}}/g, 'HKEY_LOCAL_MACHINE')
    else
      importContents = importContents.replace(/{{HKEY_ROOT}}/g, 'HKEY_CURRENT_USER')

    importTempPath = path.join(os.tmpdir(), "nylas-reg-#{Date.now()}.reg")
    fs.writeFile importTempPath, importContents, (err) =>
      return callback(err) if err

      spawn regPath, ['import', escapeBackticks(importTempPath)], (err) =>
        if isWindows7 and registerDefaultIfPossible
          defaultReg = path.join(appFolder, 'resources', 'nylas-mailto-default.reg')
          spawn regPath, ['import', escapeBackticks(defaultReg)], (err) =>
            callback(err, true)
        else
          callback(err, false)

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
exports.createShortcuts = createShortcuts
exports.updateShortcuts = updateShortcuts
exports.removeShortcuts = removeShortcuts
exports.createRegistryEntries = createRegistryEntries

# Is the Update.exe installed with N1?
exports.existsSync = -> fs.existsSync(updateDotExe)

# Restart N1 using the version pointed to by the N1.cmd shim
exports.restartN1 = (app) ->
  app.once 'will-quit', ->
    spawnUpdate(['--processStart', exeName])
  app.quit()
