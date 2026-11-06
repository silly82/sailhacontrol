#ifndef CREDENTIALS_H
#define CREDENTIALS_H

#include <functional>

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QString>
#include <QTimer>
#include <QVariantList>
#include <QVector>

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
//
// Profiles (several Home Assistant instances, e.g. home + camper van): every
// property above refers to the *active* profile, so call sites stay as they
// are. Only the active profile's secrets are loaded. Profile 0 keeps the
// secret names used up to v0.56 (an upgrade shows the same instance, nothing
// to re-enter); any other profile uses the same names with a "-p<id>" suffix.
// Ids are stable (never reused, never shifted by a delete). The list of
// {id, name} and the active id are not secret and live in dconf -- persisted
// by QML (harbour-hacontrol.qml) like connectionMode, so the C++ side needs no
// dconf library: QML hands the stored state in via restoreProfiles() and
// writes profilesConfig / activeProfileId back whenever they change.
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

    // [{id: int, name: string}, ...] in display order.
    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY profilesChanged)
    // The same list as a JSON string, for QML to persist in dconf.
    Q_PROPERTY(QString profilesConfig READ profilesConfig NOTIFY profilesChanged)
    Q_PROPERTY(int activeProfileId READ activeProfileId NOTIFY activeProfileIdChanged)
    Q_PROPERTY(QString activeProfileName READ activeProfileName NOTIFY activeProfileNameChanged)
    // dconf key prefix for instance-specific settings (favorites, watched
    // entities, cover target, mobile_app webhook, ...): profile 0 keeps the
    // pre-profile keys "/apps/harbour-hacontrol/<name>", any other profile
    // uses "/apps/harbour-hacontrol/profiles/<id>/<name>". QML binds
    // ConfigurationValue keys to `Credentials.settingsPrefix + "<name>"`.
    Q_PROPERTY(QString settingsPrefix READ settingsPrefix NOTIFY activeProfileIdChanged)

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
    QVariantList profiles() const;
    QString profilesConfig() const;
    int activeProfileId() const;
    QString activeProfileName() const;
    QString settingsPrefix() const;

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
    // Called from QML when the network may have changed (e.g. the app comes
    // back to the foreground): probes again after a short debounce.
    Q_INVOKABLE void networkMayHaveChanged();
    // For QML call sites that just saw the connection fail (WebSocket error,
    // request timeout): probes, but not more often than every few seconds,
    // so a reconnect loop doesn't turn into a probe loop.
    Q_INVOKABLE void reportConnectionProblem();

    // Called once by QML at startup with what dconf holds (empty config ==
    // pre-profile install: a single profile 0). Loading the secrets waits for
    // this, so the right profile is loaded first.
    Q_INVOKABLE void restoreProfiles(const QString &config, int activeId);
    // Returns the new profile's id. Does not switch to it.
    Q_INVOKABLE int addProfile(const QString &name);
    // Refuses to remove the last profile. Removing the active one switches to
    // a neighbour first. Also deletes the profile's secrets; its dconf
    // settings are cleared by QML (see harbour-hacontrol.qml).
    Q_INVOKABLE bool removeProfile(int id);
    Q_INVOKABLE void renameProfile(int id, const QString &name);
    Q_INVOKABLE void setActiveProfile(int id);
    Q_INVOKABLE QString settingsPrefixFor(int id) const;
    // Reads the stored internal + external URL of any profile, active or not,
    // without touching the active one's state -- for notification actions
    // that belong to an instance other than the selected one (their mobile_app
    // webhook needs only the URL, not the token). Answers asynchronously with
    // profileUrlsRead(requestId, ...); empty strings if nothing is stored.
    Q_INVOKABLE void readProfileUrls(int profileId, int requestId);

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
    void profilesChanged();
    void activeProfileIdChanged();
    void activeProfileNameChanged();
    void profileUrlsRead(int requestId, int profileId, const QString &internalUrl, const QString &externalUrl);

private:
    struct Profile {
        int id;
        QString name;
    };
    int indexOfProfile(int id) const;
    QString displayName(const Profile &profile) const;
    // Secret name for a profile: the pre-profile name for id 0, otherwise
    // "<base>-p<id>".
    static QString secretName(const QString &base, int profileId);
    void deleteSecret(const QString &name);

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
    // Applies what the load chain read, unless the active profile changed
    // meanwhile (then it loads again for the new one).
    void finishLoading();
    void storeOne(Sailfish::Secrets::StoreSecretRequest *request, const QString &name, const QString &value);
    // Deleting first makes the write an upsert; the daemon reports
    // SecretAlreadyExistsError if a value is simply overwritten, and deleting a
    // non-existent secret only yields a (ignored) error result. Name and value
    // are captured at call time: a profile switch while the delete is in
    // flight must not redirect the write to the other profile.
    void deleteThenStore(Sailfish::Secrets::DeleteSecretRequest *request,
                         Sailfish::Secrets::StoreSecretRequest *storeRequest,
                         const QString &name, const QString &value);
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

    QVector<Profile> m_profiles;
    int m_activeProfileId;
    int m_nextProfileId;
    bool m_profilesRestored;
    // Load chain state: which profile it is reading, the values read so far
    // (applied together at the end), whether one is running, and whether it
    // has to start over (active profile changed / reload() while running).
    int m_loadProfileId;
    bool m_loadInFlight;
    bool m_loadAgain;
    // A save() while the load chain runs wins over what the chain reads.
    bool m_savedDuringLoad;
    QString m_loadInternalUrl;
    QString m_loadExternalUrl;
    QString m_loadToken;

    // Reachability probe of the internal URL (GET <internal>/api/).
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_probeReply;
    QTimer m_probeTimeout;
    // While on the external URL: look every now and then whether the internal
    // one is back (e.g. home again without a network-change signal).
    QTimer m_recheckTimer;
    // Network changes come in bursts (several configurations change state at
    // once, and the new link needs a moment for DHCP/DNS); probe once after
    // they settled.
    QTimer m_networkChangeDebounce;
    qint64 m_lastProbeStarted;

    // Standalone device-lock secrets: kept unlocked once the device itself is
    // unlocked (matches the plaintext predecessor's threat model -- a
    // single-user device), encrypted at rest by the daemon.
    QString m_storagePluginName;
    QString m_encryptionPluginName;
    bool m_pluginsResolved;

    // readProfileUrls() calls made before the plugin names were known
    // (D-Bus activation by a notification action right at startup).
    struct PendingUrlRead {
        int profileId;
        int requestId;
    };
    QVector<PendingUrlRead> m_pendingUrlReads;
    void flushPendingUrlReads();
    void readOneSecret(const QString &name, std::function<void(const QString &)> done);
};

#endif // CREDENTIALS_H
