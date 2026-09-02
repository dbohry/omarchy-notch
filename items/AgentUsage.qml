import QtQuick
import Quickshell.Io

// Single shared poll that keeps the agent usage records fresh, reachable as
// host.agentUsage. Independent of the built-in omarchy.agents bar module --
// notch runs its own updater so its rings refresh on their own schedule.
Item {
  id: root
  visible: false

  property int users: 0
  property int intervalSec: 120

  Process {
    id: updateProcess
    command: ["omarchy-agent-usage-update"]
  }

  Timer {
    running: root.users > 0
    interval: root.intervalSec * 1000
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!updateProcess.running) updateProcess.running = true
  }
}
