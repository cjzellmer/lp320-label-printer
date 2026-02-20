#!/bin/bash
# Install script for HPRT LP320 thermal label printer on Raspberry Pi
# Requires: CUPS, Ghostscript, pdftoppm (poppler-utils), Python 3, Pillow

set -e

echo "=== LP320 Label Printer Install ==="

# Check dependencies
echo "Checking dependencies..."
for cmd in cups-config gs pdftoppm python3; do
    if ! command -v $cmd &>/dev/null; then
        echo "ERROR: $cmd not found. Install it first."
        echo "  sudo apt install cups ghostscript poppler-utils python3"
        exit 1
    fi
done

python3 -c "from PIL import Image" 2>/dev/null || {
    echo "ERROR: Python Pillow not found. Install it:"
    echo "  sudo pip3 install --break-system-packages Pillow"
    exit 1
}

# Install filter
echo "Installing CUPS filter..."
sudo cp lp320-bar-filter /usr/lib/cups/filter/lp320-bar-filter
sudo chmod 755 /usr/lib/cups/filter/lp320-bar-filter
sudo chown root:root /usr/lib/cups/filter/lp320-bar-filter

# Detect printer USB URI
echo "Looking for LP320 printer..."
USB_URI=$(lpinfo -v 2>/dev/null | grep -i "LP320" | awk '{print $2}')
if [ -z "$USB_URI" ]; then
    echo "WARNING: LP320 not found on USB. Is it plugged in and powered on?"
    echo "Using default URI. You can fix this later in CUPS web interface."
    USB_URI="usb:///LP320%20Printer"
fi
echo "  URI: $USB_URI"

# Install printer with PPD
echo "Configuring CUPS printer..."
sudo lpadmin -p LP320 -E \
    -v "$USB_URI" \
    -P lp320.ppd \
    -o media=w100h150 \
    -o PrintDarkness-default=12 \
    -o PrintSpeed-default=4 \
    -o printer-is-shared=true 2>/dev/null

sudo lpadmin -d LP320 2>/dev/null

# Enable sharing
sudo cupsctl --share-printers 2>/dev/null

echo ""
echo "=== Done ==="
echo "Printer LP320 installed and shared on the network."
echo "Default: 4x6 labels, darkness 12, speed 4"
echo ""
echo "On Macs: Add printer via System Settings > Printers & Scanners"
echo "IMPORTANT: Make sure 'Use' is set to AirPrint, NOT Generic PostScript Printer"
