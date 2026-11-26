import QtQuick
import QtTest
import "../widgets"
// (Run by scripts/test-scroll-assist.sh, next to a copy of
// shell/widgets/ScrollAssist.qml and a stand-in Theme.)
// A list inside a scrolling page (Settings › Add a Cloud Drive's picker).
Item {
    id: top
    width: 400; height: 300
    Flickable {
        id: page
        anchors.fill: parent
        contentHeight: 1500
        Rectangle {
            y: 40; width: 300; height: 200; color: "grey"
            ScrollAssist { id: innerSA; flickable: list }
            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: 60
                delegate: MouseArea { width: 300; height: 40; hoverEnabled: true }
            }
        }
    }
    ScrollAssist { id: outerSA; flickable: page }
    TestCase {
        name: "nested"
        when: windowShown
        function init() { outerSA.stopGlide(); innerSA.stopGlide(); page.cancelFlick(); list.cancelFlick(); page.contentY = 0; list.contentY = 0; wait(300) }
        function test_wheel_goes_to_inner_list() {
            mouseWheel(top, 150, 120, 0, -120)
            tryVerify(() => list.contentY > 50, 2000, "list scrolled")
            compare(page.contentY, 0, "page stayed")
        }
        function test_outside_scrolls_page() {
            mouseWheel(top, 370, 120, 0, -120)
            tryVerify(() => page.contentY > 50, 2000, "page scrolled")
        }
        function test_list_at_end_chains_to_page() {
            list.contentY = list.contentHeight - list.height
            wait(50)
            mouseWheel(top, 150, 120, 0, -120)
            tryVerify(() => page.contentY > 50, 2000, "page scrolled once the list is at its end")
        }

        // Touchpad swipes as Wayland sends them (ScrollBegin with no amount,
        // updates every ~10 ms, ScrollEnd with none), through wheel(). (Not
        // real QWheelEvents: QtTest can't make phased ones.)
        function swipe(sa, x, y, dys, noEnd) {
            const t0 = Date.now();
            sa.wheel(x, y, 0, 0, Qt.ScrollBegin, t0);
            dys.forEach((d, i) => sa.wheel(x, y, -d, 0, Qt.ScrollUpdate, t0 + 10 * (i + 1)));
            if (!noEnd) sa.wheel(x, y, 0, 0, Qt.ScrollEnd, t0 + 10 * dys.length + 5);
        }
        function gliding(f) { const y = f.contentY; wait(80); return f.contentY !== y; }
        function test_swipe_glides_inner_list() {
            swipe(outerSA, 150, 80, [10, 20, 30, 30, 30])
            verify(gliding(list), "the list glides after the fingers lift")
            compare(page.contentY, 0, "page stayed")
        }
        function test_second_swipe_while_gliding_keeps_gliding() {
            swipe(outerSA, 150, 80, [10, 20, 30, 30, 30])
            wait(60)
            // A quick second flick: only two events.
            swipe(outerSA, 150, 80, [25, 30])
            verify(gliding(list), "still gliding after a quick second swipe")
            wait(150)
            verify(gliding(list), "and a while later")
            compare(page.contentY, 0, "page stayed")
        }
        function test_no_end_event_still_glides() {
            swipe(outerSA, 150, 80, [10, 20, 30, 30, 30], true)
            wait(100)
            verify(gliding(list), "glides once the events stop, without ScrollEnd")
        }
        function test_swipe_back_reverses() {
            swipe(outerSA, 150, 80, [10, 20, 30, 30, 30])
            wait(60)
            swipe(outerSA, 150, 80, [-25, -30])
            const y = list.contentY
            wait(80)
            verify(list.contentY < y, "gliding back up")
        }
    }
}
