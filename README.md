## Node Control Thruk Plugin

This plugin allows you to control nodes (OMD / OS) from within Thruk.

## Features

  - OMD installation
  - OMD site updates
  - OMD cleanup old unused versions
  - OMD services start/stop
  - OS Updates

## Installation

This plugin requires OMD (https://labs.consol.de/omd/).
All steps have to be done as site user:

    %> cd etc/thruk/plugins-enabled/
    %> git clone https://github.com/sni/thruk-plugin-node-control.git node-control
    %> omd reload apache

You now have a new menu item under System -> Node Control.

## Setup

The controlled sites need to have sudo permissions for omd and their package
manager.

 - Debian: `siteuser  ALL=(ALL) NOPASSWD: /usr/bin/omd, NOPASSWD: /usr/bin/apt-get`
 - Centos: `siteuser  ALL=(ALL) NOPASSWD: /usr/bin/omd, NOPASSWD: /usr/bin/dnf`

(replace siteuser with the actual site user name)

Optional ssh login helps starting services if http connection does not work, for
ex. because the site is stopped.
