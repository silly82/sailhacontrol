#ifndef DEVICEINFO_H
#define DEVICEINFO_H

#include <QDir>
#include <QObject>
#include <QStorageInfo>

// Small helpers for the mobile_app device sensors that QML can't read on its
// own (see qml/components/DeviceStatusProbe.qml). Exposed to QML as the
// "DeviceInfo" context property.
class DeviceInfo : public QObject
{
    Q_OBJECT
public:
    explicit DeviceInfo(QObject *parent = nullptr) : QObject(parent) {}

    // Free space available to the user on the filesystem holding the home
    // directory, in GB (10^9 bytes, as phones/HA show it), rounded to one
    // decimal. -1 if it can't be determined.
    Q_INVOKABLE double freeStorageGb() const
    {
        QStorageInfo storage(QDir::homePath());
        if (!storage.isValid() || !storage.isReady()) {
            return -1;
        }
        const double gb = storage.bytesAvailable() / 1e9;
        return qRound(gb * 10.0) / 10.0;
    }
};

#endif // DEVICEINFO_H
