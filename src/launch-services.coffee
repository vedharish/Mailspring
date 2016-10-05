exec = require('child_process').exec
fs = require('fs')
{remote, shell} = require('electron')

bundleIdentifier = 'com.nylas.nylas-mail'

class LaunchServicesWindows
  available: ->
    true

  isRegisteredForURLScheme: (scheme, callback) ->
    exec "reg.exe query HKCU\\SOFTWARE\\Microsoft\\Windows\\Roaming\\OpenWith\\UrlAssociations\\#{scheme}\\UserChoice", (err, stdout, stderr) ->
      return callback(err) if callback and err
      callback(stdout.includes('Nylas'))

  resetURLScheme: (scheme, callback) ->
    remote.dialog.showMessageBox(null, {
      type: 'info',
      buttons: ['Thanks'],
      message: "Visit Settings to change your default mail client.",
      detail: "You'll find Nylas N1 listed as an option in Settings > System > Default Apps > Mail.",
    })

  registerForURLScheme: (scheme, callback) ->
    remote.dialog.showMessageBox null, {
      type: 'info',
      buttons: ['Dismiss', 'Learn More'],
      defaultId: 1,
      message: "Visit Settings to make Nylas N1 your default mail client.",
      detail: "You'll find Nylas N1 listed as an option in Settings > System > Default Apps > Mail. Thanks for using N1!",
    }, (button) ->
      if button is 'Learn More'
        shell.openExternal('https://support.nylas.com/hc/en-us/articles/229277648')

class LaunchServicesLinux
  available: ->
    true

  isRegisteredForURLScheme: (scheme, callback) ->
    throw new Error "isRegisteredForURLScheme is async, provide a callback" unless callback
    exec "xdg-mime query default x-scheme-handler/#{scheme}", (err, stdout, stderr) ->
      return callback(err) if callback and err
      callback(stdout.trim() is 'nylas.desktop')

  resetURLScheme: (scheme, callback) ->
    exec "xdg-mime default thunderbird.desktop x-scheme-handler/#{scheme}", (err, stdout, stderr) ->
      return callback(err) if callback and err
      callback(null, null) if callback

  registerForURLScheme: (scheme, callback) ->
    exec "xdg-mime default nylas.desktop x-scheme-handler/#{scheme}", (err, stdout, stderr) ->
      return callback(err) if callback and err
      callback(null, null) if callback

class LaunchServicesMac
  constructor: ->
    @secure = false

  available: ->
    true

  getLaunchServicesPlistPath: (callback) ->
    secure = "#{process.env.HOME}/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
    insecure = "#{process.env.HOME}/Library/Preferences/com.apple.LaunchServices.plist"

    fs.exists secure, (exists) ->
      if exists
        callback(secure)
      else
        callback(insecure)

  readDefaults: (callback) ->
    @getLaunchServicesPlistPath (plistPath) ->
      tmpPath = "#{plistPath}.#{Math.random()}"
      exec "plutil -convert json \"#{plistPath}\" -o \"#{tmpPath}\"", (err, stdout, stderr) ->
        return callback(err) if callback and err
        fs.readFile tmpPath, (err, data) ->
          return callback(err) if callback and err
          try
            data = JSON.parse(data)
            callback(data['LSHandlers'], data)
            fs.unlink(tmpPath)
          catch e
            callback(e) if callback and err

  writeDefaults: (defaults, callback) ->
    @getLaunchServicesPlistPath (plistPath) ->
      tmpPath = "#{plistPath}.#{Math.random()}"
      exec "plutil -convert json \"#{plistPath}\" -o \"#{tmpPath}\"", (err, stdout, stderr) ->
        return callback(err) if callback and err
        try
          data = fs.readFileSync(tmpPath)
          data = JSON.parse(data)
          data['LSHandlers'] = defaults
          data = JSON.stringify(data)
          fs.writeFileSync(tmpPath, data)
        catch error
          return callback(error) if callback and error

        exec "plutil -convert binary1 \"#{tmpPath}\" -o \"#{plistPath}\"", ->
          fs.unlink(tmpPath)
          exec "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user", (err, stdout, stderr) ->
            callback(err) if callback

  isRegisteredForURLScheme: (scheme, callback) ->
    throw new Error "isRegisteredForURLScheme is async, provide a callback" unless callback
    @readDefaults (defaults) ->
      for def in defaults
        if def.LSHandlerURLScheme is scheme
          return callback(def.LSHandlerRoleAll is bundleIdentifier)
      callback(false)

  resetURLScheme: (scheme, callback) ->
    @readDefaults (defaults) =>
      # Remove anything already registered for the scheme
      for ii in [defaults.length-1..0] by -1
        if defaults[ii].LSHandlerURLScheme is scheme
          defaults.splice(ii, 1)
      @writeDefaults(defaults, callback)

  registerForURLScheme: (scheme, callback) ->
    @readDefaults (defaults) =>
      # Remove anything already registered for the scheme
      for ii in [defaults.length-1..0] by -1
        if defaults[ii].LSHandlerURLScheme is scheme
          defaults.splice(ii, 1)

      # Add our scheme default
      defaults.push
        LSHandlerURLScheme: scheme
        LSHandlerRoleAll: bundleIdentifier

      @writeDefaults(defaults, callback)


if process.platform is 'darwin'
  module.exports = LaunchServicesMac
else if process.platform is 'linux'
  module.exports = LaunchServicesLinux
else if process.platform is 'win32'
  module.exports = LaunchServicesWindows
else
  module.exports = null

module.exports.LaunchServicesMac = LaunchServicesMac
module.exports.LaunchServicesLinux = LaunchServicesLinux
module.exports.LaunchServicesWindows = LaunchServicesWindows
