#ifndef SIFGENERATOR_H
#define SIFGENERATOR_H

#include <QTextEdit>

#include "meshtype.h"
#include "generalsetup.h"
#include "pdepropertyeditor.h"
#include "matpropertyeditor.h"
#include "bodypropertyeditor.h"
#include "bcpropertyeditor.h"
#include "solverparameters.h"
#include "meshcontrol.h"
#include "dynamiceditor.h"

#define HEAT_EQUATION       0
#define LINEAR_ELASTICITY   1
#define NAVIER_STOKES       2
#define ADVECTION_DIFFUSION 3
#define HELMHOLTZ_EQUATION  4


#define MAX_MATERIALS 10

class SifGenerator  {
 public:
  SifGenerator();
  ~SifGenerator();

  mesh_t *mesh;
  QTextEdit *te;
  GeneralSetup *generalSetup;
  PDEPropertyEditor *pdePropertyEditor;
  DynamicEditor *matPropertyEditor;
  BodyPropertyEditor *bodyPropertyEditor;
  BCPropertyEditor *bcPropertyEditor;
  MeshControl *meshControl;
  int cdim;

  void makeHeaderBlock();
  void makeSimulationBlock();
  void makeConstantsBlock();
  void makeBodyBlocks();
  void makeEquationBlocks();
  void makeSolverBlocks();
  void makeMaterialBlocks();
  void makeBodyForceBlocks();
  void makeBoundaryBlocks();

 private:
  void parseProcedure(Ui::solverParameterEditor);
  void parseGeneralTab(Ui::solverParameterEditor);
  void parseSteadyStateTab(Ui::solverParameterEditor);
  void parseNonlinearSystemTab(Ui::solverParameterEditor);
  void parseLinearSystemTab(Ui::solverParameterEditor);

  void addSifLine(const QString&, const QString&);
  void addSifLineBool(const QString&, bool);

  void handleLineEdit(QDomElement, QWidget*);
  void handleComboBox(QDomElement, QWidget*);
  void handleCheckBox(QDomElement, QWidget*);
};

#endif // SIFGENERATOR_H
