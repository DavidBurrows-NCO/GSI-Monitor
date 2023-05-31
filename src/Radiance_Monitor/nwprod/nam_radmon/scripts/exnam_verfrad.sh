#/bin/bash

# Run data extract/validation for regional radiance diag data
echo "---> exnam_vrfyrad.sh.ecf"

export RUN_ENVIR=${RUN_ENVIR:-nco}
export NET=${NET:-nam}
export RUN=${RUN:-nam}
#export envir=${envir:-prod}

#  Command line arguments
export PDY=${1:-${PDY:?}} 
export cyc=${2:-${cyc:?}}

#  Directories
#export DATA=${DATA:-$(pwd)}
#export COM_IN=${COMROOT}/${NET}/${envir}
#export COMIN=${COMIN:-$COM_IN/${RUN}.${PDY}}

export HOMEnam=${HOMEnam:-${NWROOT}/nam.${nam_ver}}
export FIXnam=${FIXnam:-${HOMEnam}/fix}
export USHnam=${USHnam:-${HOMEnam}/ush}

#export HOMEradmon=${HOMEradmon:-/${NWROOT}/radmon_shared.v${radmon_shared_ver}}
#export EXECradmon=${EXECradmon:-$HOMEradmon/exec}
#export FIXradmon=${FIXradmon:-${HOMEradmon}/fix}
export USHradmon=${USHradmon:-$HOMEradmon/ush}

#  Filenames
#export biascr=${biascr:-$COMOUT/${RADMON_SUFFIX}.t${cyc}z.satbias.${rgnTM}}
#export radstat=${radstat:-$COMOUT/${RADMON_SUFFIX}.t${cyc}z.radstat.${rgnTM}}
export satype_file=${satype_file:-nam_radmon_satype.txt}
export base_file=${base_file:-${FIXnam}/nam_radmon_base.tar}

#  Other variables
#export RAD_AREA=${RAD_AREA:-rgn}
export MAKE_CTL=${MAKE_CTL:-1}
export MAKE_DATA=${MAKE_DATA:-1}
export USE_ANL=${USE_ANL:-1}
export PDATE=${PDY}${cyc}
export DO_DIAG_RPT=${DO_DIAG_RPT:-1}
export DO_DATA_RPT=${DO_DATA_RPT:-1}
export NCP=${NCP:-/bin/cp}

# RM this
export NDATE=${NDATE:-/nwprod/util/exec/ndate}
echo "NDATE = $NDATE"

export Z=${Z:-"gz"}
export UNCOMPRESS=${UNCOMPRESS:-"gunzip -f"}

#  NOTE for namrr:  the contents of the t00z.radstat.tm06-tm01 are stored
#  in the _next_ day's radmon.[yyyymmdd] file to match the way the radstat
#  files are created.  
#    The pattern is for radmon.20160318:
#       t00z.radstat.tm06  contents is dated 2016031718
#       t00z.radstat.tm05  contents is dated 2016031719
#           . . .
#       t00z.radstat.tm01  contents is dated 2016031723
#       t00z.radstat.tm00  contents is dated 2016031800
#
export TANKverf=${TANKverf:-/com/${NET}/prod}
export TANKverf_rad=${TANKverf_rad:-${TANKverf}/radmon.${PDY}}

###########################################################################
# ensure work and TANK dirs exist, verify radstat and biascr are available
if [[ ! -d ${DATA} ]]; then
   mkdir $DATA
fi
cd $DATA

if [[ ! -d ${TANKverf_rad} ]]; then
   mkdir -p $TANKverf_rad
fi

if [[ "$VERBOSE" = "YES" ]]; then
   if [[ -s ${radstat} ]]; then
      echo ${radstat} is available
   fi
   if [[ -s ${biascr} ]]; then
      echo ${biascr} is available
   fi
fi
#####################################################################

data_available=0
if [[ -s ${radstat} && -s ${biascr} ]]; then
   data_available=1                                         

   #------------------------------------------------------------------
   #  Copy data files file to local data directory.  
   #  Untar radstat file.  
   #------------------------------------------------------------------

   ${NCP} ${biascr}  ./biascr.${PDATE}
   ${NCP} ${radstat} ./radstat.${PDATE}

   tar -xf radstat.${PDATE}
   rm radstat.$PDATE

   #------------------------------------------------------------------
   #  SATYPE is the list of expected satellite/instrument sources
   #  in the radstat file.  It should be stored in the $TANKverf 
   #  directory.  If it isn't there then use the $FIXnam copy.  In all 
   #  cases write it back out to the radmon.$PDY directory.  Add any
   #  new sources to the list before writing back out.
   #------------------------------------------------------------------

   radstat_satype=`ls d*ges* | awk -F_ '{ print $2 "_" $3 }'`
#   if [[ "${VERBOSE}" = "YES" ]]; then
#      echo ${radstat_satype}
#   fi

   echo satype_file = ${satype_file}
 
   #------------------------------------------------------------------
   #  Get previous cycle's date, and look for the satype_file.  Using 
   #  the previous cycle will get us the previous day's directory if 
   #  the cycle being processed is 00z.
   #------------------------------------------------------------------
   if [[ $CYC = "00" ]]; then
      pday=${PDYm1}
   else
      pday=${PDY}
   fi

#   echo "FIXnam = ${FIXnam}"

   if [[ ! -e ${TANKverf}/radmon.${pday}/${satype_file} ]]; then
      if [[ ! -e ${FIXnam}/${satype_file} ]]; then 
         export SATYPE=${radstat_satype}
#         if [[ "$VERBOSE" = "YES" ]]; then
#            echo " ${satype_file} not found.  Adding it now using radstat file contents."
#         fi
      else
         export SATYPE=`cat ${FIXnam}/${satype_file}`
      fi
   else
      export SATYPE=`cat ${TANKverf}/radmon.${pday}/${satype_file}`
   fi


   #-------------------------------------------------------------
   #  Update the SATYPE if any new sat/instrument was 
   #  found in $radstat_satype. 
   #-------------------------------------------------------------
   satype_changes=0
   new_satype=${SATYPE}
   for type in ${radstat_satype}; do
      test=`echo ${SATYPE} | grep ${type} | wc -l`

      if [[ ${test} -eq 0 ]]; then
         if [[ "$VERBOSE" = "YES" ]]; then
            echo "FOUND ${type} in radstat file but not in SATYPE list.  Adding it now."
         fi
         satype_changes=1
         new_satype="${new_satype} ${type}"
      fi
   done

   if [[ ${satype_changes} -eq 1 ]]; then
      SATYPE=${new_satype}
   fi
   export SATYPE=${SATYPE}

   echo "SATYPE = $SATYPE"  
 
   #------------------------------------------------------------------
   # Determine bin or nc4 diag files, rename, and uncompress
   #------------------------------------------------------------------

   netcdf=0

   for type in ${SATYPE}; do
      if [[ -e ./diag_${type}_ges.${PDATE}.nc4.${Z} ]]; then
         netcdf=1; break
      fi
   done

   export RADMON_NETCDF=$netcdf
   echo "RADMON_NETCDF = $RADMON_NETCDF"

   for type in ${SATYPE}; do
#      echo "type = $type"
#      echo dir_ls=`ls `
#      echo dir_ls = $dir_ls

      if [[ ! -e ./diag_${type}_ges.${PDATE}.nc4.${Z} ]]; then
         edited_satype="$(echo $SATYPE | tr ' ' '\n' | sed "/${type}/d")"
         echo "REMOVED:  $type from SATYPE"
         export SATYPE=${edited_satype}

      else 
         mv ./diag_${type}_ges.${PDATE}.nc4.${Z} ${type}.${Z}

         ${UNCOMPRESS} ./${type}.${Z}
     
         if [[ $USE_ANL -eq 1 ]]; then
            mv ./diag_${type}_anl.${PDATE}.*${Z} ${type}_anl.${Z}
            ${UNCOMPRESS} ./${type}_anl.${Z}
         fi
      fi

   done

   #------------------------------------------------------------------
   #   Run the child sccripts.
   #------------------------------------------------------------------
   export shared_scaninfo=$FIXnam/nam_radmon_scaninfo.txt
   ${USHnam}/radmon_verf_angle.sh ${PDATE}
   rc_angle=$?

   ${USHnam}/radmon_verf_bcoef.sh ${PDATE}
   rc_bcoef=$?

   ${USHnam}/radmon_verf_bcor.sh ${PDATE}
   rc_bcor=$?

   ${USHnam}/radmon_verf_time.sh ${PDATE}
   rc_time=$?

   #--------------------------------------
   #  optionally run clean_tankdir script
   #
#   if [[ ${CLEAN_TANKVERF} -eq 1 ]]; then
#      ${USHradmon}/clean_tankdir.sh rgn 10 
#      rc_clean_tankdir=$?
#      echo "rc_clean_tankdir = $rc_clean_tankdir"
#   fi

fi

#####################################################################
# Postprocessing

err=0
if [[ ${data_available} -ne 1 ]]; then
   err=1
elif [[ $rc_angle -ne 0 ]]; then
   err=$rc_angle
elif [[ $rc_bcoef -ne 0 ]]; then
   err=$rc_bcoef
elif [[ $rc_bcor -ne 0 ]]; then
   err=$rc_bcor
elif [[ $rc_time -ne 0 ]]; then
   err=$rc_time
fi

if [[ "$VERBOSE" = "YES" ]]; then
   echo "end exnam_vrfyrad.sh.ecf, exit value = ${err}"
fi


echo "<--- exnam_vrfyrad.sh.ecf"
set +x
exit ${err}

