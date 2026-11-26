import QtQuick

// Wheel events as whole notches, in the physical direction: +1 for the wheel
// (or two fingers) up/right, -1 down/left, whatever the natural-scrolling
// setting. Qt reports natural scrolling as inverted deltas (WheelEvent
// .inverted), which flipped volume and brightness; and a trackpad or
// high-resolution wheel sends many small deltas per gesture, each of which
// was a whole 5% step (far too sensitive). Small deltas add up to a notch
// (120 = one click of a classic wheel); a pause of 400 ms starts afresh.
//
//   WheelNotches { id: notches }
//   onWheel: w => { const n = notches.feed(w); if (n) step(n); }
QtObject {
    property real acc: 0
    property real last: 0
    function feed(w) {
        let d = w.angleDelta.y !== 0 ? w.angleDelta.y : w.angleDelta.x;
        if (w.inverted) d = -d;
        const now = Date.now();
        if (now - last > 400 || (acc !== 0 && Math.sign(d) !== Math.sign(acc))) acc = 0;
        last = now;
        acc += d;
        const n = acc > 0 ? Math.floor(acc / 120) : Math.ceil(acc / 120);
        acc -= n * 120;
        return n;
    }
}
