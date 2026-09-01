import QtQuick

// A Timer that fires at most `max` times before giving up, for flaky network
// fetches. Call schedule() on failure and reset() on success.
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
