// STANDS IN FOR THE HOST'S REGISTRATION, and for nothing else.
//
// At runtime `Logos.ChatBackend` is not a QML file at all: the generated view
// plugin registers ChatBackend's meta-object with
// qmlRegisterUncreatableMetaObject, so the enum the store switches on
// (`ChatBackend.Online` and friends) is the .rep's. Nothing constructs the
// type -- ChatStore reaches the real backend through the `logos` context
// property, which a test process does not have either.
//
// So this file exists to give `import Logos.ChatBackend` something to resolve
// to, with the same enumerators in the same order as
// src/ChatBackend.rep's ChatStatus. A reordering there and not here would make
// the tests disagree with the app, so keep the two in step.
import QtQuick

QtObject {
    enum ChatStatus {
        Stopped,
        Initialising,
        Online,
        Error
    }
}
