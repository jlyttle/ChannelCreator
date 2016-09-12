#!/bin/bash

# Check this to make sure we know what it's doing and whether it's doing what we want.
# For example, we aren't using myth.tv at all, so we need to change the end result of this to call
# ffmpeg or just echo out a result or error code.

MP3SPLT_OPTS="th=-70,min=0.15"

[[ "Cutlist: "  == `mythcommflag --getcutlist -f $1  |grep Cutlist` ]] \ 
    || { echo already has cutlist && exit 1; }

TMPDIR=`mktemp -d /tmp/mythcommflag.XXXXXX` || exit 1
cd $TMPDIR
touch `basename $1`.touch
ffmpeg -i $1 -acodec copy sound.mp3
mp3splt -s -p $MP3SPLT_OPTS sound.mp3

CUTLIST=`tail --lines=+3 mp3splt.log|sort -g |\
       awk 'BEGIN{start=0;ORS=","}{if($2-start<400)
       {finish=$2} else {print int(start*25+1)"-"int(finish*25-25);
       start=$1; finish=$2;}}END{print int(start*25+1)"-"}'`

mythcommflag --setcutlist $CUTLIST -f $1
