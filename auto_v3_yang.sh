#!/bin/bash
#1. Extract DDL from list in SCRTMP.AUTOSASTABSPEC
#2. Generate DDL to Teradata from item 1
#3. 3DES Encryption on the column listed in SCRTMP.AUTOSASTABSPE
#4. Export Data from DB2 and Load into Teradata

#Version Change
#Clean all debug flag
#To-Do
#1. Generate TD FastLoad Script
#2. Create TD Table

#Author: James Chen
#Update Date:20191206
#Version:3.0

dds1=$(date +"%s")


source /home/db2inst1/sqllib/db2profile

##************************************************
##  Define variables
##================================================

vSUser=scrusr  ##source DB username
vSPwd=passwd   ##source DB password
vSDB=scrtmp    ##source DBname

TB_SQL="/u01/app/data/sql/"
EXP_DIR="/u01/app/data/exp_NoEncryption/"
CTL_FL_DIR="/u01/app/ctl_fastload/"
CTL_creTB_DIR="/u01/app/ctl_creTB/"

vSecHead="SSSec_"
vLatin=" CHARACTER SET LATIN CASESPECIFIC"

vDBConn="192.168.1.31/dbc,dbc"
vDBName="yang"
vCHKPOINT="CHECKPOINT 500000"
vDelimit="SET RECORD VARTEXT \"!\""
##------------------------------------------------
##################################################



##************************************************
##  Define functions
##================================================
db2Conn()
{
  db2 +o connect to $vSDB user $vSUser using $vSPwd
}
##-------------------------------------------------------
db2Diss()
{
  db2 +o terminate
}
##-------------------------------------------------------
HeadFile()
{
  ## Head of Create.sql
  echo "Create MULTISET Table $vTAB" > $TB_SQL"$vTAB"_Create.sql
  echo ",FALLBACK ," >> $TB_SQL"$vTAB"_Create.sql	
  echo "NO BEFORE JOURNAL," >> $TB_SQL"$vTAB"_Create.sql
  echo "NO AFTER JOURNAL," >> $TB_SQL"$vTAB"_Create.sql
  echo "CHECKSUM = DEFAULT," >> $TB_SQL"$vTAB"_Create.sql
  echo "DEFAULT MERGEBLOCKRATIO (" >> $TB_SQL"$vTAB"_Create.sql
  
  ## Head of Select.sql
  echo "Select ROW_NUMBER() OVER () rownumber," > $TB_SQL"$vTAB"_Select.sql
  echo "Select " > /u01/app/test_sql/${vTAB}_test_Select.sql
  
  ## Head of fastload.fl
  echo "LOGON $vDBConn;" > "$CTL_FL_DIR$vTAB"_fastload.fl
  echo "  DATABASE $vDBName;" >> "$CTL_FL_DIR$vTAB"_fastload.fl	
  echo "    BEGIN LOADING $vDBName.$vTAB"  >> "$CTL_FL_DIR$vTAB"_fastload.fl
  echo "    ERRORFILES "$vTAB"_ET, "$vTAB"_UV" >> "$CTL_FL_DIR$vTAB"_fastload.fl
  echo "    $vCHKPOINT;" >> "$CTL_FL_DIR$vTAB"_fastload.fl
  echo "    $vDelimit;"  >> "$CTL_FL_DIR$vTAB"_fastload.fl 
  echo "    DEFINE" >> "$CTL_FL_DIR$vTAB"_fastload.fl
}
##-------------------------------------------------------
AfterSQL()
{
  #Prepare DB2 SQL For Export
  vExpSQL=`tr -d '\n' < $TB_SQL"$vTAB"_Select.sql`
  #Generate Data File from DB2
  db2Conn
  db2 +o "export to $EXP_DIR"$vTAB"_ALL.dat of del modified by codepage=950 nochardel coldel! $vExpSQL"
  db2Diss
  iEnd=`expr $y + 1`   ##回傳 $y + 1 之值
  iS=`expr $iEnd + 1`	
  iSEnd=`expr $iEnd + $h`
  
  cat $EXP_DIR"$vTAB"_ALL.dat | cut -d "!" -f1-"$iEnd" > $EXP_DIR"$vTAB"_PRE.dat
  ##echo "$EXP_DIR"$vTAB"_ALL.dat | cut -d ! -f1-$iEnd"
  #TO-DO
  #RM ALL.dat?
  #
  AFILE=$EXP_DIR"$vTAB"_PRE.dat
  if [ $h -gt 0 ]
  then
    iS=`expr $iEnd + 1`
    iSEnd=`expr $iEnd + $h`

    cat $EXP_DIR"$vTAB"_ALL.dat | cut -d "!" -f1,"$iS"-"$iSEnd" > $EXP_DIR"$vTAB"_AFT.dat
    BFILE=$EXP_DIR"$vTAB"_AFT.dat
  fi
  ####
  ##Calling DSJOB
  ##base on H Value to Run DSJOB
}
##-------------------------------------------------------
testAfterSQL()  ## test for fastload
{
  vtestExpSQL=`tr -d '\n' < /u01/app/test_sql/"$vTAB"_test_Select.sql`
  db2Conn
  db2 +o "export to /u01/app/data/exp_Encryption/"$vTAB"_Encryption.dat of del modified by codepage=950 nochardel coldel! $vtestExpSQL"
  db2Diss
}
##------------------------------------------------
##################################################



##************************************************
##  Create sql_select, sql_createTB, crtl_fastload
##================================================
echo "Create sql_select, sql_createTB, crtl_fastload============="

db2Conn
vSQL="SELECT SOURCEDB||'-'|| SOURCETB||'-'||TARGETDB||'-'||TARGETTB||'-'||GRANT||'-'||R_COLUMN FROM SCRTMP.AUTOSASTABSPEC"
vRec=($(db2 -x $vSQL))

db2Diss
j=${#vRec[@]}

typeset -u vCol  ## let table column name capital

i=0
until [ ! $i -lt $j ]
do
  vStr=${vRec[i]}
  
  set -f #aviod globbing of *
  vColvStr=(${vRec[i]//-/ })
  ##echo "vColvStr---153"
  ##echo "${vColvStr[@]}" | tr ' ' '\n'
  
  vSTBName=${vColvStr[1]}
  vTAB=`echo $vSTBName | cut -d . -f2`
  
  creTBfilename[i]=$vTAB  ##  use in <<Create crtl_creTB>>
  
  vSecCol=${vColvStr[5]}
  vSec=(${vColvStr[5]//,/ })
  h=${#vSec[@]}  #Counts of ID Related Columns
  
  
  vSQL="select colname||':'||typename||':'||length||':'||scale||':'||nulls from syscat.columns where trim(TABSCHEMA)||'.'||trim(TABNAME) = '$vSTBName' order by colno"
  db2Conn
  vColumn=($(db2 -x $vSQL))

  vSQL="select colname from syscat.columns where trim(TABSCHEMA)||'.'||trim(TABNAME) = '$vSTBName' and keyseq is not null order by keyseq"
  vKey=($(db2 -x $vSQL)) #Table Index & Sequence
  db2Diss
  
  y=${#vColumn[@]}  ##Count of Column
  r=`expr $y - 1`   ##The number of Last Row

  
  x=0
  until [ ! $x -lt $y ]
  do
    vCol[$x]=`echo ${vColumn[$x]} | cut -d : -f1`
	keyword_1=$(echo "SELECT '>'||restricted_word FROM SYSLIB.SQLRestrictedWords where restricted_word='${vCol[$x]}'" | bteq .LOGON $vDBConn 2>&1 |grep '^>' |sed -e "s/^>//");
	keyword_2=$(echo "SELECT '>'||restricted_word FROM TABLE (SYSLIB.SQLRestrictedWords_TBF()) AS t1 where restricted_word='${vCol[$x]}'" | bteq .LOGON $vDBConn 2>&1 |grep '^>' |sed -e "s/^>//");
	  
	if [ "${vCol[$x]}" == "$keyword_1" ]
	then
	  vCol[$x]=${vCol[$x]}'_T'
	else
	  if [ "${vCol[$x]}" == "$keyword_2" ]
	  then
	    vCol[$x]=${vCol[$x]}'_T'
      fi
	fi
	vType[$x]=`echo ${vColumn[$x]} | cut -d : -f2`
    vLength[$x]=`echo ${vColumn[$x]} | cut -d : -f3`
    vScale[$x]=`echo ${vColumn[$x]} | cut -d : -f4`
    vN[$x]=`echo ${vColumn[$x]} | cut -d : -f5`
    
    if [ ${vN[$x]} == "N" ]
    then
      vNull[$x]=" NOT NULL"
    else
      vNull[$x]=""
    fi
    x=`expr $x + 1`
  done
  
  
  z=0
  until [ ! $z -lt $h ]
  do
    x=0
	until [ ! $x -lt $y ]
    do
	  if [ "${vSec[$z]}" == "${vCol[$x]}" ]
	  then
	    vSecType[$z]=`echo ${vColumn[$x]} | cut -d : -f2`
		vSecLength[$z]=`echo ${vColumn[$x]} | cut -d : -f3`
		vSecScale[$z]=`echo ${vColumn[$x]} | cut -d : -f4`
		vSecN[$z]=`echo ${vColumn[$x]} | cut -d : -f5`
		if [ "${vSecN[$z]}" == "N" ]
        then
          vSecNull[$z]=" NOT NULL"
        else
          vSecNull[$z]=""
        fi
	  fi
	  x=`expr $x + 1`
	done
	z=`expr $z + 1`
  done
  
  
  HeadFile ## Head <<Create.sql>>, <<Select.sql>>, <<fastload.fl>> 


  x=0
  until [ ! $x -lt $y ]
  do
	if [ $x -eq $r ] #Determin if the row is the last
    then
	  if [ $h == 0 ]
	  then 
	    vEnd=")"
	  else
	    vEnd=","
	  fi
          
      if [ ${vType[$x]} == "DECIMAL" ]
	  then
	    echo ${vCol[$x]}" "${vType[$x]}"("${vLength[$x]}"",""${vScale[$x]}")${vNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
        if [ $h -gt 0 ]
        then
          echo ${vCol[$x]}, $vSecCol" From $vSTBName" >> $TB_SQL"$vTAB"_Select.sql
		else
	      echo ${vCol[$x]}" From $vSTBName" >> $TB_SQL"$vTAB"_Select.sql
        fi
	  elif [ ${vType[$x]} == "BIGINT" ]
	  then
	    vType[$x]="DECIMAL"
        echo ${vCol[$x]}" "${vType[$x]}"(19","0)${vNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
	    if [ $h -gt 0 ]
        then
          echo ${vCol[$x]}, $vSecCol" From $vSTBName" >> $TB_SQL"$vTAB"_Select.sql
        else
	      echo ${vCol[$x]}" From $vSTBName" >> $TB_SQL"$vTAB"_Select.sql
        fi
	  elif [ ${vType[$x]} == "DATE" ]
	  then
	    echo ${vCol[$x]}" "${vType[$x]}" FORMAT '99999999'${vNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
        if [ $h -gt 0 ]
        then
          echo ${vCol[$x]}, $vSecCol" From $vSTBName" >> $TB_SQL"$vTAB"_Select.sql
        else
          echo ${vCol[$x]}" From $vSTBName" >> $TB_SQL"$vTAB"_Select.sql
	    fi
	  elif [ ${vType[$x]} == "TIMESTAMP" ]
	  then
	    echo ${vCol[$x]}" "${vType[$x]}" FORMAT 'YYYY-MM-DD-HH.MI.SS.S(6)'${vNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
        if [ $h -gt 0 ]
        then
          echo ${vCol[$x]}, $vSecCol" From $vSTBName" >> $TB_SQL"$vTAB"_Select.sql
        else
          echo ${vCol[$x]}" From $vSTBName" >> $TB_SQL"$vTAB"_Select.sql
	    fi
	  elif [ ${vType[$x]} == "INTEGER" ]
	  then
	    echo ${vCol[$x]}" "${vType[$x]}"${vNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
        if [ $h -gt 0 ]
        then
          echo ${vCol[$x]}, $vSecCol" From $vSTBName" >> $TB_SQL"$vTAB"_Select.sql
        else
          echo ${vCol[$x]}" From $vSTBName" >> $TB_SQL"$vTAB"_Select.sql
		fi
	  else ## Varchar/Char & others
	    echo ${vCol[$x]}" "${vType[$x]}"("${vLength[$x]}")$vLatin${vNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
	    if [ $h -gt 0 ]
        then
          echo ${vCol[$x]}, $vSecCol" From $vSTBName" >> $TB_SQL"$vTAB"_Select.sql
        else
          echo ${vCol[$x]}" From $vSTBName" >> $TB_SQL"$vTAB"_Select.sql
		fi
      fi
	  AfterSQL #Action After SQL File Generation
	  testAfterSQL ##test
    else
	  vEnd=","
		  
      if [ ${vType[$x]} == "DECIMAL" ]
      then
        echo ${vCol[$x]}" "${vType[$x]}"("${vLength[$x]}"",""${vScale[$x]}")${vNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
        echo ${vCol[$x]}$vEnd >> $TB_SQL"$vTAB"_Select.sql
      elif [ ${vType[$x]} == "BIGINT" ]
      then
        vType[$x]="DECIMAL"
        echo ${vCol[$x]}" "${vType[$x]}"(19","0)${vNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
        echo ${vCol[$x]}$vEnd >> $TB_SQL"$vTAB"_Select.sql
      elif [ ${vType[$x]} == "DATE" ]
      then
		echo ${vCol[$x]}" "${vType[$x]}" FORMAT '99999999'${vNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
        echo ${vCol[$x]}$vEnd >> $TB_SQL"$vTAB"_Select.sql
	  elif [ ${vType[$x]} == "TIMESTAMP" ]
      then
		echo ${vCol[$x]}" "${vType[$x]}" FORMAT 'YYYY-MM-DD-HH.MI.SS.S(6)'${vNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
        echo ${vCol[$x]}$vEnd >> $TB_SQL"$vTAB"_Select.sql
	  elif [ ${vType[$x]} == "INTEGER" ]
      then
		echo ${vCol[$x]}" "${vType[$x]}" ${vNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
        echo ${vCol[$x]}$vEnd >> $TB_SQL"$vTAB"_Select.sql
      else  ## Varchar/Char & others
        echo ${vCol[$x]}" "${vType[$x]}"("${vLength[$x]}")$vLatin${vNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
        echo ${vCol[$x]}"$vEnd" >> $TB_SQL"$vTAB"_Select.sql
      fi  
    fi 
    x=`expr $x + 1`
  done

  ##== Start ===create table secret term-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  ##== Start ===create table secret term
  x=0
  until [ ! $x -lt $h ]
  do
    if [ $x == `expr $h - 1` ]
	then
	    vEnd=")"
	else
	    vEnd=","
	fi
    
	if [ ${vSecType[$x]} == "INTEGER" ]
	then
	  echo ${vSecHead}${vSec[$x]}" "${vSecType[$x]}${vSecNull[$x]}$vEnd >> $TB_SQL"$vTAB"_Create.sql
	elif [ ${vSecType[$x]} == "BIGINT" ]
	then
	  vSecType[$x]="DECIMAL"
	  vSecLength[$x]=19
      vSecScale[$x]=0
	  echo ${vSecHead}${vSec[$x]}" "${vSecType[$x]}"("${vSecLength[$x]}"",""${vSecScale[$x]}")${vSecNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
    elif [ ${vSecType[$x]} == "DECIMAL" ]
	then
	  echo ${vSecHead}${vSec[$x]}" "${vSecType[$x]}"("${vSecLength[$x]}"",""${vSecScale[$x]}")${vSecNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
    elif [ ${vSecType[$x]} == "DATE" ]
	then
	  echo ${vSecHead}${vSec[$x]}" "${vSecType[$x]}" FORMAT '99999999'"${vSecNull[$x]}$vEnd >> $TB_SQL"$vTAB"_Create.sql
    elif [ ${vSecType[$x]} == "TIMESTAMP" ]
	then
	  echo ${vSecHead}${vSec[$x]}" "${vSecType[$x]}" FORMAT 'YYYY-MM-DD-HH.MI.SS.S(6)'"${vSecNull[$x]}$vEnd >> $TB_SQL"$vTAB"_Create.sql
    else	
      echo ${vSecHead}${vSec[$x]}" "${vSecType[$x]}"("${vSecLength[$x]}")$vLatin${vSecNull[$x]}"$vEnd >> $TB_SQL"$vTAB"_Create.sql
    fi
	x=`expr $x + 1`
  done
  ##==  End  ===create table secret term
  ##==  End  ===create table secret term-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=



  ##== Start ===Part1. fastload crtl file-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  ##== Start ===Part1. fastload crtl file
  x=0
  until [ ! $x -lt $y ]
  do
    vEnd=","
    if [ ${vType[$x]} == "INTEGER" ]
    then
	  echo "      in_"${vCol[$x]}" (VARCHAR(10))"$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
    elif [ ${vType[$x]} == "BIGINT" ]
    then
      echo "      in_"${vCol[$x]}" (VARCHAR(19))"$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
	elif [ ${vType[$x]} == "DATE" ]
	then
	  echo "      in_"${vCol[$x]}" (VARCHAR(10))"$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
	elif [ ${vType[$x]} == "TIMESTAMP" ]
	then
	  echo "      in_"${vCol[$x]}" (VARCHAR(26))"$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
    else
      echo "      in_"${vCol[$x]}" (VARCHAR("${vLength[$x]}"))"$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
    fi
    x=`expr $x + 1`
  done
  ##------------------------------
  ##== Start ===Part1. SecCol
  x=0
  until [ ! $x -lt $h ]
  do
    if [ ${vSecType[$x]} == "INTEGER" ]
	then
      echo "      in_"${vSecHead}${vSec[$x]}" (VARCHAR(10))," >> "$CTL_FL_DIR$vTAB"_fastload.fl
    elif [ ${vSecType[$x]} == "BIGINT" ]
	then
      echo "      in_"${vSecHead}${vSec[$x]}" (VARCHAR(19))," >> "$CTL_FL_DIR$vTAB"_fastload.fl
    else
	  echo "      in_"${vSecHead}${vSec[$x]}" (VARCHAR("${vSecLength[$x]}"))," >> "$CTL_FL_DIR$vTAB"_fastload.fl
    fi
	x=`expr $x + 1`
  done
  ##==  End  ===Part1. SecCol
  ##------------------------------
  
  echo "      FILE = \"/u01/app/data/exp_Encryption/"$vTAB"_Encryption.dat\";" >> "$CTL_FL_DIR$vTAB"_fastload.fl ##need check file name
  
  ##==  End  ===Part1. fastload crtl file
  ##==  End  ===Part1. fastload crtl file-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=


  ##== Start ===Part2. fastload crtl file-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  ##== Start ===Part2. fastload crtl file
  echo "    INSERT INTO $vTAB (" >> "$CTL_FL_DIR$vTAB"_fastload.fl
  x=0
  until [ ! $x -lt $y ]
  do
	if [ $x -eq $r ] #Determin if the row is the last
    then
	  vEnd=","
      if [ $h == 0 ]
	  then 
	    vEnd=""
	  fi
	  echo "      "${vCol[$x]}$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
    else
	  echo "      "${vCol[$x]}$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
	fi
    x=`expr $x + 1`
  done
  ##------------------------------
  ##== Start ===Part2. SecCol
  x=0
  until [ ! $x -lt $h ]
  do
    if [ $x == `expr $h - 1` ]
	then
	  vEnd=""
      echo "      "${vSecHead}${vSec[$x]}$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
    else
	  vEnd=","
      echo "      "${vSecHead}${vSec[$x]}$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
	fi
	x=`expr $x + 1`
  done
  ##==  End  ===Part2. SecCol
  ##------------------------------
  
  echo "    )" >> "$CTL_FL_DIR$vTAB"_fastload.fl

  ##==  End  ===Part2. fastload crtl file
  ##==  End  ===Part2. fastload crtl file-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=


  ##== Start ===Part3. fastload crtl file-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  ##== Start ===Part3. fastload crtl file
  echo "    VALUES (" >> "$CTL_FL_DIR$vTAB"_fastload.fl
  
  x=0
  until [ ! $x -lt $y ]
  do
  	if [ $x -eq $r ] #Determin if the row is the last
    then
      if [ $h == 0 ]
	  then 
	    vEnd=""
	  else
	    vEnd=","
	  fi
	  
	  if [ ${vType[$x]} == "DATE" ]
	  then
	    echo "      :in_"${vCol[$x]}" (FORMAT '99999999')"$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
	  elif [ ${vType[$x]} == "TIMESTAMP" ]
	  then
	    echo "      :in_"${vCol[$x]}" (FORMAT 'YYYY-MM-DD-HH.MI.SS.S(6)')"$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
	  else
        echo "      :in_"${vCol[$x]}$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
      fi 
    else
	  vEnd=","
	  if [ ${vType[$x]} == "DATE" ]
	  then
	    echo "      :in_"${vCol[$x]}" (FORMAT '99999999')"$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
	  elif [ ${vType[$x]} == "TIMESTAMP" ]
	  then
	    echo "      :in_"${vCol[$x]}" (FORMAT 'YYYY-MM-DD-HH.MI.SS.S(6)')"$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
	  else
        echo "      :in_"${vCol[$x]}$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
      fi  
    fi
    x=`expr $x + 1`
  done
  ##------------------------------
  ##== Start ===Part3. SecCol
  x=0
  until [ ! $x -lt $h ]
  do    
    if [ $x == `expr $h - 1` ]
	then
	  vEnd=""
      echo "      :in_"${vSecHead}${vSec[$x]}$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
    else
	  vEnd=","
      echo "      :in_"${vSecHead}${vSec[$x]}$vEnd >> "$CTL_FL_DIR$vTAB"_fastload.fl
	fi
	x=`expr $x + 1`
  done
  ##==  End  ===Part3. SecCol
  ##------------------------------
  
  echo "    );" >> "$CTL_FL_DIR$vTAB"_fastload.fl
  ##==  End  ===Part3. fastload crtl file
  ##==  End  ===Part3. fastload crtl file-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=


  ##== Start ===Tail fastload crtl file
  ##== Start ===Tail fastload crtl file
  echo "  END LOADING;" >> "$CTL_FL_DIR$vTAB"_fastload.fl
  echo "LOGOFF;" >> "$CTL_FL_DIR$vTAB"_fastload.fl
  ##==  End  ===Tail test fastload crtl file
  ##==  End  ===Tail test fastload crtl file
  
  i=`expr $i + 1`
done
##------------------------------------------------
##################################################




##************************************************
##  Create crtl_creTB
##================================================
echo "#!/bin/bash" > "$CTL_creTB_DIR"cTB_ALL.sh
echo "bteq << EOF" >> "$CTL_creTB_DIR"cTB_ALL.sh
echo ".LOGON tdexpress1610/dbc,dbc;" >> "$CTL_creTB_DIR"cTB_ALL.sh
echo "DATABASE yang;" >> "$CTL_creTB_DIR"cTB_ALL.sh

i=0
until [ ! $i -lt $j ]
do
  echo "DROP TABLE ${creTBfilename[i]};" >> "$CTL_creTB_DIR"cTB_ALL.sh
  echo ".run file = $TB_SQL${creTBfilename[i]}_Create.sql;" >> "$CTL_creTB_DIR"cTB_ALL.sh
  i=`expr $i + 1`
done

echo "quit" >> "$CTL_creTB_DIR"cTB_ALL.sh
echo "EOF" >> "$CTL_creTB_DIR"cTB_ALL.sh
##------------------------------------------------
##################################################



##************************************************
##  Run crtl_creTB
##================================================
echo "Run crtl_creTB============================="

sh "$CTL_creTB_DIR"cTB_ALL.sh >/dev/null ## >/dev/null messageout
##------------------------------------------------
##################################################



##************************************************
##  Run crtl_fastload
##================================================
echo "Run fastload============================="

i=0
until [ ! $i -lt $j ]
do
  fastload < $CTL_FL_DIR${creTBfilename[i]}_fastload.fl >/dev/null ## >/dev/null messageout
  i=`expr $i + 1`
done
##------------------------------------------------
##################################################
##dds2=$(date +"%s")
##echo "total time: "$((dds2-dds1))