#!/bin/bash
#
# A simple script for Radarr to run on download completion
# Lets Radarr handle copying of the downloaded file and then
# updates the location of the seeded file for Transmission
# and finally removes the original downloaded file
#

#VARIABLES
REMOTE="transmission-remote -n USER:PASSWD" #Change USER and PASSWD
DLDIR="radarr" #Name of the folder radarr downlaods all torrents into, can be customised with 'Category' option in download client options

ENABLE_RADARR_REFRESH=0 #set 1 if you want radarr to refresh the movie after moving a download to scan and update directory in radarr, important for things like bazarr
ENABLE_PLEX_TRASH=0  #set 1 if you want the script to clear plex trash after moving files, some setups might end up with trash files and this just helps keep it tidy

PLEXTOKEN="PLEX TOKEN" #add plex token if ENABLE_PLEX_TRASH=1
LIBRARY="LIBRARY ID"  #sectionid/key of movie library on plex ( you can use this script to find library ids https://github.com/Cr4zyy/Sonarr-Transmission-Fixer/blob/master/plex_library_key.sh)
APIKEY="RADARR API KEY" #Only needed if ENABLE_RADARR_REFRESH=1 Radarr API Key, found in 'Settings > General'

#IPS AND PORTS change as needed
PLEX_IP="127.0.0.1"
PLEX_PORT="32400"
RADARR_IP="127.0.0.1"
RADARR_PORT="7878"

#DONT CHANGE BELOW THIS

DEST="${radarr_movie_path}"
SPATH="${radarr_moviefile_relativepath}"
TITLE="${radarr_movie_title}"
MOVIE_ID="${radarr_movie_id}"
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
    printferr "Processing $TITLE | ${radarr_movie_year}"
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
                    
                    if [ $ENABLE_PLEX_TRASH -eq 1 ]; then
                        printferr "| INFO | Telling Plex to clean up trash"
                        printf '%s | INFO  | Plex trash cleanup\n' "$DT" >> "$LOG"
                        curl -s -X PUT -H "X-Plex-Token: $PLEXTOKEN" http://$PLEX_IP:$PLEX_PORT/library/sections/$LIBRARY/emptyTrash
                    fi
                    
                    if [ $ENABLE_RADARR_REFRESH -eq 1 ]; then
                        printferr "| INFO | Telling Radarr to rescan $MOVIE_ID files."
                        printf '%s | INFO  | Radarr movie rescan\n' "$DT" >> "$LOG"
                        curl -s -H "Content-Type: application/json" -H "X-Api-Key: $APIKEY" -d '{"name":"RefreshMovie","movieIds":['$MOVIE_ID']}' http://$RADARR_IP:$RADARR_PORT/api/v3/command > /dev/null
                    fi
                else
                    printferr "| ERROR | Could not move additional files."
                    printferr "$COPYFILES"
                    printferr "Completed Processing"
                    printf '%s | ERROR | Could not move additional files.\n' "$DT" >> "$LOG"
                    printf '%s | INFO  | Completed Processing.\n' "$DT" >> "$LOG"
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
