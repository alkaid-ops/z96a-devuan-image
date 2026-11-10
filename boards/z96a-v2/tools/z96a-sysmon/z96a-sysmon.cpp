#include "z96a-sysmon.h"

#include <QFile>
#include <QFontMetrics>
#include <QPainter>

#include <QTimer>
#include <QVBoxLayout>
#include <QElapsedTimer>
#include <QEnterEvent>
#include <algorithm>
#include <cmath>

namespace {
CpuSample readCpu() {
    CpuSample s;
    QFile f(QStringLiteral("/proc/stat"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return s;
    const QByteArray line = f.readLine();
    const QList<QByteArray> parts = line.simplified().split(' ');
    if (parts.size() < 5)
        return s;
    for (int i = 1; i < parts.size() && i <= 8; ++i) {
        bool ok = false;
        const qulonglong v = parts.at(i).toULongLong(&ok);
        if (!ok)
            continue;
        s.total += v;
        if (i == 4 || i == 5) // idle + iowait
            s.idle += v;
    }
    return s;
}

int readMemPercent() {
    QFile f(QStringLiteral("/proc/meminfo"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return 0;
    qulonglong total = 0;
    qulonglong available = 0;
    while (true) {
        const QByteArray line = f.readLine();
        if (line.isEmpty())
            break;
        if (line.startsWith("MemTotal:"))
            total = line.mid(9).trimmed().split(' ').first().toULongLong();
        else if (line.startsWith("MemAvailable:"))
            available = line.mid(13).trimmed().split(' ').first().toULongLong();
    }
    if (total == 0)
        return 0;
    return int(std::lround(100.0 * double(total - available) / double(total)));
}

NetSample readNet() {
    NetSample s;
    QFile f(QStringLiteral("/proc/net/dev"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return s;
    f.readLine();
    f.readLine();
    while (true) {
        const QByteArray line = f.readLine();
        if (line.isEmpty())
            break;
        const int colon = line.indexOf(':');
        if (colon < 0)
            continue;
        const QByteArray name = line.left(colon).trimmed();
        if (name == "lo")
            continue;
        const QList<QByteArray> fields = line.mid(colon + 1).simplified().split(' ');
        if (fields.size() < 9)
            continue;
        bool ok = false;
        const qulonglong rx = fields.at(0).toULongLong(&ok);
        if (!ok)
            continue;
        const qulonglong tx = fields.at(8).toULongLong(&ok);
        if (!ok)
            continue;
        s.rx += rx;
        s.tx += tx;
    }
    return s;
}

QString speedText(double bytesPerSecond) {
    const double v = std::max(0.0, bytesPerSecond);
    if (v >= 1024.0 * 1024 * 1024)
        return QString::number(v / (1024.0 * 1024 * 1024), 'f', v < 10.0 * 1024 * 1024 * 1024 ? 1 : 0) + QStringLiteral("G");
    if (v >= 1024.0 * 1024)
        return QString::number(v / (1024.0 * 1024), 'f', v < 10.0 * 1024 * 1024 ? 1 : 0) + QStringLiteral("M");
    if (v >= 1024.0)
        return QString::number(v / 1024.0, 'f', v < 10.0 * 1024 ? 1 : 0) + QStringLiteral("K");
    return QString::number(v, 'f', 0) + QStringLiteral("B");
}
} // namespace

SysMonWidget::SysMonWidget(QWidget *parent)
    : QWidget(parent) {
    QFont f = font();
    f.setStyleHint(QFont::Monospace);
    f.setFamily(QStringLiteral("Noto Sans Mono CJK SC"));
    f.setPixelSize(13);
    setFont(f);
    setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Preferred);
    setAttribute(Qt::WA_TranslucentBackground, true);

    const QFontMetrics fm(f);
    const int width = std::max(fm.horizontalAdvance(QStringLiteral("CPU 100%  MEM 100%")),
                               fm.horizontalAdvance(QStringLiteral("↑999.9M  ↓999.9M"))) + 8;
    setFixedWidth(width);

    m_cpu = readCpu();
    m_mem = readMemPercent();
    m_net = readNet();
    m_elapsed.start();

    m_timer = new QTimer(this);
    m_timer->setInterval(2000);
    connect(m_timer, &QTimer::timeout, this, &SysMonWidget::refresh);
    m_timer->start();
    updateGeometry();
}

QSize SysMonWidget::sizeHint() const {
    const QFontMetrics fm(font());
    return QSize(width(), fm.lineSpacing() * 2 + 2);
}

void SysMonWidget::refresh() {
    const CpuSample cpu = readCpu();
    const qulonglong dTotal = cpu.total - m_cpu.total;
    const qulonglong dIdle = cpu.idle - m_cpu.idle;
    m_cpu = cpu;
    if (dTotal > 0)
        m_cpuPercent = int(std::lround(100.0 * double(dTotal - dIdle) / double(dTotal)));
    m_cpuPercent = std::clamp(m_cpuPercent, 0, 100);

    m_mem = readMemPercent();

    const NetSample net = readNet();
    const qint64 elapsedMs = m_elapsed.restart();
    if (elapsedMs > 0) {
        const double seconds = elapsedMs / 1000.0;
        m_rxSpeed = double(net.rx - m_net.rx) / seconds;
        m_txSpeed = double(net.tx - m_net.tx) / seconds;
    }
    m_net = net;

    update();
}

void SysMonWidget::paintEvent(QPaintEvent *) {
    QPainter p(this);
    p.setRenderHint(QPainter::TextAntialiasing, true);

    p.setFont(font());
    p.setPen(palette().color(QPalette::WindowText));

    const QString line1 = QStringLiteral("CPU %1%  MEM %2%").arg(m_cpuPercent).arg(m_mem);
    const QString line2 = QStringLiteral("↑%1  ↓%2").arg(speedText(m_txSpeed), speedText(m_rxSpeed));
    const QFontMetrics fm(font());
    const int lineHeight = fm.lineSpacing();
    const int totalHeight = lineHeight * 2;
    const int top = (height() - totalHeight) / 2;
    p.drawText(QRect(0, top, width(), lineHeight), Qt::AlignCenter, line1);
    p.drawText(QRect(0, top + lineHeight, width(), lineHeight), Qt::AlignCenter, line2);
}

void SysMonWidget::enterEvent(QEnterEvent *) {
    setToolTip(QStringLiteral("CPU %1%\n内存 %2%\n上传 %3/s\n下载 %4/s")
                   .arg(m_cpuPercent)
                   .arg(m_mem)
                   .arg(speedText(m_txSpeed), speedText(m_rxSpeed)));
}

Z96ASysMonPlugin::Z96ASysMonPlugin(const ILXQtPanelPluginStartupInfo &startupInfo)
    : QObject(),
      ILXQtPanelPlugin(startupInfo) {
    mWidget = new SysMonWidget();
}

Z96ASysMonPlugin::~Z96ASysMonPlugin() {
    delete mWidget;
}

QWidget *Z96ASysMonPlugin::widget() {
    return mWidget;
}
