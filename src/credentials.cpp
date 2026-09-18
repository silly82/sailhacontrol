#include "credentials.h"

#include <QDebug>
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

Credentials::Credentials(QObject *parent)
    : QObject(parent)
    , m_loaded(false)
    , m_pendingStores(0)
    , m_saveBusy(false)
    , m_lastSaveOk(false)
    , m_saveFailed(false)
    , m_storagePluginName(SecretManager::DefaultStoragePluginName)
    , m_encryptionPluginName(SecretManager::DefaultEncryptionPluginName)
    , m_pluginsResolved(false)
{
    // Requests are useless without a manager: every one of them needs to know
    // which SecretManager (i.e. which connection to sailfishsecretsd) to use.
    m_baseUrlLoad.setManager(&m_manager);
    m_tokenLoad.setManager(&m_manager);
    m_baseUrlStore.setManager(&m_manager);
    m_tokenStore.setManager(&m_manager);
    m_baseUrlDelete.setManager(&m_manager);
    m_tokenDelete.setManager(&m_manager);
    m_pluginInfo.setManager(&m_manager);

    // System-mediated interaction, no in-app prompts: reading our own secrets
    // back must not require the user to unlock anything by hand.
    m_baseUrlLoad.setUserInteractionMode(SecretManager::SystemInteraction);
    m_tokenLoad.setUserInteractionMode(SecretManager::SystemInteraction);

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
            setBaseUrl(QString::fromUtf8(m_baseUrlLoad.secret().data()));
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
            setToken(QString::fromUtf8(m_tokenLoad.secret().data()));
        } else {
            qDebug() << "Credentials: token not loaded:" << result.errorMessage();
        }
        // Lengths only -- never the values themselves, the journal is readable
        // by more than just this app.
        qDebug() << "Credentials: loaded -- baseUrl" << m_baseUrl.length()
                 << "chars, token" << m_token.length() << "chars";
        setLoaded(true);
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

    resolvePlugins();
}

QString Credentials::baseUrl() const
{
    return m_baseUrl;
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

void Credentials::save(const QString &baseUrl, const QString &token)
{
    setLastError(QString());

    // The app must behave as before the moment Settings is filled in, so the
    // properties change right away; persistence happens in the background.
    setBaseUrl(baseUrl);
    setToken(token);

    // Two stores make one save; a delete may run before each of them, which is
    // why the batch is counted here and only closed by finishStore().
    m_saveFailed = false;
    m_pendingStores = 2;
    setSaveBusy(true);
    setLastSaveOk(false);

    deleteThenStore(&m_baseUrlDelete, &m_baseUrlStore, BaseUrlSecretName);
    deleteThenStore(&m_tokenDelete, &m_tokenStore, TokenSecretName);
}

void Credentials::reload()
{
    setLoaded(false);
    setBaseUrl(QString());
    setToken(QString());
    startLoading();
}

void Credentials::startLoading()
{
    m_baseUrlLoad.setIdentifier(
        Secret::Identifier(BaseUrlSecretName, QString(), m_storagePluginName));
    m_baseUrlLoad.startRequest();
}

void Credentials::startTokenLoad()
{
    m_tokenLoad.setIdentifier(
        Secret::Identifier(TokenSecretName, QString(), m_storagePluginName));
    m_tokenLoad.startRequest();
}

void Credentials::deleteThenStore(DeleteSecretRequest *request,
                                  StoreSecretRequest *storeRequest,
                                  const QString &name)
{
    // Connected once per request here; guarded so a second save() while a
    // delete is still in flight doesn't queue up duplicate handlers.
    if (!request->property("hacontrolConnected").toBool()) {
        request->setProperty("hacontrolConnected", true);
        connect(request, &DeleteSecretRequest::statusChanged, this,
                [this, request, storeRequest, name]() {
                    if (request->status() != Request::Finished) {
                        return;
                    }
                    // A delete of a secret that was never stored fails; that is
                    // expected on the first save and not worth reporting.
                    const Result result = request->result();
                    if (result.code() != Result::Succeeded) {
                        qDebug() << "Credentials: nothing to delete for" << name
                                 << "(" << result.errorMessage() << ")";
                    }
                    storeOne(storeRequest, name,
                             storeRequest == &m_baseUrlStore ? m_baseUrl : m_token);
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

void Credentials::setBaseUrl(const QString &baseUrl)
{
    if (m_baseUrl == baseUrl) {
        return;
    }
    m_baseUrl = baseUrl;
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
