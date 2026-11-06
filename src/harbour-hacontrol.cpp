#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include "credentials.h"
#include "deviceinfo.h"

#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQuickView>
#include <QRegularExpression>
#include <QSslConfiguration>
#include <QSslCipher>
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

// Qt 5.6 predates TLS 1.3. With the device's OpenSSL 1.1.1, every TLS 1.3
// handshake goes through Qt's PSK client callback, which emits
// preSharedKeyAuthenticationRequired() -- from the QNetworkAccessManager HTTP
// thread as a blocking call into the main thread. When the main thread runs
// a handshake of its own at the same moment (the wss:// WebSocket at
// startup), both end up waiting for each other: the app froze in about two
// of five launches with an https base URL (gdb on the Jolla Phone: main
// thread in QBasicMutex::lockInternal() in libQt5Network, "Qt HTTP thread"
// in QSemaphore::acquire() under QSslSocket::preSharedKeyAuthenticationRequired).
// TLS 1.2 without PSK cipher suites never invokes that callback. Every
// reverse proxy, Nabu Casa and Tailscale serve still offers TLS 1.2.
static void configureTls()
{
    QSslConfiguration config = QSslConfiguration::defaultConfiguration();
    config.setProtocol(QSsl::TlsV1_2);
    QList<QSslCipher> ciphers;
    const QList<QSslCipher> all = config.ciphers();
    for (const QSslCipher &cipher : all) {
        if (!cipher.name().contains(QStringLiteral("PSK"))) {
            ciphers.append(cipher);
        }
    }
    config.setCiphers(ciphers);
    QSslConfiguration::setDefaultConfiguration(config);
}

int main(int argc, char *argv[])
{
    s_previousHandler = qInstallMessageHandler(redactingMessageHandler);

    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    configureTls();
    QScopedPointer<QQuickView> view(SailfishApp::createView());

    // HA URL + token live in C++ (Sailfish.Secrets can't be driven from QML --
    // see src/credentials.h). Exposing the object as a context property keeps
    // every existing QML call site (`Credentials.baseUrl`, ...) unchanged.
    Credentials credentials;
    view->rootContext()->setContextProperty(QStringLiteral("Credentials"), &credentials);

    // Device sensors for HA's mobile_app integration that need C++ (free
    // storage via QStorageInfo) -- see qml/components/DeviceStatusProbe.qml.
    DeviceInfo deviceInfo;
    view->rootContext()->setContextProperty(QStringLiteral("DeviceInfo"), &deviceInfo);

    view->setSource(SailfishApp::pathTo(QStringLiteral("qml/harbour-hacontrol.qml")));
    view->show();

    return app->exec();
}
