# LRExportHEIC

A plugin to allow Lightroom to export HEIC files.

Adopted from https://github.com/milch/LRExportHEIC

There are two components:

- The CLI component, which can convert a single input file or batch-convert a directory of `.avif` files into `.heic`. It is written in Swift.
- The plugin itself, which is the component that interfaces with Lightroom using the Lightroom SDK, written in Lua.

## Compatibility

Because the CLI component is using macOS APIs to create the HEIC file, the only supported platform is macOS. Theoretically there should be nothing preventing it from working on earlier versions, but I have only personally tested it on macOS Monterey (v12+). It definitely won't work on Windows.

Tested on AVIF files exported by Lightroom (Cloud based).

## Usage

### CLI usage

```bash
Usage: LRExportHEIC <output-file> [--input-file] [--input-dir] [--quality] [--size-limit] [--min-quality] [--max-quality] [--color-space] [--jobs] [--verbose]

Export input image file as HEIC, or batch convert .avif files in a directory

Options:
   input-file Path to input image file
    input-dir Root directory to scan for .avif files (recursively). Output is written next to inputs
      quality Compression quality between 0.0-1.0 (default: 0.8). Cannot be used with --size-limit
   size-limit Limit the size in bytes of the resulting image file, instead of specifying a quality directly. Cannot be used with --quality
  min-quality Minimal allowed compression quality, between 0.0-1.0, if --size-limit is used. Default: 0.0
  max-quality Maximal allowed compression quality, between 0.0-1.0, if --size-limit is used. Default: 1.0
  color-space Name of the output color space. Omit to use input image color space
         jobs Number of files to process in parallel when using --input-dir. Default: performance core count
```

#### Examples
- Single file:

  ```bash
  LRExportHEIC --input-file /path/in.avif /path/out.heic
  ```

- Batch convert a directory (recursively):

  ```bash
  LRExportHEIC --input-dir /path/to/folder
  ```

#### Notes:
- Batch mode writes `.heic` next to each input file and overwrites existing outputs.
- You can specify either `--quality` or `--size-limit` (they are mutually exclusive).
- If neither is provided, the CLI defaults to `--quality 0.8` for both single-file and batch mode.
- If `--jobs` is not provided, batch mode defaults to the number of performance cores (or physical cores when that information isn't available).
- Metadata (EXIF/XMP/etc.) is preserved by default.

### Plugin usage

This plugin is using Lightroom's SDK in a way that was probably not intended, so it may not work for your setup. It may mess up your files, corrupt your library, and kick your dog in the process. Proceed with caution, and always make sure you have a backup.

#### Installation

- Download the [latest release](https://github.com/milch/LRExportHEIC/releases/latest) from the sidebar
- Open Lightroom, and open the Plug-In Manager from the Menu
- Press the `add` button, and select the plugin wherever you saved it. Make sure that it is enabled.

#### Exporting HEIC files

- Select images and start the export like normal (e.g. Right click + Export)
- You will see a new "Post-Process Action" in the lower left corner of the export dialog, which you will need to highlight and then press `Insert` 
- You will see a new panel named "HEIC settings" at the bottom. Note that the regular File Settings panel is unused at this point, and settings made in that panel will be overridden by any setting you choose in the "HEIC settings" panel
- Press `Export`. Your export should proceed like normal, and you will find your files at the location you selected
- The files will have a `.jpg` extension. This is expected. You can rename them to use a `.heic` extension or leave them with the `.jpg` extension. Most applications won't care about the extension, and will be able to use the file like normal. 

The plugin also adds a new item under "Export To" named "Export HEIC". This does nothing more than hide the original File Settings panel so you don't accidentally make changes there instead of the "HEIC settings" panel. However, this is entirely optional and only a cosmetic change.

## How does it work? 

The plugin creates what the Lightroom SDK calls an "Export post-process action" or an "Export Filter Provider". As the name suggests, it allows the plugin to run some code after Lightroom has completed the initial processing of the image. Here is roughly what happens:

- Lightroom renders the image according to the user's settings
- This plugin (ExportHEIC) starts executing and is provided with a list of images and their export settings
- ExportHEIC requests a different version of the image to be rendered into a temporary location. According to the Lightroom SDK guide, now it becomes the plugin's responsibility to place the final image in the originally requested location
  - The rendering that ExportHEIC requests will be either an 8-bit or a 16-bit TIFF depending on the bit-depth selected in the HEIC settings panel
 - ExportHEIC uses a helper executable to render the temporary TIFF file created in the previous step into an HEIC file 
 - The HEIC file is placed at the originally requested location 
   - This is why it has to have a .jpg extension. If the file had a .heic extension instead, Lightroom would say that the export failed because it couldn't find the final rendered file

## Why HEIC?

HEIC is a more modern file format than the standard JPEG, which is frequently used to render photos after they have been edited, and to share them with friends or online. HEIC is well-supported by most viewers and has been used by Apple in one form or another since 2017. Camera manufacturers are also starting to adopt it, with flagship cameras like the Sony A1 or Canon R3 adding support. There are two main benefits to HEIC:

- A better compression algorithm, meaning either a lower file size for the same perceived quality or a higher quality image at the same file size
- 10-bit encoding support, allowing for a wider dynamic range and giving more latitude for further edits than the 8-bit JPEG
