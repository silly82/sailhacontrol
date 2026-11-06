#ifndef CREDENTIALS_H
#define CREDENTIALS_H

#include <QNetworkAccessManager>
#include <QNetworkConfigurationManager>
#include <QNetworkReply>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QString>
#include <QTimer>

#include <Secrets/deletesecretrequest.h>
#include <Secrets/plugininforequest.h>
#include <Secrets/secretmanager.h>
#include <Secrets/storedsecretrequest.h>
#include <Secrets/storesecretrequest.h>

// HA URL + Long-Lived Access Token, stored encrypted via Sailfish Secrets and
// exposed to QML as a context property named "Credentials" (see main()).
//
// This lives in C++ rather than in QML on purpose: the Sailfish.Secrets QML
// plugin cannot do either of the two requests this needs. Its
// StoredSecretRequest.identifier property is of type
// Sailfish::Secrets::Secret::Identifier, which is a plain C++ class that the
// plugin never registers (Secret::Identifier has no Q_OBJECT/Q_GADGET), so QML
// fails with "Cannot assign QJSValue to Sailfish::Secrets::Secret::Identifier";
// and StoreSecretRequest.secretStorageType is an enum declared without Q_ENUM,
// so assigning it from QML fails with "Cannot assign int to an unregistered
// type" -- both verified on a real device, in the journal, with v0.50-3. The
// C++ API takes the very same values without any of that trouble.
//
// The QML-visible API is deliberately the same one the previous (broken) QML
// singleton offered: baseUrl / token / loaded / save(url, token), so every
// call site keeps working unchanged.
//
// Remote access: besides the internal URL there is an optional external one
// (Nabu Casa, Tailscale, reverse proxy -- same token). `baseUrl` is the
// *effective* URL: the internal one while it answers, otherwise the external
// one (see probe()). Every call site reads `baseUrl`, so a switch is just a
// baseUrlChanged() -- REST callers use the new host from their next request
// on, and RoomsView's WebSocket, whose url is bound to it, reconnects.
class Credentials : public QObject
{
    Q_OBJECT
    Q_ENUMS(ConnectionMode)
    Q_PROPERTY(QString baseUrl READ baseUrl NOTIFY baseUrlChanged)
    // The two stored URLs as typed in Settings (baseUrl is derived from them).
    Q_PROPERTY(QString internalUrl READ internalUrl NOTIFY internalUrlChanged)
    Q_PROPERTY(QString externalUrl READ externalUrl NOTIFY externalUrlChanged)
    // true while baseUrl is the external URL.
    Q_PROPERTY(bool usingExternal READ usingExternal NOTIFY usingExternalChanged)
    // true while a reachability probe of the internal URL is in flight.
    Q_PROPERTY(bool probing READ probing NOTIFY probingChanged)
    // AutoMode / InternalOnlyMode / ExternalOnlyMode. Not a secret, so it is
    // persisted by QML (dconf) and pushed in here, see harbour-hacontrol.qml.
    Q_PROPERTY(int connectionMode READ connectionMode WRITE setConnectionMode NOTIFY connectionModeChanged)
    Q_PROPERTY(QString token READ token NOTIFY tokenChanged)
    // true once the initial load attempt has finished (success or "nothing
    // stored yet") -- lets Settings show plain empty fields instead of
    // momentarily flashing "not configured" while the async load is in flight.
    Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    // true while a save() is still being written to the daemon, and whether the
    // last completed save actually succeeded -- the one-time migration in
    // qml/harbour-hacontrol.qml only wipes the old plaintext values once the
    // encrypted copy is confirmed stored (a failed store must not lose them).
    Q_PROPERTY(bool saveBusy READ saveBusy NOTIFY saveBusyChanged)
    Q_PROPERTY(bool lastSaveOk READ lastSaveOk NOTIFY lastSaveOkChanged)

public:
    enum ConnectionMode {
        AutoMode = 0,
        InternalOnlyMode = 1,
        ExternalOnlyMode = 2
    };

    explicit Credentials(QObject *parent = Q_NULLPTR);

    QString baseUrl() const;
    QString internalUrl() const;
    QString externalUrl() const;
    bool usingExternal() const;
    bool probing() const;
    int connectionMode() const;
    void setConnectionMode(int connectionMode);
    QString token() const;
    bool loaded() const;
    QString lastError() const;
    bool saveBusy() const;
    bool lastSaveOk() const;

    // Sets the in-memory values immediately (so the app reconnects at once,
    // same behaviour as before) and writes them to the secrets daemon
    // asynchronously -- never blocks the UI thread.
    // The two-argument form keeps the external URL as it is (used by the
    // one-time dconf migration); Settings uses the three-argument form.
    Q_INVOKABLE void save(const QString &baseUrl, const QString &token);
    Q_INVOKABLE void save(const QString &baseUrl, const QString &token, const QString &externalUrl);
    Q_INVOKABLE void reload();

    // Checks whether the internal URL answers and switches baseUrl
    // accordingly. Only probes in AutoMode with both URLs set; otherwise it
    // just settles usingExternal from the mode.
    Q_INVOKABLE void probe();
    // For QML call sites that just saw the connection fail (WebSocket error,
    // request timeout): probes, but not more often than every few seconds,
    // so a reconnect loop doesn't turn into a probe loop.
    Q_INVOKABLE void reportConnectionProblem();

Q_SIGNALS:
    void baseUrlChanged();
    void internalUrlChanged();
    void externalUrlChanged();
    void usingExternalChanged();
    void probingChanged();
    void connectionModeChanged();
    void tokenChanged();
    void loadedChanged();
    void lastErrorChanged();
    void saveBusyChanged();
    void lastSaveOkChanged();

private:
    // Which plugins to talk to is not knowable in advance: the daemon refuses
    // requests naming a plugin the image doesn't register (on the Jolla Phone,
    // "No such storage plugin exists:
    // org.sailfishos.secrets.plugin.encryptedstorage.sqlcipher", although the
    // .so is installed), and an empty encryption plugin name is refused with
    // "No such encryption plugin exists: ". So ask the daemon which plugins it
    // actually has, once, before the first request.
    void resolvePlugins();
    void choosePlugins(const QVector<Sailfish::Secrets::PluginInfo> &storage,
                       const QVector<Sailfish::Secrets::PluginInfo> &encryptedStorage,
                       const QVector<Sailfish::Secrets::PluginInfo> &encryption);
    static QString firstAvailable(const QVector<Sailfish::Secrets::PluginInfo> &plugins);

    void startLoading();
    void startTokenLoad();
    void startExternalUrlLoad();
    void storeOne(Sailfish::Secrets::StoreSecretRequest *request, const QString &name, const QString &value);
    // Deleting first makes the write an upsert; the daemon reports
    // SecretAlreadyExistsError if a value is simply overwritten, and deleting a
    // non-existent secret only yields a (ignored) error result.
    void deleteThenStore(Sailfish::Secrets::DeleteSecretRequest *request,
                         Sailfish::Secrets::StoreSecretRequest *storeRequest,
                         const QString &name);
    // Value to persist for a given store request.
    QString valueFor(const Sailfish::Secrets::StoreSecretRequest *storeRequest) const;
    void setInternalUrl(const QString &internalUrl);
    void setExternalUrl(const QString &externalUrl);
    void setUsingExternal(bool usingExternal);
    // Recomputes the effective URL and emits baseUrlChanged() if it moved --
    // called after everything that can change it.
    void updateEffectiveUrl();
    QString computeEffectiveUrl() const;
    void abortProbe();
    void onProbeFinished();
    void setToken(const QString &token);
    void setLoaded(bool loaded);
    void setLastError(const QString &lastError);
    void setSaveBusy(bool saveBusy);
    void setLastSaveOk(bool lastSaveOk);
    // Called by every store request: one "save" consists of three of them, so
    // the batch is only done (and lastSaveOk final) once all have reported.
    void finishStore(bool ok, const QString &what, const QString &error);

    Sailfish::Secrets::SecretManager m_manager;
    Sailfish::Secrets::PluginInfoRequest m_pluginInfo;

    Sailfish::Secrets::StoredSecretRequest m_baseUrlLoad;
    Sailfish::Secrets::StoredSecretRequest m_tokenLoad;
    Sailfish::Secrets::StoredSecretRequest m_externalUrlLoad;
    Sailfish::Secrets::StoreSecretRequest m_baseUrlStore;
    Sailfish::Secrets::StoreSecretRequest m_tokenStore;
    Sailfish::Secrets::StoreSecretRequest m_externalUrlStore;
    Sailfish::Secrets::DeleteSecretRequest m_baseUrlDelete;
    Sailfish::Secrets::DeleteSecretRequest m_tokenDelete;
    Sailfish::Secrets::DeleteSecretRequest m_externalUrlDelete;

    // m_internalUrl is what used to be m_baseUrl (and is still stored under
    // the old "baseUrl" secret name); m_effectiveUrl is what baseUrl returns.
    QString m_internalUrl;
    QString m_externalUrl;
    QString m_effectiveUrl;
    bool m_usingExternal;
    int m_connectionMode;
    QString m_token;
    QString m_lastError;
    bool m_loaded;
    int m_pendingStores;
    bool m_saveBusy;
    bool m_lastSaveOk;
    bool m_saveFailed;

    // Reachability probe of the internal URL (GET <internal>/api/).
    QNetworkAccessManager m_network;
    QNetworkConfigurationManager m_networkConfig;
    QPointer<QNetworkReply> m_probeReply;
    QTimer m_probeTimeout;
    // While on the external URL: look every now and then whether the internal
    // one is back (e.g. home again without a network-change signal).
    QTimer m_recheckTimer;
    // Network changes come in bursts (several configurations change state at
    // once, and the new link needs a moment for DHCP/DNS); probe once after
    // they settled.
    QTimer m_networkChangeDebounce;
    // Identifiers of the network configurations currently Active, to tell a
    // real link change from the many scan-result configurationChanged()s.
    QSet<QString> m_activeConfigs;
    qint64 m_lastProbeStarted;

    // Standalone device-lock secrets: kept unlocked once the device itself is
    // unlocked (matches the plaintext predecessor's threat model -- a
    // single-user device), encrypted at rest by the daemon.
    QString m_storagePluginName;
    QString m_encryptionPluginName;
    bool m_pluginsResolved;
};

#endif // CREDENTIALS_H
