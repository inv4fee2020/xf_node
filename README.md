# XinFinOrg XDC Node 
Xinfin XDC custom Docker node installation with nginx &amp; lets encrypt TLS certificate

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
  - Add cron job for lets-encrypt auto renewal
  - Add support for docker upgrades e.g. stashing customisations & re-applying
  - Add support for single domain with sub-folder for RPC & WSS
  - Add support for multiple nginx permitted source addresses via the `xf_node.vars` file
  - Improve error detection & handling within the script
  - Add backup features to save out customisations
  - Add backup of Staked Apothem node e.g. wallet keystore etc.
