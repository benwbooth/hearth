pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Ben's calendar from Almanac (his mail and calendar app), for the menu bar
// clock: its popup's agenda and day dots, and the optional "next event" in
// the bar. helpers/hearth-calendar asks `almanac --events FROM TO` (works
// whether or not Almanac is running) and answers again whenever Almanac saves,
// so nothing here polls. Opening an event or New Event… goes through it too.
Singleton {
    id: root

    readonly property bool enabled: Settings.menubar.showCalendar !== false
    property bool available: false
    property string reason: ""
    property var calendars: []
    property var events: []
    // "YYYY-MM-DD" -> events touching that day (all-day first, then by start)
    property var byDay: ({})
    // The month the clock's popup shows (its first day); the range asked for
    // covers it, today and the week ahead.
    property date month: new Date(clock.date.getFullYear(), clock.date.getMonth(), 1)
    readonly property string today: iso(clock.date)

    SystemClock { id: clock; precision: SystemClock.Minutes }

    function pad(n) { return n < 10 ? "0" + n : "" + n; }
    function iso(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()); }
    function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n); }
    function parse(s) {
        // "YYYY-MM-DDTHH:MM" local time (Almanac's form)
        const m = /^(\d+)-(\d+)-(\d+)(?:T(\d+):(\d+))?/.exec(s || "");
        return m ? new Date(+m[1], +m[2] - 1, +m[3], +(m[4] || 0), +(m[5] || 0)) : new Date(NaN);
    }
    function dayEvents(d) { return root.byDay[typeof d === "string" ? d : iso(d)] || []; }

    readonly property string rangeText: {
        const t = clock.date;
        const today0 = new Date(t.getFullYear(), t.getMonth(), t.getDate());
        // The month grid shows up to 6 weeks from the Monday on or before the 1st.
        const gridStart = addDays(month, -7);
        const gridEnd = addDays(month, 43);
        const from = gridStart < today0 ? gridStart : today0;
        const weekOut = addDays(today0, 8);
        const to = gridEnd > weekOut ? gridEnd : weekOut;
        return iso(from) + " " + iso(to);
    }
    onRangeTextChanged: send("range " + rangeText)
    // A new day: today's events are different ones.
    onTodayChanged: send("refresh")

    function send(line) { if (proc.running) proc.write(line + "\n"); }
    function openEvent(e) { send("open " + e.id + " " + e.start); }
    function newEvent(day) { send("new " + (typeof day === "string" ? day : iso(day))); }

    // The next timed event still to start today or tomorrow (for the bar).
    readonly property var nextEvent: {
        const now = clock.date;
        let best = null;
        for (const e of root.events) {
            if (e.allDay) continue;
            const s = parse(e.start);
            if (s <= now || s - now > 36 * 3600 * 1000) continue;
            if (!best || s < parse(best.start)) best = e;
        }
        return best;
    }
    readonly property int nextInMinutes: nextEvent ? Math.max(0, Math.round((parse(nextEvent.start) - clock.date) / 60000)) : -1

    function take(d) {
        root.available = !!d.available;
        root.reason = d.reason || "";
        root.calendars = d.calendars || [];
        const list = d.events || [];
        root.events = list;
        const map = {};
        for (const e of list) {
            const s = parse(e.start), en = parse(e.end);
            let day = new Date(s.getFullYear(), s.getMonth(), s.getDate());
            let guard = 0;
            do {
                const k = iso(day);
                (map[k] = map[k] || []).push(e);
                day = addDays(day, 1);
            } while (day < en && ++guard < 400);
        }
        root.byDay = map;
    }

    // hearth-ipc call calendar newEvent 2026-11-23 | openNext | refresh
    IpcHandler {
        target: "calendar"
        function newEvent(day: string): void { root.newEvent(day || root.today); }
        function openNext(): void { if (root.nextEvent) root.openEvent(root.nextEvent); }
        function refresh(): void { root.send("refresh"); }
    }

    Process {
        id: proc
        command: ["hearth-calendar"]
        running: root.enabled
        stdinEnabled: true
        onStarted: root.send("range " + root.rangeText)
        stdout: SplitParser {
            onRead: line => { try { root.take(JSON.parse(line)); } catch (e) {} }
        }
        onExited: if (root.enabled) restart.start()
    }
    Timer {
        id: restart
        interval: 10000
        onTriggered: proc.running = root.enabled
    }
    onEnabledChanged: if (!enabled) take({})
}
