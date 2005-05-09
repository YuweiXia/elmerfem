!/******************************************************************************
! *
! *       ELMER, A Computational Fluid Dynamics Program.
! *
! *       Copyright 1st April 1995 - , Center for Scientific Computing,
! *                                    Finland.
! *
! *       All rights reserved. No part of this program may be used,
! *       reproduced or transmitted in any form or by any means
! *       without the written permission of CSC.
! *
! *****************************************************************************/
!
!/******************************************************************************
! *
! * Poisson equation solver using the boundary element method.
! *
! ******************************************************************************
! *
! *                     Author:       Juha Ruokolainen
! *
! *                    Address: Center for Scientific Computing
! *                                Tietotie 6, P.O. BOX 405
! *                                  02101 Espoo, Finland
! *                                  Tel. +358 0 457 2723
! *                                Telefax: +358 0 457 2302
! *                              EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date: 2002
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! *****************************************************************************/

!------------------------------------------------------------------------------
   MODULE GlobMat
!------------------------------------------------------------------------------
      USE Types
      REAL(KIND=dp), POINTER :: Matrix(:,:)
!------------------------------------------------------------------------------
   END MODULE GlobMat
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE PoissonBEMSolver( Model,Solver,dt,TransientSimulation )
   !DEC$ATTRIBUTES DLLEXPORT :: PoissonBEMSolver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the Poisson equation using BEM!
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear equation solver options
!
!  REAL(KIND=dp) :: dt,
!     INPUT: Timestep size for time dependent simulations
!
!  LOGICAL :: TransientSimulation
!     INPUT: Steady state or transient simulation
!
!******************************************************************************
     USE GlobMat

     USE DefUtils

     IMPLICIT NONE
!------------------------------------------------------------------------------
 
     TYPE(Model_t) :: Model
     TYPE(Solver_t):: Solver
 
     REAL(KIND=dp) :: dt
     LOGICAL :: TransientSimulation
 
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     INTEGER :: i,j,k,n,t,istat,bf_id,BoundaryNodes
 
     TYPE(Matrix_t),POINTER  :: StiffMatrix
     TYPE(Nodes_t)   :: ElementNodes
     TYPE(Element_t),POINTER :: CurrentElement
 
     REAL(KIND=dp) :: Norm,PrevNorm
     INTEGER, POINTER :: NodeIndexes(:)

     LOGICAL :: AllocationsDone = .FALSE., GotIt
 
     REAL(KIND=dp), POINTER :: Potential(:),ForceVector(:), &
                VolumeSource(:), Diagonal(:)
     INTEGER, POINTER :: PotentialPerm(:), BoundaryPerm(:)

     LOGICAL, ALLOCATABLE :: PotentialKnown(:)
 
     REAL(KIND=dp), ALLOCATABLE ::  Flx(:), Pot(:), VolumeForce(:), &
       LocalMassMatrix(:,:),LocalStiffMatrix(:,:),Load(:),LocalForce(:)
 
     REAL(KIND=dp) :: at,st,CPUTime,s
     TYPE(Variable_t), POINTER :: Var

     CHARACTER(LEN=MAX_NAME_LEN) :: EquationName

     SAVE Load, ElementNodes, VolumeSource, VolumeForce, AllocationsDone, &
      PotentialKnown, PotentialPerm, BoundaryPerm, BoundaryNodes, Pot, Flx
!------------------------------------------------------------------------------
     CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: PoissonBEM.f90,v 1.1.1.1 2005/04/21 13:29:02 vierinen Exp $"

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
        IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
           CALL Info( 'PoissonBEM', 'PoissonBEM Solver version:', Level = 0 ) 
           CALL Info( 'PoissonBEM', VersionID, Level = 0 ) 
           CALL Info( 'PoissonBEM', ' ', Level = 0 ) 
        END IF
     END IF

 
!------------------------------------------------------------------------------
!    Get variables needed for solution
!------------------------------------------------------------------------------
     Potential   => Solver % Variable % Values

     StiffMatrix => Solver % Matrix
     ForceVector => StiffMatrix % RHS
     Norm = Solver % Variable % Norm

     IF ( .NOT. AllocationsDone ) THEN
!------------------------------------------------------------------------------
!       Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
!
!       Get permutation of mesh nodes, so that boundary nodes get
!       numbered from 1..nb:
!       ---------------------------------------------------------
        ALLOCATE( PotentialPerm(Solver % Mesh % NumberOfNodes), &
                   BoundaryPerm(Solver % Mesh % NumberOfNodes), STAT=istat)

        IF ( istat /= 0 ) THEN
           CALL Fatal( 'PoissonBEMSolver', 'Memory allocation error 1.' )
        END IF

        PotentialPerm = 0
        BoundaryPerm  = 0
        BoundaryNodes = 0

        DO t=1,Solver % NumberOFActiveElements
           CurrentElement => Solver % Mesh % Elements( Solver % ActiveElements(t) )

           IF ( CurrentElement % Type % ElementCode == 101 ) CYCLE
           IF ( .NOT. ASSOCIATED( CurrentElement % BoundaryInfo ) ) CYCLE

           DO j=1,CurrentElement % Type % NumberOfNodes
              k = CurrentElement % NodeIndexes(j)
              IF ( PotentialPerm(k) == 0 ) THEN
                 BoundaryNodes = BoundaryNodes + 1
                 BoundaryPerm(BoundaryNodes) = k
                 PotentialPerm(k) = BoundaryNodes
              END IF
           END DO
        END DO

        N = Model % MaxElementNodes
 
        ALLOCATE( ElementNodes % x( N ),                  &
                  ElementNodes % y( N ),                  &
                  ElementNodes % z( N ),                  &
                  VolumeSource( N ),                      &
                  Flx( BoundaryNodes ),                   &
                  Pot( BoundaryNodes ),                   &
                  Load( BoundaryNodes ),                  &
                  Diagonal( BoundaryNodes ),              &
                  PotentialKnown( BoundaryNodes ),        &
                  Matrix( BoundaryNodes, BoundaryNodes ), &
                  VolumeForce( Solver % Mesh % NumberOfNodes ), STAT=istat )

        IF ( istat /= 0 ) THEN
           CALL Fatal( 'PoissonBEMSolver', 'Memory allocation error 2.' )
        END IF
 
        AllocationsDone = .TRUE.
     END IF

!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------
at = CPUTime()
     EquationName = ListGetString( Model % Solver % Values, 'Equation' )

     Matrix      = 0.0d0
     Load        = 0.0d0
     Diagonal    = 0.0d0
     ForceVector = 0.0d0
!------------------------------------------------------------------------------
!    Check the bndry conditions. For each node either flux or potential must be
!    given and the other is the unknown! After the  loop a logical variable
!    PotentialKnown will be true if flux is the unknown and false if potential
!    is the unknown for each node. Also vector Load will contain the known value
!    for each node. Matrix and RHS are also initialized with the 0th order
!    potential term:
!------------------------------------------------------------------------------
     DO t=1,Solver % NumberOfActiveElements

       CurrentElement => Solver % Mesh % Elements( Solver % ActiveElements(t) )
       IF ( .NOT. ASSOCIATED( CurrentElement % BoundaryInfo ) )  CYCLE
       IF ( CurrentElement % Type % ElementCode == 101 ) CYCLE

       n = CurrentElement % Type % NumberOfNodes
       NodeIndexes => CurrentElement % NodeIndexes

       DO i=1,Model % NumberOfBCs
          IF ( CurrentElement % BoundaryInfo % Constraint /= Model % BCs(i) % Tag ) CYCLE

          Load(PotentialPerm(NodeIndexes)) = ListGetReal( Model % BCs(i) % Values, &
                             'Potential' , n, NodeIndexes, GotIt )

          IF ( .NOT. GotIt ) THEN
             Load(PotentialPerm(NodeIndexes)) = ListGetReal( Model % BCs(i) % Values, &
                  TRIM(Solver % Variable % Name) , n, NodeIndexes, GotIt )
          END IF

          IF ( .NOT. GotIt ) THEN
             PotentialKnown( PotentialPerm(NodeIndexes) ) = .FALSE.

             Load(PotentialPerm(NodeIndexes)) = ListGetReal(  &
                Model % BCs(i) % Values, 'Flux', n, NodeIndexes, GotIt )
          ELSE
             PotentialKnown( PotentialPerm(NodeIndexes) ) = .TRUE.
          END IF
 
          EXIT
        END DO
     END DO

!------------------------------------------------------------------------------

!
!    Check for volume source, volume must be meshed if you want this:
!    ----------------------------------------------------------------
     VolumeForce = 0.0d0
     DO i=1,Solver % NumberOfActiveElements
!------------------------------------------------------------------------------
        CurrentElement => Solver % Mesh % Elements( Solver % ActiveElements(i) )
        IF ( ASSOCIATED( CurrentElement % BoundaryInfo ) ) CYCLE

        n = CurrentElement % Type % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes

        k = ListGetInteger( Model % Bodies( &
              CurrentElement % BodyId) % Values, 'Body Force', GotIt )
        IF ( .NOT. GotIt ) EXIT

        VolumeSource(1:n) = ListGetReal( Model % BodyForces(k) % Values, &
                     'Source', n, NodeIndexes, GotIt ) 
        IF ( .NOT. GotIt ) EXIT
 
        ElementNodes % x(1:n) = Solver % Mesh % Nodes % x( NodeIndexes )
        ElementNodes % y(1:n) = Solver % Mesh % Nodes % y( NodeIndexes )
        ElementNodes % z(1:n) = Solver % Mesh % Nodes % z( NodeIndexes )

        CALL IntegrateSource( VolumeSource, VolumeForce, &
               CurrentElement, n, ElementNodes )
     END DO


     DO i=1,BoundaryNodes
        ForceVector(i) = ForceVector(i) + VolumeForce(BoundaryPerm(i))
     END DO
!------------------------------------------------------------------------------

!
!    Matrix assembly:
!    ----------------
     DO t=1,Solver % NumberOfActiveElements
        CurrentElement => Solver % Mesh % Elements( Solver % ActiveElements(t) )
        IF ( .NOT. ASSOCIATED( CurrentElement % BoundaryInfo ) ) CYCLE
        IF ( CurrentElement % Type % ElementCode == 101 ) CYCLE

        n = CurrentElement % Type % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes
 
        ElementNodes % x(1:n) = Solver % Mesh % Nodes % x( NodeIndexes )
        ElementNodes % y(1:n) = Solver % Mesh % Nodes % y( NodeIndexes )
        ElementNodes % z(1:n) = Solver % Mesh % Nodes % z( NodeIndexes )

        CALL IntegrateMatrix( Matrix, ForceVector, Load, &
           PotentialKnown, CurrentElement, n, ElementNodes )
     END DO

     DO i=1,BoundaryNodes
        IF ( PotentialKnown(i) ) THEN
           ForceVector(i) = ForceVector(i) - Load(i) * Diagonal(i)
        ELSE
           Matrix(i,i) = Diagonal(i)
        END IF
     END DO
!------------------------------------------------------------------------------

     at = CPUTime() - at
     PRINT*,'Assembly (s): ',at

!------------------------------------------------------------------------------
!    Solve the system and we are done.
!------------------------------------------------------------------------------
     st = CPUTime()
!
!    Solve system:
     !    -------------
     CALL SolveFull( BoundaryNodes, Matrix, Potential, ForceVector, Solver )
!
!    extract potential and fluxes for the boundary nodes:
!    ----------------------------------------------------
     DO i=1,BoundaryNodes
        IF ( PotentialKnown(i) ) THEN
           Flx(i) = Potential(i)
           Pot(i) = Load(i)
        ELSE
           Flx(i) = Load(i)
           Pot(i) = Potential(i)
        END IF
     END DO
!
!    now compute potential for all mesh points:
!    ------------------------------------------
     Potential = VolumeForce
     DO i=1,BoundaryNodes
        k = Solver % Variable % Perm( BoundaryPerm(i) )
        Potential(k) = Pot(i)
     END DO

     Var => VariableGet( Solver % Mesh % Variables, 'Flux' )
     IF ( ASSOCIATED( Var ) ) THEN
        Var % Values = 0.0d0
        DO i=1,BoundaryNodes
           k = Var % Perm( BoundaryPerm(i) )
           Var % Values(k) = Flx(i)
        END DO
     END IF

     DO t=1,Solver % NumberOfActiveElements
        CurrentElement => Solver % Mesh % Elements( Solver % ActiveElements(t) )
        IF ( .NOT. ASSOCIATED( CurrentElement % BoundaryInfo ) ) CYCLE

        n = CurrentElement % Type % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes

        ElementNodes % x(1:n) = Solver % Mesh % Nodes % x( NodeIndexes )
        ElementNodes % y(1:n) = Solver % Mesh % Nodes % y( NodeIndexes )
        ElementNodes % z(1:n) = Solver % Mesh % Nodes % z( NodeIndexes )

        CALL ComputePotential( Potential, Pot, Flx, CurrentElement, n, ElementNodes )
     END DO
!
!    All done, finalize:
!    -------------------
     Solver % Variable % Norm = SQRT( SUM( Potential**2 ) / COUNT( Solver % Variable % Perm > 0 ) )

     CALL InvalidateVariable( Model % Meshes, &
                  Solver % Mesh, Solver % Variable % Name )
!------------------------------------------------------------------------------
     st = CPUTime() - st
     PRINT*,'Solve (s):    ',st
!------------------------------------------------------------------------------
 
   CONTAINS

!------------------------------------------------------------------------------
     SUBROUTINE IntegrateSource( Source, Force, Element, n, Nodes )
!------------------------------------------------------------------------------
       INTEGER :: n
       REAL(KIND=dp) :: Source(n), Force(:)
       TYPE(Nodes_t) :: Nodes
       TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
       LOGICAL :: Stat
       REAL(KIND=dp) :: SqrtElementMetric,U,V,W,S,A,L,LX,LY,LZ,x,y,z,R

       INTEGER :: i,j,k,p,q,t,dim
 
       TYPE(GaussIntegrationPoints_t) :: IntegStuff
!------------------------------------------------------------------------------
       dim = CoordinateSystemDimension()
!------------------------------------------------------------------------------
!      Numerical integration
!------------------------------------------------------------------------------
       IntegStuff = GaussPoints( Element )

       DO t=1,IntegStuff % n
          U = IntegStuff % u(t)
          V = IntegStuff % v(t)
          W = IntegStuff % w(t)
          S = IntegStuff % s(t)
!------------------------------------------------------------------------------
!         Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
          stat = ElementInfo( Element, Nodes, U, V, W, SqrtElementMetric, &
                      Basis, dBasisdx, ddBasisddx, .FALSE. )
 
          S = S * SqrtElementMetric

          LX = SUM( Nodes % x(1:n) * Basis )
          LY = SUM( Nodes % y(1:n) * Basis )
          LZ = SUM( Nodes % z(1:n) * Basis )

          DO p=1,Solver % Mesh % NumberOfNodes
             x = LX - Solver % Mesh % Nodes % x(p)
             y = LY - Solver % Mesh % Nodes % y(p)
             z = LZ - Solver % Mesh % Nodes % z(p)

             R = SQRT( x**2 + y**2 + z**2 )
             SELECT CASE(dim)
             CASE(2)
                W = -LOG(R) / (2*PI)
             CASE(3)
                W = (1 / R) / (4*PI)
             END SELECT

             DO i=1,N
                Force(p) = Force(p) + s * Source(i) * Basis(i) * W
             END DO
          END DO
       END DO
!------------------------------------------------------------------------------
     END SUBROUTINE IntegrateSource
!------------------------------------------------------------------------------
 

!------------------------------------------------------------------------------
     SUBROUTINE IntegrateMatrix( StiffMatrix, Force, Load, &
               PotentialKnown, Element, n, Nodes )
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: StiffMatrix(:,:),Force(:),Load(:)
       INTEGER :: n
       LOGICAL :: PotentialKnown(:)
       TYPE(Nodes_t) :: Nodes
       TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
       REAL(KIND=dp) :: R,LX,LY,LZ,x,y,z,dWdN
       LOGICAL :: Stat, CheckNormals
       REAL(KIND=dp) :: SqrtElementMetric,U,V,W,S,A,L,gradW(3),Normal(3)

       INTEGER :: i,j,k,p,q,t,dim
 
       TYPE(GaussIntegrationPoints_t) :: IntegStuff
!------------------------------------------------------------------------------
       dim = CoordinateSystemDimension()
!------------------------------------------------------------------------------
!      Numerical integration
!------------------------------------------------------------------------------
       SELECT CASE( Element % Type % ElementCode / 100 )
       CASE(2)
          IntegStuff = GaussPoints( Element,4 )
       CASE(3)
          IntegStuff = GaussPoints( Element,6 )
       CASE(4)
          IntegStuff = GaussPoints( Element,16 )
       END SELECT

       CheckNormals = ASSOCIATED( Element % BoundaryInfo )
       IF ( CheckNormals ) THEN
          CheckNormals = ASSOCIATED( Element % BoundaryInfo % Left  ) .OR. &
                         ASSOCIATED( Element % BoundaryInfo % Right )
       END IF

       DO t=1,IntegStuff % n
          U = IntegStuff % u(t)
          V = IntegStuff % v(t)
          W = IntegStuff % w(t)
          S = IntegStuff % s(t)
!------------------------------------------------------------------------------
!         Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
          stat = ElementInfo( Element, Nodes, U, V, W, SqrtElementMetric, &
                      Basis, dBasisdx, ddBasisddx, .FALSE. )
 
          S = S * SqrtElementMetric
          Normal = NormalVector( Element, Nodes, u,v, CheckNormals )

          LX = SUM( Nodes % x(1:n) * Basis )
          LY = SUM( Nodes % y(1:n) * Basis )
          LZ = SUM( Nodes % z(1:n) * Basis )

          DO p=1,BoundaryNodes
             k = BoundaryPerm(p)

             x = LX - Solver % Mesh % Nodes % x(k)
             y = LY - Solver % Mesh % Nodes % y(k)
             z = LZ - Solver % Mesh % Nodes % z(k)

             R = SQRT( x**2 + y**2 + z**2 )

             SELECT CASE(dim)
             CASE(2)
                W = -LOG(R) / (2*PI)
                GradW(1) = -x / (2*PI*R**2)
                GradW(2) = -y / (2*PI*R**2)
                GradW(3) = -z / (2*PI*R**2)
             CASE(3)
                W = (1 / R) / (4*PI)
                GradW(1) = -x / (4*PI*R**3)
                GradW(2) = -y / (4*PI*R**3)
                GradW(3) = -z / (4*PI*R**3)
             END SELECT

             dWdN = SUM( GradW * Normal )

             DO i=1,N
                q = PotentialPerm( Element % NodeIndexes(i) )

                IF ( PotentialKnown(q) ) THEN
                   IF ( p /= q ) THEN
                      Force(p) = Force(p) - s * Load(q) * Basis(i) * dWdN
                   END IF
                   StiffMatrix(p,q) = StiffMatrix(p,q) - s * Basis(i) * W
                ELSE
                   Force(p) = Force(p) + s * Load(q) * Basis(i) * W
                   IF ( p /= q ) THEN
                      StiffMatrix(p,q) = StiffMatrix(p,q) + s * Basis(i) * dWdN
                   END IF
                END IF

                IF ( p /= q ) THEN
                   Diagonal(p) = Diagonal(p) - s * Basis(i) * dWdN
                END IF

             END DO
          END DO
        END DO
!------------------------------------------------------------------------------
     END SUBROUTINE IntegrateMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
     SUBROUTINE ComputePotential( Potential, Pot, Flx, Element, n, Nodes )
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: Pot(:), Flx(:), Potential(:)
       INTEGER :: n
       TYPE(Nodes_t) :: Nodes
       TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
       REAL(KIND=dp) :: R,LX,LY,LZ,x,y,z,dWdN,LPOT,LFLX
       LOGICAL :: Stat, CheckNormals
       REAL(KIND=dp) :: SqrtElementMetric,U,V,W,S,A,L,gradW(3),Normal(3),ss

       INTEGER :: i,j,k,p,q,t,dim
 
       TYPE(GaussIntegrationPoints_t) :: IntegStuff
!------------------------------------------------------------------------------
       dim = CoordinateSystemDimension()
!------------------------------------------------------------------------------
!      Numerical integration
!------------------------------------------------------------------------------
       SELECT CASE( Element % Type % ElementCode / 100 )
       CASE(2)
          IntegStuff = GaussPoints( Element,4 )
       CASE(3)
          IntegStuff = GaussPoints( Element,6 )
       CASE(4)
          IntegStuff = GaussPoints( Element,16 )
       END SELECT

       CheckNormals = ASSOCIATED( Element % BoundaryInfo )
       IF ( CheckNormals ) THEN
          CheckNormals = ASSOCIATED( Element % BoundaryInfo % Left  ) .OR. &
                         ASSOCIATED( Element % BoundaryInfo % Right )
       END IF

       DO t=1,IntegStuff % n
         U = IntegStuff % u(t)
         V = IntegStuff % v(t)
         W = IntegStuff % w(t)
         S = IntegStuff % s(t)
!------------------------------------------------------------------------------
!        Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
         stat = ElementInfo( Element, Nodes, U, V, W, SqrtElementMetric, &
                     Basis, dBasisdx, ddBasisddx, .FALSE. )
 
         S = S * SqrtElementMetric
         Normal = NormalVector( Element, Nodes, u,v, CheckNormals )

         LX = SUM( Nodes % x(1:n) * Basis )
         LY = SUM( Nodes % y(1:n) * Basis )
         LZ = SUM( Nodes % z(1:n) * Basis )

         DO i=1,Solver % Mesh % NumberOfNodes
            k = Solver % Variable % Perm(i)
            IF ( k <= 0 ) CYCLE

            IF ( PotentialPerm(i) > 0 ) CYCLE

            x = LX - Solver % Mesh % Nodes % x(i)
            y = LY - Solver % Mesh % Nodes % y(i)
            z = LZ - Solver % Mesh % Nodes % z(i)

            R = SQRT( x**2 + y**2 + z**2 )

            SELECT CASE(dim)
            CASE(2)
               W = -LOG(R) / (2*PI)
               GradW(1) = -x / (2*PI*R**2)
               GradW(2) = -y / (2*PI*R**2)
               GradW(3) = -z / (2*PI*R**2)
            CASE(3)
               W = (1 / R) / (4*PI)
               GradW(1) = -x / (4*PI*R**3)
               GradW(2) = -y / (4*PI*R**3)
               GradW(3) = -z / (4*PI*R**3)
            END SELECT
            dWdN = SUM( GradW * Normal )

            DO j=1,n
               q = PotentialPerm( Element % NodeIndexes(j) )
               Potential(k) = Potential(k) - s * Basis(j) * &
                    ( Pot(q) * dWdN - Flx(q) * W )
            END DO
         END DO
!------------------------------------------------------------------------------
       END DO
!------------------------------------------------------------------------------
     END SUBROUTINE ComputePotential
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
     SUBROUTINE SolveFull( N,A,x,b,Solver )
!------------------------------------------------------------------------------
       TYPE(Solver_t) :: Solver
!------------------------------------------------------------------------------
       INTERFACE SolveLapack
          SUBROUTINE SolveLapack( N,A,x )
             INTEGER N
             DOUBLE PRECISION a(n*n), x(n)
          END SUBROUTINE SolveLapack
       END INTERFACE
!------------------------------------------------------------------------------
       INTEGER ::  N
       REAL(KIND=dp) ::  A(n*n),x(n),b(n)
!------------------------------------------------------------------------------
       SELECT CASE( ListGetString( Solver % Values, 'Linear System Solver' ) )

       CASE( 'direct' )
          CALL SolveLapack( N, A, b )
          x(1:n) = b(1:n)

       CASE( 'iterative' )
          CALL FullIterSolver( N, x, b, Solver )

       CASE DEFAULT
          CALL Fatal( 'SolveFull', 'Unknown solver type.' )

       END SELECT
!------------------------------------------------------------------------------
     END SUBROUTINE SolveFull
!------------------------------------------------------------------------------


#include <huti_fdefs.h>
!------------------------------------------------------------------------------
     SUBROUTINE FullIterSolver( N,x,b,SolverParam )
!------------------------------------------------------------------------------
       IMPLICIT NONE
!------------------------------------------------------------------------------
       TYPE(Solver_t) :: SolverParam
       INTEGER :: N
       REAL(KIND=dp), DIMENSION(:) :: x,b
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: dpar(50)

       INTEGER :: ipar(50),wsize
       REAL(KIND=dp), ALLOCATABLE :: work(:,:)

       EXTERNAL Matvec, Precond
       LOGICAL :: AbortNotConverged
!------------------------------------------------------------------------------
       ipar = 0; dpar = 0

       HUTI_WRKDIM = HUTI_CGS_WORKSIZE
       wsize = HUTI_WRKDIM
       HUTI_NDIM = N
       ALLOCATE( work(wsize,N) )

       IF ( ALL(x == 0.0) ) THEN
          HUTI_INITIALX = HUTI_RANDOMX
       ELSE
          HUTI_INITIALX = HUTI_USERSUPPLIEDX
       END IF

       HUTI_TOLERANCE = ListGetConstReal( Solver % Values, &
            'Linear System Convergence Tolerance' )

       HUTI_MAXIT = ListGetInteger( Solver % Values, &
            'Linear System Max Iterations' )

       HUTI_DBUGLVL  = ListGetInteger( SolverParam % Values, &
            'Linear System Residual Output', GotIt )

       IF ( .NOT.Gotit ) HUTI_DBUGLVL = 1

       AbortNotConverged = ListGetLogical( SolverParam % Values, &
            'Linear System Abort Not Converged', GotIt )
       IF ( .NOT. GotIt ) AbortNotConverged = .TRUE.

!------------------------------------------------------------------------------
       CALL HUTI_D_CGS( x,b,ipar,dpar,work,matvec,precond,0,0,0,0 )
!------------------------------------------------------------------------------

       DEALLOCATE( work )

       IF ( HUTI_INFO /= HUTI_CONVERGENCE ) THEN
          IF ( AbortNotConverged ) THEN
             CALL Fatal( 'IterSolve', 'Failed convergence tolerances.' )
          ELSE
             CALL Error( 'IterSolve', 'Failed convergence tolerances.' )
          END IF
       END IF
!------------------------------------------------------------------------------
     END SUBROUTINE FullIterSolver 
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   END SUBROUTINE PoissonBEMSolver
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE Precond( u,v,ipar )
!------------------------------------------------------------------------------
     USE GlobMat
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: u(*),v(*)
     INTEGER :: ipar(*)
!------------------------------------------------------------------------------
     DO i=1,HUTI_NDIM
        u(i) = v(i) / Matrix(i,i)
     END DO
!------------------------------------------------------------------------------
   END SUBROUTINE Precond
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE Matvec( u,v,ipar )
!------------------------------------------------------------------------------
     USE GlobMat
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: u(*),v(*)
     INTEGER :: ipar(*)
!------------------------------------------------------------------------------
     INTEGER :: i,j,n
     REAL(KIND=dp) :: s
!------------------------------------------------------------------------------
     n = HUTI_NDIM

     DO i=1,n
        s = 0.0d0
        DO j=1,n
           s = s + Matrix(i,j)*u(j)
        END DO
        v(i) = s
     END DO
!------------------------------------------------------------------------------
  END SUBROUTINE Matvec
!------------------------------------------------------------------------------
