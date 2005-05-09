! *****************************************************************************/
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
! * V0.0a ELMER/FEM Viewfactor computation
! *
! ******************************************************************************
! *
! *                     Author:       Juha Ruokolainen
! *
! *                    Address: Center for Scientific Computing
! *                                Tietotie 6, P.O. BOX 405
! *                                  02
! *                                  Tel. +358 0 457 2723
! *                                Telefax: +358 0 457 2302
! *                              EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date: 02 Jun 1997
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! *****************************************************************************/


   MODULE ViewFactorGlobals
     USE Types
     REAL(KIND=dp), ALLOCATABLE :: Jacobian(:,:)
   END MODULE ViewFactorGlobals

   PROGRAM ViewFactors

     USE DefUtils
     USE ViewFactorGlobals

     IMPLICIT NONE

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     TYPE(Model_t), POINTER :: Model
     TYPE(Mesh_t), POINTER  :: Mesh
     TYPE(Solver_t), POINTER  :: Solver

     INTEGER :: i,j,k,l,t,k1,k2,n,iter,Ndeg,Time,NSDOFs,MatId,istat

     REAL(KIND=dp) :: SimulationTime,dt,s,a1,a2,FMin,FMax

     INTEGER, ALLOCATABLE ::  Surfaces(:), TYPE(:)
     REAL(KIND=dp), ALLOCATABLE :: Coords(:),Normals(:),Factors(:)

     TYPE(Element_t),POINTER :: CurrentElement, Element

     INTEGER :: BandSize,SubbandSize,RadiationSurfaces,Row,Col
     INTEGER, DIMENSION(:), POINTER :: Perm

     REAL(KIND=dp) :: Norm,PrevNorm,Emissivity,MinFactor

     TYPE(Nodes_t) :: ElementNodes
     TYPE(ValueList_t), POINTER :: BC, Material

     INTEGER :: LeftNode,RightNode,LeftBody,RightBody,RadBody
     REAL(KIND=dp) :: NX,NY,NZ,NRM(3),DensL,DensR

     INTEGER :: divide

     INTEGER, POINTER :: Timesteps(:)
     INTEGER :: TimeIntervals,interval,timestep
     
     LOGICAL :: CylindricSymmetry,GotIt

     CHARACTER(LEN=MAX_NAME_LEN) :: eq,RadiationFlag, &
           ViewFactorsFile,OutputName,ModelName

     TYPE(Element_t), POINTER :: RadElements(:)
     INTEGER :: RadiationBody, MaxRadiationBody, Lelement
     LOGICAL :: RadiationOpen


     PRINT*, '------------------------------------------------'
     PRINT*,' Elmer Viewfactor computation program, welcome'
     PRINT*, '------------------------------------------------'
!------------------------------------------------------------------------------
!    Read element definition file, and initialize element types
!------------------------------------------------------------------------------
     CALL InitializeElementDescriptions
!------------------------------------------------------------------------------
!    Read Model from Elmer Data Base
!------------------------------------------------------------------------------
     PRINT*, ' '
     PRINT*, ' '
     PRINT*,'Reading Model ...       '

!------------------------------------------------------------------------------
                                                                                                                 
     OPEN( 1,file='ELMERSOLVER_STARTINFO', STATUS='OLD', ERR=10 )
     GOTO 20
                     
                                                                                         
10   CONTINUE
                                                                                                              
     CALL Fatal( 'ElmerSolver', 'Unable to find ELMERSOLVER_STARTINFO, cant execute.' )
                                                                                                              
20   CONTINUE
       READ(1,'(a)') ModelName
     CLOSE(1)

     Model => LoadModel( ModelName,.FALSE.,1,0 )

     CurrentModel => Model

     NULLIFY( Mesh )
     DO i=1,Model % NumberOfSolvers
       Solver => Model % Solvers(i)
       eq = ListGetString( Solver % Values, 'Equation' )
       IF ( TRIM(eq) == 'heat equation' ) THEN
         Mesh => Solver % Mesh
         Model % Solver => Solver
         EXIT
       ENDIF
     END DO
  
     IF ( .NOT. ASSOCIATED(Mesh) ) THEN
       PRINT*,'ERROR: ViewFactors: No heat equation definition. ' // &
                  'Cannot compute factors.'
       STOP
     END IF
     CALL SetCurrentMesh( Model,Mesh )

     PRINT*,'... Done'
     PRINT*,' '

!------------------------------------------------------------------------------
!    Figure out requested coordinate system
!------------------------------------------------------------------------------
     eq = GetString( GetSimulation(), 'Coordinate System' )

     IF ( eq(1:13) == 'cartesian 3d' ) THEN
       Coordinates = Cartesian
     ELSE IF ( eq(1:13) == 'axi symmetric' ) THEN
       Coordinates = AxisSymmetric
     ELSE IF( eq(1:19) == 'cylindric symmetric' ) THEN
       Coordinates = CylindricSymmetric
     ELSE
       CALL Error( 'ViewFactors', &
         'Unknown Global Coordinate System for Viewfactor computation ')
       CALL Error( 'ViewFactors', TRIM(eq) )
       CALL Fatal( 'ViewFactors', &
         'Only Cartesian 3D or Axi/Cylindrical Symmetric coordinates allowed. Aborting' )
     END IF

     CylindricSymmetry = Coordinates == AxisSymmetric
     CylindricSymmetry = CylindricSymmetry .OR. (Coordinates==CylindricSymmetric)
!------------------------------------------------------------------------------

     ALLOCATE( ElementNodes % x(Model % MaxElementNodes), &
         ElementNodes % y(Model % MaxElementNodes), &
         ElementNodes % z(Model % MaxElementNodes),STAT=istat )
     
     IF ( CylindricSymmetry ) THEN
       ALLOCATE( Coords(2 * Model % NumberOfNodes), STAT=istat )
       DO i=1,Model % NumberOfNodes
         Coords(2*(i-1)+1) = Model % Nodes % x(i)
         Coords(2*(i-1)+2) = Model % Nodes % y(i)
       END DO
     ELSE
       ALLOCATE( Coords(3 * Model % NumberOfNodes), STAT=istat )
       DO i=1,Model % NumberOfNodes
         Coords(3*(i-1)+1) = Model % Nodes % x(i)
         Coords(3*(i-1)+2) = Model % Nodes % y(i)
         Coords(3*(i-1)+3) = Model % Nodes % z(i)
       END DO
     END IF
     IF ( istat /= 0 ) THEN
       PRINT*,'ERROR: Viewfactors: Memory allocation error. Aborting'
       STOP
     END IF

     ! The routine originally plays with the element list and therefore
     ! when several radiation boundaries are needed both the original and 
     ! the new elementlist needs to be in the memory. Thus the hazzle.
     
     CALL AllocateVector( RadElements, Model % NumberOfBoundaryElements, 'ViewFactors' )
     RadiationBody = 0
     MaxRadiationBody = 0

 
100  RadiationBody = RadiationBody + 1
     WRITE( Message,'(A,I2)') 'Computing view factors for radiation body',RadiationBody
     CALL Info('ViewFactors',Message,Level=3)
    
!------------------------------------------------------------------------------
!    Here we start...
!------------------------------------------------------------------------------
     RadiationSurfaces = 0
     MinFactor = ListGetConstReal(Solver % Values,'Minimum View Factor',GotIt)
     IF(.NOT. GotIt) MinFactor = 1.0d-20

!------------------------------------------------------------------------------
!    loop to get the surfaces participating in radiation, discard the rest
!    of the elements...
!------------------------------------------------------------------------------


! The first time replace the element neighbour information with node 
! neigbour information. Other time skip this.

     IF(RadiationBody == 1) THEN

       DO t= 1, Model % NumberOfBoundaryElements
         
         CurrentElement => GetBoundaryElement(t)
         IF ( GetElementFamily() == 1 ) CYCLE
         
         BC => GetBC()
         IF ( .NOT. ASSOCIATED( BC ) ) CYCLE
                  
         IF ( GetLogical( BC, 'Heat Flux BC', GotIt) ) THEN
           RadiationFlag = GetString( BC, 'Radiation',GotIt )
           
           IF ( GotIt .AND. RadiationFlag(1:12) == 'diffuse gray' ) THEN

             i = MAX(1, GetInteger( BC, 'Radiation Boundary', GotIt ))
             MaxRadiationBody = MAX(i, MaxRadiationBody)
             
             j = CurrentElement % BoundaryInfo % LElement
             IF ( j > 0 ) THEN
               DO k=1,Model % Elements(j) % TYPE % numberofnodes
                 gotit = .TRUE.
                 DO l = 1,currentelement % TYPE % numberofnodes
                   IF ( model % elements(j) % Nodeindexes(k) == currentelement % nodeindexes(l) ) THEN
                     gotit = .FALSE.
                     EXIT
                   END IF
                 END DO
                 IF ( gotit ) THEN
                   currentelement % boundaryinfo % lelement = model % elements(j) % nodeindexes(k)
                   EXIT
                 END IF
               END DO
             ENDIF

             j = currentelement % boundaryinfo % relement
             IF ( j > 0 ) THEN
               DO k=1,model % elements(j) % TYPE % numberofnodes
                 gotit = .TRUE.
                 DO l = 1,currentelement % TYPE % numberofnodes
                   IF ( model % elements(j) % Nodeindexes(k) == currentelement % nodeindexes(l) ) THEN
                     gotit = .FALSE.
                     EXIT
                   END IF
                 END DO
                 IF ( gotit ) THEN
                   currentelement % boundaryinfo % relement = model % elements(j) % nodeindexes(k)
                   EXIT
                 END IF
               END DO
             END IF
           END IF
         END IF
       END DO
     END IF


     DO t=1,Model % NumberOfBoundaryElements
       CurrentElement => GetBoundaryElement(t)
       IF ( GetElementFamily() == 1 ) CYCLE
       
       BC => GetBC()
       IF ( .NOT. ASSOCIATED( BC ) ) CYCLE
       
       IF ( GetLogical( BC,'Heat Flux BC',GotIt) ) THEN
         RadiationFlag = GetString( BC, 'Radiation', GotIt )
         IF ( GotIt .AND. RadiationFlag(1:12) == 'diffuse gray' ) THEN
           i = MAX(1, GetInteger( BC, 'Radiation Boundary', GotIt ))
           IF(i == RadiationBody) THEN
             RadiationOpen = GetLogical( BC, 'Radiation Boundary Open', GotIt )
             RadiationSurfaces = RadiationSurfaces + 1
             j = t + Model % NumberOFBulkElements
             RadElements(RadiationSurfaces) = Model % Elements(j)
           END IF
         END IF
       END IF
     END DO


     N = RadiationSurfaces

     IF ( N == 0 ) THEN
       PRINT*,'WARNING: Viewfactors: No surfaces participating in radiation?'
       IF(RadiationBody < MaxRadiationBody) THEN
         GOTO 100
       ELSE
         PRINT*,'WARNING: Viewfactors: Stopping cause nothing to be done...'
         STOP
       END IF
     END IF

     WRITE( Message,'(A,I9)' ) 'Number of surfaces participating in radiation',N
     CALL Info('ViewFactors',Message)

     IF ( CylindricSymmetry ) THEN
       ALLOCATE( Surfaces(2*N), Factors(N*N), STAT=istat )
     ELSE
       ALLOCATE( Normals(3*N), Factors(N*N),Surfaces(4*N), TYPE(N), STAT=istat )
     END IF
     IF ( istat /= 0 ) THEN
       PRINT*,'ERROR: Viewfactors: Memory allocation error. Aborting'
       STOP
     END IF


     DO t=1,N
       CurrentElement => RadElements(t)
       k = CurrentElement % TYPE % NumberOfNodes

       ElementNodes % x(1:k) = Model % Nodes % x( CurrentElement % NodeIndexes )
       ElementNodes % y(1:k) = Model % Nodes % y( CurrentElement % NodeIndexes )
       ElementNodes % z(1:k) = Model % Nodes % z( CurrentElement % NodeIndexes )

       IF ( CurrentElement % TYPE % ElementCode / 100 == 3 ) THEN
         nrm = NormalVector( CurrentElement,ElementNodes, &
                 1.0d0 / 3.0d0, 1.0d0 / 3.0d0 )
       ELSE
         nrm = NormalVector( CurrentElement, ElementNodes, 0.0d0, 0.0d0 )
       END IF
          
       LeftNode  = CurrentElement % BoundaryInfo % LElement
       RightNode = CurrentElement % BoundaryInfo % RElement

       LeftBody  = CurrentElement % BoundaryInfo % LBody
       RightBody = CurrentElement % BoundaryInfo % RBody

       RadBody = ListGetInteger( Model % BCs( CurrentElement %  &
          BoundaryInfo % Constraint) % Values, 'Radiation Target Body',GotIt )

       IF ( .NOT. GotIt ) THEN
          RadBody = ListGetInteger( Model % BCs( CurrentElement %  &
             BoundaryInfo % Constraint) % Values, 'Normal Target Body',GotIt )
       END IF

       IF ( RadBody > 0 .AND. (RadBody /= RightBody .AND. RadBody /= LeftBody) ) THEN
         PRINT*,'ERROR: ViewFactors: Inconsistent direction information (Radiation Target Body)'
         PRINT*,'Radiation Target: ', RadBody, ' Left, Right: ', LeftBody, RightBody
         STOP
       END IF

       IF ( .NOT.GotIt ) THEN
         IF ( LeftBody >= 1 .AND. RightBody >= 1 ) THEN
           MatId = ListGetInteger(Model % Bodies(LeftBody) % Values,'Material')
           DensL = ListGetConstReal( Model % Materials(MatId) % Values,'Density' )

           MatId = ListGetInteger(Model % Bodies(RightBody) % Values,'Material')
           DensR = ListGetConstReal( Model % Materials(MatId) % Values,'Density' )
           IF ( DensL < DensR ) LeftNode = RightNode
         ELSE
           IF ( LeftNode <= 0 ) LeftNode = RightNode
         END IF
       ELSE
         IF ( LeftNode <= 0 ) THEN
           LeftNode = RightNode
           LeftBody = RightBody
         END IF 
         IF ( RadBody == LeftBody ) Nrm = -Nrm
       END IF


       nx = SUM(Model % Nodes % x(CurrentElement % NodeIndexes))/k - &
                   Model % Nodes % x(LeftNode)

       ny = SUM(Model % Nodes % y(CurrentElement % NodeIndexes))/k - &
                   Model % Nodes % y(LeftNode)

       nz = SUM(Model % Nodes % z(CurrentElement % NodeIndexes))/k - &
                   Model % Nodes % z(LeftNode)

       IF ( CylindricSymmetry ) THEN
         IF ( Nrm(1)*nx + Nrm(2)*Ny + Nrm(3)*nz > 0 ) THEN
           Surfaces(2*(t-1)+1) = CurrentElement % NodeIndexes(2) - 1
           Surfaces(2*(t-1)+2) = CurrentElement % NodeIndexes(1) - 1
         ELSE
           Surfaces(2*(t-1)+1) = CurrentElement % NodeIndexes(1) - 1
           Surfaces(2*(t-1)+2) = CurrentElement % NodeIndexes(2) - 1
         END IF
       ELSE
         DO i = 1,MIN(k,4)
           Surfaces(4*(t-1)+i) = CurrentElement % NodeIndexes(i) - 1
         END DO

         TYPE(t) = 404
         IF ( CurrentElement % TYPE % ElementCode / 100 == 3 ) TYPE(t) = 303

         IF ( Nrm(1)*Nx + Nrm(2)*Ny + Nrm(3)*nz > 0 ) THEN
           Normals(3*(t-1)+1:3*(t-1)+3) = -Nrm
          ELSE
           Normals(3*(t-1)+1:3*(t-1)+3) =  Nrm
          END IF
       END IF

     END DO


     CALL Info( 'ViewFactors', 'Computing viewfactors...', Level=4 )

     IF ( CylindricSymmetry ) THEN
       divide = GetInteger( GetSolverParams(), 'Viewfactor divide',GotIt)
       IF ( .NOT. GotIt ) Divide = 1
       CALL ViewFactorsAxis( N, Surfaces, Coords, Factors, divide )
     ELSE
       CALL ViewFactors3D( N, Surfaces, TYPE, Coords, Normals, &
              Factors, 1.0d-1, 1.0d-2, 1.0d-5, 16, 3 )
     END IF
     CALL Info( 'ViewFactors', '...Done.', Level=4 )


     DO i=1,N
       s = 0.0D0
       DO j=1,N
         IF(Factors((i-1)*N+j) < MinFactor) Factors((i-1)*N+j) = 0.0d0         
         s = s + Factors((i-1)*N+j)
       END DO 

       IF(i == 1) THEN
         Fmin = s 
         Fmax = s
       ELSE         
         FMin = MIN( FMin,s )
         FMax = MAX( FMax,s )
       END IF
     END DO


     CALL Info( 'ViewFactors', ' ', Level=3 )
     CALL info( 'ViewFactors', 'Viewfactors before normalizing: ', Level=3 )
     CALL Info( 'ViewFactors', ' ', Level=3 )
     WRITE( Message, * ) '        Minimum row sum: ',FMin
     CALL Info( 'ViewFactors', Message, Level=3 )
     WRITE( Message, * ) '        Maximum row sum: ',FMax
     CALL Info( 'ViewFactors', Message, Level=3 )
     CALL Info( 'ViewFactors', ' ', Level=3 )

     CALL Info( 'ViewFactors', 'Normalizing Factors... ', Level=3 )


     IF(.NOT. RadiationOpen) THEN
       CALL NormalizeFactors( Model )
       
       DO i=1,N
         s = 0.0D0
         DO j=1,N
           s = s + Factors((i-1)*N+j)
         END DO
         IF(i == 1) THEN
           Fmin = s
           Fmax = s
         ELSE
           FMin = MIN( FMin,s )
           FMax = MAX( FMax,s )
         END IF
       END DO
       CALL Info( 'ViewFactors', 'Done... ', Level=3 )
       
       CALL Info( 'ViewFactors', ' ', Level=3 )
       CALL info( 'ViewFactors', 'Viewfactors after normalizing: ', Level=3 )
       CALL Info( 'ViewFactors', ' ', Level=3 )
       WRITE( Message, * ) '        Minimum row sum: ',FMin
       CALL Info( 'ViewFactors', Message, Level=3 )
       WRITE( Message, * ) '        Minimum row sum: ',FMax
       CALL Info( 'ViewFactors', Message, Level=3 )
       CALL Info( 'ViewFactors', ' ', Level=3 )
     END IF


     ViewFactorsFile = GetString( GetSimulation(),'View Factors',GotIt)
     IF ( .NOT.GotIt ) ViewFactorsFile = 'ViewFactors.dat'
     IF(RadiationBody > 1) THEN
       WRITE(ViewFactorsFile, '(A,I1)') TRIM(ViewFactorsFile),RadiationBody
     END IF

     IF ( LEN_TRIM(Model % Mesh % Name) > 0 ) THEN
       OutputName = TRIM(OutputPath) // '/' // &
           TRIM(Model % Mesh % Name) // '/' // TRIM(ViewFactorsFile)
     ELSE
       OutputName = TRIM(ViewFactorsFile)
     END IF

     OPEN( 1,File=TRIM(OutputName),STATUS='UNKNOWN' )

     ! Use loser consttraint for MinFactor as the errors cant be renormalized any more 
     MinFactor = MinFactor / 10.0

     DO i=1,N
       k = 0
       DO j=1,N
         IF ( Factors((i-1)*N+j) > MinFactor ) k = k + 1
       END DO
       WRITE( 1,* ) k
       DO j=1,N
         IF ( Factors((i-1)*N+j) > MinFactor ) THEN
           WRITE( 1,* ) i,j,Factors((i-1)*N+j)
         END IF
       END DO
     END DO

     CLOSE(1)

     IF ( CylindricSymmetry ) THEN
       DEALLOCATE( Surfaces, Factors)
     ELSE
       DEALLOCATE( Normals, Factors, Surfaces, TYPE)
     END IF

     IF(RadiationBody < MaxRadiationBody) THEN
       GOTO 100
     END IF

     PRINT*,'*** ViewFactors: ALL DONE ***'
!    CALL FLUSH(6)

   CONTAINS
   

      SUBROUTINE NormalizeFactors( Model )

        TYPE(Model_t), POINTER :: Model

        INTEGER :: itmax=20,it = 0,i,j,k

        LOGICAL :: li,lj

        REAL(KIND=dp), ALLOCATABLE :: RHS(:),SOL(:),Areas(:),PSOL(:)

        REAL(KIND=dp) :: SUM = 0.0D0,eps=1.0D-20,s,si,sj
  
        ALLOCATE( RHS(N),SOL(N),PSOL(N),Areas(N),Jacobian(N,N),STAT=istat )

        IF ( istat /= 0 ) THEN
          PRINT*,'Viewfactors: Memory allocation error in NormalizeFactors.'
          PRINT*,'Aborting'
          STOP
        END IF

!------------------------------------------------------------------------------
!       First force the matrix (before dividing by area) to be symmetric
!------------------------------------------------------------------------------
        DO i=1,N
          Areas(i) = ElementArea( Model % Mesh, RadElements(i), &
             RadElements(i) % TYPE % NumberOfNodes )
        END DO

        DO i=1,N
          DO j=i,N
            si = Areas(i) * Factors((i-1)*N+j)
            sj = Areas(j) * Factors((j-1)*N+i)

            li = (ABS(si) < HUGE(si)) 
            lj = (ABS(sj) < HUGE(sj)) 

            IF(li .AND. lj) THEN 
              s = (si+sj)/2.0
            ELSE IF(li) THEN
              s = si
            ELSE IF(lj) THEN
              s = sj
            ELSE 
              s = 0.0
            END IF

            Factors((i-1)*N+j) = s
            Factors((j-1)*N+i) = s
          END DO
        END DO
!------------------------------------------------------------------------------
!       Next we solve the equation DFD = A by Newton iteration (this is a very
!       well behaved equation (symmetric, diagonal dominant), no need for any
!       tricks...)
!------------------------------------------------------------------------------
        SOL = 1.0D0
        SUM = 1.0D0
        it = 0

        DO WHILE( SUM > eps .AND. it < itmax )
          DO i=1,N
            SUM = 0.0D0
            DO j=1,N
              SUM = SUM + Factors((i-1)*N+j) * SOL(j)
            END DO
            SUM = SUM * SOL(i)
            RHS(i) = -(SUM - Areas(i))
          END DO

          SUM = 0.0D0
          DO i=1,N
            SUM = SUM + RHS(i)**2 / Areas(i)
          END DO
          SUM = SUM / N

          IF ( SUM <= eps ) EXIT

          DO i=1,N
            DO j=1,N
              Jacobian(i,j) = Factors((i-1)*N+j) * SOL(i)
            END DO
            DO j=1,N
              Jacobian(i,i) = Jacobian(i,i) + Factors((i-1)*N+j) * SOL(j)
            END DO
          END DO
             
          PSOL = SOL
          CALL IterSolv( N,SOL,RHS )
          SOL = PSOL + SOL

          it = it + 1
        END DO

!------------------------------------------------------------------------------
!       Normalize the factors and (re)divide by areas
!------------------------------------------------------------------------------
        DO i=1,N
          DO j=1,N
            Factors((i-1)*N+j) = Factors((i-1)*N+j)*SOL(i)*SOL(j)/Areas(i)
          END DO
        END DO

        DEALLOCATE( SOL,RHS,PSOL,Areas,Jacobian )

    END SUBROUTINE NormalizeFactors


#include <huti_fdefs.h>
!
    SUBROUTINE IterSolv( N,x,b )
      IMPLICIT NONE

      REAL(KIND=dp), DIMENSION(:) :: x,b

      REAL(KIND=dp) :: dpar(50)

      INTEGER :: N,ipar(50),wsize
      REAL(KIND=dp), ALLOCATABLE :: work(:,:)

      EXTERNAL Matvec,DiagPrec

      HUTI_NDIM = N

      ipar = 0
      dpar = 0.0D0

      HUTI_WRKDIM = HUTI_CG_WORKSIZE
      wsize = HUTI_WRKDIM
          
      HUTI_NDIM     = N
      HUTI_DBUGLVL  = 0
      HUTI_MAXIT    = 100
 
      ALLOCATE( work(wsize,N) )

      HUTI_TOLERANCE = 1.0D-12

      CALL HUTI_D_CG( x,b,ipar,dpar,work,Matvec,DiagPrec,0,0,0,0 )
          
      DEALLOCATE( work )
    END SUBROUTINE IterSolv 

  END PROGRAM ViewFactors



  SUBROUTINE DiagPrec( u,v,ipar )
    USE ViewFactorGlobals

    REAL(KIND=dp) :: u(*),v(*)
    INTEGER :: ipar(*)

    INTEGER :: i,n

    N = HUTI_NDIM
    DO i=1,N
      u(i) = v(i) / Jacobian(i,i) 
    END DO
  END SUBROUTINE DiagPrec



  SUBROUTINE Matvec( u,v,ipar )
    USE ViewFactorGlobals

    REAL(KIND=dp) :: u(*),v(*)
    INTEGER :: ipar(*)

    INTEGER :: i,j,n
    REAL(KIND=dp) :: s

    n = HUTI_NDIM

    DO i=1,n
      s = 0.0D0
      DO j=1,n
        s = s + Jacobian(i,j) * u(j)
      END DO
      v(i) = s
    END DO
  END SUBROUTINE Matvec
