#!/bin/bash


# Get current user id and store as var
USER_ID=$(getent passwd $EUID | cut -d: -f1)

# Authenticate sudo perms before script execution to avoid timeouts or errors
sudo -l > /dev/null 2>&1

# Set the sudo timeout for USER_ID to expire on reboot instead of default 5mins
echo "Defaults:$USER_ID timestamp_timeout=-1" > /tmp/xfsudotmp
sudo sh -c 'cat /tmp/xfsudotmp > /etc/sudoers.d/xfnode_deploy'

# Set Colour Vars
GREEN='\033[0;32m'
#RED='\033[0;31m'
RED='\033[0;91m'  # Intense Red
YELLOW='\033[0;33m'
BYELLOW='\033[1;33m'
NC='\033[0m' # No Color

FDATE=$(date +"%Y_%m_%d_%H_%M")

source xf_node.vars

#FUNC_VARS(){
### VARIABLE / PARAMETER DEFINITIONS
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#
#    XF_VARS_FILE="xf_node_$(hostname -f)".vars
#    if [ ! -e ~/$XF_VARS_FILE ]; then
#        #clear
#        echo
#        echo -e "${RED} #### NOTICE: No VARIABLES file found. ####${NC}"
#        echo -e "${RED} ..creating local vars file '$HOME/$XF_VARS_FILE' ${NC}"
#
#        cp sample.vars ~/$XF_VARS_FILE
#        chmod 600 ~/$XF_VARS_FILE
#
#        echo
#        echo -e "${GREEN}nano '~/$XF_VARS_FILE' ${NC}"
#        #sleep 2s
#    fi
#
#    source ~/$XF_VARS_FILE
#
#
#}



FUNC_PKG_CHECK(){

    echo -e "${GREEN}#########################################################################${NC}"
    echo
    echo -e "${GREEN}## CHECK NECESSARY PACKAGES HAVE BEEN INSTALLED...${NC}"
    echo     

    sudo apt update -y && sudo apt upgrade -y

    for i in "${SYS_PACKAGES[@]}"
    do
        hash $i &> /dev/null
        if [ $? -eq 1 ]; then
           echo >&2 "package "$i" not found. installing...."
           sudo apt install -y "$i"
        fi
        echo "packages "$i" exist. proceeding...."
    done
}


FUNC_DKR_INSTALL(){


    sudo apt-get install \
            apt-transport-https ca-certificates curl git jq \
            software-properties-common -y


    echo "Installing Docker"

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

    sudo add-apt-repository \
         "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
         $(lsb_release -cs) \
         stable"

    sudo apt-get update

    sudo apt-get install docker-ce -y

    echo "Installing Docker-Compose"

    curl -L "https://github.com/docker/compose/releases/download/1.25.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

    chmod +x /usr/local/bin/docker-compose
    sleep 5
    echo "Docker Compose Installed successfully"
}


FUNC_CLONE_NODE_SETUP(){

    echo "Clone Xinfin Node to HOME directory "
    cd ~/
    git clone https://github.com/XinFinOrg/XinFin-Node
    cd XinFin-Node/$VARVAL_CHAIN_NAME

    echo "Generating Private Key and Wallet Address into keys.json"
    docker build -t address-creator ../address-creator/ && docker run -e NUMBER_OF_KEYS=1 -e FILE=true -v "$(pwd):/work/output" -it address-creator

    PRIVATE_KEY=$(jq -r '.key0.PrivateKey' keys.json)
    sed -i "s/PRIVATE_KEY=xxxx/PRIVATE_KEY=${PRIVATE_KEY}/g" .env
    sed -i "s/INSTANCE_NAME=XF_MasterNode/INSTANCE_NAME=${VARVAL_NODE_NAME}/g" .env

    echo ""
    echo "Starting Xinfin Node ..."
    #sudo docker-compose -f docker-compose.yml up --build --force-recreate -d
    FUNC_EXIT
}




FUNC_ENABLE_UFW(){

    echo 
    echo 
    echo -e "${GREEN}#########################################################################${NC}"
    echo 
    echo -e "${GREEN}## Base Setup: Change UFW logging to ufw.log only${NC}"
    echo 
    # source: https://handyman.dulare.com/ufw-block-messages-in-syslog-how-to-get-rid-of-them/
    sudo sed -i -e 's/\#& stop/\& stop/g' /etc/rsyslog.d/20-ufw.conf
    sudo cat /etc/rsyslog.d/20-ufw.conf | grep '& stop'

    echo 
    echo 
    echo -e "${GREEN}#########################################################################${NC}" 
    echo 
    echo -e "${GREEN}## Setup: Enable Firewall...${NC}"
    echo 
    sudo systemctl start ufw && sudo systemctl status ufw
    sleep 2s
    echo "y" | sudo ufw enable
    #sudo ufw enable
    sudo ufw status verbose
}


FUNC_NODE_DEPLOY(){
    
    echo -e "${GREEN}#########################################################################${NC}"
    echo -e "${GREEN}#########################################################################${NC}"
    echo -e "${GREEN}${NC}"
    echo -e "${GREEN}             XinFin ${BYELLOW}$_OPTION${GREEN} RPC/WSS Node - Install${NC}"
    echo -e "${GREEN}${NC}"
    echo -e "${GREEN}#########################################################################${NC}"
    echo -e "${GREEN}#########################################################################${NC}"
    sleep 3s


    VARVAL_NODE_NAME="xf_node_$(hostname -f)"

    if [ "$_OPTION" == "mainnet" ]; then
        echo -e "${GREEN} ### Configuring node for ${BYELLOW}$_OPTION${GREEN}..  ###${NC}"

        VARVAL_CHAIN_NAME=$_OPTION
        VARVAL_CHAIN_RPC=$NGX_MAINNET_RPC
        VARVAL_CHAIN_WSS=$NGX_MAINNET_WSS
        VARVAL_DKR_PORT=$DKR_MAINNET_PORT

    elif [ "$_OPTION" == "testnet" ]; then
        echo -e "${GREEN} ### Configuring node for ${BYELLOW}$_OPTION${GREEN}..  ###${NC}"

        VARVAL_CHAIN_NAME=$_OPTION
        VARVAL_CHAIN_RPC=$NGX_TESTNET_RPC
        VARVAL_CHAIN_WSS=$NGX_TESTNET_WSS
        VARVAL_DKR_PORT=$DKR_TESTNET_PORT
    fi


    # loads variables 
    FUNC_VARS;

    # installs default packages listed in vars file
    FUNC_PKG_CHECK;
    FUNC_ENABLE_UFW;
    FUNC_DKR_INSTALL;
    FUNC_CLONE_NODE_SETUP;



    # Update the package list and upgrade the system
    apt update
    apt upgrade -y

    # Install Nginx
    apt install nginx -y

    # Check if UFW (Uncomplicated Firewall) is installed
    if dpkg -l | grep -q "ufw"; then
        # If UFW is installed, allow Nginx through the firewall
        ufw allow 'Nginx Full'
    else
        echo "UFW is not installed. Skipping firewall configuration."
    fi

    # Install Let's Encrypt Certbot
    apt install certbot python3-certbot-nginx -y

    # Prompt the user for the comma-separated domain list
    read -p "Enter a comma-separated list of domains (e.g., domain1.com,domain2.com): " user_domains

    # Extract the primary domain (the first entry in the list)
    primary_domain=$(echo "$user_domains" | awk -F, '{print $1}')
    echo "$primary_domain"

    # Create an array of additional domains
    IFS=',' read -ra additional_domains <<< "$user_domains"
    echo "$additional_domains"

    # Start Nginx and enable it to start at boot
    systemctl start nginx
    systemctl enable nginx

    # Create a test index.html page
    test_html="/var/www/html/index.html"
    echo "<html><head><title>Welcome to $primary_domain</title></head><body><h1>Welcome to $primary_domain</h1></body></html>" > "$test_html"

    # Request and install a Let's Encrypt SSL/TLS certificate for Nginx
    certbot --nginx -d "$user_domains"

    # Get the source IP of the current SSH session
    source_ip=$(echo $SSH_CONNECTION | awk '{print $1}')

    # Create a new Nginx configuration file with the user-provided domain and test HTML page
    nginx_config="/etc/nginx/sites-available/default"  # Modify this path if your Nginx config is in a different location

    cat <<EOF > "$nginx_config"
server {
    listen 80;
    server_name $user_domain;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $user_domain www.$user_domain;

    # SSL certificate paths
    ssl_certificate /etc/letsencrypt/live/$user_domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$user_domain/privkey.pem;

    # Other SSL settings
    ssl_protocols TLSv1.3 TLSv1.2;
    ssl_ciphers 'TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    # Additional SSL settings, including HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    location / {
        allow $source_ip;  # Allow the source IP of the SSH session
        deny all;
        proxy_pass http://your_backend_server;
        # Other proxy settings as needed
    }
    
    # Serve the test index.html page
    location = / {
        root /var/www/html;
    }

    # Additional server configuration can go here
}
EOF

    # Reload Nginx to apply the new configuration
    systemctl reload nginx

    # Provide some basic instructions
    echo "Nginx is now installed and running with a Let's Encrypt SSL/TLS certificate for the domain $user_domain."
    echo "You can access your secure web server by entering https://$user_domain in a web browser."

    FUNC_EXIT
}




FUNC_EXIT(){
    # remove the sudo timeout for USER_ID
    sudo sh -c 'rm -f /etc/sudoers.d/xfnode_deploy'
    bash ~/.profile
    sudo -u $USER_ID sh -c 'bash ~/.profile'
	exit 0
	}


FUNC_EXIT_ERROR(){
	exit 1
	}
  

case "$1" in
        mainnet)
                _OPTION="mainnet"
                FUNC_NODE_DEPLOY
                ;;
        testnet)
                _OPTION="testnet"
                FUNC_NODE_DEPLOY
                ;;
        *)
                
                echo 
                echo 
                echo "Usage: $0 {function}"
                echo 
                echo "    example: " $0 mainnet""
                echo 
                echo 
                echo "where {function} is one of the following;"
                echo 
                echo "      mainnet       ==  deploys the full Mainnet node with Nginx & LetsEncrypt TLS certificate"
                echo 
                echo "      testnet       ==  deploys the full Apothem node with Nginx & LetsEncrypt TLS certificate"
                echo
esac