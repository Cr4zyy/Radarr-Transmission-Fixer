#!/bin/bash
#
# A simple script for Radarr to run on download completion
# Lets Radarr handle copying of the downloaded file and then
# updates the location of the seeded file for Transmission
# and finally removes the original downloaded file
#

#VARIABLES
REMOTE="transmission-remote -n USER:PASSWD" #Change USER and PASSWD

DEST="${radarr_movie_path}"
SPATH="${radarr_moviefile_relativepath}"
TITLE="${radarr_movie_title}"
TORRENT_NAME="${radarr_moviefile_scenename}"
TORRENT_ID="${radarr_download_id}"
STORED_FILE="${radarr_moviefile_path}"
ORIGIN_FILE="${radarr_moviefile_sourcepath}"
EVENTTYPE="${radarr_eventtype}"
SOURCEDIR="${radarr_moviefile_sourcefolder}"

TORRENT_DIR=$(basename "$SOURCEDIR")
DEST_DIR=$(basename "$DEST")
TDEST="$DEST/$TORRENT_DIR"

DT=$(date '+%Y-%m-%d %H:%M:%S')
LOG=$(dirname $0)
LOG+="/radarrtransmissionfixer.log"

if [[ "$EVENTTYPE" == "Test" ]]; then
    printf '%s | INFO  | Radarr Event - %s\n' "$DT" "$EVENTTYPE" >> "$LOG"
    exit 0;
else
    printf '%s | INFO  | Radarr Event - %s\n' "$DT" "$EVENTTYPE" >> "$LOG"
fi

if [ -e "$STORED_FILE" ]; then
    printf '%s | INFO  | Processing new download of: %s\n' "$DT" "$TITLE" >> "$LOG"
    printf '%s | INFO  | Torrent ID: %s | Torrent Name: %s\n' "$DT" "$TORRENT_ID" "$TORRENT_NAME" >> "$LOG"
    printf '%s | INFO  | Movie file detected as: %s\n' "$DT" "$SPATH" >> "$LOG"

    
    #get torrent folder name if it has one
    if [ "TORRENT_DIR" != "$DEST_DIR" ]; then
        printf '%s | INFO  | Torrent downloads into directory, not only a file: /%s\n' "$DT" "$TORRENT_DIR" >> "$LOG"
        printf '%s | INFO  | Torrent must be moved accordingly! Creating directory...\n' "$DT" >> "$LOG"
        
        mkdir "$TDEST"
        if [ $? -eq 0 ]; then
            printf '%s | INFO  | Directory created: %s\n' "$DT" "$TDEST">> "$LOG"
        else
            printf '%s | ERROR | mv could not complete! Check Radarr log for more info\n' "$DT" >> "$LOG"
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

        if [ "TORRENT_DIR" != "$DEST_DIR" ]; then
            rm -d "$SOURCEDIR"
            if [ $? -eq 0 ]; then
                printf '%s | INFO  | Cleaning up empty directories %s\n' "$DT" "$SOURCEDIR" >> "$LOG"
            else
                printf '%s | WARN  | Failed to remove empty directory, checking to see if we have to move additional files! Check Radarr log for more info\n' "$DT" >> "$LOG"
                cp -r -u  "$SOURCEDIR"/* "$TDEST"
                if [ $? -eq 0 ]; then
                    printf '%s | INFO  | Moved additional files to: %s\n' "$DT" "$TDEST" >> "$LOG"
                    rm -rf "$SOURCEDIR"
                    printf '%s | INFO  | Deleted original additional files %s\n' "$DT" "$TDEST" >> "$LOG"
                else
                    printf '%s | ERROR | Could not move additional files. Check Radarr log for more info\n' "$DT" >> "$LOG"
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

#Log upto a maximum of 100 lines
LINECOUNT=$(wc -l < $LOG)
if (( $(echo "$LINECOUNT > 100"| bc -l) )); then
    echo "$(tail -100 $LOG)" > "$LOG"
fi
