#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QTimer>
#include <QWidget>

#include <ilxqtpanelplugin.h>

class QEnterEvent;

struct CpuSample {
    qulonglong total = 0;
    qulonglong idle = 0;
};

struct NetSample {
    qulonglong rx = 0;
    qulonglong tx = 0;
};

class SysMonWidget : public QWidget {
public:
    explicit SysMonWidget(QWidget *parent = nullptr);

    QSize sizeHint() const override;

protected:
    void paintEvent(QPaintEvent *event) override;
    void enterEvent(QEnterEvent *event) override;

private:
    void refresh();

    QTimer *m_timer = nullptr;
    QElapsedTimer m_elapsed;
    int m_cpuPercent = 0;
    int m_mem = 0;
    double m_rxSpeed = 0.0;
    double m_txSpeed = 0.0;
    CpuSample m_cpu;
    NetSample m_net;
};

class Z96ASysMonPlugin : public QObject, public ILXQtPanelPlugin {
    Q_OBJECT
public:
    explicit Z96ASysMonPlugin(const ILXQtPanelPluginStartupInfo &startupInfo);
    ~Z96ASysMonPlugin() override;

    Flags flags() const override { return PreferRightAlignment; }
    QWidget *widget() override;
    QString themeId() const override { return QStringLiteral("Z96ASysMon"); }
    bool isSeparate() const override { return true; }

private:
    SysMonWidget *mWidget = nullptr;
};

class Z96ASysMonPluginLibrary : public QObject, public ILXQtPanelPluginLibrary {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "lxqt.org/Panel/PluginInterface/3.0")
    Q_INTERFACES(ILXQtPanelPluginLibrary)
public:
    ILXQtPanelPlugin *instance(const ILXQtPanelPluginStartupInfo &startupInfo) const override {
        return new Z96ASysMonPlugin(startupInfo);
    }
};
