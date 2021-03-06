!========================================================================
!
!                   S P E C F E M 2 D  Version 7 . 0
!                   --------------------------------
!
!     Main historical authors: Dimitri Komatitsch and Jeroen Tromp
!                              CNRS, France
!                       and Princeton University, USA
!                 (there are currently many more authors!)
!                           (c) October 2017
!
! This software is a computer program whose purpose is to solve
! the two-dimensional viscoelastic anisotropic or poroelastic wave equation
! using a spectral-element method (SEM).
!
! This program is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 3 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License along
! with this program; if not, write to the Free Software Foundation, Inc.,
! 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
!
! The full text of the license is available in file "LICENSE".
!
!========================================================================

! for viscoacoustic solver

!! DK DK QUENTIN visco begin

  subroutine compute_attenuation_acoustic(potential_acoustic,potential_acoustic_old,ispec_is_acoustic, &
                                              PML_BOUNDARY_CONDITIONS,e1)

  ! updates memory variable in viscoacoustic simulation

  ! compute forces for the elastic elements
  use constants, only: CUSTOM_REAL,NGLLX,NGLLZ,TWO,ALPHA_LDDRK,BETA_LDDRK,C_LDDRK

  use specfem_par, only: nglob,nspec,nspec_ATT,ATTENUATION_VISCOACOUSTIC,N_SLS, &
                         ibool,xix,xiz,gammax,gammaz,hprime_xx,hprime_zz,ispec_is_PML, &
                         phi_nu1, inv_tau_sigma_nu1,time_stepping_scheme,i_stage,deltat,e1_LDDRK, e1_initial_rk, e1_force_RK

  implicit none

! update the memory variables using a convolution or using a differential equation
! (tests made by Ting Yu and also by Zhinan Xie, CNRS Marseille, France, show that it is better to leave it to .true.)
  logical, parameter :: CONVOLUTION_MEMORY_VARIABLES = .true.

  real(kind=CUSTOM_REAL), dimension(nglob),intent(in) :: potential_acoustic,potential_acoustic_old

  logical,dimension(nspec),intent(in) :: ispec_is_acoustic

  ! CPML coefficients and memory variables
  logical,intent(in) :: PML_BOUNDARY_CONDITIONS

  real(kind=CUSTOM_REAL), dimension(NGLLX,NGLLZ,nspec_ATT,N_SLS),intent(inout) :: e1

  ! local variables
  integer :: ispec
  integer :: i,j,i_sls

  ! nsub1 denotes discrete time step n-1
  real(kind=CUSTOM_REAL), dimension(NGLLX,NGLLZ,nspec) :: dux_dxl_n,dux_dzl_n,duz_dxl_n,duz_dzl_n
  real(kind=CUSTOM_REAL), dimension(NGLLX,NGLLZ,nspec) :: dux_dxl_nsub1,dux_dzl_nsub1,duz_dxl_nsub1,duz_dzl_nsub1

  ! for attenuation
  real(kind=CUSTOM_REAL) :: phinu1,theta_n_u,theta_nsub1_u
  double precision :: tauinvnu1,coef1,temp

  ! temporary RK4 variable
  real(kind=CUSTOM_REAL) :: weight_rk

  ! checks if anything to do
  if (.not. ATTENUATION_VISCOACOUSTIC) return

  if (.not. CONVOLUTION_MEMORY_VARIABLES) &
    stop 'CONVOLUTION_MEMORY_VARIABLES == .false. is not accurate enough and has been discontinued for now'

  ! compute gradient at time step n for attenuation
  call compute_gradient_attenuation_fluid(potential_acoustic,dux_dxl_n,duz_dxl_n, &
        dux_dzl_n,duz_dzl_n,xix,xiz,gammax,gammaz,ibool,ispec_is_acoustic,hprime_xx,hprime_zz,nspec,nglob)

  ! compute gradient at time step n-1 for attenuation
  call compute_gradient_attenuation_fluid(potential_acoustic_old,dux_dxl_nsub1,duz_dxl_nsub1, &
        dux_dzl_nsub1,duz_dzl_nsub1,xix,xiz,gammax,gammaz,ibool,ispec_is_acoustic,hprime_xx,hprime_zz,nspec,nglob)

  ! loop over spectral elements
  do ispec = 1,nspec

    if (.not. ispec_is_acoustic(ispec)) cycle

    if ((.not. PML_BOUNDARY_CONDITIONS) .or. (PML_BOUNDARY_CONDITIONS .and. (.not. ispec_is_PML(ispec)))) then

  do j = 1,NGLLZ
    do i = 1,NGLLX

      ! convention to indicate that Q = 9999 i.e. that there is no viscoacousticity at that GLL point
      if (inv_tau_sigma_nu1(i,j,ispec,1) < 0.) cycle

      theta_n_u     = (dux_dxl_n(i,j,ispec) + duz_dzl_n(i,j,ispec))
      theta_nsub1_u = (dux_dxl_nsub1(i,j,ispec) + duz_dzl_nsub1(i,j,ispec))

      ! loop on all the standard linear solids
      do i_sls = 1,N_SLS
        phinu1    = phi_nu1(i,j,ispec,i_sls)
        tauinvnu1 = inv_tau_sigma_nu1(i,j,ispec,i_sls)

        ! update e1 in convolution formulation with modified recursive convolution scheme on basis of
        ! second-order accurate convolution term calculation from equation (21) of
        ! Shumin Wang, Robert Lee, and Fernando L. Teixeira,
        ! Anisotropic-medium PML for vector FETD with modified basis functions,
        ! IEEE Transactions on Antennas and Propagation, vol. 54, no. 1, (2006)
        select case (time_stepping_scheme)

        case (1)
          ! Newmark

! update the memory variables using a convolution or using a differential equation
! From Zhinan Xie and Dimitri Komatitsch:
! For cases in which a value of tau_sigma is small, then its inverse is large,
! which may result in a in stiff ordinary differential equation to solve;
! in such a case, resorting to the convolution formulation is better.
!         if (CONVOLUTION_MEMORY_VARIABLES) then
!! DK DK inlined this for speed            call compute_coef_convolution(tauinvnu1,deltat,coef0,coef1,coef2)
            temp = exp(- 0.5d0 * tauinvnu1 * deltat)
            coef1 = (1.d0 - temp) / tauinvnu1
            e1(i,j,ispec,i_sls) = temp*temp * e1(i,j,ispec,i_sls) + phinu1 * coef1 * (theta_n_u + temp * theta_nsub1_u)
!         else
!           stop 'CONVOLUTION_MEMORY_VARIABLES == .false. is not accurate enough and has been discontinued for now'
!           e1(i,j,ispec,i_sls) = e1(i,j,ispec,i_sls) + deltat * (- e1(i,j,ispec,i_sls)*tauinvnu1 + phinu1 * theta_n_u)
!         endif

        case (2)
          ! LDDRK
          ! update e1, e11, e13 in ADE formation with fourth-order LDDRK scheme
          e1_LDDRK(i,j,ispec,i_sls) = ALPHA_LDDRK(i_stage) * e1_LDDRK(i,j,ispec,i_sls) + &
                                      deltat * (theta_n_u * phinu1 - e1(i,j,ispec,i_sls) * tauinvnu1)
          e1(i,j,ispec,i_sls) = e1(i,j,ispec,i_sls) + BETA_LDDRK(i_stage) * e1_LDDRK(i,j,ispec,i_sls)

        case (3)
          ! Runge-Kutta
          ! update e1, e11, e13 in ADE formation with classical fourth-order Runge-Kutta scheme
          e1_force_RK(i,j,ispec,i_sls,i_stage) = deltat * (theta_n_u * phinu1 - e1(i,j,ispec,i_sls) * tauinvnu1)

          if (i_stage == 1 .or. i_stage == 2 .or. i_stage == 3) then
            if (i_stage == 1) weight_rk = 0.5_CUSTOM_REAL
            if (i_stage == 2) weight_rk = 0.5_CUSTOM_REAL
            if (i_stage == 3) weight_rk = 1._CUSTOM_REAL

            if (i_stage == 1) e1_initial_rk(i,j,ispec,i_sls) = e1(i,j,ispec,i_sls)
            e1(i,j,ispec,i_sls) = e1_initial_rk(i,j,ispec,i_sls) &
                + weight_rk * e1_force_RK(i,j,ispec,i_sls,i_stage)
          else if (i_stage == 4) then
            e1(i,j,ispec,i_sls) = e1_initial_rk(i,j,ispec,i_sls) + 1._CUSTOM_REAL / 6._CUSTOM_REAL * &
                                  (e1_force_RK(i,j,ispec,i_sls,1) + 2._CUSTOM_REAL * e1_force_RK(i,j,ispec,i_sls,2) + &
                                   2._CUSTOM_REAL * e1_force_RK(i,j,ispec,i_sls,3) + e1_force_RK(i,j,ispec,i_sls,4))
          endif

        case default
          stop 'Time stepping scheme not implemented yet in viscoacoustic attenuation update'
        end select

      enddo ! i_sls

    enddo
  enddo

    endif
  enddo

  end subroutine compute_attenuation_acoustic

