# subscan

A command-line tool for extracting hardcoded subtitles from videos, designed for macOS. It uses OCR technology to recognize text from video frames, making it especially useful for extracting hardcoded subtitles from movies, TV shows, or any video content.

[![asciicast](https://asciinema.org/a/W7GO633guqkB5cq9aRvcPKoZH.svg)](https://asciinema.org/a/W7GO633guqkB5cq9aRvcPKoZH?speed=6&loop=1)

## Features

- 🎯 Extract hardcoded subtitles from any video format supported by ffmpeg
- ✂️ Crop specific areas of video frames for targeted subtitle extraction
- 🌏 Support multiple languages (including Chinese and English)
- ⚡️ Adjustable frame rate for balancing accuracy and speed
- 🚀 Fast mode for quicker processing
- 📦 Pipeline support for flexible video processing

## Installation

### Using Homebrew

```bash
# Add the tap
brew tap vangie/formula

# Install subscan
brew install subscan
```

This will install the main command `subscan` and its supporting tools:

- `subscan`: Main tool for extracting subtitles from videos
- `crop`: Tool for cropping video to specific area
- `framify`: Tool for extracting frames from video
- `ocr`: Tool for performing OCR on images

## Usage

### Basic Usage

Extract subtitles from a video file:

```bash
# Basic usage (read from file)
subscan -i video.mp4 -a 600x50+210+498 -o subtitles.txt

# Read from stdin, write to stdout
cat video.mp4 | subscan -a 600x50+210+498 > subtitles.txt
```

### Advanced Usage

```bash
# Extract with custom frame rate (2 fps)
subscan -i video.mp4 -a 600x50+210+498 -r 2 -o subtitles.txt

# Use fast mode with specific languages
subscan -i video.mp4 -a 600x50+210+498 -f -l "en-US,zh-CN" -o subtitles.txt

# Show verbose output
subscan -i video.mp4 -a 600x50+210+498 -v -o subtitles.txt
```

### How to find the subtitle area

1. Use QuickTime Player or VLC to take a screenshot of your video
2. Use Preview.app's selection tool to measure the subtitle area:
   - Width x Height: The size of the subtitle area
   - X + Y: The position from top-left corner
3. Combine these values in the format: WxH+X+Y
   - Example: `1920x200+0+880` for a bottom subtitle area
   - Example: `600x50+210+498` for a smaller subtitle area

### Supporting Tools

While these tools are primarily used by `subscan`, they can also be used independently:

```bash
# Crop a video section
crop -i video.mp4 -a 600x50+210+498 -o cropped.mp4

# Extract frames from video
framify -i video.mp4 -r 1 -exec "echo {} > /dev/null"

# Perform OCR on an image
ocr -l zh-CN,en-US image.jpg
```

## Requirements

- macOS 12.0 or later
- ffmpeg (automatically installed by Homebrew)
- Swift 5.0 or later (comes with macOS)
- Vision framework (part of macOS)

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
