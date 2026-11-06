#include "credentials.h"

#include <QDateTime>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkRequest>
#include <QUrl>
#include <QVector>

#include <Secrets/plugininfo.h>
#include <Secrets/request.h>
#include <Secrets/result.h>
#include <Secrets/secret.h>

using namespace Sailfish::Secrets;

// Same names the plaintext predecessor used as dconf keys, so the one-time
// migration in qml/harbour-hacontrol.qml ("legacy" ConfigurationValues) and any
// manual inspection line up with what is stored here.
static const QLatin1String BaseUrlSecretName("harbour-hacontrol-baseUrl");
static const QLatin1String TokenSecretName("harbour-hacontrol-token");
// Added in v0.56 as a third, separate secret rather than a new field inside
// the baseUrl secret: data stored by v0.55 and earlier simply has no such
// secret, its load fails like on a fresh install and the external URL stays
// empty -- the two existing secrets are read exactly as before. The internal
// URL keeps living under the old "baseUrl" name for the same reason.
static const QLatin1String ExternalUrlSecretName("harbour-hacontrol-externalUrl");

// Instance-specific dconf settings. Profile 0 keeps the pre-profile keys
// directly below the app's directory.
static const QLatin1String SettingsRoot("/apps/harbour-hacontrol/");

// Short on purpose: this decides how long a start away from home talks to an
// unreachable internal host before switching to the external URL.
static const int ProbeTimeoutMs = 3000;
// While on the external URL, how often to look whether the internal one is
// back even without a network-change signal.
static const int RecheckIntervalMs = 60000;
// Network changes arrive in bursts, and a fresh link needs DHCP/DNS first.
static const int NetworkChangeDebounceMs = 2000;
// reportConnectionProblem() rate limit.
static const qint64 ProbeMinIntervalMs = 10000;

Credentials::Credentials(QObject *parent)
    : QObject(parent)
    , m_usingExternal(false)
    , m_connectionMode(AutoMode)
    , m_loaded(false)
    , m_pendingStores(0)
    , m_saveBusy(false)
    , m_lastSaveOk(false)
    , m_saveFailed(false)
    , m_activeProfileId(0)
    , m_nextProfileId(1)
    , m_profilesRestored(false)
    , m_loadProfileId(0)
    , m_loadInFlight(false)
    , m_loadAgain(false)
    , m_savedDuringLoad(false)
    , m_lastProbeStarted(0)
    , m_storagePluginName(SecretManager::DefaultStoragePluginName)
    , m_encryptionPluginName(SecretManager::DefaultEncryptionPluginName)
    , m_pluginsResolved(false)
{
    // Requests are useless without a manager: every one of them needs to know
    // which SecretManager (i.e. which connection to sailfishsecretsd) to use.
    m_baseUrlLoad.setManager(&m_manager);
    m_tokenLoad.setManager(&m_manager);
    m_externalUrlLoad.setManager(&m_manager);
    m_baseUrlStore.setManager(&m_manager);
    m_tokenStore.setManager(&m_manager);
    m_externalUrlStore.setManager(&m_manager);
    m_baseUrlDelete.setManager(&m_manager);
    m_tokenDelete.setManager(&m_manager);
    m_externalUrlDelete.setManager(&m_manager);
    m_pluginInfo.setManager(&m_manager);

    // Until QML restores the stored list (restoreProfiles()): the single
    // pre-profile instance.
    Profile first;
    first.id = 0;
    m_profiles.append(first);

    // System-mediated interaction, no in-app prompts: reading our own secrets
    // back must not require the user to unlock anything by hand.
    m_baseUrlLoad.setUserInteractionMode(SecretManager::SystemInteraction);
    m_tokenLoad.setUserInteractionMode(SecretManager::SystemInteraction);
    m_externalUrlLoad.setUserInteractionMode(SecretManager::SystemInteraction);

    m_probeTimeout.setSingleShot(true);
    m_probeTimeout.setInterval(ProbeTimeoutMs);
    connect(&m_probeTimeout, &QTimer::timeout, this, [this]() {
        if (m_probeReply) {
            // Emits finished() -> onProbeFinished() sees OperationCanceledError
            // and treats the internal URL as unreachable.
            m_probeReply->abort();
        }
    });

    m_recheckTimer.setInterval(RecheckIntervalMs);
    connect(&m_recheckTimer, &QTimer::timeout, this, &Credentials::probe);

    m_networkChangeDebounce.setSingleShot(true);
    m_networkChangeDebounce.setInterval(NetworkChangeDebounceMs);
    connect(&m_networkChangeDebounce, &QTimer::timeout, this, [this]() {
        // A probe still running was started on the previous network -- its
        // answer says nothing about the new one.
        abortProbe();
        probe();
    });
    // Plain QtNetwork bearer management (Qt5Network is a Harbour-allowed
    // library). If the image ships no bearer plugin these simply never fire;
    // the WebSocket-error path (reportConnectionProblem) and the recheck timer
    // still cover switching then, just less promptly.
    connect(&m_networkConfig, &QNetworkConfigurationManager::onlineStateChanged,
            this, [this](bool) { m_networkChangeDebounce.start(); });
    connect(&m_networkConfig, &QNetworkConfigurationManager::configurationChanged,
            this, [this](const QNetworkConfiguration &config) {
                // configurationChanged also fires for every WLAN scan result
                // (Discovered flags); only a link going up or down matters.
                const bool active = config.state().testFlag(QNetworkConfiguration::Active);
                const bool wasActive = m_activeConfigs.contains(config.identifier());
                if (active == wasActive) {
                    return;
                }
                if (active) {
                    m_activeConfigs.insert(config.identifier());
                } else {
                    m_activeConfigs.remove(config.identifier());
                }
                m_networkChangeDebounce.start();
            });

    connect(&m_pluginInfo, &PluginInfoRequest::statusChanged, this, [this]() {
        if (m_pluginInfo.status() != Request::Finished) {
            return;
        }
        if (m_pluginInfo.result().code() != Result::Succeeded) {
            qWarning() << "Credentials: plugin query failed:"
                       << m_pluginInfo.result().errorMessage()
                       << "-- falling back to the default plugin names";
            m_pluginsResolved = true;
            startLoading();
            return;
        }
        choosePlugins(m_pluginInfo.storagePlugins(),
                      m_pluginInfo.encryptedStoragePlugins(),
                      m_pluginInfo.encryptionPlugins());
    });

    connect(&m_baseUrlLoad, &StoredSecretRequest::statusChanged, this, [this]() {
        if (m_baseUrlLoad.status() != Request::Finished) {
            return;
        }
        const Result result = m_baseUrlLoad.result();
        if (result.code() == Result::Succeeded) {
            m_loadInternalUrl = QString::fromUtf8(m_baseUrlLoad.secret().data());
        } else {
            // "nothing stored yet" on a fresh install lands here as well -- not
            // an error the user needs to see, the empty Settings fields are
            // evidence enough. Logged for diagnosis only.
            qDebug() << "Credentials: baseUrl not loaded:" << result.errorMessage();
        }
        // Token second, so `loaded` only flips once both are done (same
        // sequential order the QML singleton used).
        startTokenLoad();
    });

    connect(&m_tokenLoad, &StoredSecretRequest::statusChanged, this, [this]() {
        if (m_tokenLoad.status() != Request::Finished) {
            return;
        }
        const Result result = m_tokenLoad.result();
        if (result.code() == Result::Succeeded) {
            m_loadToken = QString::fromUtf8(m_tokenLoad.secret().data());
        } else {
            qDebug() << "Credentials: token not loaded:" << result.errorMessage();
        }
        startExternalUrlLoad();
    });

    connect(&m_externalUrlLoad, &StoredSecretRequest::statusChanged, this, [this]() {
        if (m_externalUrlLoad.status() != Request::Finished) {
            return;
        }
        const Result result = m_externalUrlLoad.result();
        if (result.code() == Result::Succeeded) {
            m_loadExternalUrl = QString::fromUtf8(m_externalUrlLoad.secret().data());
        } else {
            // Expected for everything stored by v0.55 or earlier, and whenever
            // no external URL was entered: there is no such secret.
            qDebug() << "Credentials: externalUrl not loaded:" << result.errorMessage();
        }
        finishLoading();
    });

    connect(&m_baseUrlStore, &StoreSecretRequest::statusChanged, this, [this]() {
        if (m_baseUrlStore.status() != Request::Finished) {
            return;
        }
        const Result result = m_baseUrlStore.result();
        finishStore(result.code() == Result::Succeeded,
                    QStringLiteral("baseUrl"),
                    result.errorMessage());
    });

    connect(&m_tokenStore, &StoreSecretRequest::statusChanged, this, [this]() {
        if (m_tokenStore.status() != Request::Finished) {
            return;
        }
        const Result result = m_tokenStore.result();
        finishStore(result.code() == Result::Succeeded,
                    QStringLiteral("token"),
                    result.errorMessage());
    });

    connect(&m_externalUrlStore, &StoreSecretRequest::statusChanged, this, [this]() {
        if (m_externalUrlStore.status() != Request::Finished) {
            return;
        }
        const Result result = m_externalUrlStore.result();
        finishStore(result.code() == Result::Succeeded,
                    QStringLiteral("externalUrl"),
                    result.errorMessage());
    });

    resolvePlugins();
}

QString Credentials::baseUrl() const
{
    return m_effectiveUrl;
}

QString Credentials::internalUrl() const
{
    return m_internalUrl;
}

QString Credentials::externalUrl() const
{
    return m_externalUrl;
}

bool Credentials::usingExternal() const
{
    return m_usingExternal;
}

bool Credentials::probing() const
{
    return !m_probeReply.isNull();
}

int Credentials::connectionMode() const
{
    return m_connectionMode;
}

void Credentials::setConnectionMode(int connectionMode)
{
    if (connectionMode < AutoMode || connectionMode > ExternalOnlyMode) {
        connectionMode = AutoMode;
    }
    if (m_connectionMode == connectionMode) {
        return;
    }
    m_connectionMode = connectionMode;
    Q_EMIT connectionModeChanged();
    abortProbe();
    probe();
}

QString Credentials::token() const
{
    return m_token;
}

bool Credentials::loaded() const
{
    return m_loaded;
}

QString Credentials::lastError() const
{
    return m_lastError;
}

bool Credentials::saveBusy() const
{
    return m_saveBusy;
}

bool Credentials::lastSaveOk() const
{
    return m_lastSaveOk;
}

void Credentials::resolvePlugins()
{
    m_pluginInfo.startRequest();
}

QString Credentials::firstAvailable(const QVector<PluginInfo> &plugins)
{
    for (const PluginInfo &plugin : plugins) {
        if (plugin.statusFlags().testFlag(PluginInfo::Available)) {
            return plugin.name();
        }
    }
    // No status information to go on: take what the daemon listed.
    return plugins.isEmpty() ? QString() : plugins.first().name();
}

void Credentials::choosePlugins(const QVector<PluginInfo> &storage,
                                const QVector<PluginInfo> &encryptedStorage,
                                const QVector<PluginInfo> &encryption)
{
    const auto names = [](const QVector<PluginInfo> &plugins) {
        QStringList names;
        for (const PluginInfo &plugin : plugins) {
            names << plugin.name();
        }
        return names.join(QStringLiteral(", "));
    };
    qDebug() << "Credentials: daemon plugins -- storage:" << names(storage)
             << "| encrypted storage:" << names(encryptedStorage)
             << "| encryption:" << names(encryption);

    // The plain storage plugin is what actually accepted this device's
    // standalone device-lock secret (verified on the phone), so prefer it and
    // only fall back to an encrypted-storage plugin if there is no plain one.
    // Encryption is not lost by that: the request names the encryption plugin,
    // so the daemon encrypts the data before handing it to the storage plugin.
    QString chosen = firstAvailable(storage);
    if (chosen.isEmpty()) {
        chosen = firstAvailable(encryptedStorage);
    }
    if (!chosen.isEmpty()) {
        m_storagePluginName = chosen;
    }
    const QString encryptionPlugin = firstAvailable(encryption);
    if (!encryptionPlugin.isEmpty()) {
        m_encryptionPluginName = encryptionPlugin;
    }

    qDebug() << "Credentials: using storage plugin" << m_storagePluginName
             << "and encryption plugin" << m_encryptionPluginName;
    m_pluginsResolved = true;
    startLoading();
}

QVariantList Credentials::profiles() const
{
    QVariantList list;
    for (const Profile &profile : m_profiles) {
        QVariantMap entry;
        entry.insert(QStringLiteral("id"), profile.id);
        entry.insert(QStringLiteral("name"), displayName(profile));
        list.append(entry);
    }
    return list;
}

QString Credentials::profilesConfig() const
{
    QJsonArray list;
    for (const Profile &profile : m_profiles) {
        QJsonObject entry;
        entry.insert(QStringLiteral("id"), profile.id);
        entry.insert(QStringLiteral("name"), profile.name);
        list.append(entry);
    }
    QJsonObject config;
    config.insert(QStringLiteral("nextId"), m_nextProfileId);
    config.insert(QStringLiteral("profiles"), list);
    return QString::fromUtf8(QJsonDocument(config).toJson(QJsonDocument::Compact));
}

int Credentials::activeProfileId() const
{
    return m_activeProfileId;
}

QString Credentials::activeProfileName() const
{
    const int index = indexOfProfile(m_activeProfileId);
    return index >= 0 ? displayName(m_profiles.at(index)) : QString();
}

QString Credentials::displayName(const Profile &profile) const
{
    // Profile 0 of an upgraded install has no name yet.
    return profile.name.isEmpty() ? tr("Home") : profile.name;
}

QString Credentials::settingsPrefix() const
{
    return settingsPrefixFor(m_activeProfileId);
}

QString Credentials::settingsPrefixFor(int id) const
{
    if (id == 0) {
        return SettingsRoot;
    }
    return SettingsRoot + QStringLiteral("profiles/") + QString::number(id) + QLatin1Char('/');
}

int Credentials::indexOfProfile(int id) const
{
    for (int i = 0; i < m_profiles.size(); ++i) {
        if (m_profiles.at(i).id == id) {
            return i;
        }
    }
    return -1;
}

QString Credentials::secretName(const QString &base, int profileId)
{
    if (profileId == 0) {
        return base;
    }
    return base + QStringLiteral("-p") + QString::number(profileId);
}

void Credentials::restoreProfiles(const QString &config, int activeId)
{
    QVector<Profile> restored;
    int nextId = 1;
    const QJsonObject object = QJsonDocument::fromJson(config.toUtf8()).object();
    const QJsonArray list = object.value(QStringLiteral("profiles")).toArray();
    for (const QJsonValue &value : list) {
        const QJsonObject entry = value.toObject();
        if (!entry.contains(QStringLiteral("id"))) {
            continue;
        }
        Profile profile;
        profile.id = entry.value(QStringLiteral("id")).toInt(-1);
        profile.name = entry.value(QStringLiteral("name")).toString();
        if (profile.id < 0) {
            continue;
        }
        bool duplicate = false;
        for (const Profile &other : restored) {
            duplicate = duplicate || other.id == profile.id;
        }
        if (duplicate) {
            continue;
        }
        restored.append(profile);
        nextId = qMax(nextId, profile.id + 1);
    }
    // Nothing stored (every install up to v0.56) or unreadable: the single
    // pre-profile instance, i.e. exactly what was there before.
    if (restored.isEmpty()) {
        Profile first;
        first.id = 0;
        restored.append(first);
    }
    nextId = qMax(nextId, object.value(QStringLiteral("nextId")).toInt(1));

    m_profiles = restored;
    m_nextProfileId = nextId;
    const int previousActive = m_activeProfileId;
    m_activeProfileId = indexOfProfile(activeId) >= 0 ? activeId : m_profiles.first().id;
    qDebug() << "Credentials:" << m_profiles.size() << "profile(s), active id" << m_activeProfileId;

    Q_EMIT profilesChanged();
    if (previousActive != m_activeProfileId) {
        Q_EMIT activeProfileIdChanged();
    }
    Q_EMIT activeProfileNameChanged();

    if (!m_profilesRestored) {
        m_profilesRestored = true;
        startLoading();
    } else {
        // A second call (not done by the app itself): load whatever is
        // active now.
        reload();
    }
}

int Credentials::addProfile(const QString &name)
{
    Profile profile;
    profile.id = m_nextProfileId++;
    profile.name = name.trimmed();
    m_profiles.append(profile);
    Q_EMIT profilesChanged();
    return profile.id;
}

bool Credentials::removeProfile(int id)
{
    const int index = indexOfProfile(id);
    if (index < 0 || m_profiles.size() <= 1) {
        return false;
    }
    if (id == m_activeProfileId) {
        // The next one in the list, or the previous one if it was the last.
        const int neighbour = index + 1 < m_profiles.size() ? index + 1 : index - 1;
        setActiveProfile(m_profiles.at(neighbour).id);
    }
    m_profiles.remove(indexOfProfile(id));
    Q_EMIT profilesChanged();

    deleteSecret(secretName(BaseUrlSecretName, id));
    deleteSecret(secretName(TokenSecretName, id));
    deleteSecret(secretName(ExternalUrlSecretName, id));
    return true;
}

void Credentials::renameProfile(int id, const QString &name)
{
    const int index = indexOfProfile(id);
    if (index < 0 || m_profiles.at(index).name == name.trimmed()) {
        return;
    }
    m_profiles[index].name = name.trimmed();
    Q_EMIT profilesChanged();
    if (id == m_activeProfileId) {
        Q_EMIT activeProfileNameChanged();
    }
}

void Credentials::setActiveProfile(int id)
{
    if (id == m_activeProfileId || indexOfProfile(id) < 0) {
        return;
    }
    qDebug() << "Credentials: switching to profile id" << id;

    // Clear everything *before* announcing the switch: every listener then
    // sees baseUrl/token go empty and come back, i.e. a baseUrlChanged() even
    // if both instances happen to use the same URL (homeassistant.local), so
    // the WebSocket always reconnects -- and nothing is ever a mix of the old
    // profile's URL and the new one's token.
    abortProbe();
    m_recheckTimer.stop();
    m_activeProfileId = id;
    setLoaded(false);
    setLastError(QString());
    setUsingExternal(false);
    setInternalUrl(QString());
    setExternalUrl(QString());
    setToken(QString());

    Q_EMIT activeProfileIdChanged();
    Q_EMIT activeProfileNameChanged();

    startLoading();
}

void Credentials::deleteSecret(const QString &name)
{
    DeleteSecretRequest *request = new DeleteSecretRequest(this);
    request->setManager(&m_manager);
    request->setIdentifier(Secret::Identifier(name, QString(), m_storagePluginName));
    request->setUserInteractionMode(SecretManager::SystemInteraction);
    connect(request, &DeleteSecretRequest::statusChanged, this, [request, name]() {
        if (request->status() != Request::Finished) {
            return;
        }
        // Fails harmlessly for secrets that were never stored (e.g. no
        // external URL) -- logged for diagnosis only.
        const Result result = request->result();
        if (result.code() == Result::Succeeded) {
            qDebug() << "Credentials: deleted" << name;
        } else {
            qDebug() << "Credentials: nothing deleted for" << name << "(" << result.errorMessage() << ")";
        }
        request->deleteLater();
    });
    request->startRequest();
}

void Credentials::save(const QString &baseUrl, const QString &token)
{
    save(baseUrl, token, m_externalUrl);
}

void Credentials::save(const QString &baseUrl, const QString &token, const QString &externalUrl)
{
    setLastError(QString());
    if (m_loadInFlight) {
        m_savedDuringLoad = true;
    }

    // The app must behave as before the moment Settings is filled in, so the
    // properties change right away; persistence happens in the background.
    setInternalUrl(baseUrl);
    setExternalUrl(externalUrl.trimmed());
    setToken(token);

    // Three stores make one save; a delete may run before each of them, which
    // is why the batch is counted here and only closed by finishStore().
    m_saveFailed = false;
    m_pendingStores = 3;
    setSaveBusy(true);
    setLastSaveOk(false);

    // Always into the active profile.
    deleteThenStore(&m_baseUrlDelete, &m_baseUrlStore,
                    secretName(BaseUrlSecretName, m_activeProfileId), m_internalUrl);
    deleteThenStore(&m_tokenDelete, &m_tokenStore,
                    secretName(TokenSecretName, m_activeProfileId), m_token);
    deleteThenStore(&m_externalUrlDelete, &m_externalUrlStore,
                    secretName(ExternalUrlSecretName, m_activeProfileId), m_externalUrl);

    // New URLs/token: whatever the last probe found no longer applies.
    abortProbe();
    probe();
}

void Credentials::reload()
{
    // Reloads the active profile.
    abortProbe();
    m_recheckTimer.stop();
    setLoaded(false);
    setUsingExternal(false);
    setInternalUrl(QString());
    setExternalUrl(QString());
    setToken(QString());
    startLoading();
}

void Credentials::probe()
{
    // Nothing to choose between: settle usingExternal from the mode alone.
    if (m_connectionMode != AutoMode || m_internalUrl.isEmpty() || m_externalUrl.isEmpty()
            || m_token.isEmpty()) {
        abortProbe();
        m_recheckTimer.stop();
        setUsingExternal(m_connectionMode == ExternalOnlyMode && !m_externalUrl.isEmpty());
        return;
    }
    if (m_probeReply) {
        return; // one at a time; its answer is just as good
    }

    m_lastProbeStarted = QDateTime::currentMSecsSinceEpoch();

    QString url = m_internalUrl;
    while (url.endsWith(QLatin1Char('/'))) {
        url.chop(1);
    }
    // GET /api/ answers {"message": "API running."} with 200 only for a valid
    // token -- an unrelated host that happens to sit at the same LAN address
    // on a foreign network won't pass for Home Assistant.
    QNetworkRequest request(QUrl(url + QStringLiteral("/api/")));
    request.setRawHeader("Authorization", "Bearer " + m_token.toUtf8());

    // Qt 5.6's QNetworkAccessManager can get stuck believing the network is
    // "not accessible" after a bearer change and then fails every request
    // at once without trying -- exactly when a probe matters most.
    m_network.setNetworkAccessible(QNetworkAccessManager::Accessible);
    m_probeReply = m_network.get(request);
    connect(m_probeReply.data(), &QNetworkReply::finished, this, &Credentials::onProbeFinished);
    m_probeTimeout.start();
    Q_EMIT probingChanged();
}

void Credentials::reportConnectionProblem()
{
    if (QDateTime::currentMSecsSinceEpoch() - m_lastProbeStarted < ProbeMinIntervalMs) {
        return;
    }
    probe();
}

void Credentials::abortProbe()
{
    m_probeTimeout.stop();
    if (!m_probeReply) {
        return;
    }
    QNetworkReply *reply = m_probeReply.data();
    m_probeReply.clear();
    // Disconnect first: an aborted, no longer wanted probe must not decide
    // anything in onProbeFinished().
    disconnect(reply, Q_NULLPTR, this, Q_NULLPTR);
    reply->abort();
    reply->deleteLater();
    Q_EMIT probingChanged();
}

void Credentials::onProbeFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
    if (!reply) {
        return;
    }
    reply->deleteLater();
    if (reply != m_probeReply.data()) {
        return; // stale
    }
    m_probeTimeout.stop();
    m_probeReply.clear();
    Q_EMIT probingChanged();

    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const bool reachable = reply->error() == QNetworkReply::NoError && status == 200;
    // Error code and HTTP status only -- errorString() names the host.
    qDebug() << "Credentials: internal URL" << (reachable ? "reachable" : "not reachable")
             << "-- network error" << reply->error() << "HTTP" << status;

    // Mode or URLs may have changed while the probe ran; probe() then already
    // settled the state, and a new probe (if any) is the one that counts.
    if (m_connectionMode != AutoMode || m_externalUrl.isEmpty()) {
        return;
    }
    setUsingExternal(!reachable);
    if (reachable) {
        m_recheckTimer.stop();
    } else if (!m_recheckTimer.isActive()) {
        m_recheckTimer.start();
    }
}

void Credentials::startLoading()
{
    // Needs both the daemon's plugin names and the profile list from dconf.
    if (!m_pluginsResolved || !m_profilesRestored) {
        return;
    }
    // The requests are members and can't run twice at once: let the running
    // chain finish and start over in finishLoading().
    if (m_loadInFlight) {
        m_loadAgain = true;
        return;
    }
    m_loadInFlight = true;
    m_loadAgain = false;
    m_savedDuringLoad = false;
    m_loadProfileId = m_activeProfileId;
    m_loadInternalUrl.clear();
    m_loadExternalUrl.clear();
    m_loadToken.clear();
    m_baseUrlLoad.setIdentifier(
        Secret::Identifier(secretName(BaseUrlSecretName, m_loadProfileId), QString(), m_storagePluginName));
    m_baseUrlLoad.startRequest();
}

void Credentials::startTokenLoad()
{
    m_tokenLoad.setIdentifier(
        Secret::Identifier(secretName(TokenSecretName, m_loadProfileId), QString(), m_storagePluginName));
    m_tokenLoad.startRequest();
}

void Credentials::startExternalUrlLoad()
{
    m_externalUrlLoad.setIdentifier(
        Secret::Identifier(secretName(ExternalUrlSecretName, m_loadProfileId), QString(), m_storagePluginName));
    m_externalUrlLoad.startRequest();
}

void Credentials::finishLoading()
{
    m_loadInFlight = false;
    if (m_loadAgain || m_loadProfileId != m_activeProfileId) {
        // Read for a profile that is no longer active (or reload() asked to
        // start over) -- discard, read again.
        m_loadAgain = false;
        startLoading();
        return;
    }
    if (!m_savedDuringLoad) {
        // All three at once: a half-applied set (new URL, old token) would
        // send one instance's token to another instance's host.
        setInternalUrl(m_loadInternalUrl);
        setExternalUrl(m_loadExternalUrl);
        setToken(m_loadToken);
    }
    m_savedDuringLoad = false;
    m_loadInternalUrl.clear();
    m_loadExternalUrl.clear();
    m_loadToken.clear();
    // Lengths only -- never the values themselves, the journal is readable
    // by more than just this app.
    qDebug() << "Credentials: loaded profile" << m_activeProfileId
             << "-- internal URL" << m_internalUrl.length()
             << "chars, external URL" << m_externalUrl.length()
             << "chars, token" << m_token.length() << "chars";
    setLoaded(true);
    probe();
}

void Credentials::deleteThenStore(DeleteSecretRequest *request,
                                  StoreSecretRequest *storeRequest,
                                  const QString &name, const QString &value)
{
    // What to write once the delete is through. Kept on the request rather
    // than captured by the lambda: the handler is connected only once, and
    // both name (per profile) and value differ from save to save.
    request->setProperty("hacontrolName", name);
    request->setProperty("hacontrolValue", value);

    // Connected once per request here; guarded so a second save() while a
    // delete is still in flight doesn't queue up duplicate handlers.
    if (!request->property("hacontrolConnected").toBool()) {
        request->setProperty("hacontrolConnected", true);
        connect(request, &DeleteSecretRequest::statusChanged, this,
                [this, request, storeRequest]() {
                    if (request->status() != Request::Finished) {
                        return;
                    }
                    const QString name = request->property("hacontrolName").toString();
                    // A delete of a secret that was never stored fails; that is
                    // expected on the first save and not worth reporting.
                    const Result result = request->result();
                    if (result.code() != Result::Succeeded) {
                        qDebug() << "Credentials: nothing to delete for" << name
                                 << "(" << result.errorMessage() << ")";
                    }
                    // An empty (optional) external URL is "stored" by the
                    // delete alone -- no point keeping an empty secret around,
                    // and the load treats a missing one as empty anyway.
                    const QString value = request->property("hacontrolValue").toString();
                    if (value.isEmpty()) {
                        finishStore(true, name + QStringLiteral(" (cleared)"), QString());
                        return;
                    }
                    storeOne(storeRequest, name, value);
                });
    }

    request->setIdentifier(
        Secret::Identifier(name, QString(), m_storagePluginName));
    request->setUserInteractionMode(SecretManager::SystemInteraction);
    request->startRequest();
}

void Credentials::storeOne(StoreSecretRequest *request, const QString &name, const QString &value)
{
    Secret secret(name, QString(), m_storagePluginName);
    secret.setData(value.toUtf8());

    request->setSecret(secret);
    request->setSecretStorageType(StoreSecretRequest::StandaloneDeviceLockSecret);
    request->setEncryptionPluginName(m_encryptionPluginName);
    // Kept unlocked once the device itself is unlocked -- matches the plaintext
    // predecessor's threat model (single-user device), just encrypted at rest
    // and mediated by the daemon instead of readable by anything that can open
    // the config file.
    request->setDeviceLockUnlockSemantic(SecretManager::DeviceLockKeepUnlocked);
    request->setAccessControlMode(SecretManager::OwnerOnlyMode);
    request->setUserInteractionMode(SecretManager::SystemInteraction);
    request->startRequest();
}

void Credentials::finishStore(bool ok, const QString &what, const QString &error)
{
    if (ok) {
        qDebug() << "Credentials: stored" << what;
    } else {
        m_saveFailed = true;
        setLastError(error);
        qWarning() << "Credentials: storing" << what << "failed:" << error;
    }

    if (m_pendingStores > 0) {
        --m_pendingStores;
    }
    if (m_pendingStores == 0) {
        setSaveBusy(false);
        setLastSaveOk(!m_saveFailed);
    }
}

void Credentials::setInternalUrl(const QString &internalUrl)
{
    if (m_internalUrl == internalUrl) {
        return;
    }
    m_internalUrl = internalUrl;
    Q_EMIT internalUrlChanged();
    updateEffectiveUrl();
}

void Credentials::setExternalUrl(const QString &externalUrl)
{
    if (m_externalUrl == externalUrl) {
        return;
    }
    m_externalUrl = externalUrl;
    Q_EMIT externalUrlChanged();
    if (m_externalUrl.isEmpty()) {
        setUsingExternal(false); // also updates the effective URL
    } else {
        updateEffectiveUrl();
    }
}

void Credentials::setUsingExternal(bool usingExternal)
{
    if (m_usingExternal != usingExternal) {
        m_usingExternal = usingExternal;
        qDebug() << "Credentials: now using the" << (usingExternal ? "external" : "internal") << "URL";
        Q_EMIT usingExternalChanged();
    }
    updateEffectiveUrl();
}

QString Credentials::computeEffectiveUrl() const
{
    return m_usingExternal && !m_externalUrl.isEmpty() ? m_externalUrl : m_internalUrl;
}

void Credentials::updateEffectiveUrl()
{
    const QString effective = computeEffectiveUrl();
    if (m_effectiveUrl == effective) {
        return;
    }
    m_effectiveUrl = effective;
    Q_EMIT baseUrlChanged();
}

void Credentials::setToken(const QString &token)
{
    if (m_token == token) {
        return;
    }
    m_token = token;
    Q_EMIT tokenChanged();
}

void Credentials::setLoaded(bool loaded)
{
    if (m_loaded == loaded) {
        return;
    }
    m_loaded = loaded;
    Q_EMIT loadedChanged();
}

void Credentials::setLastError(const QString &lastError)
{
    if (m_lastError == lastError) {
        return;
    }
    m_lastError = lastError;
    Q_EMIT lastErrorChanged();
}

void Credentials::setSaveBusy(bool saveBusy)
{
    if (m_saveBusy == saveBusy) {
        return;
    }
    m_saveBusy = saveBusy;
    Q_EMIT saveBusyChanged();
}

void Credentials::setLastSaveOk(bool lastSaveOk)
{
    if (m_lastSaveOk == lastSaveOk) {
        return;
    }
    m_lastSaveOk = lastSaveOk;
    Q_EMIT lastSaveOkChanged();
}
