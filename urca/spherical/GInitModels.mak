# A set of useful macros for putting together one of the initial model
# generator routines

# include the main Makefile stuff
include $(FBOXLIB_HOME)/Tools/F_mk/GMakedefs.mak

# default target (make just takes the one that appears first)
ALL: init_1d.$(suf).exe


#-----------------------------------------------------------------------------
# core AMReX directories
FBOXLIB_CORE := Src/BaseLib
FPP_DEFINES += -DAMREX_DEVICE=""


#-----------------------------------------------------------------------------
# default to $(MICROPHYSICS_HOME) for the EOS unless we are gamma_law_general
ifeq ($(EOS_DIR), gamma_law_general)
  EOS_TOP_DIR := $(MAESTRO_HOME)/Microphysics/EOS
else
  EOS_TOP_DIR := $(MICROPHYSICS_HOME)/EOS
endif

# we need all the thermodynamics
FPP_DEFINES += -DEXTRA_THERMO

ifeq ($(EOS_DIR), helmeos)
  EOS_DIR := helmholtz
  $(info EOS_DIR = helmeos is deprecated.  Please use helmholtz instead)
endif

# the helmeholtz eos has an include file -- also add a target to link
# the table into the problem directory.
ifeq ($(findstring helmholtz, $(EOS_DIR)), helmholtz)
  EOS_PATH := $(EOS_TOP_DIR)/helmholtz
  ALL: table
endif

table:
	@if [ ! -f helm_table.dat ]; then echo ${bold}Linking helm_table.dat${normal}; ln -s $(EOS_PATH)/helm_table.dat .;  fi

# For the URCA network in Microphysics, link the rate tables
ifeq ($(findstring URCA-simple, $(NETWORK_DIR)), URCA-simple)
  ALL: urcatables
endif


urcatables:
	@if [ ! -f 23Ne-23Na_betadecay.dat ]; then echo ${bold}Linking 23Ne-23Na_betadecay.dat${normal}; ln -s $(NETWORK_TOP_DIR)/$(NETWORK_DIR)/23Ne-23Na_betadecay.dat .;  fi
	@if [ ! -f 23Na-23Ne_electroncapture.dat ]; then echo ${bold}Linking 23Na-23Ne_electroncapture.dat${normal}; ln -s $(NETWORK_TOP_DIR)/$(NETWORK_DIR)/23Na-23Ne_electroncapture.dat .;  fi


# All networks except general_null should pull in the Microphysics repository.
ifneq ($(findstring general_null, $(NETWORK_DIR)), general_null)
  NETWORK_TOP_DIR := $(MICROPHYSICS_HOME)/networks
  include $(NETWORK_TOP_DIR)/GNetwork.mak
else
  NETWORK_TOP_DIR := $(MAESTRO_HOME)/Microphysics/networks
  MICROPHYS_CORE += $(NETWORK_TOP_DIR) $(NETWORK_TOP_DIR)/$(NETWORK_DIR)
endif

ifdef SYSTEM_BLAS
  libraries += $(BLAS_LIBRARY)
endif

# are we using the stellar conductivity?
CONDUCTIVITY_DIR ?= stellar
ifeq ($(findstring stellar, $(CONDUCTIVITY_DIR)), stellar)
  CONDUCTIVITY_TOP_DIR := $(MICROPHYSICS_HOME)/conductivity
endif

ifndef CONDUCTIVITY_TOP_DIR
  CONDUCTIVITY_TOP_DIR := $(MAESTRO_HOME)/Microphysics/conductivity
endif



# add in the network, EOS, and conductivity
MICROPHYS_CORE += $(MAESTRO_HOME)/Microphysics/EOS \
		  $(MAESTRO_HOME)/Microphysics/networks \
		  $(EOS_TOP_DIR) \
		  $(EOS_TOP_DIR)/$(EOS_DIR) \
                  $(MAESTRO_HOME)/Microphysics/conductivity \
                  $(CONDUCTIVITY_TOP_DIR)/$(CONDUCTIVITY_DIR)

# get any additional network dependencies
include $(NETWORK_TOP_DIR)/$(strip $(NETWORK_DIR))/NETWORK_REQUIRES



#-----------------------------------------------------------------------------
# extra directory
ifndef EXTRA_TOP_DIR
  EXTRA_TOP_DIR := $(MAESTRO_HOME)/
endif

EXTRAS := $(addprefix $(EXTRA_TOP_DIR)/, $(EXTRA_DIR))

ifndef EXTRA_TOP_DIR2
  EXTRA_TOP_DIR2 := $(MAESTRO_HOME)/
endif

EXTRAS += $(addprefix $(EXTRA_TOP_DIR2)/, $(EXTRA_DIR2))

ifdef NEED_VODE
  Fmdirs += Util/VODE Util/LINPACK Util/BLAS
endif

ifdef NEED_BLAS
  Fmdirs += Util/BLAS
endif

ifdef NEED_LINPACK
  UTIL_CORE += Util/LINPACK
endif

ifdef NEED_VBDF
  UTIL_CORE += Util/VBDF
endif

Fmdirs += Util/model_parser Util/simple_log


# explicitly add in any source defined in the build directory
f90sources += $(MODEL_SOURCES)


#-----------------------------------------------------------------------------
# core FBoxLib directories
Fmpack := $(foreach dir, $(FBOXLIB_CORE), $(FBOXLIB_HOME)/$(dir)/GPackage.mak)
Fmlocs := $(foreach dir, $(FBOXLIB_CORE), $(FBOXLIB_HOME)/$(dir))
Fmincs :=


# auxillary directories
Fmpack += $(foreach dir, $(Fmdirs), $(MAESTRO_HOME)/$(dir)/GPackage.mak)
Fmpack += $(foreach dir, $(MICROPHYS_CORE), $(dir)/GPackage.mak)

Fmlocs += $(foreach dir, $(Fmdirs), $(MAESTRO_HOME)/$(dir))
Fmlocs += $(foreach dir, $(MICROPHYS_CORE), $(dir))

Fmincs += $(foreach dir, $(Fmincludes), $(MAESTRO_HOME)/$(dir))

# Extras
Fmpack += $(foreach dir, $(EXTRAS), $(dir)/GPackage.mak)
Fmlocs += $(foreach dir, $(EXTRAS), $(dir))

# include the necessary GPackage.mak files that define this setup
include $(Fmpack)



# we need a probin.f90, since the various microphysics routines can
# have runtime parameters
F90sources += probin.F90

PROBIN_TEMPLATE := $(MAESTRO_HOME)/Util/parameters/dummy.probin.template
PROBIN_PARAMETER_DIRS = $(MAESTRO_HOME)/Util/initial_models/
EXTERN_PARAMETER_DIRS += $(MICROPHYS_CORE) $(NETWORK_TOP_DIR)


PROBIN_PARAMETERS := $(shell $(FBOXLIB_HOME)/Tools/F_scripts/findparams.py $(PROBIN_PARAMETER_DIRS))
EXTERN_PARAMETERS := $(shell $(FBOXLIB_HOME)/Tools/F_scripts/findparams.py $(EXTERN_PARAMETER_DIRS))


probin.F90: $(PROBIN_PARAMETERS) $(EXTERN_PARAMETERS) $(PROBIN_TEMPLATE)
	@echo " "
	@echo "${bold}WRITING probin.F90${normal}"
	$(FBOXLIB_HOME)/Tools/F_scripts/write_probin.py \
           -t $(PROBIN_TEMPLATE) -o probin.F90 -n probin \
           --pa "$(PROBIN_PARAMETERS)" --pb "$(EXTERN_PARAMETERS)"
	@echo " "


# vpath defines the directories to search for the source files

#  VPATH_LOCATIONS to first search in the problem directory      
#  Note: GMakerules.mak will include '.' at the start of the
VPATH_LOCATIONS += $(Fmlocs)


# we need the MAESTRO constants
f90sources += constants_cgs.f90
VPATH_LOCATIONS += $(MAESTRO_HOME)/Source


# list of directories to put in the Fortran include path
FINCLUDE_LOCATIONS += $(Fmincs)


#-----------------------------------------------------------------------------
# build_info stuff
deppairs: build_info.f90

build_info.f90:
	@echo " "
	@echo "${bold}WRITING build_info.f90${normal}"
	$(FBOXLIB_HOME)/Tools/F_scripts/makebuildinfo.py \
           --modules "$(Fmdirs) $(MICROPHYS_CORE) $(UNIT_DIR)" \
           --FCOMP "$(COMP)" \
           --FCOMP_version "$(FCOMP_VERSION)" \
           --f90_compile_line "$(COMPILE.f90)" \
           --f_compile_line "$(COMPILE.f)" \
           --C_compile_line "$(COMPILE.c)" \
           --link_line "$(LINK.f90)" \
           --fboxlib_home "$(FBOXLIB_HOME)" \
           --source_home "$(MICROPHYSICS_HOME)" \
           --network "$(NETWORK_DIR)" \
           --integrator "$(INTEGRATOR_DIR)" \
           --eos "$(EOS_DIR)"
	@echo " "

$(odir)/build_info.o: build_info.f90
	$(COMPILE.f90) $(OUTPUT_OPTION) build_info.f90
	rm -f build_info.f90

init_1d.$(suf).exe: $(objects)
	$(LINK.f90) -o init_1d.$(suf).exe $(objects) $(libraries)
	@echo SUCCESS

# include the fParallel Makefile rules
include $(FBOXLIB_HOME)/Tools/F_mk/GMakerules.mak


#-----------------------------------------------------------------------------
# for debugging.  To see the value of a Makefile variable,
# e.g. Fmlocs, simply do "make print-Fmlocs".  This will
# print out the value.
print-%: ; @echo $* is $($*)


#-----------------------------------------------------------------------------
# cleaning.  Add more actions to 'clean' and 'realclean' to remove
# probin.F90 and build_info.f90 -- this is where the '::' in make comes
# in handy
clean::
	$(RM) probin.F90
	$(RM) build_info.f90
