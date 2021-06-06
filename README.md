Radarr Transmission Fixer
======
**Radarr Transmission Fixer** allows you to update the seeded data location automatically of a torrent in Transmission, downloaded via Radarr.

## Setup

* Change the USER:PASSWD to your USERNAME and PASSWORD for your Transmission. If you don't have a password you can remove the '-n USER:PASSWD'
* Run this script as a "custom script" from Radarr's "Settings > Connect > Connections" option. Set it to function 'On Download/Upgrade' put in the path to the script and save.
* Make sure the script is executable by the Radarr user
* Ideally meant to run with Radarr copying files, not hardlinking
* While Radarr can handle removing of completed downloads, the script does it itself.
* BASH script

Radarr will provide all the required directory and file details to the script, which will then set the seeding location of a torrent to where you store the data and remove the origin file from the default Transmission downlaod directory, Saving you from having two files.

The script will create a log file in the directory of the script, which will be a max of 100 lines at anytime.

A radarr version of my Sonarr script because it wont be implemented. https://github.com/Cr4zyy/Sonarr-Transmission-Fixer
