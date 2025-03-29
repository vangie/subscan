#!/bin/bash

# Initialize default values
input_file="-"  # Default to stdin
output_file="-"  # Default to stdout
area=""
verbose=false

# Define colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 [-i|--input input_video|-] [-o|--output output_video|-] [-a|--area WxH+X+Y] [-v|--verbose]" >&2
    echo "Example: $0 --input video.mp4 --area 1920x200+0+880 --output cropped.mkv" >&2
    echo "Parameters:" >&2
    echo "  -i, --input     : Input video file (use '-' for stdin)" >&2
    echo "  -o, --output    : Output video file (use '-' for stdout)" >&2
    echo "  -a, --area      : Area to crop in format WxH+X+Y" >&2
    echo "  -v, --verbose   : Show ffmpeg progress output instead of progress bar" >&2
    exit 1
}

# Show usage if no arguments provided
if [ $# -eq 0 ]; then
    usage
fi

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -i|--input)
            input_file="$2"
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
        -v|--verbose)
            verbose=true
            shift
            ;;
        *)
            echo "Unknown parameter: $1" >&2
            usage
            ;;
    esac
done

# Check if area is provided
if [ -z "$area" ]; then
    echo "Error: Area parameter is required" >&2
    usage
fi

# Check if input file exists (skip check for stdin)
if [ "$input_file" != "-" ] && [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' does not exist" >&2
    exit 1
fi

# Function to display progress bar
show_progress() {
    local progress_file="$1"
    local duration=0
    local time=0
    local width=40
    local last_time=0
    local has_progress=false
    local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    # For stdin input, show spinner
    if [ "$input_file" = "-" ]; then
        printf "\rCropping %s" "${spinner[0]}" >&2
        while read -r line; do
            printf "\rCropping %s" "${spinner[i]}" >&2
            i=$(( (i + 1) % ${#spinner[@]} ))
        done < "$progress_file"
        printf "\rCropped     \n" >&2
        return
    fi

    # Get video duration
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null)
    duration=${duration:-0}
    if ! [[ "$duration" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [ "$(printf '%.0f' "$duration")" -eq 0 ]; then
        # If duration is invalid or 0, try getting it from ffmpeg directly
        duration=$(ffmpeg -i "$input_file" 2>&1 | grep "Duration" | cut -d ' ' -f 4 | sed 's/,//' | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }')
        duration=${duration:-0}
    fi
    duration=$(printf "%.0f" "$duration")

    # Initialize progress bar
    printf -v space "%${width}s" ""
    printf "\rCropping: [%s] 0%%" "${space// / }" >&2

    while read -r line; do
        if [[ $line =~ ^out_time_ms=([0-9]+)$ ]]; then
            has_progress=true
            time=$((${BASH_REMATCH[1]} / 1000000))
            # Convert to integer for comparison
            current_time=$(printf "%.0f" "$time")
            last_time_int=$(printf "%.0f" "$last_time")
            if [ "$current_time" -gt "$last_time_int" ]; then
                last_time=$time
                local percent=$((current_time * 100 / duration))
                [ "$percent" -gt 100 ] && percent=100
                local filled=$((width * percent / 100))
                printf -v bar "%${filled}s" ""; bar=${bar// /#}
                printf -v space "%$((width - filled))s" ""
                local status="Cropping"
                [ "$percent" -eq 100 ] && status="Cropped "
                printf "\r%s: [%s%s] %3d%%" "$status" "$bar" "$space" "$percent" >&2
            fi
        fi
    done < "$progress_file"

    # Show final status
    if [ "$has_progress" = true ]; then
        printf -v bar "%${width}s" ""; bar=${bar// /#}
        printf "\rCropped : [%s] 100%%\n" "$bar" >&2
    fi
}

# Common ffmpeg options
FFMPEG_OPTS="-hide_banner -y"
VIDEO_OPTS="-c:v libx264 -preset medium"
AUDIO_OPTS="-c:a copy"

# Parse crop area
IFS='x+' read -r width height x y <<< "$area"
FILTER_OPTS="-filter:v crop=$width:$height:$x:$y"

# Set format options based on output type
if [ "$output_file" = "-" ]; then
    # When outputting to pipe, use matroska format
    FORMAT_OPTS="-f matroska"
else
    # When outputting to file, use format based on extension
    FORMAT_OPTS=""
fi

# Create progress pipe if not in verbose mode
progress_pipe=""
if [ "$verbose" = false ]; then
    progress_pipe=$(mktemp -u)
    mkfifo "$progress_pipe"
    show_progress "$progress_pipe" &
    progress_pid=$!
    trap 'rm -f "$progress_pipe"; kill $progress_pid 2>/dev/null' EXIT
fi

# Determine output target
actual_output="$output_file"
if [ "$verbose" = true ] && [ "$output_file" = "-" ]; then
    actual_output="cropped.mkv"
fi

# In verbose mode, show input/output information
if [ "$verbose" = true ]; then
    if [ "$input_file" = "-" ]; then
        echo -e "${GREEN}Input ${NC}: ${BLUE}stdin (pipe)${NC}" >&2
    else
        echo -e "${GREEN}Input ${NC}: ${BLUE}$input_file${NC}" >&2
    fi
    
    if [ "$output_file" = "-" ]; then
        if [ "$actual_output" != "-" ]; then
            echo -e "${GREEN}Output${NC}: ${BLUE}stdout${NC} (via temporary file: ${BLUE}$actual_output${NC})" >&2
        else
            echo -e "${GREEN}Output${NC}: ${BLUE}stdout (pipe)${NC}" >&2
        fi
    else
        echo -e "${GREEN}Output${NC}: ${BLUE}$output_file${NC}" >&2
    fi
    echo "---" >&2
fi

# Execute ffmpeg command with provided parameters
if [ "$input_file" = "-" ] && [ "$actual_output" = "-" ]; then
    # Both input and output are pipes
    if [ "$verbose" = true ]; then
        # Save stdout to fd 3 and redirect stderr to console
        exec 3>&1
        ffmpeg $FFMPEG_OPTS -i pipe:0 $FILTER_OPTS $VIDEO_OPTS $AUDIO_OPTS $FORMAT_OPTS - 2>&2 >&3
        exec 3>&-
    else
        ffmpeg $FFMPEG_OPTS -i pipe:0 $FILTER_OPTS $VIDEO_OPTS $AUDIO_OPTS $FORMAT_OPTS - ${progress_pipe:+-progress "$progress_pipe"} 2>/dev/null
    fi
elif [ "$input_file" = "-" ]; then
    # Input is pipe, output to file
    if [ "$verbose" = true ]; then
        ffmpeg $FFMPEG_OPTS -i pipe:0 $FILTER_OPTS $VIDEO_OPTS $AUDIO_OPTS $FORMAT_OPTS "$actual_output" 2>&2
    else
        ffmpeg $FFMPEG_OPTS -i pipe:0 $FILTER_OPTS $VIDEO_OPTS $AUDIO_OPTS $FORMAT_OPTS "$actual_output" ${progress_pipe:+-progress "$progress_pipe"} 2>/dev/null
    fi
elif [ "$actual_output" = "-" ]; then
    # Input is file, output to pipe
    if [ "$verbose" = true ]; then
        # Save stdout to fd 3 and redirect stderr to console
        exec 3>&1
        ffmpeg $FFMPEG_OPTS -i "$input_file" $FILTER_OPTS $VIDEO_OPTS $AUDIO_OPTS $FORMAT_OPTS - 2>&2 >&3
        exec 3>&-
    else
        ffmpeg $FFMPEG_OPTS -i "$input_file" $FILTER_OPTS $VIDEO_OPTS $AUDIO_OPTS $FORMAT_OPTS - ${progress_pipe:+-progress "$progress_pipe"} 2>/dev/null
    fi
else
    # Both input and output are files
    if [ "$verbose" = true ]; then
        ffmpeg $FFMPEG_OPTS -i "$input_file" $FILTER_OPTS $VIDEO_OPTS $AUDIO_OPTS $FORMAT_OPTS "$actual_output" 2>&2
    else
        ffmpeg $FFMPEG_OPTS -i "$input_file" $FILTER_OPTS $VIDEO_OPTS $AUDIO_OPTS $FORMAT_OPTS "$actual_output" ${progress_pipe:+-progress "$progress_pipe"} 2>/dev/null
    fi
fi

# If in verbose mode and output was redirected to a file, copy it to stdout and keep the file
if [ "$verbose" = true ] && [ "$output_file" = "-" ] && [ -f "$actual_output" ]; then
    cat "$actual_output"
    echo -e "\n${GREEN}Note${NC}: Temporary file kept at ${BLUE}$actual_output${NC}" >&2
fi 