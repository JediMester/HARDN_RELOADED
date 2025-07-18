
## IMPORTANT NOTE
This is a fork of the original project: https://github.com/subhaniminhas/HARDN1.0
<br>
Huge kudos for Tim Burns and Christopher Bingham for their amazing and invaluable work, and also for Razvan Alexandru Ionica for spreading the word around! :) <3
Please, make sure to check it out ;)
<br>

## HARDN_RELOADED
**The goal and purpose**:
<br>
Beside all the great security features the original project has to offer, the aim is to make the tool available to a wide range of distros - with that a broader range of audience.
I would like to make sure that the tool works on as many Linux systems as possible in a modularised way, distinguishing desktops from servers/VMs and providing tailored solutions for both worlds.
<br>
**It provides** (as stated in the original project's README):
  - A robust and secure endpoint management solution designed to simplify and enhance the management of devices in your network. 
  - Advanced features for monitoring, securing, and maintaining endpoints efficiently.
  - `STIG` COMPLIANCE to align with the [Security Technical Information Guides](https://public.cyber.mil/stigs/) provided by the [DOD Cyber Exchange](https://public.cyber.mil/).

<br>
**Main features**:
(as stated in the original project's README)

**Comprehensive Monitoring**: Real-time insights into endpoint performance and activity.
**Enhanced Security**: Protect endpoints with advanced security protocols.
**Scalability**: Manage endpoints across small to large-scale networks.
**User-Friendly Interface**: Intuitive design for seamless navigation and management.
**STIG Compliance**: This release brings the utmost security for Debian Government based information systems. 


### Installation

1.  **One command**

    ```bash
    curl -LO https://raw.githubusercontent.com/opensource-for-freedom/HARDN-XDR/refs/heads/main/install.sh && sudo chmod +x install.sh && sudo ./install.sh
    ```

<br>

### Installation Notes
- HARDN-XDR is currently being developed and tested for **BARE-METAL installs of Debian based distributions and Virtual Machines**.
- Ensure you have the latest version of **Debian 12**.
- By installing HARDN-XDR with the command listed in the installation, the following changes will be made to your system:
> - A collection of security focused packages will be installed.
> - Security tools and services will be enabled.
> - System hardening and STIG settings will be applied.
> - A malware and signature detection and response system will be set up.
> - A monitoring and reporting system will be activated. 
- For a detailed list of all that will be changed, please refer to [HARDN.md](docs/HARDN.md).
- For an overview of HARDN-Debian STIG Compliance, please refer to [deb_stig.md](docs/deb_stig.md).



<br>


## Actions
- [![Auto Update Dependencies](https://github.com/OpenSource-For-Freedom/HARDN-XDR/actions/workflows/validate.yml/badge.svg)](https://github.com/OpenSource-For-Freedom/HARDN-XDR/actions/workflows/validate.yml)
<br>

## File Structure


```bash
HARDN-XDR/
├── changelog.md                 
├── docs                         
│   ├── assets                   
│   │   ├── cybersynapse.png     
│   │   └── HARDN(1).png         
│   ├── CODE_OF_CONDUCT.md       
│   ├── deb_stig.md              
│   ├── hardn-main-sh-review.md  
│   ├── HARDN.md                 
│   ├── hardn-security-tools.md  
│   └── TODO.md                  
├── install.sh                  
├── LICENSE                      
├── progs.csv                    
├── README.md                    
└── src                          
    └── setup                    
        ├── hardn-main.sh        
           
```



<br>

**Partner of the original project:**
office@cybersynapse.ro

<br>

This project is licensed under the MIT License.




