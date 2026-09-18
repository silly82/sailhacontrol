#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include "credentials.h"

#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQuickView>

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    QScopedPointer<QQuickView> view(SailfishApp::createView());

    // HA URL + token live in C++ (Sailfish.Secrets can't be driven from QML --
    // see src/credentials.h). Exposing the object as a context property keeps
    // every existing QML call site (`Credentials.baseUrl`, ...) unchanged.
    Credentials credentials;
    view->rootContext()->setContextProperty(QStringLiteral("Credentials"), &credentials);

    view->setSource(SailfishApp::pathTo(QStringLiteral("qml/harbour-hacontrol.qml")));
    view->show();

    return app->exec();
}
