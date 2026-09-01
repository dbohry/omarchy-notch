import QtQuick

// Fires at most `max` times before giving up. Call schedule() on failure,
// reset() on success.
Timer {
  id: root
  property int attempts: 0
  property int max: 3
  interval: 2500

  function schedule() {
    if (root.attempts >= root.max) return
    root.attempts++
    root.restart()
  }

  function reset() {
    root.attempts = 0
  }
}
