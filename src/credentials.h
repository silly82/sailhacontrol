#ifndef CREDENTIALS_H
#define CREDENTIALS_H

#include <QObject>
#include <QString>

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
class Credentials : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString baseUrl READ baseUrl NOTIFY baseUrlChanged)
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
    explicit Credentials(QObject *parent = Q_NULLPTR);

    QString baseUrl() const;
    QString token() const;
    bool loaded() const;
    QString lastError() const;
    bool saveBusy() const;
    bool lastSaveOk() const;

    // Sets the in-memory values immediately (so the app reconnects at once,
    // same behaviour as before) and writes them to the secrets daemon
    // asynchronously -- never blocks the UI thread.
    Q_INVOKABLE void save(const QString &baseUrl, const QString &token);
    Q_INVOKABLE void reload();

Q_SIGNALS:
    void baseUrlChanged();
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
    void storeOne(Sailfish::Secrets::StoreSecretRequest *request, const QString &name, const QString &value);
    // Deleting first makes the write an upsert; the daemon reports
    // SecretAlreadyExistsError if a value is simply overwritten, and deleting a
    // non-existent secret only yields a (ignored) error result.
    void deleteThenStore(Sailfish::Secrets::DeleteSecretRequest *request,
                         Sailfish::Secrets::StoreSecretRequest *storeRequest,
                         const QString &name);
    void setBaseUrl(const QString &baseUrl);
    void setToken(const QString &token);
    void setLoaded(bool loaded);
    void setLastError(const QString &lastError);
    void setSaveBusy(bool saveBusy);
    void setLastSaveOk(bool lastSaveOk);
    // Called by both store requests: one "save" consists of two of them, so the
    // batch is only done (and lastSaveOk final) once both have reported back.
    void finishStore(bool ok, const QString &what, const QString &error);

    Sailfish::Secrets::SecretManager m_manager;
    Sailfish::Secrets::PluginInfoRequest m_pluginInfo;

    Sailfish::Secrets::StoredSecretRequest m_baseUrlLoad;
    Sailfish::Secrets::StoredSecretRequest m_tokenLoad;
    Sailfish::Secrets::StoreSecretRequest m_baseUrlStore;
    Sailfish::Secrets::StoreSecretRequest m_tokenStore;
    Sailfish::Secrets::DeleteSecretRequest m_baseUrlDelete;
    Sailfish::Secrets::DeleteSecretRequest m_tokenDelete;

    QString m_baseUrl;
    QString m_token;
    QString m_lastError;
    bool m_loaded;
    int m_pendingStores;
    bool m_saveBusy;
    bool m_lastSaveOk;
    bool m_saveFailed;

    // Standalone device-lock secrets: kept unlocked once the device itself is
    // unlocked (matches the plaintext predecessor's threat model -- a
    // single-user device), encrypted at rest by the daemon.
    QString m_storagePluginName;
    QString m_encryptionPluginName;
    bool m_pluginsResolved;
};

#endif // CREDENTIALS_H
