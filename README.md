# XinFinOrg XDC RPC Node 
Xinfin XDC custom Docker node installation with nginx &amp; lets encrypt TLS certificate.

---

This script will take the standard XDC Docker node install and supplement it with the necessary configuration to provide a TLS secured RPC/WSS endpoint using Nginx.

**Note: If you have an existing node deployed using the standard Docker installation method from [XinFinOrg](https://github.com/XinFinOrg/XinFin-Node#method-2---setup-xinfin-masternode-bootstrap-script) then you must run the script under the same account which you originally installed your node.**



## Current functionality
 - Install options for Mainnet & Testnet
 - Supports the use of custom variables using the `xf_node.vars` file
 - Detects if existing Docker installation & modifies to support Nginx.
 - Detects UFW firewall & applies necessary firewall updates.
 - Installs & configures Nginx 
   - Currently only supports multi-domain deployment with one A record & two CNAME records (requires operator has control over the domain)
   - Automatically detects the ssh session source IP & adds to the config as a permitted source
 - Applies NIST security best practices
 
 ## Planned functionality
  - Add '0x' prefix support
  - Add cron job for lets-encrypt auto renewal
  - Add support for docker upgrades e.g. stashing customisations & re-applying
  - Add support for single domain with sub-folder for RPC & WSS
  - Add support for multiple nginx permitted IPv4 source addresses via the `xf_node.vars` file
  - Add IPv6 support for source address permit lists
  - Improve error detection & handling within the script
  - Add backup features to save out customisations
  - Add backup of Staked Apothem node e.g. wallet keystore etc.

---

## How to download & use

To download the script(s) to your local node & install, read over the following sections and when ready simply copy and paste the code snippets to your terminal window.

### Clone the repo

        cd ~/
        git clone https://github.com/inv4fee2020/xf_node.git
        cd xf_node
        chmod +x *.sh



### Vars file _'xf_node.vars'_

The vars file allows you to manually update the following variables which help to avoid interactive prompts during the install;

- `USER_DOMAINS` - note the order in which the A & CNAME records must be entered.
- `CERT_EMAIL` - email address for certificate renewals etc.

The file also controls some of the packages that are installed on the node. More features will be added over time.

Simply clone down the repo and update the file using your preferred editor such as nano;

        nano ~/xf_node/xf_node.vars


### Usage

The following example will install a `testnet` node

        ./setup.sh testnet

>        Usage: ./setup.sh {function}
>            example:  ./setup.sh testnet
>
>        where {function} is one of the following;
>
>              mainnet       ==  deploys the full Mainnet node with Nginx & Let's Encrypt TLS certificate
>              testnet       ==  deploys the full Apothem node with Nginx & Let's Encrypt TLS certificate
>              logrotate     ==  implements the logrotate config for chain log file(s)"


### Nginx related

It is assumed that the node is being deployed to a dedicated host with no other nginx configuration. The node specfic config is contained in the `NGX_CONF_NEW` variable which is a file named `xinfin`.

As part of the installation, the script adds the ssh session source IPv4 address as a permitted source for accessing reverse proxied services. Operators should update this as necessary with additional source IPv4 addresses as required.

#### Permitted Access - scripted

__tbc__



#### Permitted Access - manual

In order to add/remove source IPv4 addresses from the permit list within the nginx config, you simple access the file with your preferred editor e.g. vim or nano etc.  Each of the server blocks must be updated to reflect your desired access control policy.

Open the file with the 'nano' editor;
`sudo nano /etc/nginx/sites-available/xinfin`

Move the cursor to the server blocks, similar to the following;

        location / {
            try_files  / =404;
            allow 198.51.100.102;  # Allow the source IP of the SSH session
            allow 198.51.100.171;  # Mgmt VPS station
	        deny all;
            proxy_pass http://172.19.0.2:8556;

__ADD__ : Simply add a new line after the last allow (& above the deny all) being sure to enter a valid IPv4 address and end is a semi-colon '*_;_*'

__REMOVE__ : Simple delete the entire line.

Save the file and exit the editor.

For the changes to take effect, you will need to restart the nginx service as follows;

        sudo systemctl restart nginx


---

## Manual updates

To apply repo updates to your local clone, be sure to stash any modifications you may have made to the `xf_node.vars` file & take a manual backup also.

        cd ~/xf_node
        git stash
        cp xf_node.vars ~/xf_node_$(date +'%Y%m%d%H%M%S').vars
        git pull
        git stash apply

---

### contributers: 
A special thanks & shout out to the following community members for their input & testing;
- [@realgo140point6](https://github.com/go140point6)
- [@s4njk4n](https://github.com/s4njk4n)
- @samsam

---

### Feedback
Please provide feedback on any issues encountered or indeed functionality by utilising the relevant Github issues & [xdc.dev](https://www.xdc.dev/inv4fee2020/informative-scripted-linux-install-of-xdc-docker-node-with-nginx-lets-encrypt-4dlf) comments section and I will endeavour to update/integrate where possible.