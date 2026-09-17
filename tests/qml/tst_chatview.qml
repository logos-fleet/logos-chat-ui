import QtQuick
import QtTest

// THE ENTRY VIEW ITSELF, CONSTRUCTED (logos-workspace#248).
//
// tst_components.qml proves each ChatUi component stands up on its own. It
// says nothing about ChatView.qml, which is the file metadata.json names as
// the `view` and the only one a host ever loads -- so a binding in it that no
// component has (`failures: store.errors` against a StatusBar that has no
// `failures`) compiled clean here and died on a phone with
// `Cannot assign to non-existent property`. Nothing in this repo built its
// QML: mkLogosQmlModule copies src/qml across as plain source, so the module
// built green with the view broken.
//
// Constructing it is the whole test. There is no `logos` context property in
// this process, which is deliberate rather than a limitation -- ChatStore's
// every binding is written to fall back when the backend is absent, and that
// is the state the view is in for the first frames of every real launch.
//
// Run with the same import paths as tst_components.qml; the ChatView URL is
// resolved relative to this file, so the check has to run from a writable copy
// of the repo rather than from tests/qml alone.
TestCase {
    id: root
    name: "ChatView"

    readonly property url chatViewUrl: Qt.resolvedUrl("../../src/qml/ChatView.qml")

    // A QML error in the view is a COMPILE error: the component never reaches
    // Ready, and errorString() is the line the device would have printed.
    function test_view_compiles() {
        const component = Qt.createComponent(chatViewUrl);
        compare(component.status, Component.Ready,
                "ChatView.qml did not compile: " + component.errorString());
        component.destroy();
    }

    // And it instantiates. Compiling only proves the bindings NAME things that
    // exist; a required property left unsatisfied, or a component that throws
    // on construction, fails here instead.
    function test_view_instantiates() {
        const component = Qt.createComponent(chatViewUrl);
        compare(component.status, Component.Ready,
                "ChatView.qml did not compile: " + component.errorString());
        const view = component.createObject(root);
        verify(view !== null, "ChatView.qml did not instantiate: " + component.errorString());
        verify(view.width > 0 && view.height > 0,
               "ChatView.qml came up with no size");
        view.destroy();
        component.destroy();
    }
}
