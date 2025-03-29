#!/bin/bash

# Get the real path of the script, resolving symlinks
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
BIN_DIR="$(dirname "$REAL_PATH")"

# Function to display usage
usage() {
    echo "Usage: $0 [options]" >&2
    echo "Extract subtitles from video file" >&2
    echo >&2
    echo "Options:" >&2
    echo "  -i, --input     : Input video file (optional, default: stdin)" >&2
    echo "  -a, --area      : Area to extract in format WxH+X+Y (required)" >&2
    echo "                    Example: 1920x200+0+880 for bottom subtitle" >&2
    echo "  -o, --output    : Output file for subtitles (optional, default: stdout)" >&2
    echo "  -r, --rate      : Frame rate (frames per second, default: 1)" >&2
    echo "  -l, --language  : OCR language(s) (comma-separated, default: zh-CN,en-US)" >&2
    echo "  -f, --fast      : Use fast OCR mode" >&2
    echo "  -v, --verbose   : Show detailed processing information" >&2
    echo >&2
    echo "Examples:" >&2
    echo "  # Using pipe (read from stdin, write to stdout):" >&2
    echo "  cat video.mp4 | $0 -a 600x50+210+498 > subs.txt" >&2
    echo >&2
    echo "  # Using pipe with custom frame rate:" >&2
    echo "  cat video.mp4 | $0 -a 600x50+210+498 -r 2 > subs.txt" >&2
    echo >&2
    echo "  # Using pipe with specific language:" >&2
    echo "  cat video.mp4 | $0 -a 600x50+210+498 -l en-US > subs.txt" >&2
    echo >&2
    echo "  # Using input file (equivalent to above):" >&2
    echo "  $0 -i video.mp4 -a 600x50+210+498 -o subs.txt" >&2
    echo >&2
    echo "  # Extract Chinese and English subtitles from bottom area:" >&2
    echo "  $0 -i video.mp4 -a 1920x200+0+880 -o subs.txt" >&2
    echo >&2
    echo "  # Use fast mode for quicker processing:" >&2
    echo "  $0 -i video.mp4 -a 600x50+210+498 -f -o subs.txt" >&2
    exit 1
}

# Show usage if no arguments provided
if [ $# -eq 0 ]; then
    usage
fi

# Initialize variables
input_file="-"  # Default to stdin
area=""
output_file="-"  # Default to stdout
frame_rate="1"
language="zh-CN,en-US"
fast_mode=false
verbose=false

# Cleanup function
cleanup() {
    # Kill the entire process group
    kill -- -$$
    exit 1
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Make sure the script runs in its own process group
set -m

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -i|--input)
            input_file="$2"
            shift 2
            ;;
        -r|--rate)
            frame_rate="$2"
            shift 2
            ;;
        -o|--output)
            output_file="$2"
            shift 2
            ;;
        -a|--area)
            area="$2"
            shift 2
            ;;
        -l|--language)
            language="$2"
            shift 2
            ;;
        -f|--fast)
            fast_mode=true
            shift
            ;;
        -v|--verbose)
            verbose=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown parameter: $1" >&2
            usage
            ;;
    esac
done

# Check if input file exists (skip check for stdin)
if [ "$input_file" != "-" ] && [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' does not exist" >&2
    exit 1
fi

# Check if area is specified
if [ -z "$area" ]; then
    echo "Error: Area parameter (-a, --area) is required" >&2
    usage
fi

# Set up OCR command
ocr_cmd="$BIN_DIR/ocr.swift"
if [ "$fast_mode" = true ]; then
    ocr_cmd="$ocr_cmd -f"
fi
if [ -n "$language" ]; then
    ocr_cmd="$ocr_cmd -l $language"
fi

# Only show progress message if not outputting to stdout
if [ "$output_file" != "-" ]; then
    echo "Extracting subtitles from video..." >&2
    echo "This may take a while..." >&2
fi

# Process the video:
# 1. Crop the video if area is specified
# 2. Extract frames
# 3. Perform OCR on each frame
# 4. Remove empty lines and duplicates
process_video() {
    # Use system temporary directory for framify
    export USE_SYSTEM_TEMP=true

    # Build verbose options
    local verbose_opt=""
    if [ "$verbose" = true ]; then
        verbose_opt="-v"
    fi

    if [ -n "$area" ]; then
        # Crop video and pipe to framify
        "$BIN_DIR/crop.sh" -i "$input_file" -a "$area" -o - $verbose_opt | \
            "$BIN_DIR/framify.sh" -i - -r "$frame_rate" -exec "$ocr_cmd {}" $verbose_opt 2>/dev/null
    else
        # Directly process video with framify
        "$BIN_DIR/framify.sh" -i "$input_file" -r "$frame_rate" -exec "$ocr_cmd {}" $verbose_opt
    fi | \
        # Process the output:
        # 1. Remove empty lines
        # 2. Remove duplicate consecutive lines
        if [ "$verbose" = true ]; then
            awk 'NF { if ($0 != prev) { print $0; print $0 > "/dev/stderr" }; prev=$0 }'
        else
            awk 'NF { if ($0 != prev) print $0; prev=$0 }'
        fi

    # Clean up the environment variable
    unset USE_SYSTEM_TEMP
}

if [ "$output_file" = "-" ]; then
    # Output to stdout
    process_video
else
    # Output to file
    process_video > "$output_file"
    echo "Subtitles extracted to: $output_file" >&2
    echo "Done!" >&2
fi 