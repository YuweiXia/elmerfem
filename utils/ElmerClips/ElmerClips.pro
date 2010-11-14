TEMPLATE = app
TARGET = ElmerClips
DEPENDPATH += . src
INCLUDEPATH += . src

win32 {
   INCLUDEPATH += C:/Source/ffmpeg/include src/win32
   QMAKE_LIBDIR += C:/Source/ffmpeg/bin
   LIBS += -lavcodec -lavutil -lswscale
   DESTDIR = ElmerClips
}

CONFIG += release

HEADERS += src/preview.h src/encoder.h
SOURCES += src/main.cpp src/preview.cpp src/encoder.cpp
RESOURCES += ElmerClips.qrc
RC_FILE += ElmerClips.rc
