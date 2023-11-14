# XinFinOrg XDC Node 
Xinfin XDC custom Docker node installation with nginx &amp; lets encrypt TLS certificate

This script will take the standard XDC Docker node install and supplement it with the necessary configuration to provide a TLS secured RPC/WSS endpoint using Nginx.

**Note: If you have an existing node deployed using the standard Docker installation method from [XinFinOrg](https://github.com/XinFinOrg/XinFin-Node#method-2---setup-xinfin-masternode-bootstrap-script) then you must run the script under the same account which you originally installed your node.**

## Current functionality
 - Install options for Mainnet & Testnet
 - Supports the use of custom variables using the _'xf_node.vars'_ file
 - Detects if existing Docker installation & modifies to support Nginx.
 - Detects UFW firewall & applies necessary firewall updates.
 - Installs & configures Nginx 
 