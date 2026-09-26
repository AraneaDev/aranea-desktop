// The notification inbox: one JSON file per stored notification under
// inbox/, mirrored into a newest-first ListModel. A file lives until the user
// dismisses or acts on its notification (see InboxLogic.removesFromInbox);
// `onScreen` records whether its toast is still showing so a shell restart
// can bring the toast back.
//
// Every write, delete and read goes through one serialized Process queue: a
// burst of replaces_id updates must not race a reused Process, and a delete
// queued after a write must win.

import QtQuick
import Quickshell
import Quickshell.Io
import "NotificationLogic.js" as NotificationLogic
import "InboxLogic.js" as InboxLogic

Item {
  id: inbox

  required property string stateDir      // ~/.local/state/omarchy/notifications/
  required property int normalUrgency
  readonly property string inboxDir: stateDir + "inbox/"
  readonly property string imagesDir: stateDir + "images/"

  property alias model: inboxModel
  readonly property int count: inboxModel.count
  property int revision: 0

  signal loaded()

  ListModel { id: inboxModel }

  function indexOf(fileName: string): int {
    for (var i = 0; i < inboxModel.count; i++) {
      if (inboxModel.get(i).fileName === fileName) return i
    }
    return -1
  }

  function has(fileName: string): bool {
    return indexOf(fileName) >= 0
  }

  function get(fileName: string): var {
    var i = indexOf(fileName)
    if (i < 0) return null
    var row = inboxModel.get(i)
    return {
      fileName: row.fileName, id: row.id, originalId: row.originalId, app: row.app,
      appIcon: row.appIcon, summary: row.summary, body: row.body, image: row.image,
      glyph: row.glyph, execArgv: row.execArgv, urgency: row.urgency,
      expireTimeout: row.expireTimeout, timestamp: row.timestamp, onScreen: row.onScreen
    }
  }

  function modelRow(entry, onScreen) {
    var e = NotificationLogic.popupEntry(entry, normalUrgency)
    return {
      fileName: NotificationLogic.popupFileName(e),
      id: e.id, originalId: e.originalId, app: e.app, appIcon: e.appIcon,
      summary: e.summary, body: e.body, image: e.image, glyph: e.glyph,
      execArgv: e.execArgv, urgency: e.urgency, expireTimeout: e.expireTimeout,
      timestamp: e.timestamp, onScreen: !!onScreen
    }
  }

  function upsert(entry: var, onScreen: bool, deadline: real): void {
    if (!entry) return
    var row = modelRow(entry, onScreen)
    var i = indexOf(row.fileName)
    if (i >= 0) {
      for (var key in row) inboxModel.setProperty(i, key, row[key])
    } else {
      inboxModel.insert(0, row)
    }
    revision++
    writeFile(entry, onScreen, deadline)
    prune()
  }

  function setOnScreen(fileName: string, onScreen: bool): void {
    var i = indexOf(fileName)
    if (i < 0) return
    if (inboxModel.get(i).onScreen === onScreen) return
    inboxModel.setProperty(i, "onScreen", onScreen)
    revision++
    writeFile(get(fileName), onScreen, 0)
  }

  function remove(fileName: string): void {
    var i = indexOf(fileName)
    if (i >= 0) {
      inboxModel.remove(i)
      revision++
    }
    enqueue(["bash", "-c", "rm -f \"$1/$2\" \"$3/${2%.json}\"-*", "--",
      inboxDir, fileName, imagesDir])
  }

  function clear(): void {
    inboxModel.clear()
    revision++
    enqueue(["bash", "-c",
      "for f in \"$1\"/*.json; do\n" +
      "  [[ -e $f ]] || continue\n" +
      "  stale=\"${f##*/}\"\n" +
      "  rm -f \"$f\" \"$2/${stale%.json}\"-*\n" +
      "done", "--", inboxDir, imagesDir])
  }

  function prune(): void {
    var rows = []
    for (var i = 0; i < inboxModel.count; i++) {
      var r = inboxModel.get(i)
      rows.push({ fileName: r.fileName, timestamp: r.timestamp, urgency: r.urgency, onScreen: r.onScreen })
    }
    var result = InboxLogic.pruneInbox(rows, Date.now())
    for (var d = 0; d < result.drop.length; d++) remove(result.drop[d].fileName)
  }

  // ---------------------------------------------------- file writes

  // Consumes the remaining args as from/to pairs. Bounded read into a temp
  // file, validated, then renamed into place: the source path is
  // sender-controlled and may grow, block, or become a FIFO mid-copy, and
  // must neither hang the serialized queue nor fill the state dir.
  readonly property string copyImagesScript:
    "while (( $# >= 2 )); do\n" +
    "  if [[ -f $1 ]] && timeout 5 head -c 5242881 -- \"$1\" > \"$2.tmp\" 2>/dev/null &&\n" +
    "     (( $(stat -c%s -- \"$2.tmp\") <= 5242880 )); then mv -f -- \"$2.tmp\" \"$2\"; else rm -f -- \"$2.tmp\"; fi\n" +
    "  shift 2\n" +
    "done\n"

  // The JSON travels as an argument, never through shell interpolation.
  // Image copies run before the JSON that references them.
  function writeFile(entry, onScreen, deadline, done) {
    if (!entry) { if (done) done(); return }
    var persistable = NotificationLogic.persistablePopup(entry, imagesDir)
    var record = persistable.entry
    record.onScreen = !!onScreen
    if (deadline > 0) record.deadline = deadline
    else delete record.deadline
    var command = ["bash", "-c",
      "mkdir -p \"$1\" \"$2\" || exit 0\n" +
      "dir=\"$1\" json=\"$3\" name=\"$4\"\n" +
      "shift 4\n" +
      copyImagesScript +
      "printf '%s\\n' \"$json\" > \"$dir/$name\"", "--",
      inboxDir, imagesDir,
      NotificationLogic.serializePopup(record, normalUrgency),
      NotificationLogic.popupFileName(record)]
    for (var i = 0; i < persistable.copies.length; i++)
      command.push(persistable.copies[i].from, persistable.copies[i].to)
    enqueue(command, done)
  }

  // Record without touching the model — used by the DND path, which needs a
  // callback once the file (and its image copies) are on disk.
  function writeSilenced(entry, done) {
    var row = modelRow(entry, false)
    var i = indexOf(row.fileName)
    if (i >= 0) { for (var key in row) inboxModel.setProperty(i, key, row[key]) }
    else inboxModel.insert(0, row)
    revision++
    writeFile(entry, false, 0, done)
    prune()
  }

  // ---------------------------------------------------- queue

  property var queue: []
  property var runningDone: null

  function enqueue(command, done) {
    queue = queue.concat([{ command: command, done: done || null }])
    runNext()
  }

  function runNext(): void {
    if (fileProc.running || readProc.running || queue.length === 0) return
    var job = queue[0]
    queue = queue.slice(1)
    fileProc.command = job.command
    inbox.runningDone = job.done
    fileProc.running = true
  }

  Process {
    id: fileProc
    running: false
    onExited: {
      var done = inbox.runningDone
      inbox.runningDone = null
      if (done) {
        try { done() } catch (e) { console.warn("notifications: inbox job callback failed:", e) }
      }
      inbox.runNext()
    }
  }

  // ---------------------------------------------------- load

  property var loadDone: null

  // Popup files from before the inbox (top-level *.json in stateDir) are
  // moved into inbox/ untouched; lacking an onScreen flag they load as live
  // toasts, which is what they were. history/ is left alone on purpose.
  function load(done): void {
    loadDone = done || null
    enqueue(["bash", "-c",
      "mkdir -p \"$2\" \"$3\" || exit 0\n" +
      "for f in \"$1\"/*.json; do [[ -e $f ]] && mv -n -- \"$f\" \"$2/\"; done\n" +
      "exit 0", "--", stateDir, inboxDir, imagesDir], function() {
      readProc.command = ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", inbox.inboxDir]
      readProc.running = true
    })
  }

  Process {
    id: readProc
    running: false
    onExited: inbox.runNext()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: inbox.finishLoad(text)
    }
  }

  function finishLoad(raw: string): void {
    var entries = NotificationLogic.parsePopupFiles(raw, normalUrgency)
    inboxModel.clear()
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e.onScreen === undefined) e.onScreen = true
      inboxModel.append(modelRow(e, e.onScreen))
    }
    revision++
    prune()
    sweepOrphanImages()
    var done = loadDone
    loadDone = null
    if (done) done(entries)
    loaded()
  }

  // A restart can kill a job between its image copy and its JSON write,
  // leaving copies nothing references. Swept through the queue after load.
  function sweepOrphanImages(): void {
    enqueue(["bash", "-c",
      "for img in \"$2\"/*; do\n" +
      "  [[ -e $img ]] || continue\n" +
      "  [[ $img == *.tmp ]] && { rm -f -- \"$img\"; continue; }\n" +
      "  stem=\"${img##*/}\"\n" +
      "  stem=\"${stem%-*}\"\n" +
      "  [[ -e $1/$stem.json ]] || rm -f \"$img\"\n" +
      "done", "--", inboxDir, imagesDir])
  }
}
