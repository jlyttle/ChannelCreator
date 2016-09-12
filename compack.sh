#!/bin/bash
# Compack script for ChannelCreator. Determines cuts for each episode and how many commercials are played each break.

# Check for schedule file and see if the number of lines in it matches the number of playlist files in directory
IFS=$'\n'
EDEN=/media/sf_MEDIA_DRIVE/Eden
if [ ! -e $EDEN/schedule.db ]; then
	echo "Need to configure schedule ($EDEN/schedule.db)"
	touch $EDEN/schedule.db
	exit 1
fi
if [ $( wc -l < $EDEN/schedule.db ) -ne $( ls -l $EDEN/playlists/*.list | wc -l ) ]; then
	echo "Need to put some shows into schedule" 
	exit 1
fi

cnt=0
# For each length in the schedule iterate thru the .list files in order and increment using a counter.
for broadcastLength in $( cat $EDEN/schedule.db ); do
	cnt=$(($cnt+1))
	for episode in $( cat $EDEN/playlists/$cnt.list ); do
# Subtract the broadcast length (schedule.db minutes divided by 60 to get seconds) from the length of the file 
		broadcastLengthSeconds=$(( $broadcastLength*60 ))
		episodeLengthSeconds=$( ffmpeg -i "$episode" 2>&1 | grep "Duration"| cut -d ' ' -f 4 | sed s/,// | sed 's@\..*@@g' | awk '{ split($1, A, ":"); split(A[3], B, "."); print 3600*A[1] + 60*A[2] + B[1] }' )
		#episodeLengthSeconds=$( ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$episode" )
		comBreakLength=$( awk "BEGIN { print ( $broadcastLengthSeconds - $episodeLengthSeconds ) }" )
# (using ffprobe). The result is the commercial break length as a variable. Then use find
# to get all commercials (we'll make distinctions for blocks later) and put into coms text file.
		find $EDEN/Compacks/* -name '*.mp4' > /tmp/allcoms
		find $EDEN/Compacks/* -name '*.mkv' >> /tmp/allcoms
		find $EDEN/Compacks/* -name '*.webm' >> /tmp/allcoms
# Shuffle coms. For each com, if it's greater than break length, continue. Otherwise echo into the .list file.
		cat /tmp/allcoms | shuf -n 500 | head -n 50 > /tmp/comlist
		total=0
		for com in $( cat /tmp/comlist ); do
			previousComLength=$comLength
			comLength=$( ffmpeg -i "$com" 2>&1 | grep "Duration"| cut -d ' ' -f 4 | sed s/,// | sed 's@\..*@@g' | awk '{ split($1, A, ":"); split(A[3], B, "."); print 3600*A[1] + 60*A[2] + B[1] }' )
			#comLength=$( ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$com" )
			if [[ $comLength == N/A || -z $comLength ]]; then
				comLength=$previousComLength
				continue
			fi
			total=$( awk "BEGIN { print ( $comLength + $total ) }" )
			if (( $( echo "$total $comBreakLength" | awk '{ print ($1 > $2) }' ) )); then
				total=$( awk "BEGIN { print ( $total - $comLength ) }" )
			elif (( $( echo "$total $comBreakLength" | awk '{ print ($1 < $2) }' ) )); then
				echo "file://$com" >> $EDEN/playlists/$cnt.list
			fi
		done
# Add this length to a total and keep iterating (check about 50 coms, should be no more). 
# The break length divided by this total gives us the factor to stretch the last com by.
		lastComStretchAmountSeconds=$( awk "BEGIN { print ( $comBreakLength - $total ) }" )
		targetLastComLength=$( awk "BEGIN { print ( $comLength + $lastComStretchAmountSeconds ) }" )
		factor=$( awk "BEGIN { print ( $comLength / $targetLastComLength ) }" ) # reverse if using vlc rate
		audio=$( awk "BEGIN { print ( $targetLastComLength / $comLength )}" )
# Since vlc considers playback rate to be an unsafe option, (may be possible with VLM and vlc acting as a jockey) we use ffmpeg 
# to stretch the last com by the factor amount and place it in a separate folder. We then delete the last line of the list and 
# echo the new file's location into .list.
		comName=$( basename "$com" )
		ffmpeg -n -i "$com" -filter_complex "[0:v]setpts=${factor}*PTS[v];[0:a]atempo=${audio}[a]" -map "[v]" -map "[a]" $EDEN/stretchedComs/$comName
# Using sed, remove the last line and then echo the stretched com into the list.
		targetLineNumber=$( wc -l < $EDEN/playlists/$cnt.list )
		targetLine=$( cat $EDEN/playlists/$cnt.list | head -$targetLineNumber | tail -1 )
		sed -i "\:$targetLine:d" $EDEN/playlists/$cnt.list
		echo "file://$EDEN/stretchedComs/$comName" >> $EDEN/playlists/$cnt.list
done; done
# Now we create the master m3u. Echo the necessary m3u header info into the master and begin iterating thru the
# .list files and echoing into the master.
master=$( date +%Y-%m-%d-EDEN )
touch $EDEN/playlists/$master.m3u
echo "#EXTM3U" >> $EDEN/playlists/$master.m3u
cnt=0
for f in `find $EDEN/playlists/*.list`; do
	cnt=$(($cnt+1))
	cat $EDEN/playlists/$cnt.list >> $EDEN/playlists/$master.m3u
# We create an exception for the mtv playlist by latching onto 23.list. Add its members to the master m3u and then
# create an mtv block. We need it to be an hour and a half. Use find to get all music videos, then
# Randomly sort them, iterate thru, echo to a list, and add to a total, without going over. The total length of the block in second
# minus the total counted is the amount of seconds to stretch the last vid (silly for now but we'll fix). 
# The length of the last video plus the amount to stretch gives us the target amount. The target divided by 
# the length of the last video is our factor. Echo the factor into the mtv list before the last line.
	if [ $cnt = 23 ]; then
		touch $EDEN/MTV/MTV.list
		find $EDEN/MTV/* -name '*.mp4' > /tmp/allmtv
		cat /tmp/allmtv | shuf -n 500 > /tmp/mtvlist
		total=0
		for vid in $( cat /tmp/mtvlist ); do
			previousVidLength=$vidLength
			vidLength=$( ffmpeg -i "$vid" 2>&1 | grep "Duration"| cut -d ' ' -f 4 | sed s/,// | sed 's@\..*@@g' | awk '{ split($1, A, ":"); split(A[3], B, "."); print 3600*A[1] + 60*A[2] + B[1] }' )
			#vidLength=$( ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$vid" )
			if [[ $vidLength == N/A || -z $vidLength ]]; then
				vidLength=$previousVidLength
				continue
			fi
			total=$( awk "BEGIN { print ( $vidLength + $total ) }" )
			if (( $( echo "$total 5400" | awk '{ print ( $1 > $2 ) }' ) )); then
				total=$( awk "BEGIN { print ( $total - $vidLength ) }" )
			elif (( $( echo "$total 5400" | awk '{ print ( $1 < $2 ) }' ) )); then
				echo "file://$vid" >> $EDEN/MTV/MTV.list
			fi
		done
		lastVidStretchAmountSeconds=$( awk "BEGIN { print ( 5400 - $total ) }" )
		targetLastVidLength=$( awk "BEGIN { print ( $vidLength - $lastVidStretchAmountSeconds ) }" )
		mtvFactor=$( awk "BEGIN { print ( $vidLength / $targetLastVidLength ) }" ) # reverse if using vlc rate
		mtvAudio=$( awk "BEGIN { print ( $targetLastVidLength / $vidLength )}" )
		vidName=$( basename "$vid" )
		ffmpeg -n -i "$vid" -filter_complex "[0:v]setpts=${mtvFactor}*PTS[v];[0:a]atempo=${mtvAudio}[a]" -map "[v]" -map "[a]" $EDEN/stretchedComs/$vidName
		targetLineNumber=$( wc -l < $EDEN/MTV/MTV.list )
		sed -i "\:$targetLineNumber:d" $EDEN/MTV/MTV.list
		echo "file://$EDEN/stretchedComs/$vidName" >> $EDEN/MTV/MTV.list
		cat $EDEN/MTV/MTV.list >> $EDEN/playlists/$master.m3u
	fi
done
# The resulting m3u should (!) be able to be streamed as is on a schedule at 6am and stay on course throughout the day.
# We need to eventually integrate a safety net because of crashes, however. (Have a script run in the background, if it's closed wait until the next date period and skip to the correct index.)
# We can also look into VLM as a jockey system as originally intended with mpv. This would make a safety net much more plausible.
# Buffer (cache) may need to be increased for vlc when starting it up to prevent stuttering at any point.

# Cleanup
#rm $EDEN/playlists/*.list
#rm $EDEN/MTV/MTV.list

