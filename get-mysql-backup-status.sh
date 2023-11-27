#!/bin/env bash

DATE=$(/bin/date '+%Y.%m.%d')
Color_Off='\033[0m'
Red='\033[0;31m'
Green='\033[0;32m'               #Variables with text color for output.
Yellow='\033[0;33m'
White='\033[0;37m'
dbUser=""
dbPass=""
dbName=""
launchFrom=""                    #Here we will set from what env. the scrips was launched - shell or cron.
confFile="./settings.local"      #The name of main config file.

#Head to the current directory of the script it has been launched from. Check if we are launched from symlink or any other place as subshell process.
echo "${0}" | egrep -e '^\..*' > /dev/null 2>&1
if [[ "${?}" == "0" ]]; then
  #the script is launched from shell manually
  scriptName=$(echo "${0}" | sed 's/.//')
  scriptPath=$(realpath -e "${0}" | sed "s/\\${scriptName}//")
  launchFrom="shell"
  cd "${scriptPath}"
else
  #the script is launched from cron or any parent process
  scriptName="$(basename "${0}")"
  scriptPath="$(echo "${0}" | sed "s/${scriptName}//")"
  launchFrom="cron"
  cd "${scriptPath}"
fi

if ! [[ -f "${confFile}" ]]; then
	echo -e "${Red}Warning! ${confFile} with all important settings is not found!${Color_Off}"
	exit 1
else
	#getting all necessary variables from external file
    source "${confFile}"
    #checking all variables are set. No empty one.
    if [[ -z "${dbName}" ]]; then
        echo -e "${Red}Logging into MySQL database is disabled.There is no sense to launch this script.${Color_Off}"
        exit 3
    fi
    if [[ -z "${dbUser}" ]] || [[ -z "${dbPass}" ]]; then
        echo -e "${Red}Error! Some of two important variable in ${confFile} is empty!${Color_Off}"
        echo -e "${Yellow}dbUser="${dbUser}"\ndbPass="${dbPass}"${Color_Off}"
		exit 1
	fi
fi

#check what we've got as the first parameter.If it is too long - drop error.
if ! [[ -z "${1}" ]] && [[ ${#1} -gt 10 ]]; then
	echo -e "${Red}Too long parameter! Seems it is some mistake in here.${Color_Off}"
	exit 1
elif [[ -z "${1}" ]]; then
    echo -e "${Red}No parameter defined!${Color_Off}"
    echo -e "${Yellow}Usage: $(basename "${0}") <todayLog/weeklyLog> <domain>${Color_Off}"
    exit 1
fi

if [[ ! -z "$2" ]]; then
    if [ ${#2} -gt 22 ]; then
	    echo -e "${Red}Too long domain name.${Color_Off}"
	    exit 1
    fi
else
    echo -e "${Red}Domain is not defined.${Color_Off}"
    echo -e "${Yellow}Usage: $(basename "${0}") <todayLog/weeklyLog> <domain>${Color_Off}"
    exit 1
fi

case "${1}" in
todayLog)
    RES=$(mysql -u${dbUser} -p${dbPass} -e "USE ${dbName};SELECT Result FROM Daily WHERE Date='${DATE}' AND Domain='${2}' LIMIT 1;" | tail -1)
    if [[ -z "${RES}" ]]; then
        echo "255"
    else
        echo "${RES}"
    fi
    ;;
weeklyLog)
    RES=$(mysql -u${dbUser} -p${dbPass} -e "USE ${dbName};SELECT Result FROM Weekly WHERE Date='${DATE}' AND Domain='${2}' LIMIT 1;" | tail -1)
    if [[ -z "${RES}" ]]; then
        echo "255"
    else
        echo "${RES}"
    fi
    ;;
*)
    echo "No such command!"
    exit 1
    ;;
esac
