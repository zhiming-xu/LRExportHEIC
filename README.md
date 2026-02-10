# LRExportHEIC

A plugin to allow Lightroom to export HEIC files.

Adopted from https://github.com/milch/LRExportHEIC with only CLI use which can convert a single input file or batch-convert a directory of `.avif` files into `.heic`. It is written in Swift.

## Compatibility

Because the CLI component is using macOS APIs to create the HEIC file, the only supported platform is macOS. Works for me on MacOS Sequioa and Tahoe. Tested on AVIF files exported by Lightroom (Cloud based).

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

## Reference
Read about more details in the original repository, linked above.
