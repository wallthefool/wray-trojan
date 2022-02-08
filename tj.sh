#!/bin/bash

# This file is accessible as https://install.direct/go.sh
# Original source is located at github.com/v2ray/v2ray-core/release/install-release.sh

# If not specify, default meaning of return value:
# 0: Success
# 1: System error
# 2: Application error
# 3: Network error

# CLI arguments
PROXY=''
HELP=''
FORCE=''
CHECK=''
REMOVE=''
VERSION=''
VSRC_ROOT='/root/trojan'
EXTRACT_ONLY=''
LOCAL=''
LOCAL_INSTALL=''
DIST_SRC='github'
ERROR_IF_UPTODATE=''

CUR_VER=""
NEW_VER=""
VDIS=''
ZIPFILE="/root/trojan/trojan.zip"
V2RAY_RUNNING=0

CMD_INSTALL=""
CMD_UPDATE=""
SOFTWARE_UPDATED=0

SYSTEMCTL_CMD=$(command -v systemctl 2>/dev/null)
SERVICE_CMD=$(command -v service 2>/dev/null)

#######color code########
RED="31m"      # Error message
GREEN="32m"    # Success message
YELLOW="33m"   # Warning message
BLUE="36m"     # Info message


#########################
while [[ $# > 0 ]]; do
    case "$1" in
        -h|--help)
        HELP="1"
        ;;
        --host)
        HOST="$2"
        shift
        ;;
        --token)
        TOKEN="$2"
        shift
        ;;
        *)
                # unknown option
        ;;
    esac
    shift # past argument or value
done

colorEcho(){
    echo -e "\033[${1}${@:2}\033[0m" 1>& 2
}

archAffix(){
    case $(uname -m) in
        i686|i386)
            echo '386'
        ;;
        x86_64|amd64)
            echo 'amd64'
        ;;
        *armv7*|armv6l)
            echo 'arm'
        ;;
        *armv8*|aarch64)
            echo 'arm64'
        ;;
        *mips64le*)
            echo 'mips64le'
        ;;
        *mips64*)
            echo 'mips64'
        ;;
        *mipsle*)
            echo 'mipsle'
        ;;
        *mips*)
            echo 'mips'
        ;;
        *s390x*)
            echo 's390x'
        ;;
        ppc64le)
            echo 'ppc64le'
        ;;
        ppc64)
            echo 'ppc64'
        ;;
        *)
            return 1
        ;;
    esac
	return 0
}

zipRoot() {
    unzip -lqq "$1" | awk -e '
        NR == 1 {
            prefix = $4;
        }
        NR != 1 {
            prefix_len = length(prefix);
            cur_len = length($4);

            for (len = prefix_len < cur_len ? prefix_len : cur_len; len >= 1; len -= 1) {
                sub_prefix = substr(prefix, 1, len);
                sub_cur = substr($4, 1, len);

                if (sub_prefix == sub_cur) {
                    prefix = sub_prefix;
                    break;
                }
            }

            if (len == 0) {
                prefix = "";
                nextfile;
            }
        }
        END {
            print prefix;
        }
    '
}

downloadTrojan(){
    rm -rf /root/trojan
    mkdir -p /root/trojan
    DOWNLOAD_LINK="https://github.com/wallthefool/wray-trojan/raw/main/manager-new-linux-${VDIS}.zip"
    colorEcho ${BLUE} "Downloading Trojan-Work: ${DOWNLOAD_LINK}"
    curl ${PROXY} -L -H "Cache-Control: no-cache" -o ${ZIPFILE} ${DOWNLOAD_LINK}
    if [ $? != 0 ];then
        colorEcho ${RED} "Failed to download! Please check your network or try again."
        return 3
    fi
    return 0
}

installSoftware(){
    COMPONENT=$1
    if [[ -n `command -v $COMPONENT` ]]; then
        return 0
    fi

    getPMT
    if [[ $? -eq 1 ]]; then
        colorEcho ${RED} "The system package manager tool isn't APT or YUM, please install ${COMPONENT} manually."
        return 1
    fi
    if [[ $SOFTWARE_UPDATED -eq 0 ]]; then
        colorEcho ${BLUE} "Updating software repo"
        $CMD_UPDATE
        SOFTWARE_UPDATED=1
    fi

    colorEcho ${BLUE} "Installing ${COMPONENT}"
    $CMD_INSTALL $COMPONENT
    if [[ $? -ne 0 ]]; then
        colorEcho ${RED} "Failed to install ${COMPONENT}. Please install it manually."
        return 1
    fi
    return 0
}

# return 1: not apt, yum, or zypper
getPMT(){
    if [[ -n `command -v apt-get` ]];then
        CMD_INSTALL="apt-get -y -qq install"
        CMD_UPDATE="apt-get -qq update"
    elif [[ -n `command -v yum` ]]; then
        CMD_INSTALL="yum -y -q install"
        CMD_UPDATE="yum -q makecache"
    elif [[ -n `command -v zypper` ]]; then
        CMD_INSTALL="zypper -y install"
        CMD_UPDATE="zypper ref"
    else
        return 1
    fi
    return 0
}


main(){
    
    killall 'trojan-go'
    killall 'trojan-work'
    
    local ARCH=$(uname -m)
    VDIS="$(archAffix)"


    # download via network and extract
    installSoftware "curl" || return $?
    installSoftware "lsof" || return $?
    downloadTrojan || return $?
    installSoftware unzip || return $?
    local ZIPROOT="$(zipRoot "${ZIPFILE}")"

    unzip -o "${ZIPFILE}" -d '/root/trojan' && \
    chmod 777 '/root/trojan/trojan-work' '/root/trojan/trojan/trojan-go' || {
        colorEcho ${RED} "Failed to chmod trojan-work."
        return 1
    }
    # Install Trojan server config to /etc/v2ray
    cat '/root/trojan/config.yaml.example' | \
    sed -e "s?http://whmcs.com?${HOST}?g; s?demo?${TOKEN}?g;" - > \
    '/root/trojan/config.yaml' || {
        colorEcho ${YELLOW} "Failed to create Trojan configuration file. Please create it manually."
        return 1
    }
    # nohup '/root/trojan/trojan-work' >'/root/trojan/trojan-work.log' 2>&1 &
    echo "[Unit]
    After=network.target
    [Service]
    WorkingDirectory=/root/trojan/
    Type=simple
    LimitCPU=infinity
    LimitFSIZE=infinity
    LimitDATA=infinity
    LimitSTACK=infinity
    LimitCORE=infinity
    LimitRSS=infinity
    LimitNOFILE=infinity
    LimitAS=infinity
    LimitNPROC=infinity
    LimitMEMLOCK=infinity
    LimitLOCKS=infinity
    LimitSIGPENDING=infinity
    LimitMSGQUEUE=infinity
    LimitRTPRIO=infinity
    LimitRTTIME=infinity
    ExecStart=/root/trojan/trojan-work
    Restart=on-failure
    [Install]
    WantedBy=multi-user.target" > /etc/systemd/system/trojan-work.service
    systemctl daemon-reload
    systemctl enable trojan-work
    colorEcho ${GREEN} "Trojan-Work is installed."
    # rm -rf /root/trojan
    return 0
}

main
