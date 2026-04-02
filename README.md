# LP320 Thermal Label Printer — Linux/Raspberry Pi Driver

A CUPS driver for the HPRT LP320 (and LabelRange LP320) thermal label printer on Linux/Raspberry Pi. Turns your Pi into a network print server for 4x6 shipping labels — print from any Mac, PC, or device on your network.

## The Problem

The HPRT LP320 is a budget 4x6 thermal label printer popular for shipping labels (FedEx, UPS, USPS, Pirate Ship, etc.). HPRT provides no Linux or ARM driver. The existing community TSPL CUPS driver uses `BITMAP` commands which **do not work** on the LP320 because it uses a USB-to-parallel bridge chip (ICS Advent `0fe6:811e`) that corrupts binary data.

## The Solution

This driver bypasses the broken `BITMAP` command entirely. Instead it:

1. Receives PDF or PostScript input from CUPS (works with any client driver)
2. Rasterizes to a monochrome image at 203 DPI using `pdftoppm` (PDF) or Ghostscript (PostScript)
3. Auto-crops whitespace margins from the source
4. Adds 1/8" margins on all sides to prevent edge clipping
5. Scans each row for contiguous runs of black pixels
6. Merges runs vertically into rectangles for efficiency
7. Emits pure ASCII `BAR` commands (no binary data = no corruption through the USB bridge)
8. Wraps in TSPL header with configurable size, speed, and darkness

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
- Configure the CUPS printer with sensible defaults (4x6 labels, darkness 13, speed 3)
- Enable network sharing so other devices can discover it

## Adding the Printer on macOS

1. **System Settings → Printers & Scanners → Add Printer, Scanner, or Fax...**
2. If LP320 appears in the Default/Bonjour list, select it. Otherwise click the **IP** tab and enter:
   - **Protocol:** IPP
   - **Address:** `raspberrypi.local` (or your Pi's IP)
   - **Queue:** `printers/LP320`
3. For the **"Use"** dropdown, any of these will work:
   - **Secure AirPrint** or **AirPrint** — best option if available, sends PDF directly
   - **Auto Select** — queries the Pi and picks automatically (may resolve to Generic PostScript Printer, which is fine)
   - **Generic PostScript Printer** — works correctly; the Pi's filter handles the PostScript-to-label conversion server-side
4. Click **Add**

Then just Cmd+P from any app and select LP320.

> **Note:** All print processing happens on the Pi, not the Mac. The Mac just sends the document over the network. It doesn't matter which driver the Mac selects — the Pi's filter accepts PDF, PostScript, and images and converts them all to label output correctly.

## Adding the Printer on Windows

1. **Settings → Bluetooth & devices → Printers & scanners → Add device**
2. If LP320 doesn't appear automatically, click **Add manually** and select **Add a printer using an IP address or hostname**
3. Enter:
   - **Device type:** IPP
   - **Hostname or IP:** `http://raspberrypi.local:631/printers/LP320`
4. For driver, select **Microsoft IPP Class Driver**
5. Click **Next** to finish

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

### Print Darkness (Heat)

Controls how much heat the print head applies. Higher = darker/bolder, but too high will overcook the label. Range: 5–15. Default: 13.

```bash
lpadmin -p LP320 -o PrintDarkness-default=13
```

### Print Speed

How fast the label feeds through the print head, in inches per second. Slower = more contact time = darker output. Faster = lighter but quicker. Range: 2–6 in/sec. Default: 3.

```bash
lpadmin -p LP320 -o PrintSpeed-default=3
```

> **Tip:** Speed and darkness work together. If labels are too light, try lowering speed before increasing darkness — you get better results with less heat.

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
PDF or PostScript (from Mac/PC/phone)
  → pdftoppm or Ghostscript (rasterize to grayscale at 203 DPI)
  → Pillow (auto-crop whitespace, scale to fit label with 1/8" margins, threshold to monochrome)
  → BAR command generator (horizontal run detection + vertical merging)
  → TSPL output (SIZE, GAP, SPEED, DENSITY, DIRECTION, CLS, BAR..., PRINT)
  → USB bridge → printer
```

The filter handles PDF (via `pdftoppm`), PostScript (via Ghostscript), and image files (PNG, JPEG, etc.) directly. PostScript input — including from macOS "Generic PostScript Printer" driver — is rasterized at the document's native page size and then auto-cropped and scaled to the label, so it produces correct output regardless of the source page size.

## Troubleshooting

**"Filter failed" error in CUPS:** Check `/tmp/lp320-filter.log` for details. If the log is empty, the filter may have crashed before starting — run `sudo cupsenable LP320` to clear the error and retry.

**Blank labels / form feed only:** The printer is receiving raw data with no TSPL translation. Make sure the filter is installed and the printer is configured with the PPD (not as a "Raw" printer).

**Labels too light:** Lower the speed first (`PrintSpeed-default=2`), then increase darkness if still needed (`PrintDarkness-default=14`).

**Labels too dark / all black:** Decrease darkness: `lpadmin -p LP320 -o PrintDarkness-default=8`

**Printer not found on network from Mac:** Make sure CUPS sharing and Avahi are enabled:
```bash
sudo cupsctl --share-printers
sudo systemctl enable --now avahi-daemon
```
If the printer still doesn't appear, add it manually via the IP tab (see macOS instructions above).

**Mac shows wrong driver options:** It doesn't matter. The Pi handles all conversion server-side. Whether the Mac selects AirPrint, Auto Select, or Generic PostScript Printer, the output will be the same.

## Files

| File | Description |
|------|-------------|
| `lp320-bar-filter` | Python CUPS filter — converts PDF/PS/images to TSPL BAR commands |
| `lp320.ppd` | PPD file — printer capabilities, page sizes, options |
| `install.sh` | One-command installer |

## License

MIT
