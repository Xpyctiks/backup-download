#!/usr/bin/env bash

#release 1.4.112
NAME=$(/bin/date '+%d.%m.%Y')           #Name of current folder for download - created from current datestamp.
Color_Off='\033[0m'
Red='\033[0;31m'
Green='\033[0;32m'                      #Variables with text color for output.
Yellow='\033[0;33m'
White='\033[0;37m'
RESULT="0"                              #Result of completion of operation - 1(fail) or 0(success) for DB write.
DOMAIN=""                               #Domain we are working with (for record to DB).
TYPE=""                                 #Type of operation - Daily or Weekly.
TYPE2=""                                #Type of operation - Daily or Weekly in lower case for some functions.
LOG=""                                  #Variable for text for putting in DB as log message.
workArr=()                              #Array to be filled by strings with path of our new downloads to set permissions for them in the end.
launchFrom=""                           #Here we will set from what env. the scrips was launched - shell or cron.
scpUser=""                              #Var. for future user for SCP login.
rsyncUser=""                            #Var. for future user for Rsync.
confFile="./settings.local"
lockFile="/var/run/backup-download.pid" #Lock file to prevent launch of few copies at the same time

#Head to the current directory of the script it has been launched from. Check if we are launched from symlink or any other place as subshell process.
echo "${0}" | egrep -e '^\..*' > /dev/null 2>&1
if [[ "${?}" == "0" ]]; then
  #the script is launched from shell manually
  scriptName=$(echo "${0}" | sed 's/.//')
  scriptPath=$(realpath -e ${0} | sed "s/\\${scriptName}//")
  launchFrom="shell"
  cd "${scriptPath}"
else
  #the script is launched from cron or any parent process
  scriptName="$(basename "${0}")"
  scriptPath="$(echo "${0}" | sed "s/${scriptName}//")"
  launchFrom="cron"
  cd "${scriptPath}"
fi

#check config file.Get values from it if it is found, or creating new one if it is not.
if ! [[ -f "${confFile}" ]]; then
	echo -e "${Yellow}Warning! ${confFile} with all important settings is not found and it was created. Please, fill in the file and then this program will works!${Color_Off}"
	cat << EOF > "${confFile}"
#User for access to DB for write logs.
dbUser="BackupLogging"

#Password for access to DB for write logs.
dbPass=""

#DB name.If empty - will not use mysql at all for logging.See README
dbName=""

#Backup-download.sh. Name of the file with list of servers to download backups from.
serverList="backup-download.list"

#Backup.sh list of what should be backed up.
backupList="backup.list"

#Backup-download.sh. Folder where backups will be downloaded.
backupsFolder=""

#Backup.sh. Folder where local backups will be stored.
localBackupsFolder=""

#MarkerDir using for make sure the encrypted volume for backups is mounted.Could be ignored. See README
markerDir=""

#Where to store backup log files with output of Rsync working process.
logDir="/var/log/backup-download"

#Name of the file with checksum list from remote servers.Important to use with checksum check option.
shaFileRem="sha1sum.remote"

#Name of local file to compare checksums of received files with the remote one.
shaFileLoc="sha1sum.local"

#Path and name of app to create checksum. SHA1 default.
shaApp="/usr/bin/sha1sum"

#Lock file to prevent launch of few copies at the same time
lockFile="/var/run/backup-download.pid"

#Telegram api token. Looks like 123456789:abcdefghigklmnopqrstuvwxyz
telegramToken=""

#Telegram chat_id. 9 digits usually.
telegramChat=""

#Update permissions on all downloaded files and folders after download completed. 1 - yes, 0 - no.
updPerm="1"

#Backup-download.sh files permissions.For downloaded backup files.
permFiles="600"

#Backup-download.sh folders permissions.For downloaded backups.
permFolders="700"

#UID for backup.sh script.Will be an owner of newely created backups
uid="root"

#GID for backup.sh script.Will be an owner of newely created backups
gid="bckp"
EOF
	exit 1
else
	#getting all necessary variables from external file
    source "${confFile}"
    #checking all variables are set. No empty one.
	if [[ -z "${dbUser}" ]] || [[ -z "${dbPass}" ]] || [[ -z "${serverList}" ]] || [[ -z "${backupsFolder}" ]] || [[ -z "${logDir}" ]] || [[ -z "${shaFileRem}" ]] || [[ -z "${shaFileLoc}" ]] \
  || [[ -z "${shaApp}" ]] || [[ -z "${lockFile}" ]] || [[ -z "${updPerm}" ]] || [[ -z "${permFiles}" ]] || [[ -z "${permFolders}" ]]; then
    echo -e "${Red}Error! Some important variables in ${confFile} are empty!${Color_Off}"
    echo -e "${Yellow}dbUser=${dbUser}\ndbPass=${dbPass}\nserverList=${serverList}\nbackupsFolder=${backupsFolder}\nlogDir=${logDir}\nshaFileRem=${shaFileRem}\nshaFileLoc=${shaFileLoc}${Color_Off}"
    echo -e "${Yellow}shaApp=${shaApp}\nlockFile=${lockFile}\nupdPerm=${updPerm}\npermFiles=${permFiles}\npermFolders=${permFolders}${Color_Off}"
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
          echo -e "${Red}Error! Curl is not installed! Can't send message to Telegram${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
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
    echo -e "${Red}Error! Another copy is still running!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
    sendTelegram "Error! Another copy is still running!"
  fi
  exit 2
fi

#Check the servers config file
if ! [[ -f "${serverList}" ]]; then
  if [[ "${launchFrom}" == "shell" ]]; then
    cat << EOF > "${serverList}"
#Format of this config file:
#<hostname> <dnsname> <type> <dailyType> <weeklyType> <remScpDir> <scpUser> <remRsyncDir> <rsyncUser>
#<hostname>    - Name of a host which is used as folder name on backup server and in log messages.
#<dnsname>     - DNS or IP address of the host. Just for connections.
#<type>        - What we can do with that host - download "all" (daily and weekly), or only "daily" or "weekly" backups.
#<dailyType>   - How to do daily downloads: via "scp" or "rsync".
#<weeklyType>  - How to do weekly downloads: via "scp" or "rsync".
#<remScpDir>   - Remote directory with backups. For example: /home/backup. Inside os this dir. must be folders "Daily" and "Weekly" with backups.
#<scpUser>     - Username for SCP connection.
#<remRsyncDir> - Remote directory to be fully synced with a local one.Can be ignored if not use Rsync.
#<rsyncUser>   - Username for Rsync connection. If not set, scpUser's value will be used.Can be ignored if not use Rsync.
#Example:
#cloudserver1.infra clo01phx0.domain.com all scp scp home/backup bckp 
#cloudserver2.infra clo01phx1.domain.com all scp rsync home/backup bckp /var/www root
#
EOF
  echo -e "${Red}File ${serverList} with a list of servers for backup is not found!\nCreated new one. Please, fill it in with your settings.${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo "File ${serverList} with a list of servers for backup is not found! Launch this script from shell to auto generate the file.Can't continue..." >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
    sendTelegram "File ${serverList} with a list of servers for backup is not found! Launch this script from shell to auto generate the file.Can't continue..."
  fi
  exit 1
else
  if ! [[ -s "${serverList}" ]]; then
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Red}File ${serverList} with a list of servers for backup is empty!\nCan't continue...${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo "${Red}File ${serverList} with a list of servers for backup is empty!\nCan't continue...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
      sendTelegram "File ${serverList} with a list of servers for backup is empty! Can't continue.."
    fi    
    exit 1
  fi
fi

#Check do we have parameters and are they correct?
if [[ -z "${1}" ]]; then 
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Yellow}Usage: ${0} <type>"
    echo -e  "Type:\n\t${White}daily${Yellow} - download daily backups\n\t${White}weekly${Yellow} - download weekly backups${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo "Launched without any parameter!" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
    sendTelegram "Launched without any parameter!"
  fi
  exit 1
elif [[ "${1}" == "daily" ]] || [[ "${1}" == "Daily" ]]; then
  #setting type of launch depending on the parameter we got
  TYPE="Daily"
  TYPE2="daily"
elif [[ "${1}" == "weekly" ]] || [[ "${1}" == "Weekly" ]]; then
  #setting type of launch depending on the parameter we got
  TYPE="Weekly"
  TYPE2="weekly"
else
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Red}Unknown parameter!${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo -e "${Red}Unknown parameter!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
    sendTelegram "Unknown parameter!"
  fi    
  exit 1
fi

#Logging to DB function. ${TYPE} means name of table in there - Daily or Weekly
function Log() {
  if ! [[ -z "${dbName}" ]]; then
  mysql -u"${dbUser}" -p"${dbPass}" "${dbName}" << EOF
INSERT INTO ${TYPE} (Domain, Type, Result, Critical, Message) VALUES ("$1","$2","$3","$4","$5");
EOF
  fi
}

#Check does the MarkerDir exists - if not, that means encrypted partition is not mounted.
#This function is ignored if empty value of "markerDir" is set.
if ! [[ -z "${markerDir}" ]]; then
  if ! [[ -d "${markerDir}" ]]; then
    LOG+="$(/bin/date '+%d.%m.%Y %H:%m:%S') Encrypted backups volume is not mounted! Exiting!"
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Red}${LOG}${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Red}${LOG}${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
      sendTelegram "${LOG}"
    fi
    Log "-" "-" "1" "1" "${LOG}"
    exit 1
  fi
fi

#Check does the logDir exist and create it if it's not
if ! [[ -d "${logDir}" ]]; then
    mkdir -p "${logDir}"
fi

#main function to download using Rsync
function downloadRsync()
{
  local hostName="${1}"
  local dnsName="${2}"
  local rsyncUser="${3}"
  local remRsyncDir="${4}"
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Yellow}Starting ${White}Rsync${Yellow} download ${White}${TYPE2}${Yellow} backups from ${White}${hostName}${Yellow} as ${White}${dnsName}${Yellow}...${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo -e "${Yellow}Starting ${White}Rsync${Yellow} download ${White}${TYPE2}${Yellow} backups from ${White}${hostName}${Yellow} as ${White}${dnsName}${Yellow}...${Color_Off}"  >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
  fi
  LOG=""
  #check the type of allowed actions with host - "daily" only, "weekly" only, "all"
  if [[ "${hostType}" != "${TYPE2}" ]] && [[ ${hostType} != "all" ]]; then
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Red}Host ${Yellow}${hostName}${Red} is not allowed to use ${TYPE} downloading. Skipping...${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Red}Host ${Yellow}${hostName}${Red} is not allowed to use ${TYPE} downloading. Skipping...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
    fi
    continue
  fi
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Yellow}\tHeading to ${backupsFolder}/${hostName}/${TYPE2}/...${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo -e "${Yellow}\tHeading to ${backupsFolder}/${hostName}/${TYPE2}/...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
  fi
  cd "${backupsFolder}"/"${hostName}"/"${TYPE2}"/
  if [[ "${?}" == "0" ]]; then
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Yellow}\tDoing rsync -raP --delete ${scpUser}@${dnsName}:${remRsyncDir} ${backupsFolder}/${hostName}/${TYPE2}/ > /dev/null 2>&1${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Yellow}\tDoing rsync -raP --delete ${scpUser}@${dnsName}:${remRsyncDir} ${backupsFolder}/${hostName}/${TYPE2}/ > /dev/null 2>&1${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
    fi
    #Adding starting header to log file.
    if [[ "${launchFrom}" == "shell" ]]; then
      echo "------------------------------------Started $(/bin/date '+%d.%m.%Y %H:%m:%S') ${hostName}--------------------------------------"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo "------------------------------------Started $(/bin/date '+%d.%m.%Y %H:%m:%S') ${hostName}--------------------------------------" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
    fi
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Yellow}Backup folder size BEFORE: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/)${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Yellow}Backup folder size BEFORE: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/)${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
    fi
    rsync -raP --delete "${rsyncUser}"@"${dnsName}":"${remRsyncDir}" "${backupsFolder}"/"${hostName}"/"${TYPE2}"/ >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
  if [[ "$?" == "0" ]]; then
  #Here and futher - adding text to the special variable, which will be written to DB in the end.
    LOG+="${hostName} done successfully!"
      if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${Yellow}\tBackup folder size AFTER: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/)${Color_Off}"
      elif [[ "${launchFrom}" == "cron" ]]; then
        echo -e "${Yellow}\tBackup folder size AFTER: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/)${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
      fi
      #Setting up secure permissions
      chmod 700 "${backupsFolder}"/"${hostName}"/"${TYPE2}"/
      if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${White}${hostName}${Green} done successfully!${Color_Off}"
      elif [[ "${launchFrom}" == "cron" ]]; then
        echo -e "${White}${hostName}${Green} done successfully!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
      fi
      #Writing to our DB result with codes and text from the variable
    Log "${hostName}" "${TYPE}" "0" "0" "${LOG}"
    #Adding finishing trailer to log file.
    if [[ "${launchFrom}" == "shell" ]]; then
      echo "------------------------------------Finished $(/bin/date '+%d.%m.%Y %H:%m:%S') ${hostName}--------------------------------------"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo "------------------------------------Finished $(/bin/date '+%d.%m.%Y %H:%m:%S') ${hostName}--------------------------------------" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
    fi
  else
    LOG+="\n"
    LOG+="${hostName} error while downloading!"
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Red}${hostName} error while downloading!${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Red}${hostName} error while downloading!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
      sendTelegram "${hostName} error while downloading!"
    fi
    #Writing to our DB result with codes and text from the variable
    Log "${hostName}" "${TYPE}" "1" "0" "${LOG}"
    #Adding finishing trailer to log file.
    if [[ "${launchFrom}" == "shell" ]]; then
      echo "------------------------------------Finished $(/bin/date '+%d.%m.%Y %H:%m:%S') ${hostName}--------------------------------------"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo "------------------------------------Finished $(/bin/date '+%d.%m.%Y %H:%m:%S') ${hostName}--------------------------------------" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
    fi
  fi
  else
    LOG+="${hostName} error changing dir to ${backupsFolder}/${hostName}/${TYPE2}/!"
    Log "${hostName}" "${TYPE}" "1" "1" "${LOG}"
    sendTelegram "${LOG}"
  fi
}

#main function to download using Scp
function downloadScp()
{
  local hostName="${1}"
  local dnsName="${2}"
  local scpUser="${3}"
  local remScpDir="${4}"
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Yellow}Starting ${White}SCP${Yellow} download ${White}${TYPE2}${Yellow} backups from ${White}${hostName}${Yellow} as ${White}${dnsName}${Yellow}...${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo -e "${Yellow}Starting ${White}SCP${Yellow} download ${White}${TYPE2}${Yellow} backups from ${White}${hostName}${Yellow} as ${White}${dnsName}${Yellow}...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
  fi
  LOG=""
  #if current day folder not exists - create it
  if [[ ! -d "${backupsFolder}/${hostName}/${TYPE2}/${NAME}" ]]; then
    mkdir -p "${backupsFolder}"/"${hostName}"/"${TYPE2}"/"${NAME}"
  fi
  if [[ "${launchFrom}" == "shell" ]]; then
    echo -e "${Yellow}\tHeading to ${backupsFolder}/${hostName}/${TYPE2}/${NAME}...${Color_Off}"
  elif [[ "${launchFrom}" == "cron" ]]; then
    echo -e "${Yellow}\tHeading to ${backupsFolder}/${hostName}/${TYPE2}/${NAME}...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
  fi
  cd "${backupsFolder}"/"${hostName}"/"${TYPE2}"/"${NAME}"
  if [[ "${?}" == "0" ]]; then
    #Clearing folder.We don't need anything unexpected in our folder.
    rm -f * > /dev/null 2>&1
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Yellow}\tDoing scp ${scpUser}@${dnsName}:${remScpDir}/${TYPE2}/${NAME}/* . 2>&1${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Yellow}\tDoing scp ${scpUser}@${dnsName}:${remScpDir}/${TYPE2}/${NAME}/* . 2>&1${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
    fi
    LOG+=$(scp "${scpUser}"@"${dnsName}":"${remScpDir}"/"${TYPE2}"/"${NAME}"/* . 2>&1)
    if [[ "$?" == "0" ]]; then
      #If folder with backups has special sha1 checksums file - do the check
      if [[ -f "${shaFileRem}" ]] && [[ -f "${shaApp}" ]]; then
        #Creating local checksums list
        "${shaApp}" *.gz > "${shaFileLoc}"
        #Comparing with received file from remote server
        diff "${shaFileRem}" "${shaFileLoc}" > /dev/null
        if [[ "$?" == "0" ]]; then
          LOG+="${hostName} done successfully! Checksums ok!"
          if [[ "${launchFrom}" == "shell" ]]; then
            echo -e "${Green}${hostName} done successfully! Checksums ok! Backup folder size: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/${NAME})${Color_Off}"
          elif [[ "${launchFrom}" == "cron" ]]; then
            echo -e "${Green}${hostName} done successfully! Checksums ok! Backup folder size: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/${NAME})${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
          fi
          workArr+=("${backupsFolder}/${hostName}/${TYPE2}/${NAME}")
          Log "${hostName}" "${TYPE}" "0" "0" "${LOG}"
          rm -f ${shaFileLoc} > /dev/null
          #Creating file which make us able to see that everything in this directory is ok
          touch sha1sum-OK
        else
          LOG+="${hostName} done successfully! But checksums are NOT ok!"
          if [[ "${launchFrom}" == "shell" ]]; then
            echo -e "${Green}${hostName} done successfully!${Yellow} But checksums are NOT ok!${Green} Backup folder size: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/${NAME})${Color_Off}"
          elif [[ "${launchFrom}" == "cron" ]]; then
            echo -e "${Green}${hostName} done successfully!${Yellow} But checksums are NOT ok!${Green} Backup folder size: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/${NAME})${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
            sendTelegram "${LOG}"
          fi
          workArr+=("${backupsFolder}/${hostName}/${TYPE2}/${NAME}")
          Log "${hostName}" "${TYPE}" "2" "0" "${LOG}"
          #Creating file which make us able to see that in this directory we have problems with backups
          touch sha1sum-FAILED
        fi
      else
        #If no checksum file in directory or problems with sha1 check executable file
        if ! [[ -f "${shaApp}" ]]; then
          LOG+="${hostName} done successfully! Program ${shaApp} not found! Unable to check checksums!"
          if [[ "${launchFrom}" == "shell" ]]; then
            echo -e "${Green}${hostName} done successfully!${Yellow} Program ${shaApp} not found! Unable to check checksums!${Green} Backup folder size: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/${NAME})${Color_Off}"
          elif [[ "${launchFrom}" == "cron" ]]; then
            echo -e "${Green}${hostName} done successfully!${Yellow} Program ${shaApp} not found! Unable to check checksums!${Green} Backup folder size: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/${NAME})${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
          fi
        else
          LOG+="${hostName} done successfully! No checksums file to check!"
          if [[ "${launchFrom}" == "shell" ]]; then
            echo -e "${Green}${hostName} done successfully! ${Yellow}No checksums file found! ${Green}Backup folder size: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/${NAME})${Color_Off}"
          elif [[ "${launchFrom}" == "cron" ]]; then
            echo -e "${Green}${hostName} done successfully! ${Yellow}No checksums file found! ${Green}Backup folder size: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/${NAME})${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
          fi
        fi
        workArr+=("${backupsFolder}/${hostName}/${TYPE2}/${NAME}")
        Log "${hostName}" "${TYPE}" "2" "0" "${LOG}"
      fi
    else
      LOG+="\n"
      LOG+="${hostName} error while downloading!"
      if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${Red}${hostName} error while downloading backups!${Color_Off}"
      elif [[ "${launchFrom}" == "cron" ]]; then
        echo -e "${Red}${hostName} error while downloading backups!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
        sendTelegram "${hostName} error while downloading backups!"
      fi
      Log "${hostName}" "${TYPE}" "1" "0" "${LOG}"
    fi
  else
    LOG+="${hostName} error changing dir to ${backupsFolder}/${hostName}/${TYPE2}/${NAME}!"
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Red}${LOG}${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Red}${LOG}${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
      sendTelegram "${LOG}"
    fi
    Log "${hostName}" "${TYPE}" "1" "1" "${LOG}"
  fi
}

#Function sets permissions to folders from workArr() variable and files inside them.
function updatePermissions()
{
  #if updPem parameter in config set to 1, then do it
  if [[ "${updPerm}" == "1" ]]; then
    for (( i=0; i < ${#workArr[@]}; i++))
    {
      chmod "${permFolders}" "${workArr[${i}]}"
      if [[ "${?}" != "0" ]]; then
        if [[ "${launchFrom}" == "shell" ]]; then
          echo -e "${Red}\tUnexpected error while setting up folder permission on ${workArr[${i}]}${Color_Off}"
        elif [[ "${launchFrom}" == "cron" ]]; then
          echo -e "${Red}\tUnexpected error while setting up folder permission on ${workArr[${i}]}${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
          sendTelegram "Unexpected error while setting up folder permission on ${workArr[${i}]}"
        fi
      fi
      chmod "${permFiles}" "${workArr[${i}]}"/*
      if [[ "${?}" != "0" ]]; then
        if [[ "${launchFrom}" == "shell" ]]; then
          echo -e "${Red}\tUnexpected error while setting up files permissions on ${workArr[${i}]}/*${Color_Off}"
        elif [[ "${launchFrom}" == "cron" ]]; then
          echo -e "${Red}\tUnexpected error while setting up files permissions on ${workArr[${i}]}/*${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
          sendTelegram "Unexpected error while setting up files permissions on ${workArr[${i}]}/*"
        fi
      fi
      if [[ "${launchFrom}" == "shell" ]]; then
        echo -e "${Yellow}${workArr[${i}]} setting of permissions done.${Color_Off}"
      elif [[ "${launchFrom}" == "cron" ]]; then
        echo -e "${Yellow}${workArr[${i}]} setting of permissions done.${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
      fi
    }
  fi
}

#Main function.Everything starts here.
#creating lock file
touch ${lockFile}
if [[ "${launchFrom}" == "shell" ]]; then
  echo -e "${Green}--------------------------------------------------------------$(/bin/date '+%d.%m.%Y %H:%m:%S') Starting new tasks:-------------------------------------------------------------${Color_Off}"
  if [[ -z "${dbName}" ]]; then
    echo -e "${Yellow}------------MySQL logging is not enabled. See README------------${Color_Off}"
  fi
  if [[ "${updPerm}" != "1" ]]; then
    echo -e "${Yellow}------------Permissions update is not enabled. See README------------${Color_Off}"
  fi
elif [[ "${launchFrom}" == "cron" ]]; then
  echo -e "${Green}-----------------------------------------------$(/bin/date '+%d.%m.%Y %H:%m:%S') Starting new tasks:----------------------------------------------${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
  if [[ -z "${dbName}" ]]; then
    echo -e "${Yellow}------------MySQL logging is not enabled. See README------------${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
  fi
  if [[ "${updPerm}" != "1" ]]; then
    echo -e "${Yellow}------------Permissions update is not enabled. See README------------${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
  fi
  if [[ -z "${telegramChat}" || -z "${telegramToken}" ]]; then
    echo -e "${Yellow}------------Telegram notifications are not enabled. See README------------${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
  fi
fi
#Reading  config file and parsing it
while read hostName dnsName hostType dailyType weeklyType remScpDir scpUser remRsyncDir rsyncUser; do
  #Skipping comments strings - if anywhere is # symbol.
  if [[ "${hostName}" == *"#"* || "${dnsName}" == *"#"* || "${hostType}" == *"#"* || "${dailyType}" == *"#"* || "${weeklyType}" == *"#"* \
  || "${remScpDir}" == *"#"* || "${scpUser}" == *"#"* || "${remRsyncDir}" == *"#"* || "${rsyncUser}" == *"#"* ]]; then
    continue
  fi
  #Check do all variables are filled by data. If not, shows up error and skipping this string
  if [[ -z "${hostName}" || -z "${dnsName}" || -z "${hostType}" || -z "${dailyType}" || -z "${weeklyType}" || -z "${remScpDir}" || -z "${scpUser}" ]]; then
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Red}Error parsing string data from the config file! Some important variables are not set!${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Red}Error parsing string data from the config file! Some important variables are not set!${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
      sendTelegram "Error parsing string data from the config file! Some important variables are not set!"
    fi
    continue
  fi
  #Download for Daily and Weekly type with SCP 
  if [ "${hostType}" == "${TYPE2}" ] || [ "${hostType}" == "all" ]; then
    #Daily backup via scp
    if  ([ "${TYPE2}" == "daily" ] && [ "${dailyType}" == "scp" ]); then
      downloadScp "${hostName}" "${dnsName}" "${scpUser}" "${remScpDir}"
      continue
    #Weekly backup via scp
    elif ([ "${TYPE2}" == "weekly" ] && [ "${weeklyType}" == "scp" ]); then
      downloadScp "${hostName}" "${dnsName}" "${scpUser}" "${remScpDir}"
      continue
    #Daily backup via rsync
    elif ([ "${TYPE2}" == "daily" ] && [ "${dailyType}" == "rsync" ]); then
      if [[ -z "${rsyncUser}" ]]; then
        rsyncUser="${scpUser}"
      fi
      downloadRsync "${hostName}" "${dnsName}" "${rsyncUser}" "${remRsyncDir}"
      continue
    #Weekly backup via rsync
    elif ([ "${TYPE2}" == "weekly" ] && [ "${weeklyType}" == "rsync" ]); then
      if [[ -z "${rsyncUser}" ]]; then
        rsyncUser="${scpUser}"
      fi
      downloadRsync "${hostName}" "${dnsName}" "${rsyncUser}" "${remRsyncDir}"
      continue
    fi
  else
    if [[ "${launchFrom}" == "shell" ]]; then
      echo -e "${Red}Host ${Yellow}${hostName}${Red} is not allowed to use ${TYPE} downloading. Skipping...${Color_Off}"
    elif [[ "${launchFrom}" == "cron" ]]; then
      echo -e "${Red}Host ${Yellow}${hostName}${Red} is not allowed to use ${TYPE} downloading. Skipping...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
    fi
    continue
  fi
done <<< $(cat "${serverList}")
#Updating mode for files and folder to secure values
if [[ "${launchFrom}" == "shell" ]]; then
  echo -e "${Yellow}Almost done. Setting up correct permissions on backups...${Color_Off}"
elif [[ "${launchFrom}" == "cron" ]]; then
  echo -e "${Yellow}Almost done. Setting up correct permissions on backups...${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
fi
updatePermissions
if [[ "${launchFrom}" == "shell" ]]; then
  echo -e "${Green}---------------------------------------------------------$(/bin/date '+%d.%m.%Y %H:%m:%S') All tasks done successfully!---------------------------------------------------------${Color_Off}"
elif [[ "${launchFrom}" == "cron" ]]; then
  echo -e "${Green}------------------------------------------$(/bin/date '+%d.%m.%Y %H:%m:%S') All tasks done successfully!------------------------------------------${Color_Off}" >> "${logDir}"/"${NAME}"-"${TYPE2}"-download.log
fi
#removing lock
rm -f ${lockFile}
