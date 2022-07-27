## Node Control Thruk Plugin

This plugin allows you to control nodes (OMD / OS) from within Thruk.

## Installation

This plugin requires OMD (https://labs.consol.de/omd/).
All steps have to be done as site user:

    %> cd etc/thruk/plugins-enabled/
    %> git clone https://github.com/sni/thruk-plugin-node-control.git node-control
    %> omd reload apache

You now have a new menu item under System -> Node Control.

