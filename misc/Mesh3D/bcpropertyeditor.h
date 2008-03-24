#ifndef BCPROPERTYEDITOR_H
#define BCPROPERTYEDITOR_H

#define MAX_BCS 100000

#include <QWidget>

#include "ui_bcpropertyeditor.h"

class QTextEdit;
class QPushButton;
class QMenu;
class QTabWidget;

class bcProperty_t {
 public:
  bool defined;
  QString temperature;
  QString heatFlux;
  QString displacement1;
  QString displacement2;
  QString displacement3;
};

class BCPropertyEditor : public QDialog
{
  Q_OBJECT

public:
  BCPropertyEditor(QWidget *parent = 0);
  ~BCPropertyEditor();

  bcProperty_t bcProperty[MAX_BCS];

  bool bcEditActive;

  void editProperties(int);
  void updateActiveSheets();

  Ui::bcPropertyDialog ui;

  int bcIndex;
  int maxindex;

private slots:
  void temperatureChanged(const QString&);
  void heatFluxChanged(const QString&);
  void displacement1Changed(const QString&);
  void displacement2Changed(const QString&);
  void displacement3Changed(const QString&);

private:

};

#endif // BCPROPERTYEDITOR_H
