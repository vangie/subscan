#!/bin/bash

# Initialize default values
input_file=""
frame_rate="1"
output_dir=""  # Will be set based on input filename or default to 'frames' for stdin
exec_cmd=""
verbose=false
# Allow using system temporary directory via environment variable
USE_SYSTEM_TEMP="${USE_SYSTEM_TEMP:-false}"

# Define colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Set FFREPORT to /dev/null to suppress report file creation
export FFREPORT="file=/dev/null"

# Cleanup function to handle interrupts
cleanup() {
    # Kill all child processes
    pkill -P $$
    # Remove temporary directory only if using system temp
    if [ "$USE_SYSTEM_TEMP" = "true" ] && [ -n "$output_dir" ] && [ -d "$output_dir" ]; then
        rm -rf "$output_dir"
    fi
}

# Set up signal handlers for interrupts
trap cleanup SIGINT SIGTERM

# Function to display usage
usage() {
    echo "Usage: $0 [-i|--input input_video] [-r|--rate frame_rate] [-o|--output output_dir] [-exec command] [-v|--verbose]" >&2
    echo "Example: $0 --input video.mp4 --rate 1" >&2
    echo "Parameters:" >&2
    echo "  -i, --input     : Input video file (optional when using stdin)" >&2
    echo "  -r, --rate      : Frame rate (frames per second, default: 1)" >&2
    echo "  -o, --output    : Output directory for frames (default: inputname_frames, or 'frames' for stdin)" >&2
    echo "  -exec           : Execute command for each frame. Use {} as frame placeholder" >&2
    echo "  -v, --verbose   : Show ffmpeg progress output instead of progress bar" >&2
    echo >&2
    echo "Examples:" >&2
    echo "  # Extract 1 frame per second (output to 'video_frames' directory):" >&2
    echo "  $0 -i video.mp4" >&2
    echo >&2
    echo "  # Extract 2 frames per second to custom directory:" >&2
    echo "  $0 -i video.mp4 -r 2 -o custom_frames" >&2
    echo >&2
    echo "  # Using stdin (output to 'frames' directory):" >&2
    echo "  cat video.mp4 | $0" >&2
    echo >&2
    echo "  # Extract frames and perform OCR on each frame:" >&2
    echo "  $0 -i video.mp4 -exec './ocr.swift {}'" >&2
    echo >&2
    echo "  # Extract frames and process with custom command:" >&2
    echo "  $0 -i video.mp4 -exec 'convert {} -resize 50% resized_{}'" >&2
    exit 1
}

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
            output_dir="$2"
            shift 2
            ;;
        -exec)
            exec_cmd="$2"
            shift 2
            ;;
        -v|--verbose)
            verbose=true
            shift
            ;;
        -\?|--help)
            usage
            ;;
        *)
            echo "Unknown parameter: $1" >&2
            usage
            ;;
    esac
done

# Check if reading from stdin
if [ -t 0 ]; then
    # Terminal input (not a pipe)
    if [ -z "$input_file" ]; then
        echo "Error: Input file is required when not using stdin" >&2
        usage
    fi
else
    # Stdin input (pipe)
    input_file="-"
fi

# Check if input file exists (skip check for stdin)
if [ "$input_file" != "-" ] && [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' does not exist" >&2
    exit 1
fi

# Set default output directory if not specified
if [ -z "$output_dir" ]; then
    if [ "$USE_SYSTEM_TEMP" = "true" ] || [ -n "$exec_cmd" -a "$verbose" = false ]; then
        # Use system temp directory for processing or when explicitly requested
        output_dir="$(mktemp -d)"
        trap 'rm -rf "$output_dir"' EXIT
    else
        # Default directory naming for normal usage
        if [ "$input_file" = "-" ]; then
            output_dir="frames"
        else
            # Get filename without extension and add _frames
            filename=$(basename -- "$input_file")
            filename="${filename%.*}"
            output_dir="${filename}_frames"
        fi
        # Create output directory if it doesn't exist
        mkdir -p "$output_dir"
    fi
fi

# Validate frame rate
if ! [[ "$frame_rate" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Error: Frame rate must be a positive number" >&2
    exit 1
fi

# Function to display progress bar
show_progress() {
    local progress_file="$1"
    local duration=0
    local time=0
    local width=40
    local last_time=0

    # Get video duration if input is a file
    if [ "$input_file" != "-" ]; then
        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null)
        duration=${duration:-0}
        if ! [[ "$duration" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [ "$(printf '%.0f' "$duration")" -eq 0 ]; then
            # If duration is invalid or 0, try getting it from ffmpeg directly
            duration=$(ffmpeg -i "$input_file" 2>&1 | grep "Duration" | cut -d ' ' -f 4 | sed 's/,//' | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }')
            duration=${duration:-0}
        fi
        duration=$(printf "%.0f" "$duration")
    fi

    # Initialize progress bar
    printf -v space "%${width}s" ""
    printf "\rFraming : [%s] 0%%" "${space// / }" >&2

    while read -r line; do
        if [[ $line =~ ^out_time_ms=([0-9]+)$ ]]; then
            time=$((${BASH_REMATCH[1]} / 1000000))
            # Convert to integer for comparison
            current_time=$(printf "%.0f" "$time")
            last_time_int=$(printf "%.0f" "$last_time")
            if [ "$current_time" -gt "$last_time_int" ]; then
                last_time=$time
                if [ "$duration" -gt 0 ]; then
                    local percent=$((current_time * 100 / duration))
                    [ "$percent" -gt 100 ] && percent=100
                    local filled=$((width * percent / 100))
                    printf -v bar "%${filled}s" ""; bar=${bar// /#}
                    printf -v space "%$((width - filled))s" ""
                    local status="Framing "
                    [ "$percent" -eq 100 ] && status="Framed  "
                    printf "\r%s: [%s%s] %3d%%" "$status" "$bar" "$space" "$percent" >&2
                else
                    # If we can't get duration, estimate progress based on time
                    local filled=$((current_time * width / 100))
                    [ "$filled" -gt "$width" ] && filled=$width
                    printf -v bar "%${filled}s" ""; bar=${bar// /#}
                    printf -v space "%$((width - filled))s" ""
                    printf "\rFraming : [%s%s]" "$bar" "$space" >&2
                fi
            fi
        fi
    done < "$progress_file"

    # Ensure we show 100% at the end
    printf -v bar "%${width}s" ""; bar=${bar// /#}
    printf "\rFramed  : [%s] 100%%\n" "$bar" >&2
}

# Common ffmpeg options
if [ "$verbose" = true ]; then
    FFMPEG_OPTS="-hide_banner"
else
    FFMPEG_OPTS="-hide_banner -v error"
fi

# Add input options for better pipe handling
INPUT_OPTS="-analyzeduration 100M -probesize 100M"
FRAME_OPTS="-vf fps=$frame_rate -frame_pts 1"
FORMAT_OPTS="-start_number 1"

# Show input/output information in verbose mode
if [ "$verbose" = true ]; then
    if [ "$input_file" = "-" ]; then
        echo -e "${GREEN}Input ${NC}: ${BLUE}stdin (pipe)${NC}" >&2
    else
        echo -e "${GREEN}Input ${NC}: ${BLUE}$input_file${NC}" >&2
    fi
    echo -e "${GREEN}Output${NC}: ${BLUE}$output_dir${NC}" >&2
    echo -e "${GREEN}Rate  ${NC}: ${BLUE}$frame_rate fps${NC}" >&2
    if [ -n "$exec_cmd" ]; then
        echo -e "${GREEN}Exec  ${NC}: ${BLUE}$exec_cmd${NC}" >&2
    fi
    echo "---" >&2
fi

# Create progress pipe for showing progress (only if not in verbose mode)
progress_pipe=""
if [ "$verbose" = false ]; then
    progress_pipe=$(mktemp -u)
    mkfifo "$progress_pipe"
    show_progress "$progress_pipe" &
    progress_pid=$!
    # Set up cleanup for normal exit - only remove progress pipe and temp dir if using system temp
    trap 'rm -f "$progress_pipe"; kill $progress_pid 2>/dev/null; [ "$USE_SYSTEM_TEMP" = "true" ] && cleanup' EXIT
else
    trap '[ "$USE_SYSTEM_TEMP" = "true" ] && cleanup' EXIT
fi

# Execute ffmpeg command with provided parameters
if [ "$input_file" = "-" ]; then
    # Reading from stdin
    if [ "$verbose" = true ]; then
        unset FFREPORT
        ffmpeg $FFMPEG_OPTS $INPUT_OPTS -i pipe:0 $FRAME_OPTS $FORMAT_OPTS "$output_dir/frame_%04d.jpg"
        frame_count=$(find "$output_dir" -name "frame_*.jpg" | wc -l)
        if [ $frame_count -gt 0 ]; then
            echo -e "\n${GREEN}Extracted${NC}: ${BLUE}$frame_count frames${NC}" >&2
        else
            echo -e "\n${GREEN}Error${NC}: ${BLUE}No frames were extracted${NC}" >&2
            exit 1
        fi
    else
        ffmpeg $FFMPEG_OPTS $INPUT_OPTS -stats -i pipe:0 $FRAME_OPTS $FORMAT_OPTS -progress "$progress_pipe" "$output_dir/frame_%04d.jpg" 2>/dev/null
    fi
else
    # Reading from file
    if [ "$verbose" = true ]; then
        unset FFREPORT
        ffmpeg $FFMPEG_OPTS -i "$input_file" $FRAME_OPTS $FORMAT_OPTS "$output_dir/frame_%04d.jpg"
        frame_count=$(find "$output_dir" -name "frame_*.jpg" | wc -l)
        if [ $frame_count -gt 0 ]; then
            echo -e "\n${GREEN}Extracted${NC}: ${BLUE}$frame_count frames${NC}" >&2
        else
            echo -e "\n${GREEN}Error${NC}: ${BLUE}No frames were extracted${NC}" >&2
            exit 1
        fi
    else
        ffmpeg $FFMPEG_OPTS -stats -i "$input_file" $FRAME_OPTS $FORMAT_OPTS -progress "$progress_pipe" "$output_dir/frame_%04d.jpg" 2>/dev/null
    fi
fi

# Execute command on each frame if specified
if [ -n "$exec_cmd" ] && [ -d "$output_dir" ]; then
    if [ "$verbose" = true ]; then
        echo -e "\n${GREEN}Executing${NC}: ${BLUE}$exec_cmd${NC} on each frame" >&2
        echo "---" >&2
    fi
    # Use find and xargs for better signal handling
    find "$output_dir" -name "frame_*.jpg" -print0 | sort -z | xargs -0 -I{} sh -c "$exec_cmd"
fi 