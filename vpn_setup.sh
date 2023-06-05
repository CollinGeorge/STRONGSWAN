#!/usr/bin/env bash

set -e

# Check if the script is being run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script needs to be run as root to install necessary packages and configure the VPN."
   exit 1
fi

# Install necessary packages if not already installed
if ! dpkg -s strongswan openssl libstrongswan-gcm >/dev/null 2>&1; then
  echo "This script requires strongSwan, OpenSSL, and libstrongswan-gcm packages to be installed. Installing packages now..."
  apt-get update && apt-get -y install strongswan openssl libstrongswan-gcm
  if [ $? -ne 0 ]; then
    echo "Failed to install packages. Aborting."
    exit 1
  fi
fi

# Configure SSH daemon for added security
echo "Configuring SSH daemon..."
sed -i 's/#Port 22/Port 22022/g' /etc/ssh/sshd_config
/etc/ssh/sshd_config
systemctl reload sshd

# Install fail2ban to protect against brute-force attacks
echo "Installing fail2ban..."
apt-get -y install fail2ban
systemctl enable fail2ban

# Find the user's public IP address
echo "Finding your public IP address..."
USER_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)
echo "Your public IP address is $USER_IP."

# Set up variables for certificate authority
DEFAULT_CA_NAME="MyVPN CA"
DEFAULT_CA_STATE="CA"
DEFAULT_CA_CITY="San Francisco"
DEFAULT_CA_ORG="MyVPN"
DEFAULT_CA_UNIT="CA"
DEFAULT_CA_FQDN="myvpn-ca.example.com"

# Prompt the user to enter parameters for certificate authority
read -p "Enter a name for the certificate authority (default: $DEFAULT_CA_NAME): " CA_NAME
CA_NAME=${CA_NAME:-$DEFAULT_CA_NAME}

read -p "Enter a two-letter abbreviation for the state or province where your organization is located (default: $DEFAULT_CA_STATE): " CA_STATE
CA_STATE=${CA_STATE:-$DEFAULT_CA_STATE}

read -p "Enter the name of the city where your organization is located (default: $DEFAULT_CA_CITY): " CA_CITY
CA_CITY=${CA_CITY:-$DEFAULT_CA_CITY}

read -p "Enter the name of your organization (default: $DEFAULT_CA_ORG): " CA_ORG
CA_ORG=${CA_ORG:-$DEFAULT_CA_ORG}

read -p "Enter the name of your organizational unit (default: $DEFAULT_CA_UNIT): " CA_UNIT
CA_UNIT=${CA_UNIT:-$DEFAULT_CA_UNIT}

read -p "Enter the fully qualified domain name (FQDN) of the CA (default: $DEFAULT_CA_FQDN): " CA_FQDN
CA_FQDN=${CA_FQDN:-$DEFAULT_CA_FQDN}

# Find VPN subnet
VPN_SUBNET=$(ip route | awk '/default via/ {print $(NF-1)}')

# Create certificate authority if not already created
CA_SUBJECT="/C=US/ST=$CA_STATE/L=$CA_CITY/O=$CA_ORG/OU=$CA_UNIT/CN=$CA_FQDN"
CA_KEY="/etc/ipsec.d/private/ca.key"
CA_CERT="/etc/ipsec.d/certs/ca.crt"

if [ ! -f "$CA_KEY" ] || [ ! -f "$CA_CERT" ]; then
  openssl req -new -x509 -days 3650 -nodes -subj "$CA_SUBJECT" -keyout "$CA_KEY" -out "$CA_CERT" -batch
fi

# Enable strong encryption and hashing for VPN connection
sed -i 's/^\(auth_sha1_v4=\).*/\1strong/' /etc/strongswan.d/charon/dh.conf
sed -i 's/^\(ike=aes256-sha1-modp1024\)/#\1/' /etc/strongswan.d/charon/ike.conf
sed -i 's/^\(ike=aes256-sha384-modp2048\)/#\1/' /etc/strongswan.d/charon/ike.conf
sed -i 's/^\(ike=aes256gcm16-sha384-modp2048\)/#\1/' /etc/strongswan.d/charon/ike.conf
sed -i 's/^\(esp=aes256-sha1\)/#\1/' /etc/strongswan.d/charon/esp.conf
sed -i 's/^\(esp=aes256-sha256\)/#\1/' /etc/strongswan.d/charon/esp.conf
sed -i 's/^\(esp=aes256gcm16\)/#\1/' /etc/strongswan.d/charon/esp.conf
sed -i 's/^\(dh_group=modp1024\)/#\1/' /etc/strongswan.d/charon/defaults.conf
sed -i 's/^\(dh_group=modp2048\)/\1/' /etc/strongswan.d/charon/defaults.conf
systemctl restart strongswan.service

# Prompt the user to enter a passphrase for the client key
read -r -s -p "Enter a passphrase for the client key: " PASSPHRASE
printf "\n"

# Set client directory
CLIENT_DIR="/etc/ipsec.d/private"

# Prompt the user for client name
read -r -p "Enter client name: " CLIENT_NAME

# Check if the client key and certificate already exist
if [ -f "$CLIENT_DIR/$CLIENT_NAME.key" ] && [ -f "$CLIENT_DIR/$CLIENT_NAME.crt" ]; then
  printf "Client key and certificate already exist for %s.\n" "$CLIENT_NAME"
  read -r -p "Do you want to overwrite the existing key and certificate? [y/N] " OVERWRITE
  case "$OVERWRITE" in
    [yY][eE][sS]|[yY])
      # Proceed with overwriting existing key and certificate
      ;;
    *)
      # Exit script if user does not confirm overwrite
      printf "Exiting without generating client key and certificate.\n"
      exit 0
      ;;
  esac
fi

# Select an encryption algorithm and key length
echo "Select an encryption algorithm:"
select ENCRYPTION_ALGORITHM in "aes128" "aes192" "aes256" "des" "gcm"; do
  case $ENCRYPTION_ALGORITHM in
    aes128|aes192|aes256|des|gcm)
      break
      ;;
    *)
      echo "Invalid choice. Please try again."
      ;;
  esac
done

if [ "$ENCRYPTION_ALGORITHM" == "gcm" ]; then
  echo "Select a key length:"
  select KEY_LENGTH in "128" "192" "256"; do
    case $KEY_LENGTH in
      128|192|256)
        break
        ;;
      *)
        echo "Invalid choice. Please try again."
        ;;
    esac
  done
else
  KEY_LENGTH="256"
fi

# Generate the client key and CSR
echo "Generating client key and CSR for $CLIENT_NAME..."
umask 077
ipsec pki --gen --type rsa --size 4096 --outform pem > "$CLIENT_DIR/$CLIENT_NAME.key"
chmod 400 "$CLIENT_DIR/$CLIENT_NAME.key"
ipsec pki --req --in "$CLIENT_DIR/$CLIENT_NAME.key" --type rsa --dn "C=US, O=VPN Server, CN=$CLIENT_NAME" --outform pem > "$CLIENT_DIR/$CLIENT_NAME.csr"

# Sign the client CSR with the CA
echo "Signing client CSR for $CLIENT_NAME..."
ipsec pki --issue --in "$CLIENT_DIR/$CLIENT_NAME.csr" --type rsa --cacert "$CA_CERT" --cakey "$CA_KEY" --digest sha256 --outform pem > "$CLIENT_DIR/$CLIENT_NAME.crt"

# Encrypt the client key with a passphrase
echo "Encrypting client key with passphrase..."
openssl rsa -aes256 -in "$CLIENT_DIR/$CLIENT_NAME.key" -out "$CLIENT_DIR/$CLIENT_NAME.key.enc" -passout "pass:$PASSPHRASE"
mv "$CLIENT_DIR/$CLIENT_NAME.key.enc" "$CLIENT_DIR/$CLIENT_NAME.key"

echo "Client certificate and key for $CLIENT_NAME generated successfully."

# Prompt for custom DNS
read -p "Enter primary DNS (default: 8.8.8.8): " DNS1
DNS1=${DNS1:-"8.8.8.8"}
read -p "Enter secondary DNS (default: 8.8.4.4): " DNS2
DNS2=${DNS2:-"8.8.4.4"}

# Configure IPsec with DH key exchange
cat << EOF > /etc/ipsec.conf
config setup
  charondebug="ike 2, knl 2, cfg 2"
  uniqueids=yes
  strictcrlpolicy=no
  # Enable DH key exchange with 2048-bit key length or more
  dh-params=/etc/ipsec.d/private/dhparams.pem

conn %default
  ikelifetime=60m
  keylife=20m
  rekeymargin=3m
  keyingtries=1
  # Use DH key exchange
  keyexchange=ikev2
  left=%any
  leftsubnet=$VPN_SUBNET
  leftauth=pubkey
  leftcert=server.crt
  leftid=@myvpn.example.com
  right=%any
  rightsubnet=$VPN_SUBNET
  rightauth=pubkey
  # Use DH key exchange
  rightdh=%same
  auto=add

conn myvpn
  leftfirewall=yes
  leftsourceip=%config
  leftcert=$CLIENT_CERT
  leftid=$CLIENT_SUBJECT
  rightauth=pubkey
  rightcert=$CA_CERT
  rightid=@myvpn.example.com
  # Use DH key exchange
  rightdh=%same
  auto=start
EOF

# Generate DH parameters with 2048-bit key length or more
if [ ! -f /etc/ipsec.d/private/dhparams.pem ]; then
  echo "Generating DH parameters with 2048-bit key length or more..."
  mkdir -p /etc/ipsec.d/private
  openssl dhparam -out /etc/ipsec.d/private/dhparams.pem 2048
  chmod 600 /etc/ipsec.d/private/dhparams.pem
  echo "DH parameters generated."
fi

# Configure strongSwan
cat << EOF > /etc/strongswan.conf
charon {
  load_modular = yes
  plugins {
    include strongswan.d/charon/*.conf
  }
  # Use custom DNS
  dns1 = $DNS1
  dns2 = $DNS2
}
EOF

# Configure Firewall
if ! command -v ufw >/dev/null 2>&1; then
  echo "UFW is not installed. Installing now..."
  apt-get update && apt-get -y install ufw
  echo "UFW installed."
fi

# Enable firewall and configure rules
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 500,4500/udp
ufw allow in on lo
ufw enable

echo "Firewall rules configured."

# Restart services
systemctl restart strongswan
systemctl restart ufw