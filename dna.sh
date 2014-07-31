#!/bin/bash

	
if [ $# -eq 3 ]; then
	callFunc=$1
	rc=$2
	if [ $callFunc == "start" ]; then
		resource=$3
	else
		JOBID=$3
	fi
	
elif [ $# -eq 4 ]; then
	callFunc=$1
	rc=$2
	JOBID=$3
	slurmJobNodeList=$4
else
	callFunc=usage
	
fi

PWD=`pwd`
Path=/usr/local/Cluster-Apps/slurm/bin
partition=`cat $PWD/config.cf | grep -w "Partition" | awk '{print $3}'`
path=`cat $PWD/config.cf | grep -w "Path" | awk '{print $3}'`

function start 
{
#Read partion from config.cf
	partition=`cat $PWD/config.cf | grep -w "Partition" | awk '{print $3}'`
	submitJobToSLURM $resource $rc
	#$Path/sbatch $PWD/$resource $PWD/$rc
	if [ $? -eq 0 ]; then
		echo -e "Job submission completed!!"
	else
		echo -e "Error : Some issue occurs while submitting!!"
	fi



}

function submitJobToSLURM {

	getResource=`echo $1`
        echo -e "Job submission to SLURM initiated!!"
        getJobID=`$Path/sbatch $PWD/$getResource $PWD/$rc | awk '{print $4}'`
        while true;do
                sleep 2

                # Check job status
                STATUS=`squeue -j $getJobID -t PD,R -h -o %t`

                if [ "$STATUS" = "R" ];then
                        # Job is running, break the while loop
                        break
                elif [ "$STATUS" != "PD" ];then
                        echo "Job is not Running or Pending. Aborting"
                        scancel $getJobID
                        exit 1
                fi

                echo -n "."

        done

        while true;do
                STATUS=`squeue -j $getJobID -t PD,R -h -o %t`
                if [ "$STATUS" = "" ]; then
                        break;
                fi
                echo -n "."
        done

        echo -e "Job submission to SLURM Completed and CH process!!\n"
}

function check {

	slurmJobNodeList=$PWD/machine.file.$JOBID

	if [ -f $slurmJobNodeList ]; then
       		for machine in `cat $slurmJobNodeList`
        	do
                	for rcPid in `ssh $machine ps -ef | grep $rc | grep -v grep | grep -v slurmd | grep -v $callFunc |awk '{print $2}'`
                	do
				if [ "$rcPid" == "" ]; then
					echo "Check operation performed on $machine. No binary running!!"
				else
					echo "Binary($rc) still running on $machine. Hence, exiting!!"
					echo "Please execute - dna stop $rc $resource !!"
					exit
				fi	
                	done
        	done
	else
		echo "Error : Either JOBID is wrong or machine.file.$JOBID has been removed!!"
	fi
}

function stop {

	slurmJobNodeList=$PWD/machine.file.$JOBID

	if [ -f $slurmJobNodeList ]; then
       		for machine in `cat $slurmJobNodeList`
        	do
                	for rcPid in `ssh $machine ps -ef | grep $rc | grep -v grep | grep -v slurmd | grep -v $callFunc | grep -v bin | awk '{print $2}'`
                	do
				if [ "$rcPid" == "" ]; then
					echo "Stop operation performed. No binary running to kill!!"
				else
					echo "Killing binary ($rc) running on $machine!!"
					kill $rcPid
				fi	
                	done
        	done
	else
		echo "Error : Either JOBID is wrong or machine.file.$JOBID has been removed!!"
	fi
}

#This function generated CAD list
function generatingCADFile {

        echo -e "Generating CAD File\n============\n"
        touch $PWD/CAD.$JOBID.file
        portNo=6010 # Has some issue with automation, but can be done.
        # Create a file in the format <Hostname>:<Port no>
        while read line
        do
                echo $line | sed "s/$/:${portNo}/" >> $PWD/CAD.$JOBID.file
                portNo=`expr ${portNo} + 1`

        done<$slurmJobNodeList
        echo `cat $PWD/CAD.$JOBID.file`
}

function md5sum {

        /usr/bin/md5sum $path >  $PWD/md5sum.md5
        status=`/usr/bin/md5sum -c $PWD/md5sum.md5`
        if [ "$status" == "$path: OK" ];then
                return 0
        else
                return 1
        fi
}

function startingCHprocess {

        echo -e "\n============\nCH Process initiated\n============\n"
        flag=0
        for machine in `cat $slurmJobNodeList`
        do
                if [ $flag -eq 0 ]
                then
                        echo -e "Skip Master node IP\n============\n"
                        getMasterIP=$machine
                        flag=1
                else
                        ipAdd=`ssh $machine nslookup $machine | grep Address | tail -1 | awk '{print $2}'`
                        portNo=`cat $PWD/CAD.$JOBID.file | grep $machine | cut -f2 -d":"`
                        echo -e "\n============\nStarting Slave==<$ipAdd>=====<$portNo>=====\n============\n"
                        srun -p tesla --nodelist $machine --exclusive $rc slave $ipAdd $portNo 1>> $PWD/slurm-$JOBID.out &
                	sleep 2
               		echo -e "Sleeping for 2 secs!!"
                fi
        done

        ipAdd=`nslookup $getMasterIP | grep Address | tail -1 | awk '{print $2}'`
        portNo=`cat $PWD/CAD.$JOBID.file | grep $getMasterIP | cut -f2 -d":"`
        echo -e "\n============\nStarting Master====<$ipAdd>=====<$portNo>=====\n============\n"
        echo -e "Results of dot-product\n=============================\n" >> $PWD/dot-product-result.log
        srun -p tesla --nodelist $getMasterIP --exclusive $rc master $ipAdd $portNo 1>> $PWD/slurm-$JOBID.out

        #wait
        echo -e "\n============\nCH Process initiation completed\n============\n"
}



####### Main

function usage
{
	echo -e "Usage: "
	echo -e "./dna.sh start <dot-product binary> <requested SLURM resource script>"
	echo -e "./dna.sh check <dot-product binary> <JOBID>"
	echo -e "./dna.sh stop <dot-product binary> <JOBID>"
	
}

$callFunc 
