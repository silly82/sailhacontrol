#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include "credentials.h"

#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQuickView>
#include <QRegularExpression>
#include <cstdio>

// Camera stills are loaded via /api/camera_proxy/<id>?token=<access_token>
// (QML Image can't send an Authorization header). When such a load fails, Qt
// itself logs the full URL ("QML Image: Error transferring ..."), which would
// put the camera's access token into the journal. Redact token= values from
// every message before handing it to the default handler.
static QtMessageHandler s_previousHandler = nullptr;

static void redactingMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    static const QRegularExpression tokenParam(QStringLiteral("([?&]token=)[^&\\s\"']+"));
    QString redacted = message;
    redacted.replace(tokenParam, QStringLiteral("\\1***"));
    if (s_previousHandler) {
        s_previousHandler(type, context, redacted);
    } else {
        // Defensive: should not happen (Qt returns its default handler),
        // but never swallow messages.
        fprintf(stderr, "%s\n", qPrintable(qFormatLogMessage(type, context, redacted)));
        fflush(stderr);
    }
}

int main(int argc, char *argv[])
{
    s_previousHandler = qInstallMessageHandler(redactingMessageHandler);

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
