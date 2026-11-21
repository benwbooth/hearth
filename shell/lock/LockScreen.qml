import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services"

// The lock screen's ext-session-lock: a surface on every screen while
// services/Lock.qml says locked. Only Lock.finishUnlock() (after a PAM
// success) ends it. Destroying the lock without unlocking (hearth
// crashing) leaves the compositor locked, which is what we want.
Scope {
    Connections {
        target: Lock
        function onLockedChanged() {
            if (lock.locked !== Lock.locked) lock.locked = Lock.locked;
        }
    }

    WlSessionLock {
        id: lock
        locked: false
        onLockedChanged: {
            // The compositor refused or ended the lock (another locker holds it).
            if (!locked && Lock.locked && !Lock.unlocking) {
                console.warn("hearth lock: the compositor ended the lock");
                Lock.compositorEnded();
            }
        }
        onSecureChanged: Lock.secure = secure

        WlSessionLockSurface {
            id: surf
            color: "black"
            LockSurface {
                anchors.fill: parent
                screen: surf.screen
            }
        }
    }
}
