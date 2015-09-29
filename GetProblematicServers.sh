#!/bin/bash
# get statistics for individual IPs behind a domain

URLS=( "http://127.0.0.1"
       "http://127.0.0.1:8080" )
# time between consecutive measurements
DELAY=30
# number of times to hit the endpoint
SAMPLESIZE=20
# set the separator to newlines to help get arrays to play nicely with the ouput of curl and the like
IFS=$'\r\n'
# where to keep temporary files
root="/${HOME}/.probservertempfiles"
IPS=()
# 1=info 2=actual data
debug=0

# create root dir if nonexistent
if [ ! -d ${root} ]; then
	mkdir ${root}
fi

connect ()
#
# hit an endpoint ${SAMPLESIZE} amount of times and get the IP it resolved to and the Time to First Byte (TTFVB)
#
{
	i=0
	while [ ${i} -le ${SAMPLESIZE} ]; do
		curl -m 20 -v "${1}" -o /dev/null -w 'TTFB:%{time_starttransfer}' 2>&1 | grep -Po '(?<=Trying )[0-9\.]*(?=\.\.\.)|^TTFB:[0-9]{1,3}\.[0-9]{3}'
		let i=i+1
	done
}

gatherstats ()
#
# iterate through the ${URLS[@]} array and gather the raw data for later statistics
#
{
	[ ${debug} -gt 0 ] && echo "Gathering stats"
	for URL in ${URLS[@]}; do 
	[ ${debug} -gt 1 ] && echo "URL: ${URL}"
		response=$(connect "${URL}")
		IP=$(echo $response | head -n 1 | cut -d' ' -f1)
		TTFB=($(printf -- '%s\n' "${response[@]}" | grep TTFB | cut -c6-10))
	[ ${debug} -gt 0 ] && echo "Stats gathered"
	[ ${debug} -gt 1 ] && echo "response=$(for r in ${response[@]}; do echo "${r}"; done)"
	[ ${debug} -gt 1 ] && echo "IP=${IP}"
	[ ${debug} -gt 1 ] && echo "TTFB=$(for t in ${TTFB[@]}; do echo "${t}"; done)"
	[ ${debug} -gt 0 ] && echo "Calling updatearray"
		updatearray ${IP} ${TTFB[@]}
	done
}

updatearray ()
#
# Add any new IPs to an array to track them, and then write out TTFBs to a file
#
{
	IP=$1
	TTFB=$2
	[ ${debug} -gt 1 ] && echo "IP=${IP}"
	[ ${debug} -gt 1 ] && echo "TTFB=${TTFB[@]}"
	[ ${debug} -gt 1 ] && echo "IPS=$(for ip in ${IPS[@]}; do echo IP:${ip}; done)"
	case "${IPS[@]}" in 
	*"${IP}"*)
	[ ${debug} -gt 0 ] && echo "IP Exists in array"
	;;
	*)
	[ ${debug} -gt 0 ] && echo "IP added to array"
		IPS+=(${IP})
	esac
	[ ${debug} -gt 0 ] && echo "Writing TTFB to ${IP}ttfb"
	echo ${TTFB[@]} | sed -e 's/\ /\n/g' >> $root/${IP}ttfb
}

calcstats ()
#
# Iterate through IPs to calculate avg and max TTFB for each
#
{
	[ ${debug} -gt 0 ] && echo "Calculating stats"
	for ip in ${IPS[@]}; do
	[ ${debug} -gt 0 ] && echo "Calculating for IP ${ip}"
		sum=0
		total=0
		while read time; do
			sum=$(echo $sum + $time | bc)
			total=$(echo $total + 1 | bc)			
		done < ${root}/${ip}ttfb
		# sed here to add a leading zero if necessary (bc doesn't do it automatically)
		# scale=3 sets 3 significant digits after the decimal
		avg=$(echo "scale=3; $sum/$total" | bc -l | sed 's/^\./0./')
		max=$(sort -nr ${root}/${ip}ttfb | head -1)
	[ ${debug} -gt 1 ] && echo "avg=${avg}"
	[ ${debug} -gt 1 ] && echo "max=${max}"
		# add the average to the end of the file and then set the max to the max TTFB seen
		echo ${avg} >>${root}/${ip}avg
		echo ${max} > ${root}/${ip}max
	done
	[ ${debug} -gt 0 ] && echo "Done calculating stats"
}

displaystats ()
#
# displays timestamp and stats for each IP
# last (up to) 5 averages and maximums
#
{
	[ ${debug} -gt 0 ] && echo "Displaying stats"
	echo "======================================================="
	echo "===$(date)                Stats==="
	echo "======================================================="
	for ip in ${IPS[@]}; do
		echo "${ip}:"
		# sets ${iplength} to be the number of lines in the ${ip}avg file
		iplength=$( cat ${root}/${ip}avg | wc -l)
	[ ${debug} -gt 1 ] && echo "iplength=${iplength}"
		echo -e "\tLast (up to) 5 averages:"
		i=0
		# ${current} is the number of lines minus the counter, ${i}
		# this a counter of the line number to print
		# it needs to be 1 or greater because you can't print line 0 of a file
		current=$(echo "${iplength} - ${i}" | bc)
		# ${i} needs to be less than 5 because that's the number of averages we want to print
		while [[ ${i} -lt 5 ]] && [[ ${current} -ge 1 ]]; do
	[ ${debug} -gt 1 ] && echo "current=${current}"
	[ ${debug} -gt 1 ] && echo "i=${i}"
			echo -en "\t\t"
			# print ${current} line from the ipavg file (just the first 5 characters, so will display as 0.015 for example, or 20.10)
			sed -n "${current}p" "${root}/${ip}avg" | cut -c1-5
			let i=i+1
			# update the current linecount so the while up there will check an up-to-date number
			current=$(echo "${iplength} - ${i}" | bc)
		done
		echo -e "\tMaximum:"
		echo -en "\t\t"
		cat ${root}/${ip}max
	done
}

resetstats ()
#
# remove temporary files so stats are clean on each run
# TODO: grab IPs from the file and populate the array so the script can be paused and resumed instead of having to start fresh every time
#
{
	[ ${debug} -gt 0 ] && echo "Resetting stats"
	[ ${debug} -gt 0 ] && echo $(ls ${root} -l | wc -l)" files in the directory"
	[ ${debug} -gt 0 ] && echo "root=${root}"
	find ${root} -type f -exec rm {} \;
	[ ${debug} -gt 0 ] && echo "Stats Reset"
	[ ${debug} -gt 0 ] && echo $(ls ${root} -1 | wc -l)" files in the directory"
}

[ ${debug} -gt 0 ] && echo "Calling resetstats"
resetstats

# main loop
while true; do
	[ ${debug} -gt 0 ] && echo "Calling gatherstats"
	gatherstats
	[ ${debug} -gt 0 ] && echo "Calling calcstats"
	calcstats
	[ ${debug} -gt 0 ] && echo "Calling displaystats"	
	displaystats
	[ ${debug} -gt 0 ] && echo "Sleeping ${DELAY} seconds"
	sleep ${DELAY}
done
