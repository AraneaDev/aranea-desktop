// The notification inbox, instantiated once by Service.qml (service.inbox):
// one JSON file per stored notification under inbox/, mirrored into a
// newest-first ListModel. A file lives until the user dismisses or acts on it
// from the center.
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

  // Plugin state directory, with a trailing slash; set by Service.qml.
  required property string stateDir      // ~/.local/state/omarchy/notifications/
  // The host's normal urgency value, the default for entries without one.
  required property int normalUrgency
  // Where the entry files live.
  readonly property string inboxDir: stateDir + "inbox/"
  // Where the entries' image copies live (see NotificationLogic.persistablePopup).
  readonly property string imagesDir: stateDir + "images/"

  // Inbox rows, newest first; each row carries its fileName.
  property alias model: inboxModel
  // Number of inbox entries.
  readonly property int count: inboxModel.count
  // Bumped on every model change, so bindings that read rows re-evaluate.
  property int revision: 0
  // True once the first directory read has been merged in.
  property bool loadedOnce: false

  // Emitted after each directory read has been merged into the model.
  signal loaded

  ListModel {
    id: inboxModel
  }

  // Model index of the entry with this file name, or -1.
  function indexOf(fileName: string): int {
    for (var i = 0; i < inboxModel.count; i++) {
      if (inboxModel.get(i).fileName === fileName)
        return i
    }
    return -1
  }

  // Whether an entry with this file name is in the model.
  function has(fileName: string): bool {
    return indexOf(fileName) >= 0
  }

  // A plain copy of the entry with this file name, or null.
  function get(fileName: string): var {
    var i = indexOf(fileName)
    if (i < 0)
      return null
    var row = inboxModel.get(i)
    return {
      fileName: row.fileName,
      id: row.id,
      originalId: row.originalId,
      app: row.app,
      appIcon: row.appIcon,
      summary: row.summary,
      body: row.body,
      image: row.image,
      glyph: row.glyph,
      execArgv: row.execArgv,
      urgency: row.urgency,
      expireTimeout: row.expireTimeout,
      timestamp: row.timestamp,
      sourceKey: row.sourceKey
    }
  }

  // Normalizes an entry (NotificationLogic.popupEntry) into a model row with its fileName.
  function modelRow(entry) {
    var e = NotificationLogic.popupEntry(entry, normalUrgency)
    return {
      fileName: NotificationLogic.popupFileName(e),
      id: e.id,
      originalId: e.originalId,
      app: e.app,
      appIcon: e.appIcon,
      summary: e.summary,
      body: e.body,
      image: e.image,
      glyph: e.glyph,
      execArgv: e.execArgv,
      urgency: e.urgency,
      expireTimeout: e.expireTimeout,
      timestamp: e.timestamp,
      sourceKey: e.sourceKey
    }
  }

  // Adds an entry or updates the one with the same file name, writes its file and
  // prunes the inbox.
  function upsert(entry: var): void {
    if (!entry)
      return
    var row = modelRow(entry)
    var i = indexOf(row.fileName)
    if (i >= 0) {
      for (var key in row)
        inboxModel.setProperty(i, key, row[key])
    } else {
      inboxModel.insert(0, row)
    }
    revision++
    writeFile(entry)
    prune()
  }

  // Removes an entry from the model and deletes its file and image copies.
  function remove(fileName: string): void {
    var i = indexOf(fileName)
    if (i >= 0) {
      inboxModel.remove(i)
      revision++
    }
    enqueue(["bash", "-c", "rm -f \"$1/$2\" \"$3/${2%.json}\"-*", "--", inboxDir, fileName, imagesDir])
  }

  // Empties the model and deletes every entry file with its image copies.
  function clear(): void {
    inboxModel.clear()
    revision++
    enqueue(["bash", "-c", "for f in \"$1\"/*.json; do\n" + "  [[ -e $f ]] || continue\n" + "  stale=\"${f##*/}\"\n" + "  rm -f \"$f\" \"$2/${stale%.json}\"-*\n" + "done", "--", inboxDir, imagesDir])
  }

  // Removes the entries InboxLogic.pruneInbox drops (too old or over the limit).
  function prune(): void {
    var rows = []
    for (var i = 0; i < inboxModel.count; i++) {
      var r = inboxModel.get(i)
      rows.push({
        fileName: r.fileName,
        timestamp: r.timestamp,
        urgency: r.urgency,
        sourceKey: r.sourceKey
      })
    }
    var result = InboxLogic.pruneInbox(rows, Date.now())
    for (var d = 0; d < result.drop.length; d++)
      remove(result.drop[d].fileName)
  }

  // ---------------------------------------------------- file writes

  // Consumes the remaining args as from/to pairs. Bounded read into a temp
  // file, validated, then renamed into place: the source path is
  // sender-controlled and may grow, block, or become a FIFO mid-copy, and
  // must neither hang the serialized queue nor fill the state dir.
  readonly property string copyImagesScript: "while (( $# >= 2 )); do\n" + "  if [[ -f $1 ]] && timeout 5 head -c 5242881 -- \"$1\" > \"$2.tmp\" 2>/dev/null &&\n" + "     (( $(stat -c%s -- \"$2.tmp\") <= 5242880 )); then mv -f -- \"$2.tmp\" \"$2\"; else rm -f -- \"$2.tmp\"; fi\n" + "  shift 2\n" + "done\n"

  // The JSON travels on stdin (one line; serializePopup is compact), never as
  // an argument (argv is limited to 128 KiB per argument) or through shell
  // interpolation. Image copies run before the JSON that references them.
  // done, when given, receives the persisted record once the write finished.
  function writeFile(entry, done) {
    if (!entry) {
      if (done)
        done(null)
      return
    }
    var persistable = NotificationLogic.persistablePopup(entry, imagesDir)
    var record = persistable.entry
    var command = ["bash", "-c", "IFS= read -r json || exit 0\n" + "mkdir -p \"$1\" \"$2\" || exit 0\n" + "dir=\"$1\" name=\"$3\"\n" + "shift 3\n" + copyImagesScript + "printf '%s\\n' \"$json\" > \"$dir/$name.tmp\" && mv -f -- \"$dir/$name.tmp\" \"$dir/$name\"", "--", inboxDir, imagesDir, NotificationLogic.popupFileName(record)]
    for (var i = 0; i < persistable.copies.length; i++)
      command.push(persistable.copies[i].from, persistable.copies[i].to)
    enqueue(command, done ? function () {
      done(record)
    } : null, NotificationLogic.serializePopup(record, normalUrgency))
  }

  // ---------------------------------------------------- queue

  // Pending file jobs, each {command, done, stdin}, run one at a time by fileProc.
  property var queue: []
  // Callback of the job fileProc is running, called when it exits.
  property var runningDone: null
  // Line written to the running job's stdin when it starts, or "".
  property string runningStdin: ""
  // Whether the running job's process started (a failed start never exits).
  property bool runningStarted: false

  // Queues an argv to run after every job already queued, with an optional done
  // callback and an optional line for its stdin.
  function enqueue(command, done, stdin) {
    queue = queue.concat([
      {
        command: command,
        done: done || null,
        stdin: stdin || ""
      }
    ])
    runNext()
  }

  // Starts the next queued job unless a job or the directory read is running.
  function runNext(): void {
    if (fileProc.running || readProc.running || queue.length === 0)
      return
    var job = queue[0]
    queue = queue.slice(1)
    fileProc.command = job.command
    fileProc.stdinEnabled = job.stdin.length > 0
    inbox.runningStdin = job.stdin
    inbox.runningDone = job.done
    inbox.runningStarted = false
    fileProc.running = true
  }

  // Calls the running job's done callback once and starts the next job.
  function finishJob(): void {
    var done = inbox.runningDone
    inbox.runningDone = null
    inbox.runningStdin = ""
    if (done) {
      try {
        done()
      } catch (e) {
        console.warn("notifications: inbox job callback failed:", e)
      }
    }
    inbox.runNext()
  }

  Process {
    id: fileProc
    running: false
    onStarted: {
      inbox.runningStarted = true
      if (inbox.runningStdin)
        fileProc.write(inbox.runningStdin + "\n")
    }
    // A process that fails to start (e.g. E2BIG) never emits exited.
    onRunningChanged: if (!running && !inbox.runningStarted) {
      console.warn("notifications: inbox job failed to start")
      inbox.finishJob()
    }
    onExited: inbox.finishJob()
  }

  // ---------------------------------------------------- load

  // Callback of the pending load(), called with the parsed entries.
  property var loadDone: null

  // Popup files from before the inbox (top-level *.json in stateDir) are
  // moved into inbox/ untouched. history/ is left alone on purpose.
  function load(done): void {
    loadDone = done || null
    enqueue(["bash", "-c", "mkdir -p \"$2\" \"$3\" || exit 0\n" + "for f in \"$1\"/*.json; do [[ -e $f ]] && mv -n -- \"$f\" \"$2/\"; done\n" + "exit 0", "--", stateDir, inboxDir, imagesDir], function () {
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

  // Rows upserted while the directory was being read are not on disk yet (their
  // writes are queued behind the read), so merge them with what the read
  // returned instead of replacing the model.
  function finishLoad(raw: string): void {
    var entries = NotificationLogic.parsePopupFiles(raw, normalUrgency)
    var rows = []
    var seen = {}
    for (var i = 0; i < entries.length; i++) {
      var row = modelRow(entries[i])
      seen[row.fileName] = true
      // A legacy health item (1.7.0 posted system-health problems here with
      // a sourceKey); health now lives in its own dropdown.
      if (row.sourceKey) {
        remove(row.fileName)
        continue
      }
      rows.push(row)
    }
    for (var j = 0; j < inboxModel.count; j++) {
      var live = inboxModel.get(j)
      if (!seen[live.fileName])
        rows.push(get(live.fileName))
    }
    rows.sort(function (a, b) {
      return (b.timestamp || 0) - (a.timestamp || 0)
    })
    inboxModel.clear()
    for (var k = 0; k < rows.length; k++)
      inboxModel.append(rows[k])
    revision++
    prune()
    sweepOrphanImages()
    var done = loadDone
    loadDone = null
    if (done)
      done(entries)
    loadedOnce = true
    loaded()
  }

  // A restart can kill a job between its image copy and its JSON write,
  // leaving copies nothing references. Swept through the queue after load.
  function sweepOrphanImages(): void {
    enqueue(["bash", "-c", "for img in \"$2\"/*; do\n" + "  [[ -e $img ]] || continue\n" + "  [[ $img == *.tmp ]] && { rm -f -- \"$img\"; continue; }\n" + "  stem=\"${img##*/}\"\n" + "  stem=\"${stem%-*}\"\n" + "  [[ -e $1/$stem.json ]] || rm -f \"$img\"\n" + "done", "--", inboxDir, imagesDir])
  }
}
