#!/bin/sh

function usage {
#  echo "Usage:  MinMonPlt.sh SUFFIX [PDATE] [EDATE]"
  echo "Usage:  MinMonPlt.sh SUFFIX [PDATE]"
  echo "            SUFFIX is data source identifier that matches data in "
  echo "              the $TANKverf/stats directory."
  echo "            PDATE (format:  YYYYMMDDHH) optional, is only/first date to plot"
#  echo "            EDATE (format:  YYYYMMDDHH) optional, is last date to plot"
}

set -ax
echo start MinMonPlt.sh

nargs=$#
if [[ $nargs -lt 1 ]]; then
   usage
   exit 1
fi

export SUFFIX=$1

if [[ $nargs -ge 2 ]]; then
   export PDATE=$2
fi
#if [[ $nargs -eq 3 ]]; then
#   export EDATE=$3
#fi

this_file=`basename $0`
this_dir=`dirname $0`

#--------------------------------------------------
# source verison, config, and user_settings files
#--------------------------------------------------
top_parm=${this_dir}/../../parm

minmon_version_file=${minmon_version:-${top_parm}/MinMon.ver}
if [[ -s ${minmon_version_file} ]]; then
   . ${minmon_version_file}
   echo "able to source ${minmon_version_file}"
else
   echo "Unable to source ${minmon_version_file} file"
   exit 2
fi

minmon_config=${minmon_config:-${top_parm}/MinMon_config}
if [[ -s ${minmon_config} ]]; then
   . ${minmon_config}
   echo "able to source ${minmon_config}"
else
   echo "Unable to source ${minmon_config} file"
   exit 3
fi

minmon_user_settings=${minmon_user_settings:-${top_parm}/MinMon_user_settings}
if [[ -s ${minmon_user_settings} ]]; then
   . ${minmon_user_settings}
   echo "able to source ${minmon_user_settings}"
else
   echo "Unable to source ${minmon_user_settings} file"
   exit 4
fi

plot_minmon_conf=${plot_minmon_conf:-${IG_PARM}/plot_minmon_conf}
if [[ -s ${plot_minmon_conf} ]]; then
   . ${plot_minmon_conf}
   echo "able to source ${plot_minmon_conf}"
else
   echo "Unable to source ${plot_minmon_conf} file"
   exit 5
fi


#--------------------------------------------------------------------
#  Check for my monitoring use.  Abort if running on prod machine.
#--------------------------------------------------------------------
if [[ RUN_ONLY_ON_DEV =  1 ]]; then
   is_prod=`${IG_SCRIPTS}/onprod.sh`
   if [[ $is_prod = 1 ]]; then
      exit 10
   fi
fi


#--------------------------------------------------------------------
#  Specify TANKDIR for this suffix
#--------------------------------------------------------------------
if [[ $AREA == "glb" ]]; then
   export TANKDIR=${TANKverf}/stats/${SUFFIX}/gsistat
else
   export TANKDIR=${TANKverf}/stats/regional/${SUFFIX}/gsistat
fi

#--------------------------------------------------------------------
#  If PDATE wasn't specified as an argument then plot the last
#  available cycle.
#--------------------------------------------------------------------
if [[ ${#PDATE} -le 0 ]]; then
   lastdir=`ls -1d ${TANKDIR}/GDAS_minmon.* | tail -1`
   lastln=`cat $lastdir/GDAS.gnorm_data.txt | tail -1`
   export PDATE=`echo $lastln | gawk '{split($0,a,","); print a[1] a[2] a[3] a[4]}'`
fi

#--------------------------------------------------------------------
#  Create the WORKDIR and link the data files to it
#--------------------------------------------------------------------
if [[ -d $WORKDIR ]]; then
  rm -rf $WORKDIR
fi
mkdir $WORKDIR
cd $WORKDIR

#--------------------------------------------------------------------
#  Copy gnorm_data.txt file to WORKDIR.
#--------------------------------------------------------------------
pdy=`echo $PDATE|cut -c1-8`
gnorm_file=${TANKDIR}/${SUFFIX}_minmon.${pdy}/${SUFFIX}.gnorm_data.txt
local_gnorm=gnorm_data.txt

if [[ -s ${gnorm_file} ]]; then
   cp ${gnorm_file} ./${local_gnorm}
else
   echo "WARNING:  Unable to locate ${gnorm_file}!"
fi

#------------------------------------------------------------------
#  Copy the cost.txt and cost_terms.txt files files locally
#
#  These aren't used for processing but will be pushed to the
#    server from the tmp dir.
#------------------------------------------------------------------
costs=${TANKDIR}/${SUFFIX}_minmon.${pdy}/${SUFFIX}.${PDATE}.costs.txt
cost_terms=${TANKDIR}/${SUFFIX}_minmon.${pdy}/${SUFFIX}.${PDATE}.cost_terms.txt

if [[ -s ${costs} ]]; then
   cp ${costs} .
else
   echo "WARNING:  Unable to locate ${costs}"
fi

if [[ -s ${cost_terms} ]]; then
  cp ${cost_terms} .
else
   echo "WARNING:  Unable to locate ${cost_terms}"
fi


bdate=`$NDATE -174 $PDATE`
edate=$PDATE
cdate=$bdate

#------------------------------------------------------------------
#  Add links for required data files (gnorms and reduction) to 
#   enable calculation of 7 day average
#------------------------------------------------------------------
while [[ $cdate -le $edate ]]; do
   echo "processing cdate = $cdate"
   pdy=`echo $cdate|cut -c1-8`

   gnorms_file=${TANKDIR}/${SUFFIX}_minmon.${pdy}/${SUFFIX}.${cdate}.gnorms.ieee_d
   local_gnorm=${cdate}.gnorms.ieee_d

   reduct_file=${TANKDIR}/${SUFFIX}_minmon.${pdy}/${SUFFIX}.${cdate}.reduction.ieee_d
   local_reduct=${cdate}.reduction.ieee_d

   if [[ -s ${gnorms_file} ]]; then
      ln -s ${gnorms_file} ${WORKDIR}/${local_gnorm}
   else
      echo "WARNING:  Unable to locate ${gnorms_file}"
   fi
   if [[ -s ${reduct_file} ]]; then
      ln -s ${reduct_file} ${WORKDIR}/${local_reduct}
   else
      echo "WARNING:  Unable to locate ${reduct_file}"
   fi

   adate=`$NDATE +6 $cdate`
   cdate=$adate
done


#--------------------------------------------------------------------
#  Main processing loop.  
#  Run extract_all_gnorms.pl script and generate single cycle plot.
#
#  RM this loop or add an optional end date to the args list and 
#  process each date in turn.
#
#  And alternate plot method might be to simply plot the last 
#  available cycle if no PDATE is included.  Could use find_cycle.pl
#  to find the last one and done.
#
#  Also should an attempt to plot a date for which there is no data
#  produce an error exit?  I think so.
#--------------------------------------------------------------------
not_done=1
ctr=0
while [ $not_done -eq 1 ] && [ $ctr -le 20 ]; do

   #-----------------------------------------------------------------
   #  copy over the control files and update the tdef lines 
   #  according to the $suffix
   #-----------------------------------------------------------------
   if [[ ! -e ${WORKDIR}/allgnorm.ctl ]]; then
      cp ${IG_GRDS}/${AREA}_allgnorm.ctl ${WORKDIR}/allgnorm.ctl
   fi
 
   if [[ ! -e ${WORKDIR}/reduction.ctl ]]; then
      cp ${IG_GRDS}/${AREA}_reduction.ctl ${WORKDIR}/reduction.ctl
   fi

  
   # 
   # update the tdef line in the ctl files
   # 
   bdate=`$NDATE -168 $PDATE`
   ${IG_SCRIPTS}/update_ctl_tdef.sh ${WORKDIR}/allgnorm.ctl ${bdate}
   ${IG_SCRIPTS}/update_ctl_tdef.sh ${WORKDIR}/reduction.ctl ${bdate}

#   if [[ $AREA = "glb" ]]; then
#      ${SCRIPTS}/update_ctl_xdef.sh ${WORKDIR}/allgnorm.ctl 202 
#   fi

   #######################
   # Q:  does NDAS really use 101 instead of 102?  That can't be somehow....
   #######################

   if [[ $SUFFIX = "RAP" ]]; then
      ${IG_SCRIPTS}/update_ctl_xdef.sh ${WORKDIR}/allgnorm.ctl 102 
   fi

   #-----------------------------------------------------------------
   #  Copy the plot script and build the plot driver script 
   #-----------------------------------------------------------------
   if [[ ! -e ${WORKDIR}/plot_gnorms.gs ]]; then
      cp ${IG_GRDS}/plot_gnorms.gs ${WORKDIR}/.
   fi
   if [[ ! -e ${WORKDIR}/plot_reduction.gs ]]; then
      cp ${IG_GRDS}/plot_reduction.gs ${WORKDIR}/.
   fi
 
 
cat << EOF >${PDATE}_plot_gnorms.gs
'open allgnorm.ctl'
'run plot_gnorms.gs $SUFFIX $PDATE x1100 y850'
'quit'
EOF

cat << EOF >${PDATE}_plot_reduction.gs
'open reduction.ctl'
'run plot_reduction.gs $SUFFIX $PDATE x1100 y850'
'quit'
EOF

  #-----------------------------------------------------------------
  #  Run the plot driver script and move the image into ./tmp
  #-----------------------------------------------------------------
  GRADS=`which grads`
  $TIMEX $GRADS -blc "run ${PDATE}_plot_gnorms.gs"
  $TIMEX $GRADS -blc "run ${PDATE}_plot_reduction.gs"

  if [[ ! -d ${WORKDIR}/tmp ]]; then
     mkdir ${WORKDIR}/tmp
  fi
  mv *.png tmp/.

  #-----------------------------------------------------------------
  #  copy the modified gnorm_data.txt file to tmp
  #-----------------------------------------------------------------
#  cp -f gnorm_data.txt ${TANKDIR}/
  cp gnorm_data.txt tmp/${SUFFIX}.gnorm_data.txt

 
  ctr=`expr $ctr + 1`
done

#-----------------------------------------------------------------
# copy all cost files to tmp 
#-----------------------------------------------------------------
cp *cost*.txt tmp/.

#--------------------------------------------------------------------
#  Build and run the plot driver script for the four cycle plot and 
#  move the image into ./tmp
#--------------------------------------------------------------------
#PDATE=`${SCRIPTS}/get_last_cycle.pl ${WORKDIR}/gnorm_data.txt`
#cp ${SCRIPTS}/plot_4_gnorms.gs ${WORKDIR}/.
#
#cat << EOF >${PDATE}_plot_4_gnorms.gs
#'open allgnorm.ctl'
#'run plot_4_gnorms.gs $SUFFIX $PDATE x1100 y850'
#'quit'
#EOF

#$TIMEX $GRADS -blc "run ${PDATE}_plot_4_gnorms.gs"
#
#if [[ ! -d ${WORKDIR}/tmp ]]; then
#   mkdir ${WORKDIR}/tmp
#fi
#mv *.png tmp/.

#--------------------------------------------------------------------
#  Push the image & txt files over to the server
#--------------------------------------------------------------------
   if [[ $MY_MACHINE = "wcoss" ]]; then
      cd ./tmp
#      echo "webuser:    $WEBUSER"
#      echo "webserver:  $WEBSERVER"
#      echo "webdir:     $WEBDIR"
      $RSYNC -ave ssh --exclude *.ctl*  ./ \
        ${WEBUSER}@${WEBSERVER}:${WEBDIR}/
   fi
#--------------------------------------------------------------------
#  Call update_save.sh to copy latest 15 days worth of data files 
#  from $TANKDIR to /sss.../da/save so prod machine can access the 
#  same data.
#--------------------------------------------------------------------

#   ${SCRIPTS}/update_sss.sh

#cd ${WORKDIR}
#cd ..
#rm -rf ${WORKDIR}

echo end MinMonPlt.sh
exit
