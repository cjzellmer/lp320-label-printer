# LP320 Thermal Label Printer — Linux/Raspberry Pi Driver

A CUPS driver for the HPRT LP320 (and LabelRange LP320) thermal label printer on Linux/Raspberry Pi. Turns your Pi into a network print server for 4x6 shipping labels — print from any Mac, PC, or device on your network.

## The Problem

The HPRT LP320 is a budget 4x6 thermal label printer popular for shipping labels (FedEx, UPS, USPS, Pirate Ship, etc.). HPRT provides no Linux or ARM driver. The existing community TSPL CUPS driver uses `BITMAP` commands which **do not work** on the LP320 because it uses a USB-to-parallel bridge chip (ICS Advent `0fe6:811e`) that corrupts binary data.

## The Solution

This driver bypasses the broken `BITMAP` command entirely. Instead it:

1. Receives PDF input from CUPS
2. Rasterizes to a monochrome image at 203 DPI using `pdftoppm`
3. Auto-crops whitespace margins from the source
4. Scans each row for contiguous runs of black pixels
5. Merges runs vertically into rectangles for efficiency
6. Emits pure ASCII `BAR` commands (no binary data = no corruption through the USB bridge)
7. Wraps in TSPL header with configurable size, speed, and darkness

A typical 4x6 shipping label produces ~5,000 BAR commands (~95KB) and prints in a few seconds.

## Compatibility

**Printers:** HPRT LP320, LabelRange LP320, and likely other budget TSPL printers with USB-to-parallel bridges (check `lsusb` for vendor `0fe6`).

**Platforms:** Tested on Raspberry Pi 5 (aarch64, Debian Bookworm). Should work on any Linux with CUPS, Python 3, Pillow, Ghostscript, and poppler-utils.

**Clients:** Any device that can print to a network printer — macOS, Windows, Linux, iOS (AirPrint), Android.

## Prerequisites

```bash
sudo apt install cups ghostscript poppler-utils python3
sudo pip3 install --break-system-packages Pillow
```

## Install

```bash
git clone https://github.com/cjzellmer/lp320-label-printer.git
cd lp320-label-printer
./install.sh
```

The install script will:
- Copy the filter to `/usr/lib/cups/filter/`
- Auto-detect the printer's USB URI
- Configure the CUPS printer with sensible defaults (4x6 labels, darkness 12)
- Enable network sharing so other devices can discover it

## Adding the Printer on macOS

1. **System Settings → Printers & Scanners → Add Printer**
2. Select **LP320** from the network/Bonjour list
3. **Important:** Make sure the **"Use"** dropdown says **AirPrint** — do NOT select "Generic PostScript Printer" (this causes the Mac to convert PDFs to PostScript which produces garbled output)
4. Click **Add**

Then just Cmd+P from any app and select LP320.

## Configuration

### Label Size

Default is 4x6 (101.6mm x 152.4mm). Available sizes can be changed in the CUPS web interface at `http://your-pi-ip:631` or via command line:

```bash
# 4x6 (default)
lpadmin -p LP320 -o media=w100h150

# 4x4
lpadmin -p LP320 -o media=w100h100

# 4x3
lpadmin -p LP320 -o media=w100h75
```

### Print Darkness

Range: 5–15. Default: 12.

```bash
lpadmin -p LP320 -o PrintDarkness-default=12
```

### Print Speed

Range: 2–6 in/sec. Default: 4.

```bash
lpadmin -p LP320 -o PrintSpeed-default=4
```

## How It Works

The LP320 speaks TSPL (Taiwan Semiconductor Printer Language), a command set for thermal label printers. Most TSPL drivers send raster images using the `BITMAP` command, which embeds raw binary pixel data inline with the command stream.

The LP320's USB interface is not a native USB controller — it's an **ICS Advent USB-to-parallel bridge chip** (`0fe6:811e`) soldered onto the printer board. This bridge was designed for text-mode parallel printing and **corrupts arbitrary binary data** passing through it.

The `BAR` command, however, is pure ASCII text:
```
BAR x,y,width,height
```

This driver converts the entire label image into `BAR` commands — one per rectangular black region. Adjacent identical pixel runs are merged vertically to minimize the number of commands. The result is a pure ASCII TSPL stream that passes through the USB bridge without corruption.

### Filter Pipeline

```
PDF (from Mac/PC)
  → pdftoppm (rasterize to grayscale at 203 DPI)
  → Pillow (auto-crop margins, threshold to monochrome)
  → BAR command generator (horizontal run detection + vertical merging)
  → TSPL output (SIZE, GAP, SPEED, DENSITY, DIRECTION, CLS, BAR..., PRINT)
  → USB bridge → printer
```

PostScript input (from some CUPS configurations) is handled via direct Ghostscript rasterization.

## Troubleshooting

**Blank labels / form feed only:** The printer is receiving raw data with no TSPL translation. Make sure the filter is installed and the printer is configured with the PPD (not as a "Raw" printer).

**Garbled / skewed output from one Mac but not another:** Check the "Use" setting in Printers & Scanners. If it says "Generic PostScript Printer", the Mac is converting to PostScript before sending. Change to AirPrint.

**Labels too light:** Increase darkness: `lpadmin -p LP320 -o PrintDarkness-default=14`

**Labels too dark / all black:** Decrease darkness: `lpadmin -p LP320 -o PrintDarkness-default=8`

**Margins / wasted space on labels:** The filter auto-crops whitespace. If you're still seeing margins, the source PDF might have content (like a white border with a thin outline) that prevents cropping.

**Printer not found on network:** Make sure CUPS sharing and Avahi are enabled:
```bash
sudo cupsctl --share-printers
sudo systemctl enable --now avahi-daemon
```

## Files

| File | Description |
|------|-------------|
| `lp320-bar-filter` | Python CUPS filter — converts PDF/PS/images to TSPL BAR commands |
| `lp320.ppd` | PPD file — printer capabilities, page sizes, options |
| `install.sh` | One-command installer |

## License

MIT
