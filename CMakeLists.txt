cmake_minimum_required(VERSION 3.21)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

project(cachyos-pi
        VERSION 2.0.0
        LANGUAGES CXX)

include(GNUInstallDirs)
include(StandardProjectSettings)
include(CompilerWarnings)
include(EnableCcache)
include(Linker)
include(Sanitizers)

find_package(PkgConfig REQUIRED)
find_package(Qt6 6.10 REQUIRED COMPONENTS Core Gui Widgets Qml Quick QuickControls2 Network Concurrent LinguistTools)
find_package(AppStreamQt 1.0 REQUIRED)
pkg_check_modules(LIBALPM REQUIRED IMPORTED_TARGET libalpm>=15.0.0)

qt_standard_project_setup(REQUIRES 6.10 I18N_SOURCE_LANGUAGE en)
qt_policy(SET QTP0004 NEW)

include(CPM)
CPMAddPackage(
    NAME rapidyaml
    GITHUB_REPOSITORY biojppm/rapidyaml
    GIT_TAG v0.16.0
    EXCLUDE_FROM_ALL YES
)
CPMAddPackage(
    NAME fmt
    GITHUB_REPOSITORY fmtlib/fmt
    GIT_TAG 12.2.0
    EXCLUDE_FROM_ALL YES
)
CPMAddPackage(
    NAME spdlog
    GITHUB_REPOSITORY gabime/spdlog
    GIT_TAG v1.17.0
    EXCLUDE_FROM_ALL YES
)
# Only the header is used, its CMakeLists is too old for current CMake.
CPMAddPackage(
    NAME backward
    GITHUB_REPOSITORY bombela/backward-cpp
    GIT_TAG v1.6
    DOWNLOAD_ONLY YES
)

# supress fmt&spdlog warnings
set_target_properties(fmt spdlog PROPERTIES SYSTEM TRUE)

add_library(backward INTERFACE)
target_include_directories(backward SYSTEM INTERFACE "${backward_SOURCE_DIR}")
# With libdw, crash traces show file and line numbers instead of bare addresses.
pkg_check_modules(LIBDW IMPORTED_TARGET libdw)
if(LIBDW_FOUND)
    target_compile_definitions(backward INTERFACE BACKWARD_HAS_DW=1)
    target_link_libraries(backward INTERFACE PkgConfig::LIBDW)
else()
    message(STATUS "libdw not found: crash traces will lack file and line numbers")
endif()

add_library(project_options INTERFACE)
target_compile_features(project_options INTERFACE cxx_std_26)
target_compile_definitions(project_options INTERFACE QT_DISABLE_DEPRECATED_UP_TO=0x060A00)
configure_linker(project_options)
enable_sanitizers(project_options)

add_library(project_warnings INTERFACE)
set_project_warnings(project_warnings)

##
## Manjaro fork: a distribution build sets these, see cmake/Manjaro.cmake. Left empty,
## the build is upstream's.
##
set(PI_DISTRO_NAME "" CACHE STRING "Distribution name shown in place of CachyOS")
set(PI_APP_ID "" CACHE STRING "Program, desktop file and polkit name")
set(PI_LOGO_ICON "" CACHE STRING "Icon theme name of the distribution's logo")
set(PI_OWN_REPO_PREFIX "cachyos" CACHE STRING "Repositories shown as the distribution's own (empty: all)")
set(PI_RATE_MIRRORS "" CACHE STRING "Mirror ranking program run by the helper")
set(PI_RATE_MIRRORS_ARGV "" CACHE STRING "Its argv, a CMake list starting with argv[0]")
set(PI_PKGLIST "${CMAKE_CURRENT_SOURCE_DIR}/pkglist.yaml" CACHE FILEPATH "The start page's app list")
set(PI_DESKTOP_FILE "" CACHE FILEPATH "Desktop file installed in place of cachyos-pi.desktop")

if(PI_APP_ID)
    set(PI_HELPER_DIR "${CMAKE_INSTALL_FULL_LIBDIR}/${PI_APP_ID}")
    set(PI_HELPER_NAME "${PI_APP_ID}-helper")
else()
    set(PI_HELPER_DIR "${CMAKE_INSTALL_FULL_LIBDIR}/cachyos-pi")
    set(PI_HELPER_NAME cachyos-pi-helper)
endif()
set(PI_BRAND_DEFINITIONS PI_OWN_REPO_PREFIX="${PI_OWN_REPO_PREFIX}")
if(PI_DISTRO_NAME)
    list(APPEND PI_BRAND_DEFINITIONS PI_DISTRO_NAME="${PI_DISTRO_NAME}" PI_APP_ID="${PI_APP_ID}"
        PI_LOGO_ICON="${PI_LOGO_ICON}")
endif()
if(PI_RATE_MIRRORS)
    list(TRANSFORM PI_RATE_MIRRORS_ARGV PREPEND "\"" OUTPUT_VARIABLE argv)
    list(TRANSFORM argv APPEND "\"")
    list(JOIN argv "," argv)
    list(APPEND PI_BRAND_DEFINITIONS PI_RATE_MIRRORS="${PI_RATE_MIRRORS}" "PI_RATE_MIRRORS_ARGV=${argv}")
endif()

# import backend
if(BUILD_TESTING)
    include(CTest)
endif()
add_subdirectory(libpi)

##
## PKGBUILD scanner: text analysis only, shared by the GUI, the CLI and the tests.
##
add_library(pi-scan STATIC src/files.hpp src/pkgscan.hpp src/pkgscan.cpp src/gitoutput.hpp src/gitoutput.cpp)
target_include_directories(pi-scan PUBLIC src)
target_link_libraries(pi-scan PUBLIC Qt6::Core PRIVATE pi::pi project_options project_warnings)
# the GUI registers Finding, ScriptFile and DiffRun for QML
qt_extract_metatypes(pi-scan)

add_executable(cachyos-pi-scan src/scan/main.cpp)
target_compile_definitions(cachyos-pi-scan PRIVATE PI_VERSION="${PROJECT_VERSION}")
target_link_libraries(cachyos-pi-scan PRIVATE pi-scan project_options project_warnings backward)

##
## AppImage menu entries: text handling only, shared by the GUI and the tests.
##
add_library(pi-appimage STATIC src/appimagedesktop.hpp src/appimagedesktop.cpp
    src/appimagesource.hpp src/appimagesource.cpp
    src/appimageimport.hpp src/appimageimport.cpp)
target_include_directories(pi-appimage PUBLIC src)
target_link_libraries(pi-appimage PUBLIC Qt6::Core PRIVATE project_options project_warnings)

##
## GUI
##
qt_add_executable(${PROJECT_NAME}
    src/main.cpp src/files.hpp src/process.hpp src/qt_utils.hpp src/memory.hpp
    src/alpmdb.hpp src/alpmdb.cpp
    src/catalog.hpp src/catalog.cpp
    src/packagelist.hpp src/packagelist.cpp
    src/packagemodel.hpp src/packagemodel.cpp
    src/aurclient.hpp src/aurclient.cpp
    src/flatpakclient.hpp src/flatpakclient.cpp
    src/appimageclient.hpp src/appimageclient.cpp
    src/iconprovider.hpp src/iconprovider.cpp
    src/icontheme.hpp src/icontheme.cpp
    src/graphics.hpp src/graphics.cpp
    src/transaction.hpp src/transaction.cpp
    src/updatenotice.hpp src/updatenotice.cpp
    src/backend.hpp src/backend.cpp
    src/brand.hpp src/brand.cpp
    src/instance.hpp src/instance.cpp)

set(PI_QML_FILES
    qml/Main.qml
    qml/Look.qml
    qml/AppearanceSettings.qml
    qml/Glyph.qml
    qml/AppIcon.qml
    qml/AppCard.qml
    qml/PackageRow.qml
    qml/PillButton.qml
    qml/SourceBadge.qml
    qml/NavButton.qml
    qml/SearchField.qml
    qml/HomePage.qml
    qml/BrowsePage.qml
    qml/PageHeader.qml
    qml/PageList.qml
    qml/UpdatesBanner.qml
    qml/EmptyState.qml
    qml/DetailsPage.qml
    qml/ThemePreview.qml
    qml/DetailsHero.qml
    qml/ScreenshotStrip.qml
    qml/FactsCard.qml
    qml/UpdatesPage.qml
    qml/UpdateNoticeBox.qml
    qml/AurPage.qml
    qml/AurDetailsPage.qml
    qml/FlatpakPage.qml
    qml/FlatpakDetailsPage.qml
    qml/AppImagePage.qml
    qml/Toggle.qml
    qml/InfoItem.qml
    qml/WebLink.qml
    qml/SettingsPage.qml
    qml/CodeView.qml
    qml/WheelScroll.qml
    qml/PlainText.qml
    qml/Heading.qml
    qml/SectionTitle.qml
    qml/Muted.qml
    qml/Notice.qml
    qml/ScrollPage.qml
    qml/Card.qml
    qml/Pill.qml
    qml/Chip.qml
    qml/Dialog.qml
    qml/TransactionDialog.qml
    qml/SourceCard.qml
    qml/SettingCard.qml
)
# Serve the QML files from the module root. Left in qml/, each file would also see its
# siblings through the implicit directory import, which knows nothing about the qmldir
# (and so would treat the Look singleton as a plain type).
foreach(file IN LISTS PI_QML_FILES)
    get_filename_component(name "${file}" NAME)
    set_source_files_properties("${file}" PROPERTIES QT_RESOURCE_ALIAS "${name}")
endforeach()
# must precede qt_add_qml_module
set_source_files_properties(qml/Look.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
# Manjaro fork: another app list keeps the resource name the code loads
set_source_files_properties("${PI_PKGLIST}" PROPERTIES QT_RESOURCE_ALIAS pkglist.yaml)

qt_add_qml_module(${PROJECT_NAME}
    URI CachyOS.PackageInstaller
    VERSION 1.0
    QML_FILES ${PI_QML_FILES}
    RESOURCES
        ${PI_PKGLIST}
        icons/cachyos-pi.png
        icons/cachyos-kernel.png
        icons/cachyos-logo.png)

# glob over all translations in the folder
file(GLOB PI_TS_FILES CONFIGURE_DEPENDS i18n/cachyos-pi_*.ts)
list(REMOVE_ITEM PI_TS_FILES ${CMAKE_CURRENT_SOURCE_DIR}/i18n/cachyos-pi_en.ts)
qt_add_translations(TARGETS ${PROJECT_NAME} SOURCE_TARGETS ${PROJECT_NAME} pi-scan
    TS_FILES ${PI_TS_FILES} PLURALS_TS_FILE i18n/cachyos-pi_en.ts)

target_compile_definitions(${PROJECT_NAME} PRIVATE
    ${PI_BRAND_DEFINITIONS}
    PI_VERSION="${PROJECT_VERSION}"
    PI_HELPER_PATH="${PI_HELPER_DIR}/${PI_HELPER_NAME}")
target_include_directories(${PROJECT_NAME} PRIVATE src)
target_link_libraries(${PROJECT_NAME} PRIVATE
    project_options project_warnings pi::pi pi-scan pi-appimage
    Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Network Qt6::Concurrent
    AppStreamQt PkgConfig::LIBALPM ryml::ryml backward)

# The project warnings are for our own sources, not for the code qmlcachegen generates.
get_target_property(pi_sources ${PROJECT_NAME} SOURCES)
list(FILTER pi_sources INCLUDE REGEX "/\\.rcc/qmlcache/")
set_source_files_properties(${pi_sources} TARGET_DIRECTORY ${PROJECT_NAME} PROPERTIES COMPILE_OPTIONS "-w")

##
## Privileged helper: the only thing that runs as root (through pkexec).
##
add_executable(cachyos-pi-helper src/helper/main.cpp src/helper/shared.hpp)
target_link_libraries(cachyos-pi-helper PRIVATE pi::names project_options project_warnings)
target_compile_definitions(cachyos-pi-helper PRIVATE ${PI_BRAND_DEFINITIONS})

if(PI_APP_ID)
    set_target_properties(${PROJECT_NAME} PROPERTIES OUTPUT_NAME "${PI_APP_ID}")
    set_target_properties(cachyos-pi-scan PROPERTIES OUTPUT_NAME "${PI_APP_ID}-scan")
    set_target_properties(cachyos-pi-helper PROPERTIES OUTPUT_NAME "${PI_HELPER_NAME}")
endif()

##
## Install
##
configure_file(org.cachyos.cachyos-pi.policy.in org.cachyos.cachyos-pi.policy @ONLY)

install(TARGETS ${PROJECT_NAME} RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(TARGETS cachyos-pi-scan RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(TARGETS cachyos-pi-helper RUNTIME DESTINATION ${PI_HELPER_DIR})
if(PI_DISTRO_NAME)
    # Manjaro fork: own polkit ids, vendor and icon, the distribution's desktop file,
    # no CachyOS icon or AppStream entry.
    file(READ "${CMAKE_CURRENT_BINARY_DIR}/org.cachyos.cachyos-pi.policy" policy)
    string(REPLACE "org.cachyos.cachyos-pi." "org.${PI_APP_ID}." policy "${policy}")
    string(REPLACE "/cachyos-pi-helper<" "/${PI_HELPER_NAME}<" policy "${policy}")
    string(REPLACE "<vendor>CachyOS</vendor>" "<vendor>${PI_DISTRO_NAME}</vendor>" policy "${policy}")
    string(REPLACE "<icon_name>cachyos-pi</icon_name>" "<icon_name>${PI_LOGO_ICON}</icon_name>" policy "${policy}")
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/org.${PI_APP_ID}.policy" "${policy}")
    install(FILES "${CMAKE_CURRENT_BINARY_DIR}/org.${PI_APP_ID}.policy"
            DESTINATION ${CMAKE_INSTALL_DATADIR}/polkit-1/actions)
    configure_file("${PI_DESKTOP_FILE}" "${CMAKE_CURRENT_BINARY_DIR}/${PI_APP_ID}.desktop" @ONLY)
    install(FILES "${CMAKE_CURRENT_BINARY_DIR}/${PI_APP_ID}.desktop" DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
else()
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/org.cachyos.cachyos-pi.policy"
        DESTINATION ${CMAKE_INSTALL_DATADIR}/polkit-1/actions)
install(FILES cachyos-pi.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES org.cachyos.cachyos-pi.metainfo.xml DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)
install(FILES icons/cachyos-pi.png DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/256x256/apps)
endif()

##
## Tests
##
if(BUILD_TESTING)
    find_package(Qt6 6.10 REQUIRED COMPONENTS Test)
    qt_add_executable(test-pkgscan tests/test_pkgscan.cpp)
    target_compile_definitions(test-pkgscan PRIVATE TEST_DATA_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/data")
    target_link_libraries(test-pkgscan PRIVATE pi-scan project_options Qt6::Test)
    add_test(NAME pkgscan COMMAND test-pkgscan)

    qt_add_executable(test-gitoutput tests/test_gitoutput.cpp)
    target_link_libraries(test-gitoutput PRIVATE pi-scan project_options Qt6::Test)
    add_test(NAME gitoutput COMMAND test-gitoutput)

    qt_add_executable(test-pkglist tests/test_pkglist.cpp
        src/alpmdb.hpp src/alpmdb.cpp
        src/packagelist.hpp src/packagelist.cpp
        src/catalog.hpp src/catalog.cpp)
    target_compile_definitions(test-pkglist PRIVATE PKGLIST_FILE="${PI_PKGLIST}")
    target_include_directories(test-pkglist PRIVATE src)
    target_link_libraries(test-pkglist PRIVATE project_options project_warnings pi::pi
        Qt6::Test Qt6::Qml AppStreamQt PkgConfig::LIBALPM ryml::ryml)
    add_test(NAME pkglist COMMAND test-pkglist)

    qt_add_executable(test-packagemodel tests/test_packagemodel.cpp
        src/alpmdb.hpp src/alpmdb.cpp
        src/packagelist.hpp src/packagelist.cpp
        src/packagemodel.hpp src/packagemodel.cpp)
    target_include_directories(test-packagemodel PRIVATE src)
    target_link_libraries(test-packagemodel PRIVATE project_options project_warnings pi::pi
        Qt6::Test Qt6::Qml PkgConfig::LIBALPM)
    add_test(NAME packagemodel COMMAND test-packagemodel)

    qt_add_executable(test-packagefilter tests/test_packagefilter.cpp
        src/alpmdb.hpp src/alpmdb.cpp
        src/packagelist.hpp src/packagelist.cpp
        src/packagemodel.hpp src/packagemodel.cpp)
    target_include_directories(test-packagefilter PRIVATE src)
    target_link_libraries(test-packagefilter PRIVATE project_options project_warnings pi::pi
        Qt6::Test Qt6::Qml PkgConfig::LIBALPM)
    add_test(NAME packagefilter COMMAND test-packagefilter)

    qt_add_executable(test-updatenotice tests/test_updatenotice.cpp
        src/updatenotice.hpp src/updatenotice.cpp)
    target_compile_definitions(test-updatenotice PRIVATE PI_VERSION="${PROJECT_VERSION}")
    target_include_directories(test-updatenotice PRIVATE src)
    target_link_libraries(test-updatenotice PRIVATE project_options project_warnings
        Qt6::Test Qt6::Qml Qt6::Network)
    add_test(NAME updatenotice COMMAND test-updatenotice)

    add_executable(cachyos-pi-helper-test src/helper/main.cpp)
    target_compile_definitions(cachyos-pi-helper-test PRIVATE PI_HELPER_TESTING)
    target_link_libraries(cachyos-pi-helper-test PRIVATE pi::names project_options project_warnings)

    qt_add_executable(test-helper tests/test_helper.cpp)
    target_compile_definitions(test-helper PRIVATE
        TEST_DATA_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/data"
        HELPER="$<TARGET_FILE:cachyos-pi-helper-test>")
    target_link_libraries(test-helper PRIVATE project_options Qt6::Test)
    add_dependencies(test-helper cachyos-pi-helper-test)
    add_test(NAME helper COMMAND test-helper)

    qt_add_executable(test-appimage tests/test_appimage.cpp)
    target_link_libraries(test-appimage PRIVATE pi-appimage project_options Qt6::Test)
    add_test(NAME appimage COMMAND test-appimage)

    qt_add_executable(test-icontheme tests/test_icontheme.cpp src/icontheme.hpp src/icontheme.cpp)
    target_include_directories(test-icontheme PRIVATE src)
    target_link_libraries(test-icontheme PRIVATE project_options project_warnings Qt6::Test)
    add_test(NAME icontheme COMMAND test-icontheme)
endif()
