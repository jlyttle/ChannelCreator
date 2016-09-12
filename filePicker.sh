#!/bin/bash

# Random episode picker for ChannelCreator
# Changes:
#    This version uses a database file with full filenames instead of setting and clearing the archive bit on Windows
#    We can now rely on symlinks to the numbered folders instead of copying files over.
#    This script is run once rather than having many duplicates.

# Declare a list of supported extensions and start a counter for our playlists
IFS=$'\n'
extensionList=(avi mp4 mkv)
cnt=0
EDEN="/media/sf_MEDIA_DRIVE/Eden"
cd $EDEN/playlists

# Create the database file if it doesn't exist
if [ ! -e $EDEN/database.db ]; then
    touch $EDEN/database.db
fi
# for all directories in the TV folder, do the rest of the script
for d in `find /media/sf_MEDIA_DRIVE/Eden/TV/* -type d`
do

# Increment the counter for every item in the loop
cnt=$(($cnt+1))
while [ -e $cnt.list ]; do cnt=$(($cnt+1)); done
touch $cnt.list
#echo "#EXTM3U" > $cnt.m3u

function dbRemove {
    # Remove all files in the folder from the database file if there are no more unused ones
    for f in $( cat /tmp/episodeFiles ); do
        sed -i "\:$f:d" $EDEN/database.db
    done
    Loop
}

function AddList {
    #echo "#EXTINF:$1" >> $cnt.m3u
     echo "file://$1" >> $cnt.list
}

function randomFilePicker {
    winner=$( cat /tmp/edenFilePicker | shuf -n 1000 | head -n1 )
    echo $winner >> $EDEN/database.db
    echo "$winner ---> $cnt.list" >> /tmp/edenbug
    AddList $winner
}

function Loop {
if [ -e /tmp/edenFilePicker ]; then rm /tmp/edenFilePicker && touch /tmp/edenFilePicker; else touch /tmp/edenFilePicker; fi
if [ -e /tmp/episodeFiles ]; then rm /tmp/episodeFiles && touch /tmp/episodeFiles; else touch /tmp/episodeFiles; fi

find $d -name '*.*' >> /tmp/episodeFiles
for f in $( cat /tmp/episodeFiles );
do
    fileExt=$( echo "$f" | rev | cut -d '.' -f 1 | rev )
    for ext in ${extensionList[@]}; do [ "$ext" == "$fileExt" ] && echo "$f" >> /tmp/edenFilePicker
    done
done

for f in $( cat /tmp/edenFilePicker ); do
    if grep -Fx "$f" $EDEN/database.db; then
        sed -i "\:$f:d" /tmp/edenFilePicker
    fi
done

if [ ! -s /tmp/edenFilePicker ]; then dbRemove; else randomFilePicker; fi
}

Loop
continue
done
