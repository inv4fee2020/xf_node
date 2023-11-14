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

        sudo apt-get update -y

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
    NODE_DIR="XinFin-Node"

    if [ ! -d "$NODE_DIR" ]; then
      echo "The directory '$NODE_DIR' does not exist."
        git clone https://github.com/XinFinOrg/XinFin-Node
    else
      echo "The directory '$NODE_DIR' exists."
    fi

    cd $NODE_DIR/$VARVAL_CHAIN_NAME


    ## update the email address with random mail address
    ## CONTACT_DETAILS=YOUR_EMAIL_ADDRESS
    sudo sed  -i 's|^CONTACT_DETAILS.*|CONTACT_DETAILS=noreply@rpc.local|g' .env


    ## update the yml file with network config to allow nginx to pass traffic

    # Specify the input YAML file
    input_file="docker-compose.yml"

    # Create a backup of the original YAML file with a timestamp
    backup_file="docker-compose-$(date +'%Y%m%d%H%M%S').yml"

    # Copy the original file to the backup file
    sudo cp "$input_file" "$backup_file"


    if [ "$_OPTION" == "testnet" ]; then


    ## update the .env file 
    ## NODE_NAME=XF_MasterNode
    sudo sed  -i.bak 's|^NODE_NAME.*|NODE_NAME='$VARVAL_NODE_NAME'|g' .env

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

    # Use awk to perform the replacement and maintain YAML formatting
    sudo awk -v search="$search_text" -v replace="$replace_text" '{
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
    }' "$input_file" | sudo tee "$input_file.tmp" > /dev/null
    #> "$input_file.tmp"

    # Replace the original file with the temporary file
    sudo mv "$input_file.tmp" "$input_file"

    elif [ "$_OPTION" == "mainnet" ]; then


    ## update the .env file 
    ## NODE_NAME=XF_MasterNode
    sudo sed  -i.bak 's|^INSTANCE_NAME.*|INSTANCE_NAME='$VARVAL_NODE_NAME'|g' .env

    # Define the search text

    search_text='    ports:'
    #search_text='    env_file: .env'
    
    # Find the line number containing the search text
    line_number=$(sudo grep -n "$search_text" "$input_file" | cut -d ":" -f 1)
    
        if [ -n "$line_number" ]; then
            # Replace the content starting from the found line
            #sudo sed -i "${line_number}q; ${line_number}n; ${line_number}s|.*|$replacement_text|" "$input_file"
            #sudo sed -i "${line_number}s|.*|$replacement_text|g" "$input_file"
            sudo sed -i "${line_number},\$d" "$input_file"
            sudo cat << EOF | sudo tee -a $input_file
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
        - subnet: "172.19.0.0/24"
EOF
            #echo -e "$replacement_text" >> "$input_file"
            echo
            echo -e "${YELLOW}Replacement successful!${NC}"
            echo
        else
            echo
            echo -e "${YELLOW}Search text not found in the file.${NC}"
            echo
        fi

    fi

    echo -e "${YELLOW}Replacement complete, and a backup has been created as $backup_file.${NC}"


    sudo docker-compose -f docker-compose.yml up -d
    sleep 3s
    echo 
    echo -e "${YELLOW}Starting Xinfin Node ...${NC}"
    sleep 2s
    #FUNC_EXIT
}



FUNC_SETUP_UFW_PORTS(){
    echo 
    echo 
    echo -e "${YELLOW}#########################################################################${NC}" 
    echo 
    echo -e "${YELLOW}## Base Setup: Configure Firewall...${NC}"
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
    echo -e "${YELLOW}## Base Setup: Change UFW logging to ufw.log only${NC}"
    echo 
    # source: https://handyman.dulare.com/ufw-block-messages-in-syslog-how-to-get-rid-of-them/
    sudo sed -i -e 's/\#& stop/\& stop/g' /etc/rsyslog.d/20-ufw.conf
    sudo cat /etc/rsyslog.d/20-ufw.conf | grep '& stop'

    echo 
    echo 
    echo -e "${GREEN}#########################################################################${NC}" 
    echo 
    echo -e "${YELLOW}## Setup: Enable Firewall...${NC}"
    echo 
    sudo systemctl start ufw && sudo systemctl status ufw
    sleep 2s
    echo "y" | sudo ufw enable
    #sudo ufw enable
    sudo ufw status verbose
}



FUNC_CERTBOT(){


    # Install Let's Encrypt Certbot
    sudo apt install certbot python3-certbot-nginx -y

    # Prompt for user domains if not provided as a variable
    if [ -z "$USER_DOMAINS" ]; then
        read -p "Enter a comma-separated list of domains, A record followed by CNAME records for RPC & WSS (e.g., domain1.com,domain2.com): " USER_DOMAINS
    fi

    echo -e "${YELLOW}$USER_DOMAINS${NC}"

    IFS=',' read -ra DOMAINS_ARRAY <<< "$USER_DOMAINS"
    A_RECORD="${DOMAINS_ARRAY[0]}"
    CNAME_RECORD1="${DOMAINS_ARRAY[1]}"
    CNAME_RECORD2="${DOMAINS_ARRAY[2]}" 

    # Start Nginx and enable it to start at boot
    sudo systemctl start nginx
    sudo systemctl enable nginx

    # Request and install a Let's Encrypt SSL/TLS certificate for Nginx
    sudo certbot --nginx  -m "inv4fee2020@gmail.com" -n --agree-tos -d "$USER_DOMAINS"

}


FUNC_NODE_DEPLOY(){
    
    echo -e "${GREEN}#########################################################################${NC}"
    echo -e "${YELLOW}#########################################################################${NC}"
    echo -e "${GREEN}${NC}"
    echo -e "${GREEN}             XinFin ${BYELLOW}$_OPTION${GREEN} RPC/WSS Node - Install${NC}"
    echo -e "${GREEN}${NC}"
    echo -e "${YELLOW}#########################################################################${NC}"
    echo -e "${GREEN}#########################################################################${NC}"
    sleep 3s

    #USER_DOMAINS=""
    source ~/xf_node/xf_node.vars


    # installs default packages listed in vars file
    FUNC_PKG_CHECK;


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


    VARVAL_NODE_NAME="xf_node_$(hostname -s)"
    echo -e "${BYELLOW}  || Node name is : $VARVAL_NODE_NAME ||"
    #VARVAL_CHAIN_RPC=$NGX_RPC
    echo -e "${BYELLOW}  || Node RPC port is : $VARVAL_CHAIN_RPC ||"
    #VARVAL_CHAIN_WSS=$NGX_WSS
    echo -e "${BYELLOW}  || Node WSS port is : $VARVAL_CHAIN_WSS  ||${NC}"
    sleep 3s

    # Install Nginx - Check if NGINX  is installed
    nginx -v 
    if [ $? != 0 ]; then
        echo -e "${RED} ## NGINX is not installed. Installing now.${NC}"
        apt update -y
        sudo apt install nginx -y
    else
        # If NGINX is already installed.. skipping
        echo "NGINX is already installed. Skipping"
    fi


    # Check if UFW (Uncomplicated Firewall) is installed
    sudo ufw version
    if [ $? = 0 ]; then
        # If UFW is installed, allow Nginx through the firewall
        sudo ufw allow 'Nginx Full'
    else
        echo "UFW is not installed. Skipping firewall configuration."
    fi



    # Update the package list and upgrade the system
    #apt update -y
    #apt upgrade -y

    #Docker install
    FUNC_DKR_INSTALL;

    #XinFin Node setup
    FUNC_CLONE_NODE_SETUP;

    FUNC_CERTBOT;

    # Firewall config
    FUNC_SETUP_UFW_PORTS;
    FUNC_ENABLE_UFW;


    # Get the source IP of the current SSH session
    SRC_IP=$(echo $SSH_CONNECTION | awk '{print $1}')
    DCKR_HOST_IP=$(sudo docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $VARVAL_CHAIN_NAME_xinfinnetwork_1)

    # Create a new Nginx configuration file with the user-provided domain and test HTML page


    echo
    echo -e "${GREEN}#########################################################################${NC}"
    echo -e "${YELLOW}## Setup: Creating a new Nginx configuration file ...${NC}"
    echo
     
      # Modify this path if your Nginx config is in a different location
    #sudo mv $NGX_CONF_OLD "$NGX_CONF_OLD.orig"
    sudo touch $NGX_CONF_NEW
    sudo chmod 666 $NGX_CONF_NEW 
    
    sudo cat <<EOF > $NGX_CONF_NEW
server {
    listen 80;
    server_name $A_RECORD $CNAME_RECORD1 $CNAME_RECORD2;
    return 301 https://$server_name$request_uri;
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
        try_files $uri $uri/ =404;
        allow $SRC_IP;  # Allow the source IP of the SSH session
        deny all;
        proxy_pass http://172.19.0.2:$VARVAL_CHAIN_RPC;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
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
        try_files $uri $uri/ =404;
        allow $SRC_IP;  # Allow the source IP of the SSH session
        deny all;
        proxy_pass http://172.19.0.2:$VARVAL_CHAIN_WSS;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;

        # These three are critical to getting XDC node websockets to work
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
    sudo chmod 644 $NGX_CONF_NEW
    sudo ln -s $NGX_CONF_NEW /etc/nginx/sites-enabled/
    sudo rm -f $NGX_CONF_OLD
    # Reload Nginx to apply the new configuration
    sudo systemctl reload nginx

    # Provide some basic instructions

    echo
    echo -e "${GREEN}#########################################################################${NC}"
    echo -e "${YELLOW}## Setup: Created a new Nginx configuration file ...${NC}"
    echo
    echo -e "${YELLOW}##  Nginx is now installed and running with a Let's Encrypt SSL/TLS certificate for the domain $A_RECORD.${NC}"
    echo -e "${YELLOW}##  You can access your secure web server by entering https://$CNAME_RECORD1 of https://$CNAME_RECORD2 in a web browser.${NC}"

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