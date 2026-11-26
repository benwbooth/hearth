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
            ScrollAssist { flickable: list }
            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: 60
                delegate: MouseArea { width: 300; height: 40; hoverEnabled: true }
            }
        }
    }
    ScrollAssist { flickable: page }
    TestCase {
        name: "nested"
        when: windowShown
        function init() { page.cancelFlick(); list.cancelFlick(); page.contentY = 0; list.contentY = 0; wait(300) }
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
    }
}
