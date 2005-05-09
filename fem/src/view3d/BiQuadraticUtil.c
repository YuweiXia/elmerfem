/******************************************************************************
 *
 *       ELMER, A Computational Fluid Dynamics Program.
 *
 *       Copyright 1st April 1995 - , Center for Scientific Computing,
 *                                    Finland.
 *
 *       All rights reserved. No part of this program may be used,
 *       reproduced or transmitted in any form or by any means
 *       without the written permission of CSC.
 *
 *****************************************************************************/

/******************************************************************************
 *
 *
 *
 ******************************************************************************
 *
 *                     Author:       Juha Ruokolainen
 *
 *                    Address: Center for Scientific Computing
 *                                Tietotie 6, P.O. BOX 405
 *                                  02
 *                                  Tel. +358 0 457 2723
 *                                Telefax: +358 0 457 2302
 *                              EMail: Juha.Ruokolainen@csc.fi
 *
 *                       Date: 02 Jun 1997
 *
 *                Modified by:
 *
 *       Date of modification:
 *
 *****************************************************************************/

/*******************************************************************************

Utilities for biquadratic elements.

Juha Ruokolainen/CSC - 23 Aug 1995

*******************************************************************************/

#include <ViewFactors.h>


/*******************************************************************************

Convert monomial basis biquadratic polynomial to bezier (bernstein basis) form.

23 Aug 1995

*******************************************************************************/
void BiQuadraticMonomialToBezier(double *MonomialFactors,double *BezierFactors)
{
     static double CMatrix[3][3] =
     {
         { 1.0,   0.0,     0.0   },
         { 1.0, 1.0/2.0,   0.0   },
         { 1.0,   1.0,     1.0,  }
     };

     double s,A[3][3];

     int i,j,k;

/*
     (inv(a')*(inv(a')*r1)')'
     (a*(a*x)')'
*/

     for( i=0; i<3; i++ )
     for( j=0; j<3; j++ )
     {
         s = 0.0;
         for( k=0; k<3; k++ ) s += CMatrix[i][k]*MonomialFactors[3*k+j]; 
         A[i][j] = s;
     }

     for( i=0; i<3; i++ )
     for( j=0; j<3; j++ )
     {
         s = 0.0;
         for( k=0; k<3; k++ ) s += CMatrix[i][k]*A[j][k];
         BezierFactors[3*j+i] = s;
     }
}

/*******************************************************************************

Convert bezier (bernstein basis) form polynomial to monomial form.

23 Aug 1995

*******************************************************************************/
void BiQuadraticBezierToMonomial(double *MonomialFactors,double *BezierFactors)
{
     static double CMatrix[3][3] =
     {
         { 1.0, -2.0,  1.0 },
         { 0.0,  2.0, -2.0 },
         { 0.0,  0.0,  1.0 }
     };

     double s,A[3][3];

     int i,j,k,n;

     for( i=0; i<3; i++ )
     for( j=0; j<3; j++ )
     {
         s = 0.0;
         for( k=0; k<3; k++ ) s += BezierFactors[3*i+k]*CMatrix[k][j]; 
         A[i][j] = s;
     }

     n = 0;
     for( i=0; i<3; i++ )
     for( j=0; j<3; j++,n++ )
     {
         s = 0.0;
         for( k=0; k<3; k++ ) s += CMatrix[k][i]*A[k][j];
         MonomialFactors[n] = s;
     }
}

/*******************************************************************************

Subdivide biquadratic polynomial to two parts in first of the parameters.

23 Aug 1995

*******************************************************************************/
void BiQuadraticBezierSubdivideHalfU(double *I,double *L,double *R)
{
    double t;
    int j;

    for( j=0; j<3; j++,I+=3,R+=3,L+=3 )
    {
        t = 0.5*(I[0]+I[2]);

        R[2] = I[2];
        R[1] = 0.5*(I[1]+I[2]);

        L[2] = I[0];
        L[1] = 0.5*(I[0]+I[1]);

        L[0] = R[0] = 0.5*(t+I[1]);
    }
}

/*******************************************************************************

Subdivide biquadratic polynomial to two parts in second of the parameters.

23 Aug 1995

*******************************************************************************/
void BiQuadraticBezierSubdivideHalfV(double *I,double *L,double *R)
{
    double t;
    int j;

    for( j=0; j<3; j++,I++,R++,L++ )
    {
        t = 0.5*(I[0]+I[6]);

        R[6] = I[6];
        R[3] = 0.5*(I[3]+I[6]);

        L[6] = I[0];
        L[3] = 0.5*(I[0]+I[3]);

        L[0] = R[0] = 0.5*(t+I[3]);
    }
}

/*******************************************************************************

Test biquadratic polynomial for planarity by testing how well the bezier control
points fullfill the plane equation.

23 Aug 1995

*******************************************************************************/
int BiQuadraticIsAPlane( double *X,double *Y, double *Z )
{
    double Ax,Ay,Az,Cx,Cy,Cz,Dx,Dy,Dz,D,Nx,Ny,Nz,R;
    int i;

    Ax = X[0];
    Ay = Y[0];
    Az = Z[0];

    for( i=9; i>0; i-- )
    {
        Cx = X[i];
        Cy = Y[i];
        Cz = Z[i];
        if ( ABS(Ax-Cx)>1.0E-8||ABS(Ay-Cy)>1.0E-8||ABS(Az-Cz)>1.0E-8 ) break;
    }

    Dx = Cx - Ax;
    Dy = Cy - Ay;
    Dz = Cz - Az;

    for( ;i>0; i-- )
    {
        Cx = X[i] - Ax;
        Cy = Y[i] - Ay;
        Cz = Z[i] - Az;

        Nx =  Dy*Cz - Cy*Dz;
        Ny = -Dx*Cz - Cx*Dz;
        Nz =  Dx*Cy - Cx*Dy;
        if ( Nx*Nx + Ny*Ny + Nz*Nz > 1.0E-8 ) break;
    }

    D = -Ax*Nx - Ay*Ny - Az*Nz;

    R = 0.0;
    for( i=0; i<9; i++ ) R += ABS(Nx*X[i] + Ny*Y[i] + Nz*Z[i] + D);

    return R<1.0E-4;
}


/*******************************************************************************

Subdive a biquadratic polynomial surface in longer of the parameters. Also compute
a bounding volume for the surface.

23 Aug 1995

*******************************************************************************/
void BiQuadraticSubdivide( Geometry_t *Geometry, int SubLev,int Where )
{
     BiQuadratic_t *LeftQuadratic, *RightQuadratic;
     BBox_t *BBox;
     double ULength,VLength;

     int j;

#if 0
{
    volatile static int l=0;
    fprintf( stderr, "add new node (total: %d,level: %d,",2*l,SubLev );
    if ( Where ) fprintf( stderr, " from: Integrate\n" );
    else fprintf( stderr, "from: raytrace\n" );
    l++;
}
#endif

     Geometry->Left = (Geometry_t *)calloc(sizeof(Geometry_t),1);
     LeftQuadratic = Geometry->Left->BiQuadratic = (BiQuadratic_t *)malloc(sizeof(BiQuadratic_t));

     Geometry->Right = (Geometry_t *)calloc(sizeof(Geometry_t),1);
     RightQuadratic = Geometry->Right->BiQuadratic = (BiQuadratic_t *)malloc(sizeof(BiQuadratic_t));

     Geometry->Left->GeometryType = Geometry->Right->GeometryType = GEOMETRY_BICUBIC;

     ULength = BiQuadraticLength(Geometry,1);
     VLength = BiQuadraticLength(Geometry,0);

     if ( ULength>VLength )
     {
         for( j=0; j<6; j++ )
         {
             BiQuadraticBezierSubdivideHalfU( Geometry->BiQuadratic->BezierFactors[j],
               LeftQuadratic->BezierFactors[j], RightQuadratic->BezierFactors[j] );
         }
     } else
     {
         for( j=0; j<6; j++ )
         {
             BiQuadraticBezierSubdivideHalfV( Geometry->BiQuadratic->BezierFactors[j],
               LeftQuadratic->BezierFactors[j],RightQuadratic->BezierFactors[j] );
         }
     }

     for( j=0; j<6; j++ )
     {
         BiQuadraticBezierToMonomial(  LeftQuadratic->PolyFactors[j],LeftQuadratic->BezierFactors[j] );
         BiQuadraticBezierToMonomial( RightQuadratic->PolyFactors[j],RightQuadratic->BezierFactors[j] );
     }

     if ( Where ) return;

     BBox = &Geometry->Left->BBox;
     BBox->XMin = BBox->XMax = LeftQuadratic->BezierFactors[0][0];
     BBox->YMin = BBox->YMax = LeftQuadratic->BezierFactors[1][0];
     BBox->ZMin = BBox->ZMax = LeftQuadratic->BezierFactors[2][0];

     for( j=0; j<9; j++ )
     {
         BBox->XMin = MIN(BBox->XMin,LeftQuadratic->BezierFactors[0][j]);
         BBox->XMax = MAX(BBox->XMax,LeftQuadratic->BezierFactors[0][j]);

         BBox->YMin = MIN(BBox->YMin,LeftQuadratic->BezierFactors[1][j]);
         BBox->YMax = MAX(BBox->YMax,LeftQuadratic->BezierFactors[1][j]);

         BBox->ZMin = MIN(BBox->ZMin,LeftQuadratic->BezierFactors[2][j]);
         BBox->ZMax = MAX(BBox->ZMax,LeftQuadratic->BezierFactors[2][j]);
     }

     BBox->XMin = MAX(BBox->XMin,Geometry->BBox.XMin);
     BBox->YMin = MAX(BBox->YMin,Geometry->BBox.YMin);
     BBox->ZMin = MAX(BBox->ZMin,Geometry->BBox.ZMin);
     BBox->XMax = MIN(BBox->XMax,Geometry->BBox.XMax);
     BBox->YMax = MIN(BBox->YMax,Geometry->BBox.YMax);
     BBox->ZMax = MIN(BBox->ZMax,Geometry->BBox.ZMax);

     BBox = &Geometry->Right->BBox;
     BBox->XMin = BBox->XMax = RightQuadratic->BezierFactors[0][0];
     BBox->YMin = BBox->YMax = RightQuadratic->BezierFactors[1][0];
     BBox->ZMin = BBox->ZMax = RightQuadratic->BezierFactors[2][0];

     for( j=0; j<9; j++ )
     {
         BBox->XMin = MIN(BBox->XMin,RightQuadratic->BezierFactors[0][j]);
         BBox->XMax = MAX(BBox->XMax,RightQuadratic->BezierFactors[0][j]);
         BBox->YMin = MIN(BBox->YMin,RightQuadratic->BezierFactors[1][j]);
         BBox->YMax = MAX(BBox->YMax,RightQuadratic->BezierFactors[1][j]);
         BBox->ZMin = MIN(BBox->ZMin,RightQuadratic->BezierFactors[2][j]);
         BBox->ZMax = MAX(BBox->ZMax,RightQuadratic->BezierFactors[2][j]);
     }

     BBox->XMin = MAX(BBox->XMin,Geometry->BBox.XMin);
     BBox->YMin = MAX(BBox->YMin,Geometry->BBox.YMin);
     BBox->ZMin = MAX(BBox->ZMin,Geometry->BBox.ZMin);
     BBox->XMax = MIN(BBox->XMax,Geometry->BBox.XMax);
     BBox->YMax = MIN(BBox->YMax,Geometry->BBox.YMax);
     BBox->ZMax = MIN(BBox->ZMax,Geometry->BBox.ZMax);

     if ( BiQuadraticIsAPlane( Geometry->Left->BiQuadratic->BezierFactors[0],
                           Geometry->Left->BiQuadratic->BezierFactors[1],
                           Geometry->Left->BiQuadratic->BezierFactors[2] ) )
         Geometry->Left->Flags |= GEOMETRY_FLAG_PLANE;

     if ( BiQuadraticIsAPlane( Geometry->Right->BiQuadratic->BezierFactors[0],
                           Geometry->Right->BiQuadratic->BezierFactors[1],
                           Geometry->Right->BiQuadratic->BezierFactors[2] ) )
         Geometry->Right->Flags |= GEOMETRY_FLAG_PLANE;
}
 
/*******************************************************************************

Compute element of (iso)line for a (bi)quadratic polynomial.

23 Aug 1995

*******************************************************************************/
double BiQuadraticEofL(double U,double V,double *X,double *Y,double *Z,int UnotV)
{
    double dXdU,dYdU,dZdU,dXdV,dYdV,dZdV,Auu,Auv,Avv,detA;

    int i;

    dXdU = BiQuadraticPartialU(U,V,X);
    dXdV = BiQuadraticPartialV(U,V,X);

    dYdU = BiQuadraticPartialU(U,V,Y);
    dYdV = BiQuadraticPartialV(U,V,Y);

    dZdU = BiQuadraticPartialU(U,V,Z);
    dZdV = BiQuadraticPartialV(U,V,Z);

    Auu = dXdU*dXdU + dYdU*dYdU + dZdU*dZdU; /* surface metric a    */
    Auv = dXdU*dXdV + dYdU*dYdV + dZdU*dZdV; /*                 ij  */
    Avv = dXdV*dXdV + dYdV*dYdV + dZdV*dZdV;

    if ( UnotV )
        return sqrt(Auu);
    else
        return sqrt(Avv);
}

/*******************************************************************************

Compute element of area for a biquadratic polynomial.

23 Aug 1995

*******************************************************************************/
double BiQuadraticEofA(double U,double V,double *X,double *Y,double *Z)
{
    double dXdU,dYdU,dZdU,dXdV,dYdV,dZdV,Auu,Auv,Avv,detA;

    int i;

    dXdU = BiQuadraticPartialU(U,V,X);
    dXdV = BiQuadraticPartialV(U,V,X);

    dYdU = BiQuadraticPartialU(U,V,Y);
    dYdV = BiQuadraticPartialV(U,V,Y);

    dZdU = BiQuadraticPartialU(U,V,Z);
    dZdV = BiQuadraticPartialV(U,V,Z);

    Auu = dXdU*dXdU + dYdU*dYdU + dZdU*dZdU; /* surface metric a    */
    Auv = dXdU*dXdV + dYdU*dYdV + dZdU*dZdV; /*                 ij  */
    Avv = dXdV*dXdV + dYdV*dYdV + dZdV*dZdV;

    detA = Auu*Avv - Auv*Auv;

    return sqrt(detA);
}

/*******************************************************************************

Compute isoline length of a biquadratic polynomial in given parameter.

23 Aug 1995

*******************************************************************************/
double BiQuadraticLength( Geometry_t *Geometry,int UnotV )
{
    double *X,*Y,*Z,EofL,Length;

    int i,j=0;

    X = Geometry->BiQuadratic->PolyFactors[0];
    Y = Geometry->BiQuadratic->PolyFactors[1];
    Z = Geometry->BiQuadratic->PolyFactors[2];

    Length = 0.0;
    for( j=0; j<3; j++ )
    for( i=0; i<N_Integ1d; i++ )
    {
        if ( UnotV )
            EofL = BiQuadraticEofL(U_Integ1d[i],j/3.0,X,Y,Z,1);
        else
            EofL = BiQuadraticEofL(j/3.0,U_Integ1d[i],X,Y,Z,0);

        Length += S_Integ1d[i]*EofL;
    }

    return Length;
}

/*******************************************************************************

Compute area of a biquadratic polynomial surface.

23 Aug 1995

*******************************************************************************/
double BiQuadraticArea( Geometry_t *Geometry )
{
    double *X,*Y,*Z,EofA,Area;

    int i;

    X = Geometry->BiQuadratic->PolyFactors[0];
    Y = Geometry->BiQuadratic->PolyFactors[1];
    Z = Geometry->BiQuadratic->PolyFactors[2];

    Area = 0.0;
    for( i=0; i<N_Integ; i++ )
    {
        EofA = BiQuadraticEofA(U_Integ[i],V_Integ[i],X,Y,Z);
        Area += S_Integ[i]*EofA;
    }

    return Area;
}


/*******************************************************************************

Compute differential area to area viewfactor for biquadratic surface elements by
direct numerical integration.

24 Aug 1995

*******************************************************************************/
double BiQuadraticIntegrateDiffToArea( Geometry_t *GB,
  double FX,double FY,double FZ,double NFX,double NFY,double NFZ)
{
    double F,R,cosA,cosB,EA,EAF,EAT,PI=2*acos(0.0);
    double DX,DY,DZ,NTX,NTY,NTZ,U,V;

    double *BX  = GB->BiQuadratic->PolyFactors[0];
    double *BY  = GB->BiQuadratic->PolyFactors[1];
    double *BZ  = GB->BiQuadratic->PolyFactors[2];

    double *NBX = GB->BiQuadratic->PolyFactors[3];
    double *NBY = GB->BiQuadratic->PolyFactors[4];
    double *NBZ = GB->BiQuadratic->PolyFactors[5];

    int i,j;

    F  = 0.0;
    for( i=0; i<N_Integ; i++ )
    {
        U = U_Integ[i];
        V = V_Integ[i];
        
        DX  = BiQuadraticValue(U,V,BX) - FX;
        DY  = BiQuadraticValue(U,V,BY) - FY;
        DZ  = BiQuadraticValue(U,V,BZ) - FZ;

        cosA =  DX*NFX + DY*NFY + DZ*NFZ;
        if ( cosA <= 1.0E-9 ) continue;

        NTX = BiQuadraticValue(U,V,NBX);
        NTY = BiQuadraticValue(U,V,NBY);
        NTZ = BiQuadraticValue(U,V,NBZ);

        R = NTX*NTX + NTY*NTY + NTZ*NTZ;
        if ( ABS(1-R) > 1.0E-7 )
        {
            R = 1.0/sqrt(R);
            NTX *= R;
            NTY *= R;
            NTZ *= R;
        }

        cosB = -DX*NTX - DY*NTY - DZ*NTZ;
        if ( cosB <= 1.0E-9 ) continue;

        R = DX*DX + DY*DY + DZ*DZ;

        EA = BiQuadraticEofA(U,V,BX,BY,BZ);
        F += EA*cosA*cosB*S_Integ[i]/(R*R);
    }

    return F;
}

/*******************************************************************************

Compute area to area viewfactor for biquadratic surface elements by subdivision
and direct numerical integration when the differential viewfactors match given
magnitude criterion or areas of the elements are small enough. Blocking of the
view between the elements is resolved by ray traceing.

24 Aug 1995

*******************************************************************************/
void BiQuadraticComputeViewFactors(Geometry_t *GA,Geometry_t *GB,int LevelA,int LevelB)
{
    double FX,FY,FZ,DX,DY,DZ,U,V,Hit;
    double F,Fa,Fb,EA,PI=2*acos(0.0);

    double *AX  = GA->BiQuadratic->PolyFactors[0];
    double *AY  = GA->BiQuadratic->PolyFactors[1];
    double *AZ  = GA->BiQuadratic->PolyFactors[2];

    double *BX  = GB->BiQuadratic->PolyFactors[0];
    double *BY  = GB->BiQuadratic->PolyFactors[1];
    double *BZ  = GB->BiQuadratic->PolyFactors[2];

    int i,j;

#ifdef TODO
    Fa = Fb = BiQuadraticIntegrateDiffToArea(GA,0.5,0.5,GB);

    if ( GA != GB ) Fb = BiQuadraticIntegrateDiffToArea(GB,0.5,0.5,GA);
#endif

    if ( Fa < 1.0E-10 && Fb < 1.0E-10 ) return;

    if ( (Fa<FactorEPS || GB->Area<AreaEPS) && (Fb<FactorEPS || GA->Area<AreaEPS) )
    {
        GeometryList_t *Link;

        Hit = 16.0;
        for( i=0; i<16; i++ )
        {
            U = drand48(); V = drand48();

            FX = BiQuadraticValue(U,V,AX);
            FY = BiQuadraticValue(U,V,AY);
            FZ = BiQuadraticValue(U,V,AZ);

            U = drand48(); V = drand48();

            DX = BiQuadraticValue(U,V,BX) - FX;
            DY = BiQuadraticValue(U,V,BY) - FY;
            DZ = BiQuadraticValue(U,V,BZ) - FZ;

            Hit -= RayHitGeometry( FX,FY,FZ,DX,DY,DZ );
        }

        if ( Hit == 0 ) return;

        if ( Hit == 16 || (Fa<FactorEPS/2 && Fb<FactorEPS/2) )
        {
            Hit /= 16.0;

            F = 0.0;
            for( i=0; i<N_Integ; i++ )
            {
                U = U_Integ[i];
                V = V_Integ[i];
                EA = BiQuadraticEofA(U,V,AX,AY,AZ);
#ifdef TODO
                F += S_Integ[i]*EA*BiQuadraticIntegrateDiffToArea(GA,U,V,GB);
#endif
            }

            F = Hit*F / PI;
            Fb = F / GB->Area;
            Fa = F / GA->Area;

            Link = (GeometryList_t *)calloc(sizeof(GeometryList_t),1);
            Link->Next = GA->Link;
            GA->Link = Link;

            Link->Entry = GB;
            Link->ViewFactor = Fa;

            if ( GA != GB )
            {
                Link = (GeometryList_t *)calloc(sizeof(GeometryList_t),1);
                Link->Next = GB->Link;
                GB->Link = Link;

                Link->Entry = GA;
                Link->ViewFactor = Fb;
            }

            return;
        }
    }

    if ( GA == GB )
    {
        if ( !GB->Left ) BiQuadraticSubdivide( GB, LevelB,1 );

        if ( GB->Flags & GEOMETRY_FLAG_LEAF )
        {
            GB->Flags &= ~GEOMETRY_FLAG_LEAF;
            GB->Left->Flags  |= GEOMETRY_FLAG_LEAF;
            GB->Right->Flags |= GEOMETRY_FLAG_LEAF;

            if ( !GB->Left->Area )
            {
                GB->Left->Area  = BiQuadraticArea(GB->Left);
                GB->Right->Area = BiQuadraticArea(GB->Right);
            }
        }

        BiQuadraticComputeViewFactors( GB->Left, GB->Left, LevelB+1,LevelB+1 );
        BiQuadraticComputeViewFactors( GB->Right,GB->Right,LevelB+1,LevelB+1 );
        BiQuadraticComputeViewFactors( GB->Left, GB->Right,LevelB+1,LevelB+1 );
    }
    else if ( Fa > Fb )
    {
        if ( !GB->Left ) BiQuadraticSubdivide( GB, LevelB,1 );

        if ( GB->Flags & GEOMETRY_FLAG_LEAF )
        {    
            GB->Flags &= ~GEOMETRY_FLAG_LEAF;
            GB->Left->Flags  |= GEOMETRY_FLAG_LEAF;
            GB->Right->Flags |= GEOMETRY_FLAG_LEAF;

            if ( !GB->Left->Area)
            {
                GB->Left->Area  = BiQuadraticArea(GB->Left);
                GB->Right->Area = BiQuadraticArea(GB->Right);
            }
        }

        BiQuadraticComputeViewFactors( GA,GB->Left,LevelA,LevelB+1 );
        BiQuadraticComputeViewFactors( GA,GB->Right,LevelA,LevelB+1 );
    } else
    {
        if ( !GA->Left ) BiQuadraticSubdivide( GA, LevelA,1 );

        if ( GA->Flags & GEOMETRY_FLAG_LEAF )
        {
            GA->Flags &= ~GEOMETRY_FLAG_LEAF;
            GA->Left->Flags  |= GEOMETRY_FLAG_LEAF;
            GA->Right->Flags |= GEOMETRY_FLAG_LEAF;

            if ( !GA->Left->Area )
            {
                GA->Left->Area  = BiQuadraticArea(GA->Left);
                GA->Right->Area = BiQuadraticArea(GA->Right);
            }
        }

        BiQuadraticComputeViewFactors( GA->Left,GB,LevelA+1,LevelB );
        BiQuadraticComputeViewFactors( GA->Right,GB,LevelA+1,LevelB );
    }
}

