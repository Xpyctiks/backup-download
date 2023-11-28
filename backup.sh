#!/bin/env bash

DATE=$(/bin/date '+%d.%m.%Y %H:%M:%S') #Date to use for logging.
NAME=$(/bin/date '+%d.%m.%Y')          #Name for folders we are working with.
Color_Off='\033[0m'
Red='\033[0;31m'
Green='\033[0;32m'                     #Colors for text to console.
Yellow='\033[0;33m'
White='\033[0;37m'
confFile="./settings.local"            #Name of the config file with list of backup sources.
launchFrom=""                          #Here we will set from what env. the scrips was launched - shell or cron.
type=""                                #Type of the action - daily or weekly.
pathArr=()                             #Array with paths to be backed up.
dbArr=()                               #Array with DB names to be dumped.
deny=""                                #Variable with lock value - we can deny launch of "daily" or "weekly" or "all" functions for that host
lockFile="/var/run/backup.sh.pid"      #Lock file to prevent launch of few copies at the same time
TYPE=""                                #Var. to keep type of launch - daily or weekly

#Head to the current directory of the script it has been launched from. Check if we are launched from symlink or any other place as subshell process.
echo "${0}" | egrep -e '^\..*' > /dev/null 2>&1
if [[ "${?}" == "0" ]]; then
  #The script is launched from shell manually
  scriptName=$(echo "${0}" | sed 's/.//')
  scriptPath=$(realpath -e "${0}" | sed "s/\\${scriptName}//")
  launchFrom="shell"
  cd "${scriptPath}"
else
  #The script is launched from cron or any parent process
  scriptName=$(basename "${0}")
  scriptPath=$(echo "${0}" | sed "s/${scriptName}//")
  launchFrom="cron"
  cd "${scriptPath}"
fi

#check config file.Get values from it if it is found, or creating new one if it is not.
if ! [[ -f "${confFile}" ]]; then
	echo -e "${Red}Warning! ${confFile} with all important settings is not found and must be created. Please, launch once backup-download.sh script.It will generate config file.${Color_Off}"
	exit 1
else
	#getting all necessary variables from external file
  source "${confFile}"
  #checking all variables are set. No empty one.
	if [[ -z "${localBackupsFolder}" ]] || [[ -z "${logDir}" ]] || [[ -z "${shaFileRem}" ]] || [[ -z "${shaFileLoc}" ]] || [[ -z "${shaApp}" ]] || [[ -z "${lockFile}" ]] || [[ -z "${updPerm}" ]] \
  || [[ -z "${uid}" ]] || [[ -z "${gid}" ]] || [[ -z "${backupList}" ]]; then
    echo -e "${Red}Error! Some important variables in ${confFile} are empty!${Color_Off}"
    echo -e "${Yellow}backupsFolder=${localBackupsFolder}\nlogDir=${logDir}\nshaFileRem=${shaFileRem}\nshaFileLoc=${shaFileLoc}\nshaApp=${shaApp}${Color_Off}"
    echo -e "${Yellow}updPerm=${updPerm}\nuid=${uid}\ngid=${gid}\nbackupList=${backupList}${Color_Off}"
		exit 1
	fi
fi

#Function to send messages to Telegram.Getting message as a value passed to the function: via ${1}.
function sendTelegram() {
  if ! [[ -z "${telegramChat}" ]] && [[ -z "${telegramToken}" ]]; then
    #send via Telegram only when it is launched from cron.Else just show the message.
    if [[ "${launchFrom}" == "cron" ]]; then
      #test is Curl installed and available
      curl > /dev/null
      if [[ "${?}" == "2" ]]; then
        subj="🚩Alert! Backup-download.sh:"
        curl  --header "Content-Type: application/json" --request "POST" --data "{\"chat_id\":\"${telegramChat}\",\"text\":\"${subj}\n${1}\"}" "https://api.telegram.org/bot${telegramToken}/sendMessage"
      else
        if [[ "${launchFrom}" == "shell" ]]; then
          echo -e "${Red}Error! Curl is not installed! Can't send message to Telegram${Color_Off}"
        elif [[ "${launchFrom}" == "cron" ]]; then
          echo -e "${Red}Error! Curl is not installed! Can't send message to Telegram${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
        fi
        break
      fi
    fi
  fi
}

#check another copy is still running
if [[ -f "${lockFile}" ]]; then
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Red}Error! Another copy is still running!${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo -e "${Red}Error! Another copy is still running!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
    sendTelegram "Error! Another copy is still running!"
  fi
  exit 2
fi

#Check the servers config file
if ! [[ -f "${backupList}" ]]; then
  if [[ "${launchFrom}" == "shell" ]]; then
    cat << EOF > "${backupList}"
#Config file format
#<type>: <value> where:
#<type> should be: "db:" or "backup:"
#<value> - a path to folder for backup, or name of DB to backup. Path must be without / at the end.
#example:
#db: siteDatabase
#backup: /var/www
#
EOF
  echo -e "${Red}File ${backupList} with a list of points to backup is not found!\nCreated new one. Please, fill it in with your settings.${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo "File ${backupList} with a list of servers for backup is not found! Launch this script from shell to auto generate the file.Can't continue..." >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
    sendTelegram "File ${backupList} with a list of servers for backup is not found! Launch this script from shell to auto generate the file.Can't continue..."
  fi
  exit 1
else
  if ! [[ -s "${backupList}" ]]; then
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Red}File ${backupList} with a list of points to backup is empty!\nCan't continue...${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo "${Red}File ${backupList} with a list of points to backup is empty!\nCan't continue...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
      sendTelegram "File ${backupList} with a list of points to backup is empty! Can't continue.."
    fi    
    exit 1
  fi
fi

#Check do we have a parameters and they are correct
if [[ -z "${1}" ]]; then
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Yellow}Usage: ${0} <type>"
    echo -e  "Type:\n\t${White}daily${Yellow} - create daily backups\n\t${White}weekly${Yellow} - create weekly backups${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo -e "${Red}No parameters defined!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
    sendTelegram "No parameters defined!"
  fi
  exit 1
fi
if [[ "${1}" != "daily" ]] && [[ "${1}" != "weekly" ]]; then
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Red}Unknown parameter!${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo -e "${Red}Unknown parameter defined!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
    sendTelegram "Unknown parameter defined!"
  fi
  exit 1
fi
if [[ "${1}" == "daily" ]] || [[ "${1}" == "Daily" ]]; then
  #setting type of launch depending on the parameter we got
  TYPE="daily"
elif [[ "${1}" == "weekly" ]] || [[ "${1}" == "Weekly" ]]; then
    #setting type of launch depending on the parameter we got
  TYPE="weekly"
fi

#getting all necessary info from config file
while read parameter value; do
  #Skipping comments strings - if anywhere is # symbol.
  if [[ "${parameter}" == *"#"* ]] || [[ "${value}" == *"#"* ]]; then
      continue
  fi
  #Parsing the config file and filling our arrays with data.
  if [[ ! -z "${parameter}" ]] && [[ ! -z "${value}" ]]; then
    if [[ ${parameter} == "db:" ]]; then
      dbArr+=("${value}")
    elif [[ ${parameter} == "backup:" ]]; then
      pathArr+=("${value}")
    elif [[ ${parameter} == "deny:" ]]; then
      if [[ "${value}" == "daily" ]] || [[ "${value}" == "weekly" ]] || [[ "${value}" == "all" ]]; then
        deny=${value}
      elif [[ ${parameter} == "deny:" ]]; then
        if [[ "${launchFrom}" == "shell" ]]; then
          echo -e "${Red}Skipping "deny:" parameter with wrong data: ${value}${Color_Off}"
        elif [[ "${launchFrom}" == "cron" ]]; then
          echo -e "${Red}Skipping "deny:" parameter with wrong data: ${value}${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
          sendTelegram "Skipping "deny:" parameter with wrong data: ${value}"
        fi
      fi
    else
      #silent skipping parameter that could be not defined, but showing warning if the parameter is unknown for us
      if [[ ${parameter} != "deny:" ]]; then
        if [[ "${launchFrom}" == "shell" ]]; then
          echo -e "${Red}Skipping string with wrong data: ${parameter} ${value}${Color_Off}"
        elif [[ "${launchFrom}" == "cron" ]]; then
          echo -e "${Red}Skipping string with wrong data: ${parameter} ${value}${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
          sendTelegram "Skipping string with wrong data: ${parameter} ${value}"
        fi
      fi
    fi
else
  #silent skipping parameter that could be not defined, but showing warning if the parameter is unknown for us
  if [[ ${parameter} != "deny:" ]]; then
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Red}Skipping wrong string: ${parameter} ${value}${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Red}Skipping wrong string: ${parameter} ${value}${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
      sendTelegram "Skipping wrong string: ${parameter} ${value}"
    fi
  fi
fi
done <<< $(cat "${backupList}")

#Checking do our arrays are filled in by data
if ([ "${#pathArr[@]}" == "0" ] && [ "${#dbArr[@]}" == "0" ]); then
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Red}Both DB and Path arrays are empty.That means you have problems with data in config file.Interrupting...${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo -e "${Red}Both DB and Path arrays are empty.That means you have problems with data in config file.Interrupting...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
    sendTelegram "Both DB and Path arrays are empty.That means you have problems with data in config file.Interrupting..."
  fi
  exit 1
fi

#Main function that processes the main task
if [[ "${1}" == "daily" ]]; then
  if [[ "${deny}" == "daily" ]] || [[ "${deny}" == "all" ]]; then
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Red}Daily backups denied by the configuration file!${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Red}Daily backups denied by the configuration file!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
      sendTelegram "Daily backups denied by the configuration file!"
    fi
    exit 1
  fi
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Green}----------------${DATE} Starting daily backups-----------------${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo -e "${Green}----------------${DATE} Starting daily backups-----------------${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
  fi
  if [[ ! -d "${localBackupsFolder}/daily/${NAME}" ]]; then
    mkdir -p "${localBackupsFolder}"/daily/"${NAME}"
	  chown "${uid}":"${gid}" "${localBackupsFolder}"/daily/"${NAME}"
	  chmod 750 "${localBackupsFolder}"/daily/"${NAME}"
  fi
  cd "${localBackupsFolder}"/daily/"${NAME}"
  if [[ "${?}" == "0" ]]; then
    #if dbArray is not empty - doing dumps.If it is - skipping and go to all-databases backup
    if [[ ${#dbArr[@]} -gt 0 ]]; then
      #making dumps from list from dbArray
      for (( i=0; i < ${#dbArr[@]}; i++ ))
      {
        mysqldump --add-drop-database "${dbArr[${i}]}" > "${dbArr[${i}]}".sql
        if [[ "${?}" != "0" ]]; then
          if [[ "${launchFrom}" == "shell" ]]; then
            echo -e "${Red}\tUnexpected error while creating dump of ${dbArr[${i}]}!Skipping...${Color_Off}"
          elif [[ "${launchFrom}" == "cron" ]]; then
            echo -e "${Red}\tUnexpected error while creating dump of ${dbArr[${i}]}!Skipping...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
            sendTelegram "Unexpected error while creating dump of ${dbArr[${i}]}!Skipping..."
          fi
        else
          if [[ "${launchFrom}" == "shell" ]]; then
            echo -e "${Yellow}\tDB ${dbArr[${i}]} completed...${Color_Off}"
          elif [[ "${launchFrom}" == "cron" ]]; then
            echo -e "${Yellow}\tDB ${dbArr[${i}]} completed...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
          fi
        fi
      }
      if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${Yellow}\tDB dumps completed! Moving on...${Color_Off}"
      elif [[ "${launchFrom}" == "cron" ]]; then
        echo -e "${Yellow}\tDB dumps completed! Moving on...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
      fi
    fi
    #Making dump for All-databases
    mysqldump --all-databases --add-drop-database > AllDB-daily.sql
    if [[ "${?}" != "0" ]]; then
      if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${Red}\tUnexpected error while creating All-databases backup!Skipping...${Color_Off}"
      elif [[ "${launchFrom}" == "cron" ]]; then
        echo -e "${Red}\tUnexpected error while creating All-databases backup!Skipping...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
        sendTelegram "Unexpected error while creating All-databases backup!Skipping..."
      fi
    fi
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Yellow}\tAll-databases dump completed! Moving on...${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Yellow}\tAll-databases dump completed! Moving on...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
    fi    
    #Compressing all dumps and removing the originals if success
    while read name; do
      tar -czf ${name}.tar.gz ${name} > /dev/null 2>&1
      if [[ "${?}" == "0" ]]; then
        rm ${name}
      fi
    done <<< $(ls *.sql)
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Yellow}\tDB dumps compression done! Moving on...${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Yellow}\tDB dumps compression done! Moving on...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
      sendTelegram "DB dumps compression done! Moving on..."
    fi    
    #If everything is ok with our SHA1 app - creating checksums
    if [[ -f "${shaApp}" ]]; then
      "${shaApp}" *.gz > "${shaFileRem}"
      if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${Yellow}\tSHA1 checksums creation done!${Color_Off}"
      elif [[ "${launchFrom}" == "cron" ]]; then
        echo -e "${Yellow}\tSHA1 checksums creation done!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
      fi
    else
      if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${Red}\t${shaApp} not found! Checksum file not created!${Color_Off}"
      elif [[ "${launchFrom}" == "cron" ]]; then
        echo -e "${Red}\t${shaApp} not found! Checksum file not created!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
        sendTelegram "${shaApp} not found! Checksum file not created!"
      fi
    fi
  fi
  chown "${uid}":"${gid}" *
  chmod 640 *
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Green}----------------All tasks completed successfully!----------------${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo -e "${Green}----------------All tasks completed successfully!----------------${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
  fi
  sendTelegram "✅backup.sh Daily local mysql server backups created successfully!"
  exit 0
fi

if [[ "${1}" == "weekly" ]]; then
  if [[ "${deny}" == "weekly" ]] || [[ "${deny}" == "all" ]]; then
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Red}Weekly backups denied by the configuration file!${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Red}Weekly backups denied by the configuration file!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
      sendTelegram "Weekly backups denied by the configuration file!"
    fi
    exit 1
  fi
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Green}-----------------${DATE} Starting weekly backups-----------------${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo -e "${Green}-----------------${DATE} Starting weekly backups-----------------${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
  fi
  if [[ ! -d "${localBackupsFolder}/weekly/${NAME}" ]]; then
    mkdir -p "${localBackupsFolder}"/weekly/"${NAME}"
	  chown "${uid}":"${gid}" "${localBackupsFolder}"/daily/"${NAME}"
	  chmod 750 "${localBackupsFolder}"/daily/"${NAME}"
  fi
  cd "${localBackupsFolder}"/weekly/"${NAME}"
  if [[ "${?}" == "0" ]]; then
    #making dumps from list from dbArray
    for (( i=0; i < ${#dbArr[@]}; i++))
    {
      mysqldump --add-drop-database "${dbArr[${i}]}" > "${dbArr[${i}]}".sql
      if [[ "${?}" != "0" ]]; then
        if [[ "${launchFrom}" == "shell" ]]; then
          echo -e "${Red}\tUnexpected error while creating dump of ${dbArr[${i}]}!Skipping...${Color_Off}"
        elif [[ "${launchFrom}" == "cron" ]]; then
          echo -e "${Red}\tUnexpected error while creating dump of ${dbArr[${i}]}!Skipping...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
          sendTelegram "Unexpected error while creating dump of ${dbArr[${i}]}!Skipping..."
        fi
      fi
      if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${Yellow}\tDB ${dbArr[${i}]} completed...${Color_Off}"
      elif [[ "${launchFrom}" == "cron" ]]; then
          echo -e "${Yellow}\tDB ${dbArr[${i}]} completed...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
      fi
    }
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Yellow}\tDB dumps completed! Moving on...${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Yellow}\tDB dumps completed! Moving on...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
    fi
    #making dump for All-databases
    mysqldump --all-databases --add-drop-database > AllDB-daily.sql
    if [[ "${?}" != "0" ]]; then
      if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${Red}\tUnexpected error while creating All-databases backup!Skipping...${Color_Off}"
      elif [[ "${launchFrom}" == "cron" ]]; then
        echo -e "${Red}\tUnexpected error while creating All-databases backup!Skipping...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
        sendTelegram "Unexpected error while creating All-databases backup!Skipping..."
      fi
    fi
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Yellow}\tAll-databases dump completed! Moving on...${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Yellow}\tAll-databases dump completed! Moving on...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
    fi
    #compressing all dumps and removing the original one if success
    while read name; do
      tar -czf "${name}".tar.gz "${name}" > /dev/null 2>&1
      if [[ "${?}" == "0" ]]; then
        rm "${name}"
      fi
    done <<< $(ls *.sql)
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Yellow}\tDB dumps compression done! Moving on...${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Yellow}\tDB dumps compression done! Moving on...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
    fi
    #making backups from list from pathArray
    for (( i=0; i < ${#pathArr[@]}; i++))
    {
      #--------very important function - removes aboslute path from $value to get correct name for future archive file and checks for trailing / at all path strings----------
      #counts how much sybols does our current path has
      c=$(echo "${pathArr[${i}]}" | wc -c)
      #check does it contain trailing slash
      lastSymbol=$(echo "${pathArr[${i}]:((${c}-2)):${c}}")
      if [[ ${lastSymbol} != "/" ]]; then
        #if not contains - add the trailing slash symbol
        pathArr[${i}]="${pathArr[${i}]}/"
      fi
      #now generate a correct name for archive file
      bkpName=$(echo "${pathArr[${i}]}" | cut -d"/" -f $(echo "${pathArr[${i}]}" | grep -o "/" | wc -l))
      #-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
      tar -czf "${bkpName}".tar.gz "${pathArr[${i}]}" > /dev/null 2>&1
      if [[ "${?}" != "0" ]]; then
        if [[ "${launchFrom}" == "shell" ]]; then
          echo -e "${Red}\tUnexpected error while creating backups of ${pathArr[${i}]}!Skipping...${Color_Off}"
        elif [[ "${launchFrom}" == "cron" ]]; then
          echo -e "${Red}\tUnexpected error while creating backups of ${pathArr[${i}]}!Skipping...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
          sendTelegram "Unexpected error while creating backups of ${pathArr[${i}]}!Skipping..."
        fi
      fi
      if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${Yellow}\tBackup of ${pathArr[${i}]} completed...${Color_Off}"
      elif [[ "${launchFrom}" == "cron" ]]; then
        echo -e "${Yellow}\tBackup of ${pathArr[${i}]} completed...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
      fi
    }
    if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${Yellow}\tAll backups done! Moving on...${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Yellow}\tAll backups done! Moving on...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
    fi
    if [[ -f "${shaApp}" ]]; then
      "${shaApp}" *.gz >> "${shaFileRem}"
      if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${Yellow}\tSHA1 checksums creation done!${Color_Off}"
      elif [[ "${launchFrom}" == "cron" ]]; then
        echo -e "${Yellow}\tSHA1 checksums creation done!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
      fi
    else
      if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${Red}\t${shaApp} not found! Checksum file not created!${Color_Off}"
      elif [[ "${launchFrom}" == "cron" ]]; then
        echo -e "${Red}\t${shaApp} not found! Checksum file not created!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
        sendTelegram "${shaApp} not found! Checksum file not created!"
      fi
    fi
  fi
  chown "${uid}":"${gid}" *
  chmod 640 *
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Green}-----------------All weekly tasks completed successfully!-----------------${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo -e "${Green}-----------------All weekly tasks completed successfully!-----------------${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE}"-backup.log
  fi
  sendTelegram "✅backup.sh Weekly local backups created successfully!"
  exit 0
fi
