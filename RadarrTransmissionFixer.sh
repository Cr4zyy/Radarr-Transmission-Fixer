#!/bin/bash
#
# A simple script for Radarr to run on download completion
# Lets Radarr handle copying of the downloaded file and then
# updates the location of the seeded file for Transmission
# and finally removes the original downloaded file
#
# Will put "errors" into Radarr event log, this isnt always
# going to be an actual error, just an easy way to display
# what the script is doing in some cases it will move files 
# radarr expected to find itself and it will give you warnings

#VARIABLES
REMOTE="transmission-remote -n USER:PASSWD" #Change USER and PASSWD, or remove if not required
DLDIR="radarr" #Name of the folder radarr downlaods all torrents into, can be customised with 'Category' option in download client options

DEST="${radarr_movie_path}"
SPATH="${radarr_moviefile_relativepath}"
TITLE="${radarr_movie_title}"
TORRENT_NAME="${radarr_moviefile_scenename}"
TORRENT_ID="${radarr_download_id}"
STORED_FILE="${radarr_moviefile_path}"
ORIGIN_FILE="${radarr_moviefile_sourcepath}"
EVENTTYPE="${radarr_eventtype}"
SOURCEDIR="${radarr_moviefile_sourcefolder}"
RELATIVEDIR="${radarr_moviefile_relativepath}"

TORRENT_DIR=$(basename "$SOURCEDIR")
DEST_DIR=$(basename "$DEST")
TDEST="$DEST/$TORRENT_DIR"

DT=$(date '+%Y-%m-%d %H:%M:%S')
LOG=$(dirname $0)
LOG+="/radarrtransmissionfixer.log"

printferr() { printf '%s\n' "$@" 1>&2; }

if [[ "$EVENTTYPE" == "Test" ]]; then
    printf '%s | INFO  | Radarr Event - %s\n' "$DT" "$EVENTTYPE" >> "$LOG"
    printferr "Connection Test"
    exit 0;
else
    printf '%s | INFO  | Radarr Event - %s\n' "$DT" "$EVENTTYPE" >> "$LOG"
    printferr "Processing..."
fi

if [ -e "$STORED_FILE" ]; then
    printf '%s | INFO  | Processing new download of: %s\n' "$DT" "$TITLE" >> "$LOG"
    printf '%s | INFO  | Torrent ID: %s | Torrent Name: %s\n' "$DT" "$TORRENT_ID" "$TORRENT_NAME" >> "$LOG"
    printf '%s | INFO  | Movie file detected as: %s\n' "$DT" "$SPATH" >> "$LOG"

    
    #get torrent folder name if it has one
    if [ "$TORRENT_DIR" != "$DLDIR" ]; then
        printferr "Download is in a folder"
        printf '%s | INFO  | Torrent downloads into directory, not only a file: /%s\n' "$DT" "$TORRENT_DIR" >> "$LOG"
        printf '%s | INFO  | Torrent must be moved accordingly! Creating directory...\n' "$DT" >> "$LOG"
        
        mkdir "$TDEST"
        if [ $? -eq 0 ]; then
            printf '%s | INFO  | Directory created: %s\n' "$DT" "$TDEST">> "$LOG"
        else
            printf '%s | ERROR | mkdir could not complete! Check Radarr log for more info\n' "$DT" >> "$LOG"
        fi

        mv "$STORED_FILE" "$TDEST"
        if [ $? -eq 0 ]; then
            printf '%s | INFO  | Moving file from: %s  ->  %s\n' "$DT" "$STORED_FILE" "$TDEST">> "$LOG"
        else
            printf '%s | ERROR  | mv could not complete! Check Radarr log for more info\n' "$DT" >> "$LOG"
        fi
    fi
    
    #REMOTE -t TorrentID --find /New/Torrent/Data/Location
    $REMOTE -t "$TORRENT_ID" --find "$DEST"
    printf '%s | INFO  | Torrent ID: %s, data now in: %s\n' "$DT" "$TORRENT_ID" "$DEST" >> "$LOG"

    if [ -e "$ORIGIN_FILE" ]; then
        rm -f "$ORIGIN_FILE"
        printf '%s | INFO  | Deleting origin file: %s from %s\n' "$DT" "$TORRENT_NAME" "$SOURCEDIR" >> "$LOG"

        if [ "$TORRENT_DIR" != "$DLDIR" ]; then
            rm -d "$SOURCEDIR"
            if [ $? -eq 0 ]; then
                printf '%s | INFO  | Cleaning up empty directories %s\n' "$DT" "$SOURCEDIR" >> "$LOG"
            else
                printf '%s | WARN  | Failed to remove directory, checking to see if we have to move additional files! Check Radarr log for more info\n' "$DT" >> "$LOG"
                COPYFILES=$(cp -r -u -v "$SOURCEDIR"/* "$TDEST"  2>&1)                  
                if [ $? -eq 0 ]; then
                    printf '%s | INFO  | Moved additional files as follows:\n%s\n' "$DT" "$COPYFILES" >> "$LOG"
                    printferr "Folder detected and copied files in folder"
                    printferr "$COPYFILES"
                    
                    rm -rf "$SOURCEDIR"
                    printf '%s | INFO  | Deleted original additional files %s\n' "$DT" "$TDEST" >> "$LOG"
                    #We moved torrent folders, verify torrent to make sure everything is ok!
                    $REMOTE -t "$TORRENT_ID" -v
                else
                    printferr "| ERROR | Could not move additional files."
                    printferr "$COPYFILES"
                    printf '%s | ERROR | Could not move additional files.\n' "$DT" >> "$LOG"
                fi
            fi
            
        fi
        
    else
        printf '%s | ERROR | No origin file found to remove for: %s | %s\n' "$DT" "$TORRENT_NAME" "$TORRENT_ID" >> "$LOG"
    fi
else
    if [ -e "$ORIGIN_FILE" ]; then
        printf '%s | ERROR | Stored file not located in: %s\n' "$DT" "$STORED_FILE" >> "$LOG"
        printf '%s | ERROR | Not moving torrent file for: %s\n' "$DT" "$TORRENT_NAME" >> "$LOG"
    else
        printf '%s | ERROR | No file exists to move or find!\n' "$DT" >> "$LOG"
    fi
fi

#Log upto a maximum of 200 lines
LINECOUNT=$(wc -l < $LOG)
if (( $(echo "$LINECOUNT > 200"| bc -l) )); then
    echo "$(tail -200 $LOG)" > "$LOG"
fi
