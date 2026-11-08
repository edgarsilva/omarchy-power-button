.pragma library

// The action catalogue. Commands are Omarchy's own session scripts wherever
// one exists (`omarchy-system-*`, `omarchy-launch-screensaver`) so this plugin
// inherits whatever those grow later — confirmation prompts, sleep locks,
// update-on-reboot — instead of forking their behaviour into QML. Only
// "Turn screens off" has no Omarchy equivalent, so it dispatches to Hyprland.
//
// `key` is deliberately absent: PanelKeyCatcher already claims h/j/k/l for
// cursor movement and x for delete, which rules out the obvious first-letter
// accelerators (Lock and Shutdown both collide). Rows are numbered 1-9 at render
// time instead — unambiguous, and the number is what the row pill shows.
var ACTIONS = [
  {
    id: "screens-off",
    label: "Turn screens off",
    // ConfirmDialog's buttons are a fixed width — "Turn screens off" clips.
    confirmLabel: "Turn off",
    icon: "󱍳",
    group: "Screen",
    detail: "Wake them with the mouse or a key",
    // Hyprland 0.56 moved dispatchers to Lua; the bare `dpms off` form now
    // exits 7. Omarchy's own scripts (omarchy-launch-screensaver) use this
    // same try-new-then-legacy chain, so older Hyprland keeps working.
    command: "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })' >/dev/null 2>&1 || hyprctl dispatch dpms off",
    destructive: false
  },
  {
    id: "lock",
    label: "Lock",
    icon: "",
    group: "Screen",
    detail: "Password or fingerprint to return",
    command: "omarchy-system-lock",
    destructive: false
  },
  {
    id: "suspend",
    label: "Suspend",
    icon: "󰒲",
    group: "Session",
    detail: "Sleep to RAM",
    command: "systemctl suspend",
    // Mirrors omarchy-menu: the suspend-off toggle hides the row entirely.
    requires: "suspend",
    destructive: false
  },
  {
    id: "hibernate",
    label: "Hibernate",
    icon: "󰤁",
    group: "Session",
    detail: "Sleep to disk, survives a flat battery",
    command: "systemctl hibernate",
    // Only appears where hibernation is actually set up — it needs swap at
    // least the size of RAM, which most desktops do not have.
    requires: "hibernate",
    destructive: false
  },
  {
    id: "shutdown",
    label: "Shutdown",
    icon: "󰐥",
    group: "Session",
    detail: "Power the machine off",
    command: "omarchy system shutdown",
    destructive: true
  },
  {
    id: "reboot",
    label: "Reboot",
    icon: "󰜉",
    group: "Session",
    detail: "Restart the machine",
    command: "omarchy system reboot",
    destructive: true
  },
  {
    id: "logout",
    label: "Logout",
    icon: "󰍃",
    group: "Session",
    detail: "End the Hyprland session",
    command: "omarchy system logout",
    destructive: true
  }
]

function byLabel(label) {
  for (var i = 0; i < ACTIONS.length; i++) {
    if (ACTIONS[i].label === label) return ACTIONS[i]
  }
  return null
}

function byId(id) {
  for (var i = 0; i < ACTIONS.length; i++) {
    if (ACTIONS[i].id === id) return ACTIONS[i]
  }
  return null
}

// `available` is the Service's capability map: { suspend: bool, hibernate: bool }.
// An action with no `requires` is always available; one that names a missing
// capability drops out of the list rather than failing on click.
function isAvailable(action, available) {
  if (!action.requires) return true
  return !!(available && available[action.requires])
}

// `selected` is the multiselect setting: a list of labels, or empty for "all".
// Selection never reorders — the catalogue order is the menu order, so the
// numbering stays stable no matter how the setting was assembled.
function visibleActions(selected, available) {
  var wanted = Array.isArray(selected) ? selected : []
  var out = []
  for (var i = 0; i < ACTIONS.length; i++) {
    var action = ACTIONS[i]
    if (!isAvailable(action, available)) continue
    if (wanted.length > 0 && wanted.indexOf(action.label) === -1) continue
    out.push(action)
  }
  return out
}

// Rows carry their own group header flag so the panel renders one flat
// Repeater instead of nesting a Repeater per group — nested delegates make
// the keyboard cursor index arithmetic much harder to keep honest.
function rowsFor(selected, available, grouped) {
  var actions = visibleActions(selected, available)
  var rows = []
  var lastGroup = ""
  for (var i = 0; i < actions.length; i++) {
    var action = actions[i]
    rows.push({
      action: action,
      index: i,
      number: i + 1,
      header: grouped && action.group !== lastGroup ? action.group : ""
    })
    lastGroup = action.group
  }
  return rows
}

function parseProbe(raw) {
  try {
    var json = JSON.parse(String(raw || "").trim() || "{}")
    return {
      ok: true,
      suspend: json.suspend !== false,
      hibernate: json.hibernate === true,
      uptime: Number(json.uptime) || 0,
      user: String(json.user || ""),
      host: String(json.host || "")
    }
  } catch (e) {
    // Probe failed (no /proc, helper missing). Assume the common case rather
    // than emptying the menu: assume suspend works, hibernate does not.
    return { ok: false, suspend: true, hibernate: false, uptime: 0, user: "", host: "" }
  }
}

// "up 3d 4h", "up 51m", "up 40s" — one unit of precision past the leading one,
// which is as much as a power menu ever needs.
function formatUptime(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var days = Math.floor(total / 86400)
  var hours = Math.floor((total % 86400) / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  if (days > 0) return "up " + days + "d " + hours + "h"
  if (hours > 0) return "up " + hours + "h " + minutes + "m"
  if (minutes > 0) return "up " + minutes + "m"
  return "up " + total + "s"
}

function sessionLine(probe) {
  var parts = []
  if (probe && probe.user && probe.host) parts.push(probe.user + "@" + probe.host)
  else if (probe && probe.user) parts.push(probe.user)
  if (probe && probe.uptime > 0) parts.push(formatUptime(probe.uptime))
  return parts.join(" · ")
}

function confirmMessage(action) {
  return action.label === "Logout" ? "Log out of this session?" : action.label + " now?"
}

function confirmLabel(action) {
  if (!action) return "Confirm"
  return action.confirmLabel || action.label
}
