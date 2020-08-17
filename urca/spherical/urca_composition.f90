module urca_composition_module

  use amrex_fort_module, only : rt => amrex_real
  use network, only: nspec

  implicit none

  private xn_in, xn_out
  public set_urca_composition, c12_in, c12_out, o16_in, o16_out, &
         ne23_in, ne23_out, na23_in, na23_out, urca_23_dens, &
         urca_shell_type, shell_atan_kappa, na_ne_23

  real (kind=rt) :: c12_in  = 0.0d0, c12_out  = 0.0d0, &
                      o16_in  = 0.0d0, o16_out  = 0.0d0, &
                      ne23_in = 0.0d0, ne23_out = 0.0d0, &
                      na23_in = 0.0d0, na23_out = 0.0d0, &
                      urca_23_dens = 0.0d0, shell_atan_kappa = 0.0d0, &
                      na_ne_23 = 0.0d0

  real (kind=rt) :: xn_in(nspec), xn_out(nspec)

  character (len=128) :: urca_shell_type = ""

contains

  subroutine init_urca_composition()
    use amrex_error_module
    use network, only: network_species_index

    implicit none

    integer :: ihe4, ic12, io16, ine20, ine23, ina23, img23

    ! get the species indices
    ihe4  = network_species_index("helium-4")
    ic12  = network_species_index("carbon-12")
    io16  = network_species_index("oxygen-16")
    ine20 = network_species_index("neon-20")
    ine23 = network_species_index("neon-23")
    ina23 = network_species_index("sodium-23")
    img23 = network_species_index("magnesium-23")

    ! check the required species exist
    if (ihe4 < 0 .or. &
        ic12 < 0 .or. io16 < 0 .or. ine20 < 0 .or. &
        ine23 < 0 .or. ina23 < 0 .or. img23 < 0) then
       call amrex_error("ERROR: species not defined")
    endif

    ! check the species mass fractions
    if (c12_in < 0.0_rt .or. c12_in > 1.0_rt) then
       call amrex_error("ERROR: c12_in must be between 0 and 1")
    endif
    if (c12_out < 0.0_rt .or. c12_out > 1.0_rt) then
       call amrex_error("ERROR: c12_out must be between 0 and 1")
    endif
    if (o16_in < 0.0_rt .or. o16_in > 1.0_rt) then
       call amrex_error("ERROR: o16_in must be between 0 and 1")
    endif
    if (o16_out < 0.0_rt .or. o16_out > 1.0_rt) then
       call amrex_error("ERROR: o16_out must be between 0 and 1")
    endif
    if (ne23_in < 0.0_rt .or. ne23_in > 1.0_rt) then
       call amrex_error("ERROR: ne23_in must be between 0 and 1")
    endif
    if (ne23_out < 0.0_rt .or. ne23_out > 1.0_rt) then
       call amrex_error("ERROR: ne23_out must be between 0 and 1")
    endif
    if (na23_in < 0.0_rt .or. na23_in > 1.0_rt) then
       call amrex_error("ERROR: na23_in must be between 0 and 1")
    endif
    if (na23_out < 0.0_rt .or. na23_out > 1.0_rt) then
       call amrex_error("ERROR: na23_out must be between 0 and 1")
    endif

    ! Set the composition within and outside the urca shell
    ! If a non-jump profile is used at the shell, these are asymptotic
    xn_in(:)    = 0.0d0
    xn_in(ic12) = c12_in
    xn_in(io16) = o16_in
    xn_in(ine23) = ne23_in
    xn_in(ina23) = na23_in

    xn_out(:)    = 0.0d0
    xn_out(ic12) = c12_out
    xn_out(io16) = o16_out
    xn_out(ine23) = ne23_out
    xn_out(ina23) = na23_out
  end subroutine init_urca_composition


  subroutine set_urca_composition(eos_state)

    ! Construct composition profiles given a choice of
    ! the type of profile denoted by urca_shell_type.
    ! "jump": impose sharp species discontinuity
    ! "atan": use arctan to smooth composition profile
    use amrex_error_module
    use amrex_fort_module, only : rt => amrex_real
    use network
    use eos_type_module, only: eos_t

    type (eos_t), intent(inout) :: eos_state

    if (urca_shell_type .eq. "jump") then
       call composition_jump(eos_state, urca_23_dens, xn_in, xn_out)
    else if (urca_shell_type .eq. "atan") then
       call composition_atan(eos_state, urca_23_dens, xn_in, xn_out, shell_atan_kappa)
    else if (urca_shell_type .eq. "equilibrium") then
       call composition_equilibrium(eos_state)
    else
       call amrex_error("ERROR: invalid urca_shell_type")
    end if

    ! Floor species so abundances below 1E-30 are 0.0d0
    call floor_species(eos_state)
    
    ! Renormalize species
    call renormalize_species(eos_state)

  end subroutine set_urca_composition


  subroutine floor_species(eos_state)

    ! Species mass fractions below 1E-30 should just be 0.0
    ! This prevents getting abundances of ~1E-100. Note that
    ! the initial model writing omits the "E" in the exponent
    ! if the exponent requires 3 digits.
    use amrex_constants_module, only: ZERO
    use amrex_fort_module, only : rt => amrex_real
    use eos_type_module, only: eos_t
    use network, only: nspec

    type (eos_t), intent(inout) :: eos_state
    real (kind=rt), parameter :: mass_fraction_floor = 1.0d-30
    integer :: i

    do i = 1, nspec
       if (eos_state % xn(i) < mass_fraction_floor) then
          eos_state % xn(i) = ZERO
       end if
    end do

  end subroutine floor_species


  subroutine renormalize_species(eos_state)

    ! Renormalize the mass fractions so they sum to 1
    use amrex_fort_module, only : rt => amrex_real
    use eos_type_module, only: eos_t

    type (eos_t), intent(inout) :: eos_state
    real (kind=rt) :: sumx

    sumx = sum(eos_state % xn)
    eos_state % xn(:) = eos_state % xn(:)/sumx

  end subroutine renormalize_species


  subroutine composition_jump(eos_state, shell_rho, xn_left, xn_right)
    use amrex_fort_module, only : rt => amrex_real
    use amrex_constants_module, only: HALF
    use network
    use eos_type_module, only: eos_t

    type (eos_t), intent(inout) :: eos_state
    real (kind=rt), intent( in) :: shell_rho
    real (kind=rt), intent( in), dimension(nspec) :: xn_left, xn_right

    if (eos_state % rho < shell_rho) then
       eos_state % xn = xn_right
    else if (eos_state % rho > shell_rho) then
       eos_state % xn = xn_left
    else
       eos_state % xn = HALF*(xn_right + xn_left)
    end if
  end subroutine composition_jump


  subroutine composition_atan(eos_state, shell_rho, xn_left, xn_right, &
                              shell_atan_kappa)
    use amrex_fort_module, only : rt => amrex_real
    use amrex_constants_module, only: TWO, HALF, M_PI
    use network
    use eos_type_module, only: eos_t

    type (eos_t), intent(inout) :: eos_state
    real (kind=rt), intent(in) :: shell_rho, shell_atan_kappa
    real (kind=rt), intent(in),  dimension(nspec) :: xn_left, xn_right
    real (kind=rt), dimension(nspec) :: A, B

    B = HALF * (xn_left + xn_right)
    A = xn_right - B

    eos_state % xn = (TWO/M_PI) * A * atan(shell_atan_kappa * (shell_rho - eos_state % rho)) + B
  end subroutine composition_atan


  subroutine composition_equilibrium(eos_state)

    use amrex_fort_module, only : rt => amrex_real
    use amrex_constants_module, only: ZERO, HALF, ONE
    use amrex_error_module,  only: amrex_error
    use network
    use actual_network, only: k_na23__ne23, k_ne23__na23
    use actual_rhs_module, only: rate_eval_t, evaluate_rates
    use eos_type_module, only: eos_t
    use eos_composition_module
    use burn_type_module, only: burn_t, eos_to_burn

    implicit none

    type (eos_t), intent(inout) :: eos_state
    type (burn_t) :: burn_state
    double precision :: fopt, r_ecap, r_beta, dx
    double precision, parameter :: rate_equilibrium_tol = 1.0e-10
    integer, parameter :: max_equilibrium_iters = 10000
    type (rate_eval_t) :: rate_eval

    ! Get some mass fraction indices
    integer :: ic12, io16, ine23, ina23, j

    ! get the species indices
    ic12  = network_species_index("carbon-12")
    io16  = network_species_index("oxygen-16")
    ine23 = network_species_index("neon-23")
    ina23 = network_species_index("sodium-23")
    
    ! Initialize mass fractions given "in" values
    eos_state % xn(:)    = 0.0d0
    eos_state % xn(ic12) = c12_in
    eos_state % xn(io16) = o16_in
    eos_state % xn(ine23) = HALF * na_ne_23
    eos_state % xn(ina23) = HALF * na_ne_23

    ! Estimate the mass fractions approximating the rates as
    ! independent of ye.
    call composition(eos_state)
    call eos_to_burn(eos_state, burn_state)
    call evaluate_rates(burn_state, rate_eval)

    r_ecap = rate_eval % screened_rates(k_na23__ne23)
    r_beta = rate_eval % screened_rates(k_ne23__na23)

    eos_state % xn(ine23) = na_ne_23/(ONE + r_beta/r_ecap)
    eos_state % xn(ina23) = na_ne_23 - eos_state % xn(ine23)

    ! Keep the mass fraction sum X(ne23) + X(na23) = na_ne_23
    ! Find the A=23 mass fractions such that A=23 Urca rates are in equilibrium
    ! Do Newton iterations approximating the rates as independent of mass fraction
    call fopt_urca_23(eos_state, fopt, r_ecap, r_beta)
!    write(*,*) 'fopt = ', fopt
    j = 1
    do while (abs(fopt) > rate_equilibrium_tol .and. j < max_equilibrium_iters)
!       write(*,*) 'iteration ', j, ' fopt = ', fopt
       dx = -fopt/(r_ecap + r_beta)       
       if (fopt > ZERO) then
          eos_state % xn(ina23) = eos_state % xn(ina23) + dx
          eos_state % xn(ine23) = na_ne_23 - eos_state % xn(ina23)
          call fopt_urca_23(eos_state, fopt, r_ecap, r_beta)
       else
          eos_state % xn(ine23) = eos_state % xn(ine23) - dx
          eos_state % xn(ina23) = na_ne_23 - eos_state % xn(ine23)
          call fopt_urca_23(eos_state, fopt, r_ecap, r_beta)
       end if
       j = j + 1
!       write(*,*) 'xn = ', eos_state % xn
    end do

    if (j == max_equilibrium_iters) then
       call amrex_error("species iteration did not converge!")
    end if

  end subroutine composition_equilibrium


  subroutine fopt_urca_23(eos_state, fopt, r_ecap, r_beta)

    use amrex_constants_module, only: HALF
    use eos_type_module, only: eos_t
    use eos_composition_module, only : composition
    use network
    use actual_network, only: k_na23__ne23, k_ne23__na23
    use actual_rhs_module, only: rate_eval_t, evaluate_rates
    use burn_type_module, only: burn_t, eos_to_burn

    implicit none

    type (eos_t), intent(inout) :: eos_state
    double precision, intent(out) :: fopt, r_ecap, r_beta
    double precision :: xr_ecap, xr_beta
    integer :: ine23, ina23
    type (burn_t) :: burn_state
    type (rate_eval_t) :: rate_eval

    ine23 = network_species_index("neon-23")
    ina23 = network_species_index("sodium-23")

    call composition(eos_state)
    call eos_to_burn(eos_state, burn_state)
    call evaluate_rates(burn_state, rate_eval)

    r_ecap = rate_eval % screened_rates(k_na23__ne23)
    r_beta = rate_eval % screened_rates(k_ne23__na23)

    xr_ecap = burn_state % xn(ina23) * r_ecap
    xr_beta = burn_state % xn(ine23) * r_beta

    fopt = xr_ecap - xr_beta

  end subroutine fopt_urca_23

end module urca_composition_module
