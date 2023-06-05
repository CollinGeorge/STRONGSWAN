# STRONGSWAN
Script to create an encrypted communications channel using Strong Swan.

VPN Server Setup Script

This is a script written in Bash that automates the setup of a VPN (Virtual Private Network) server using the strongSwan software on a Linux machine. It simplifies the process of installing the necessary packages, configuring security settings, generating certificates and keys, and setting up the firewall.

Encryption and Security

The script focuses on providing strong encryption and security for the VPN connections. It uses the following encryption algorithms and key lengths:

Encryption Algorithms: The user can choose from aes128, aes192, aes256, des, or gcm. AES (Advanced Encryption Standard) is a widely used symmetric encryption algorithm, while DES (Data Encryption Standard) is an older encryption algorithm. GCM (Galois/Counter Mode) is an authenticated encryption mode that provides additional security features.

Key Length: The script supports key lengths of 128, 192, or 256 bits for symmetric encryption algorithms. The longer the key length, the stronger the encryption.

The script also configures the SSH daemon to use a non-standard port for added security and installs fail2ban, which protects against brute-force attacks on the server.

Usage

To use this script, follow these steps:

Clone the repository or download the script file to your Linux machine.
Open a terminal and navigate to the directory where the script is located.
Make the script executable by running the following command:
bash
Copy code
'''chmod +x vpn_setup.sh'''
Run the script as the root user by executing the following command:

<pre>
bash
#!/usr/bin/env bash

set -e

bash
sudo ./vpn_setup.sh
</pre>

Note: Running the script as the root user is required because it needs administrative privileges to install packages and modify system configurations.

Follow the prompts and provide the necessary information when prompted. The script will guide you through the configuration process, such as entering the parameters for the certificate authority (CA), setting a passphrase for the client key, choosing encryption algorithms and key lengths, and customizing DNS settings.

Once the script finishes running, the VPN server should be set up and ready to use. The generated client certificate and key will be available in the specified directory (/etc/ipsec.d/private by default).

To connect to the VPN server, use a VPN client software that supports IKEv2 protocol and import the client certificate and key. The server's public IP address and the configured encryption algorithm and key length should be provided when configuring the client.
Firewall Configuration

The script uses UFW (Uncomplicated Firewall) to configure the firewall rules. By default, the script allows SSH connections, as well as IPsec ports 500 and 4500 for VPN connections. All other incoming traffic is blocked, providing an additional layer of security.

License

This script is licensed under the MIT License. Feel free to modify and distribute it as needed.

Disclaimer: Use this script at your own risk. Make sure to review and understand the code before running it on your system. The script modifies system configurations and installs packages, which may have an impact on the stability and security of your system.
