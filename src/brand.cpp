// SPDX-License-Identifier: GPL-3.0-or-later
// Manjaro fork: see brand.hpp.
#include "brand.hpp"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QHash>
#include <QIcon>
#include <QQmlAbstractUrlInterceptor>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QTranslator>

using namespace Qt::StringLiterals;

#ifndef PI_DISTRO_NAME
#define PI_DISTRO_NAME ""
#endif
#ifndef PI_APP_ID
#define PI_APP_ID ""
#endif
#ifndef PI_LOGO_ICON
#define PI_LOGO_ICON ""
#endif

namespace {

/// Texts that need more than the name changed, as they read in English.
const QHash<QString, QString>& wholeTexts() {
    static const QHash<QString, QString> texts{
        {u"CachyOS Package Installer"_s, u"Package Installer for %1"_s.arg(PI_DISTRO_NAME)},
        {u"Optimised packages from the CachyOS and Arch repositories, plus the AUR when you want it."_s,
         u"Packages from the %1 repositories, plus the AUR when you want it."_s.arg(PI_DISTRO_NAME)},
        {u"Blue-black with the colours of the CachyOS logo"_s, u"Blue-black with a teal accent"_s},
        {u"Build recipes written by the community. They are not reviewed by CachyOS, are built on your machine and can run any code while doing so, so read the PKGBUILD before installing."_s,
         u"Build recipes written by the community. They are not reviewed by %1, are built on your machine and can run any code while doing so, so read the PKGBUILD before installing. They are written for Arch Linux, which is often ahead of %1 stable, so some fail to build or to run."_s
             .arg(PI_DISTRO_NAME)},
        {u"Packages are downloaded from the first mirror that answers. Ranking measures the Arch and CachyOS mirrors from your connection and rewrites the mirror lists to prefer the fast ones. Worth doing when downloads are slow or fail."_s,
         u"Packages are downloaded from the first mirror that answers. Ranking measures the %1 mirrors from your connection and rewrites the mirror list to prefer the fast ones. Worth doing when downloads are slow or fail."_s
             .arg(PI_DISTRO_NAME)},
        {u"The download speed of the Arch and CachyOS mirrors will be measured and the mirror lists rewritten to prefer the fast ones. This takes a minute or two; a copy of the current lists is kept until the next ranking."_s,
         u"The download speed of the %1 mirrors will be measured and the mirror list rewritten to prefer the fast ones. This takes a minute or two."_s
             .arg(PI_DISTRO_NAME)},
        {u"Ranking needs the “cachyos-rate-mirrors” package, which is not installed."_s,
         u"Ranking needs the “pacman-mirrors” package, which is not installed."_s},
        {u"Install cachyos-rate-mirrors"_s, u"Install pacman-mirrors"_s},
        {u"Building AUR packages needs “paru”, which is not installed. You can still search and review packages."_s,
         u"Building AUR packages needs “paru”, which is not installed. It is not in the %1 repositories: open any AUR package and choose “Install paru” to build it from the AUR. You can still search and review packages."_s
             .arg(PI_DISTRO_NAME)},
    };
    return texts;
}

QString rebrand(const QString& text) {
    auto changed = text;
    // the tool first: its name contains the distribution's
    changed.replace("cachyos-rate-mirrors"_L1, "pacman-mirrors"_L1);
    return changed.replace("CachyOS"_L1, QLatin1StringView(PI_DISTRO_NAME));
}

/// Asks the app's translators, then rebrands what they give (or the English text).
class BrandTranslator final : public QTranslator {
 public:
    /// `inner` in the order Qt would ask them: the last installed first.
    explicit BrandTranslator(QList<QTranslator*> inner) : m_inner(std::move(inner)) {}

    QString translate(const char* context, const char* source, const char* disambiguation, int n) const override {
        const auto english = QString::fromUtf8(source);
        QString translated;
        for (const auto* inner : m_inner) {
            translated = inner->translate(context, source, disambiguation, n);
            if (!translated.isEmpty()) {
                break;
            }
        }
        // In English a few texts are rewritten as a whole; in another language the
        // translation is kept, with the names changed: better than English in between.
        if (translated.isEmpty() || translated == english) {
            if (const auto whole = wholeTexts().constFind(english); whole != wholeTexts().cend()) {
                return *whole;
            }
        }
        const auto text       = translated.isEmpty() ? english : translated;
        const auto branded    = rebrand(text);
        // nothing to change and nothing translated: let Qt fall back as usual
        return translated.isEmpty() && branded == text ? QString() : branded;
    }

    bool isEmpty() const override { return false; }

 private:
    QList<QTranslator*> m_inner;
};

/// The app's own pictures of the CachyOS logo.
bool isLogo(const QUrl& url) {
    const auto path = url.path();
    return path.endsWith("/icons/cachyos-pi.png"_L1) || path.endsWith("/icons/cachyos-logo.png"_L1);
}

class LogoInterceptor final : public QQmlAbstractUrlInterceptor {
 public:
    QUrl intercept(const QUrl& url, DataType type) override {
        return type == UrlString && isLogo(url) ? QUrl(u"image://brand/logo"_s) : url;
    }
};

/// The distribution's logo from the icon theme, drawn at the size asked for.
class LogoProvider final : public QQuickImageProvider {
 public:
    LogoProvider() : QQuickImageProvider(QQuickImageProvider::Pixmap) {}

    QPixmap requestPixmap(const QString& /*id*/, QSize* size, const QSize& requested) override {
        const QSize wanted = requested.isValid() && !requested.isEmpty() ? requested : QSize(256, 256);
        auto icon          = QIcon::fromTheme(QStringLiteral(PI_LOGO_ICON));
        if (icon.isNull()) {
            icon = QIcon::fromTheme(u"system-software-install"_s);
        }
        QPixmap pixmap = icon.isNull() ? QPixmap() : icon.pixmap(wanted);
        if (pixmap.isNull()) {
            pixmap = QPixmap(wanted);
            pixmap.fill(Qt::transparent);
        }
        if (size != nullptr) {
            *size = pixmap.size();
        }
        return pixmap;
    }
};

}  // namespace

namespace brand {

bool active() {
    return PI_DISTRO_NAME[0] != '\0';
}

void apply() {
    if (!active()) {
        return;
    }
    // the ones main() loaded, children of the application in the order installed
    QList<QTranslator*> loaded;
    for (auto* child : QCoreApplication::instance()->findChildren<QTranslator*>(Qt::FindDirectChildrenOnly)) {
        if (QCoreApplication::removeTranslator(child)) {
            loaded.prepend(child);
        }
    }
    static BrandTranslator translator(std::move(loaded));
    QCoreApplication::installTranslator(&translator);

    if (PI_APP_ID[0] != '\0') {
        QCoreApplication::setOrganizationName(QStringLiteral(PI_APP_ID));
        QCoreApplication::setApplicationName(QStringLiteral(PI_APP_ID));
        QGuiApplication::setDesktopFileName(QStringLiteral(PI_APP_ID));
    }
    if (PI_LOGO_ICON[0] != '\0') {
        QGuiApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral(PI_LOGO_ICON)));
    }
}

void applyToEngine(QQmlEngine& engine) {
    if (active() && PI_LOGO_ICON[0] != '\0') {
        static LogoInterceptor interceptor;
        engine.addUrlInterceptor(&interceptor);
        engine.addImageProvider(u"brand"_s, new LogoProvider);  // owned by the engine
    }
}

}  // namespace brand
