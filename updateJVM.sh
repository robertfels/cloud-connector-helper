#!/bin/bash

# URL and basic information
URL="https://tools.hana.ondemand.com/#cloud"
DOWNLOAD_BASE_URL="https://tools.hana.ondemand.com/additional"

# Determine the currently installed version
INSTALLED_PACKAGE=$(rpm -qa | grep "sapjvm")
CURRENT_VERSION=$(echo "$INSTALLED_PACKAGE" | sed 's/sapjvm-\([^-]*\)-\([^-]*\).*/\1.\2/')

#echo "Currently installed version: $CURRENT_VERSION"

# Dynamically determine the new version
NEW_VERSION=$(curl -s "$URL" | grep -oP "sapjvm-\K[0-9.]+(?=-linux-x64.zip)" | sort -V | tail -n1)

# Check if a new version is available
if [ "$NEW_VERSION" = "$CURRENT_VERSION" ]; then
    echo "The latest version is already installed: $CURRENT_VERSION"
    exit 0
fi

#echo "New version available: $NEW_VERSION"

# Extract EULA information
EULA_COOKIE_NAME=$(curl -s "$URL" | grep -oP "eulaConst.devLicense.cookieName = '\K[^']+" )
EULA_COOKIE_VALUE=$(curl -s "$URL" | grep -oP "eulaConst.devLicense.cookieValue = '\K[^']+" )

if [ -z "$EULA_COOKIE_VALUE" ]; then
    echo "Failed to extract EULA cookie value."
    exit 1
fi

EULA_URL="https://$EULA_COOKIE_VALUE"

echo "Please read the EULA at: $EULA_URL"
read -p "Do you accept the EULA? (y/N) " ACCEPT_EULA

if [ "${ACCEPT_EULA,,}" != "y" ]; then
    echo "You did not accept the EULA. Update aborted."
    exit 1
fi

# Confirm update installation
echo "An update from version $CURRENT_VERSION to $NEW_VERSION is available."
read -p "Do you want to proceed with the update? (y/N) " PROCEED_UPDATE

if [ "${PROCEED_UPDATE,,}" != "y" ]; then
    echo "Update aborted by the user."
    exit 1
fi

# Download URLs
DOWNLOAD_URL="$DOWNLOAD_BASE_URL/sapjvm-$NEW_VERSION-linux-x64.rpm"
SHA1_URL="$DOWNLOAD_URL.sha1"

cleanup() {
    echo "Cleaning up temporary files..."
    cd ..
    rm -rf sapcc_update
}

# Preparations for the update
mkdir -p sapcc_update && cd sapcc_update || { echo "Failed to create/update directory."; exit 1; }

# Download the new SAP JVM version and SHA1 hash using simple progress meter
echo "Downloading the new SAP JVM version..."
if ! curl -# -b "$EULA_COOKIE_NAME=$EULA_COOKIE_VALUE" -O "$DOWNLOAD_URL"; then
    echo "Failed to download the SAP JVM version."
    cleanup
    exit 1
fi

echo "Downloading SHA1 hash..."
if ! curl -# -b "$EULA_COOKIE_NAME=$EULA_COOKIE_VALUE" -O "$SHA1_URL"; then
    echo "Failed to download the SHA1 hash."
    cleanup
    exit 1
fi

FILENAME="sapjvm-$NEW_VERSION-linux-x64.rpm"
SHA1_FILENAME="$FILENAME.sha1"

# Verify the SHA1 hash
echo "Verifying the SHA1 hash..."
SHA1SUM_EXPECTED=$(cat "$SHA1_FILENAME")
SHA1SUM_ACTUAL=$(sha1sum "$FILENAME" | awk '{print $1}')

if [ "$SHA1SUM_EXPECTED" != "$SHA1SUM_ACTUAL" ]; then
    echo "Hash verification failed. Update aborted."
    cleanup
    exit 1
fi

echo "Hash verification successful."

# Unpack the downloaded update package
#unzip "$FILENAME"

RPM_PACKAGE=$FILENAME

# Update the SAP JVM
echo "Updating the SAP JVM..."
if ! sudo rpm -U "$RPM_PACKAGE"; then
    echo "Update failed."
    cleanup
    exit 1
fi

# Cleanup: Delete downloaded and unpacked files
cleanup

echo "Update completed."