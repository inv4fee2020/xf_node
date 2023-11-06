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

    #sudo apt update -y && sudo apt upgrade -y

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

    if ! command -v docker &> /dev/null; then
        echo "Docker is not installed. installing..."

        echo "Installing Docker"

        #sudo apt-get update

        sudo apt-get install \
                apt-transport-https \
                ca-certificates \
                curl \
                software-properties-common -y

        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

        sudo add-apt-repository \
             "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
             $(lsb_release -cs) \
             stable"

        sudo apt-get update

        sudo apt-get install docker-ce -y

        sudo curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose


        sudo chmod +x /usr/local/bin/docker-compose
        sleep 5
        echo "Docker Installed successfully"
    else
        echo "Docker is already installed. skipping.."
    fi
}


FUNC_CLONE_NODE_SETUP(){

    echo "Clone Xinfin Node to HOME directory "
    cd ~/
    directory="XinFin-Node"

    if [ ! -d "$directory" ]; then
      echo "The directory '$directory' does not exist."
        git clone https://github.com/XinFinOrg/XinFin-Node
    else
      echo "The directory '$directory' exists."
    fi
    cd $directory/$VARVAL_CHAIN_NAME

    ## update the .env file with the $VARVAL_NODE_NAME
    ## NODE_NAME=XF_MasterNode
    sed  -i.bak 's|^NODE_NAME.*|NODE_NAME='$VARVAL_NODE_NAME'|g' .env

    ## update the email address with random mail address
    ## CONTACT_DETAILS=YOUR_EMAIL_ADDRESS
    sed  -i 's|^CONTACT_DETAILS.*|CONTACT_DETAILS=noreply@rpc.local|g' .env


    ## update the yml file with network config to allow nginx to pass traffic

    # Define the search text
    search_text='    network_mode: "host"'

    # Define the replacement text with a variable for the port value

replace_text="\
    networks:
      mynetwork:
        ipv4_address: 172.19.0.2
    ports:
      - \"$VARVAL_DKR_PORT:$VARVAL_DKR_PORT\"
networks:
  mynetwork:
    ipam:
      driver: default
      config:
        - subnet: \"172.19.0.0/24\""

    # Specify the input YAML file
    input_file="docker-compose.yml"

    # Create a backup of the original YAML file with a timestamp
    backup_file="docker-compose-$(date +'%Y%m%d%H%M%S').yml"

    # Copy the original file to the backup file
    cp "$input_file" "$backup_file"

    # Use awk to perform the replacement and maintain YAML formatting
    awk -v search="$search_text" -v replace="$replace_text" '{
      if ($0 == search) {
        printf("%s\n", replace)
        found = 1
      } else {
        print
      }
    }END{
      if (!found) {
        print "Error: Search text not found in the input file." > "/dev/stderr"
        exit 1
      }
    }' "$input_file" > "$input_file.tmp"

    # Replace the original file with the temporary file
    mv "$input_file.tmp" "$input_file"

    echo "Replacement complete, and a backup has been created as $backup_file."


    sudo docker-compose -f docker-compose.yml up -d
    echo ""
    echo "Starting Xinfin Node ..."
    #FUNC_EXIT
}



FUNC_SETUP_UFW_PORTS(){
    echo 
    echo 
    echo -e "${GREEN}#########################################################################${NC}" 
    echo 
    echo -e "${GREEN}## Base Setup: Configure Firewall...${NC}"
    echo 

    # Get current SSH port number 
    CPORT=$(sudo ss -tlpn | grep sshd | awk '{print$4}' | cut -d ':' -f 2 -s)
    #echo $CPORT
    sudo ufw allow $CPORT/tcp
    sudo ufw allow $VARVAL_DKR_PORT/tcp
    sudo ufw status verbose
    sleep 2s
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

    USER_DOMAINS=""
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
    #FUNC_VARS;

    # installs default packages listed in vars file
    FUNC_PKG_CHECK;

    # Firewall config
    FUNC_SETUP_UFW_PORTS
    FUNC_ENABLE_UFW;

    #Docker install
    #FUNC_DKR_INSTALL;

    #XinFin Node setup
    #FUNC_CLONE_NODE_SETUP;



    # Update the package list and upgrade the system
    #apt update
    #apt upgrade -y

    # Install Nginx
    sudo apt install nginx -y

    # Check if UFW (Uncomplicated Firewall) is installed
    if dpkg -l | grep -q "ufw"; then
        # If UFW is installed, allow Nginx through the firewall
        sudo ufw allow 'Nginx Full'
    else
        echo "UFW is not installed. Skipping firewall configuration."
    fi

    # Install Let's Encrypt Certbot
    sudo apt install certbot python3-certbot-nginx -y

    # Prompt for user domains if not provided as a variable
    #if [ -z "$USER_DOMAINS" ]; then
    #    read -p "Enter a comma-separated list of domains, A record followed by CNAME records for RPC & WSS (e.g., domain1.com,domain2.com): " USER_DOMAINS
    #fi

    USER_DOMAINS="roci.inv4fee.xyz,apothem-rpc.inv4fee.xyz,apothem-ws.inv4fee.xyz"
    echo "$USER_DOMAINS"

    IFS=',' read -ra DOMAINS_ARRAY <<< "$USER_DOMAINS"
    A_RECORD="${DOMAINS_ARRAY[0]}"
    CNAME_RECORD1="${DOMAINS_ARRAY[1]}"
    CNAME_RECORD2="${DOMAINS_ARRAY[2]}" 

    # Start Nginx and enable it to start at boot
    sudo systemctl start nginx
    sudo systemctl enable nginx

    # Create a test index.html page
    test_html="/var/www/html/index.html"
    sudo echo "<html><head><title>Welcome to $A_RECORD</title></head><body><h1>Welcome to $A_RECORD</h1></body></html>" > "$test_html"

    # Request and install a Let's Encrypt SSL/TLS certificate for Nginx
    sudo certbot --nginx -d "$USER_DOMAINS" -m "inv4fee2020@gmail.com"

    # Get the source IP of the current SSH session
    source_ip=$(echo $SSH_CONNECTION | awk '{print $1}')

    # Create a new Nginx configuration file with the user-provided domain and test HTML page
    nginx_config="/etc/nginx/sites-available/default"  # Modify this path if your Nginx config is in a different location
    sudo mv $nginx_config "$nginx_config.orig"
    sudo cat <<EOF > "$nginx_config"
server {
    listen 80;
    server_name $CNAME_RECORD1;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $CNAME_RECORD1;

    # SSL certificate paths
    ssl_certificate /etc/letsencrypt/live/$A_RECORD/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$A_RECORD/privkey.pem;

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
server {
    listen 80;
    server_name $CNAME_RECORD2;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $CNAME_RECORD2;

    # SSL certificate paths
    ssl_certificate /etc/letsencrypt/live/$A_RECORD/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$A_RECORD/privkey.pem;

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
    sudo systemctl reload nginx

    # Provide some basic instructions
    echo "Nginx is now installed and running with a Let's Encrypt SSL/TLS certificate for the domain $user_domain."
    echo "You can access your secure web server by entering https://$CNAME_RECORD1 of https://$CNAME_RECORD2 in a web browser."

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