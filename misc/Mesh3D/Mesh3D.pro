######################################################################
# Automatically generated by qmake (2.01a) ti 26. helmi 20:19:48 2008
######################################################################

TEMPLATE = app
TARGET = 
DEPENDPATH += . forms
INCLUDEPATH += .

QT += opengl
LIBS += -lng -ldl

# Input
HEADERS += glwidget.h \
           helpers.h \
           mainwindow.h \
           meshcontrol.h \
           meshingthread.h \
           meshtype.h \
           sifwindow.h \
           tetgen.h
FORMS += forms/meshcontrol.ui
SOURCES += glwidget.cpp \
           helpers.cpp \
           main.cpp \
           mainwindow.cpp \
           meshcontrol.cpp \
           meshingthread.cpp \
           sifwindow.cpp
