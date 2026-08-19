import QtQuick
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Everything this plugin needs to know about the machine, in one batched
// probe: which sleep states are usable and how long the session has been up.
// Nothing here polls on a timer — a power menu is only ever read at the
// moment it opens, so the probe runs on open (and once at startup so the
// first paint is never blank).
Item {
  id: root

  property var settings: ({})

  property var probe: ({ ok: false, suspend: true, hibernate: false, uptime: 0, user: "", host: "" })
  property bool probing: false

  readonly property var available: ({ suspend: probe.suspend, hibernate: probe.hibernate })
  readonly property string sessionLine: Model.sessionLine(probe)

  readonly property string screenOffCommand: {
    var custom = String(setting("screenOffCommand", "")).trim()
    return custom !== "" ? custom : Model.byId("screens-off").command
  }
  // A click that turns the screens off releases the mouse button afterwards,
  // and on some setups that release is enough to wake DPMS straight back up.
  // Delaying the dispatch past the release is the standard fix.
  readonly property int screenOffDelayMs: {
    var value = parseInt(setting("screenOffDelayMs", 400), 10)
    if (!isFinite(value)) return 400
    return Math.max(0, Math.min(5000, value))
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh() {
    if (probeProcess.running) return
    probing = true
    probeProcess.running = true
  }

  function commandFor(action) {
    if (!action) return ""
    if (action.id === "screens-off") {
      return screenOffDelayMs > 0
        ? "sleep " + (screenOffDelayMs / 1000).toFixed(2) + "; " + screenOffCommand
        : screenOffCommand
    }
    return action.command
  }

  // Detached on purpose. Logout and shutdown tear down the session the shell
  // itself lives in; a tracked Process would be killed mid-flight by the very
  // thing it started.
  function run(action) {
    var command = commandFor(action)
    if (command !== "") Util.execDetached(command)
  }

  Process {
    id: probeProcess
    command: ["bash", "-lc",
      'suspend=true; hibernate=false; ' +
      'omarchy-toggle-enabled suspend-off >/dev/null 2>&1 && suspend=false; ' +
      'omarchy-hibernation-available >/dev/null 2>&1 && hibernate=true; ' +
      'uptime=$(cut -d" " -f1 /proc/uptime 2>/dev/null || echo 0); ' +
      'printf \'{"suspend":%s,"hibernate":%s,"uptime":%s,"user":"%s","host":"%s"}\\n\' ' +
      '"$suspend" "$hibernate" "$uptime" "${USER:-$(id -un)}" "$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)"']
    stdout: StdioCollector { id: probeStdout; waitForEnd: true }
    onExited: {
      root.probing = false
      var parsed = Model.parseProbe(probeStdout.text)
      // A failed probe keeps the previous answer rather than collapsing the
      // menu — a transient bash failure should not make Suspend disappear.
      if (parsed.ok) root.probe = parsed
    }
  }

  Component.onCompleted: refresh()
}
