#!/bin/bash
#
# A simple script for Radarr to run on download completion
# Lets Radarr handle copying of the downloaded file and then
# updates the location of the seeded file for Transmission
# and finally removes the original downloaded file
#

#VARIABLES
REMOTE="transmission-remote -n USER:PASSWD" #Change USER and PASSWD
DLDIR="radarr" #Name of the folder radarr downloads all torrents into, can be customised with 'Category' option in download client options

#set 1 if you want radarr to refresh the movie after moving a download to scan and update directory in radarr, important for things like bazarr
#only applies when directories are moved
ENABLE_RADARR_REFRESH=0

#set 1 if you want the script to clear plex trash after moving files, some setups might end up with trash files and this just helps keep it tidy
#only applies when directories are moved
ENABLE_PLEX_TRASH=0

#set 1 if you want radarr to unmonitor a movie after successful download and import, dont use if you want upgrades
ENABLE_UNMONITOR=0

PLEXTOKEN="PLEX TOKEN" #add PLEXTOKEN and LIBRARY if ENABLE_PLEX_TRASH=1
LIBRARY="LIBRARY ID"  #sectionid/key of movie library on plex ( you can use this script to find library ids https://github.com/Cr4zyy/Sonarr-Transmission-Fixer/blob/master/plex_library_key.sh)
APIKEY="RADARR API KEY" #Only needed if ENABLE_RADARR_REFRESH=1 Radarr API Key, found in 'Settings > General'

#IPS AND PORTS change as needed
PLEX_IP="127.0.0.1"
PLEX_PORT="32400"
RADARR_IP="127.0.0.1"
RADARR_PORT="7878"

LOGLINES="1000" # How many lines the log should limit itself to

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

LOG=$(dirname $0)
LOG+="/radarrtransmissionfixer.log"

log() { 
    local LEVEL="$1"
    shift

    if [[ "$LEVEL" == "DEBUG" && "$ENABLE_DEBUG" -ne 1 ]]; then
        return
    elif [[ "$LEVEL" == "INFO" || "$LEVEL" == "WARN" ]]; then
        LEVEL="$LEVEL "
    fi
    local timestamp message arrmsg
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    message="$timestamp | $LEVEL | $*"
    arrmsg="$LEVEL | $*"
    
    #file log
    echo "$message" | tee -a "$LOG"
    #arr log
    echo "$arrmsg" >&2  # stderr shows as error in arr but whatever
}

if [[ "$EVENTTYPE" == "Test" ]]; then
    log INFO "New Event - $EVENTTYPE"
    exit 0;
elif [[ "$EVENTTYPE" == "Download" ]]; then
    log INFO "New Event - $EVENTTYPE | Processing $TITLE | ${radarr_movie_year}"
else
    log WARN "Unsupported Radarr Event - $EVENTTYPE"
    log WARN "Set DEBUG=1 for more info"
    log DEBUG "EVENTTYPE - $EVENTTYPE"
    log DEBUG "DEST - $DEST"
    log DEBUG "SPATH - $SPATH"
    log DEBUG "TORRENT_NAME - $TORRENT_NAME"
    log DEBUG "TORRENT_ID - $TORRENT_ID"
    log DEBUG "STORED_FILE - $STORED_FILE"
    log DEBUG "ORIGIN_FILE - $ORIGIN_FILE"
    log DEBUG "SOURCEDIR - $SOURCEDIR"
    log DEBUG "RELATIVEDIR - $RELATIVEDIR"
    log DEBUG "TITLE - $TITLE"
    log DEBUG "MOVIE_ID - $MOVIE_ID"
    log DEBUG "TORRENT_DIR - $TORRENT_DIR"
    log DEBUG "TDEST - $TDEST"
    exit 0
fi

if [ -e "$STORED_FILE" ]; then
    log INFO "Processing new download of: $TITLE"
    log INFO "Torrent ID: $TORRENT_ID | Torrent Name: $TORRENT_NAME"
    log INFO "Movie file detected as: $SPATH"
    
    #get torrent folder name if it has one
    if [ "$TORRENT_DIR" != "$DLDIR" ]; then
        log INFO "Torrent downloads into a directory, not a single file: $TORRENT_DIR"
        log INFO "Torrent must be moved accordingly. Creating directory..."
        
        mkdir "$TDEST"
        if [ $? -eq 0 ]; then
            log INFO "Directory created: $TDEST"
        else
            log ERROR "mkdir failed to complete. Radarr log may provide more detail"
        fi

        mv "$STORED_FILE" "$TDEST"
        if [ $? -eq 0 ]; then
            log INFO "Moving file | $STORED_FILE | -> | $TDEST"
        else
            log ERROR "mv failed to complete. Radarr log may provide more detail"
        fi
    fi
    
    #REMOTE -t TorrentID --find /New/Torrent/Data/Location
    $REMOTE -t "$TORRENT_ID" --find "$DEST"
    log INFO "Torrent ID: $TORRENT_ID | Data now in: $STORED_FILE"

    if [ -e "$ORIGIN_FILE" ]; then
        rm -f "$ORIGIN_FILE"
        log INFO "Deleting origin file: $TORRENT_NAME | from | $SOURCEDIR"

        if [ "$TORRENT_DIR" != "$DLDIR" ]; then
            rm -d "$SOURCEDIR"
            if [ $? -eq 0 ]; then
                log INFO "Cleaning up empty directory $SOURCEDIR"
            else
                log WARN "Failed to remove directory. Checking to see if additional files need moving..."
                COPYFILES=$(cp -r -u -v "$SOURCEDIR"/* "$TDEST"  2>&1)                  
                if [ $? -eq 0 ]; then
                    log INFO "Moved additional files as follows:"
                    log INFO "$COPYFILES"
                    
                    rm -rf "$SOURCEDIR"
                    log INFO "Deleted original additional files $TDEST"
                    #We moved torrent folders, verify torrent to make sure everything is ok!
                    $REMOTE -t "$TORRENT_ID" -v
                    
                    if [ $ENABLE_PLEX_TRASH -eq 1 ]; then
                        log INFO "Telling Plex to clean up trash"
                        curl -s -X PUT -H "X-Plex-Token: $PLEXTOKEN" http://$PLEX_IP:$PLEX_PORT/library/sections/$LIBRARY/emptyTrash
                    fi
                    
                    if [ $ENABLE_RADARR_REFRESH -eq 1 ]; then
                        log INFO "Telling Radarr to rescan $MOVIE_ID files"
                        curl -s -H "Content-Type: application/json" -H "X-Api-Key: $APIKEY" -d '{"name":"RefreshMovie","movieIds":['$MOVIE_ID']}' http://$RADARR_IP:$RADARR_PORT/api/v3/command > /dev/null
                    fi
                else
                    log ERROR "Could not move additional files"
                    log ERROR "$COPYFILES"
                    log ERROR "Ended processing"
                fi
            fi
            
        fi
        
    else
        log ERROR "No origin file found to remove for: $TORRENT_ID | $TORRENT_NAME"
    fi
else
    if [ -e "$ORIGIN_FILE" ]; then
        log ERROR "Stored file not located in expected directory: $STORED_FILE"
        log ERROR "Not moving file for torrent ID: $TORRENT_ID | $TORRENT_NAME"
    else
        log ERROR "No file found to move"
    fi
fi

if [ $ENABLE_UNMONITOR -eq 1 ]; then
    log INFO "Unmonitoring ID: $MOVIE_ID | $TITLE in Radarr"
    curl -s -X 'PUT' "http://$RADARR_IP:$RADARR_PORT/api/v3/movie/editor" -H 'accept: */*' -H 'Content-Type: application/json' -H "X-Api-Key: $APIKEY" -d "{\"movieIds\":[$MOVIE_ID],\"monitored\": false}" > /dev/null
fi

#Log upto a maximum of $LOGLINES lines
LINECOUNT=$(wc -l < $LOG)
if (( $(echo "$LINECOUNT > $LOGLINES"| bc -l) )); then
    echo "$(tail -$LOGLINES $LOG)" > "$LOG"
fi

